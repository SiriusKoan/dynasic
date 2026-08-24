import AppKit
import Accelerate
import CoreAudio
import Darwin
import Foundation
import LyricsCore

enum AppleMusicWaveformError: Error, Equatable {
    case permissionDenied
    case musicUnavailable
    case unsupportedFormat
    case coreAudio(operation: String, status: OSStatus)
}

final class WaveformSampleRing: @unchecked Sendable {
    static let maximumBatchCount = 32_768

    private let storage = UnsafeMutablePointer<Float>.allocate(
        capacity: WaveformSampleRing.maximumBatchCount
    )
    private var readIndex: Int64 = 0
    private var writeIndex: Int64 = 0

    deinit {
        storage.deallocate()
    }

    func push(_ value: Float) {
        var value = value
        withUnsafePointer(to: &value) { pointer in
            push(UnsafeBufferPointer(start: pointer, count: 1))
        }
    }

    func push(_ samples: UnsafeBufferPointer<Float>) {
        guard let source = samples.baseAddress, !samples.isEmpty else { return }

        let read = atomicLoad(&readIndex)
        let write = atomicLoad(&writeIndex)
        let unreadCount = min(
            Int64(Self.maximumBatchCount),
            max(0, write - read)
        )
        let freeCount = Int64(Self.maximumBatchCount) - unreadCount
        let count = min(Int64(samples.count), freeCount)
        guard count > 0 else { return }

        // The producer never advances readIndex. If the consumer falls behind,
        // retain unread samples and accept only the newest part that fits.
        let sourceOffset = samples.count - Int(count)
        let sourceSamples = source.advanced(by: sourceOffset)
        let storageOffset = Int(write % Int64(Self.maximumBatchCount))
        let firstCount = min(Int(count), Self.maximumBatchCount - storageOffset)
        let byteCount = MemoryLayout<Float>.stride

        memcpy(
            storage.advanced(by: storageOffset),
            sourceSamples,
            firstCount * byteCount
        )
        if firstCount < Int(count) {
            memcpy(
                storage,
                sourceSamples.advanced(by: firstCount),
                (Int(count) - firstCount) * byteCount
            )
        }

        OSMemoryBarrier()
        _ = OSAtomicCompareAndSwap64Barrier(
            write,
            write + count,
            &writeIndex
        )
    }

    func pop() -> Float? {
        var value: Float = 0
        let count = withUnsafeMutablePointer(to: &value) { pointer in
            pop(into: UnsafeMutableBufferPointer(start: pointer, count: 1))
        }
        return count == 1 ? value : nil
    }

    @discardableResult
    func pop(into output: UnsafeMutableBufferPointer<Float>) -> Int {
        guard let destination = output.baseAddress, !output.isEmpty else { return 0 }

        let read = atomicLoad(&readIndex)
        let write = atomicLoad(&writeIndex)
        let availableCount = min(
            Int64(Self.maximumBatchCount),
            max(0, write - read)
        )
        let count = min(Int64(output.count), availableCount)
        guard count > 0 else { return 0 }

        let storageOffset = Int(read % Int64(Self.maximumBatchCount))
        let firstCount = min(Int(count), Self.maximumBatchCount - storageOffset)
        let byteCount = MemoryLayout<Float>.stride

        memcpy(
            destination,
            storage.advanced(by: storageOffset),
            firstCount * byteCount
        )
        if firstCount < Int(count) {
            memcpy(
                destination.advanced(by: firstCount),
                storage,
                (Int(count) - firstCount) * byteCount
            )
        }

        OSMemoryBarrier()
        _ = OSAtomicCompareAndSwap64Barrier(
            read,
            read + count,
            &readIndex
        )
        return Int(count)
    }

    func clear() {
        readIndex = 0
        writeIndex = 0
    }

    private func atomicLoad(_ value: inout Int64) -> Int64 {
        OSAtomicAdd64Barrier(0, &value)
    }
}

final class WaveformSpectrumAnalyzer {
    static let sampleCount = 2_048

    private static let decibelFloor: Float = -72
    private static let fftBinCount = sampleCount / 2
    private static let log2SampleCount = vDSP_Length(log2(Float(sampleCount)))

    private let fftSetup: FFTSetup
    private let window: [Float]
    private let windowSum: Float
    private let fftBandIndices: [Int]
    private let bandBinCounts: [Int]

    private var history = Array(repeating: Float.zero, count: sampleCount)
    private var historyWriteIndex = 0
    private var receivedSampleCount = 0
    private var fftInput = Array(repeating: Float.zero, count: sampleCount)
    private var real = Array(repeating: Float.zero, count: fftBinCount)
    private var imaginary = Array(repeating: Float.zero, count: fftBinCount)
    private var bandPowers = Array(
        repeating: Float.zero,
        count: WaveformSpectrumProcessor.columnCount
    )
    private var levels = Array(
        repeating: Float.zero,
        count: WaveformSpectrumProcessor.columnCount
    )

    init?(sampleRate: Double) {
        guard sampleRate.isFinite,
              sampleRate > Double(WaveformSpectrumProcessor.minimumFrequency),
              let fftSetup = vDSP_create_fftsetup(
                  Self.log2SampleCount,
                  FFTRadix(kFFTRadix2)
              ) else { return nil }

        self.fftSetup = fftSetup
        let denominator = Float(Self.sampleCount - 1)
        window = (0..<Self.sampleCount).map { index in
            0.5 - 0.5 * cos(2 * .pi * Float(index) / denominator)
        }
        windowSum = window.reduce(0, +)

        var indices = Array(repeating: -1, count: Self.fftBinCount)
        var counts = Array(
            repeating: 0,
            count: WaveformSpectrumProcessor.columnCount
        )
        for fftIndex in 1..<Self.fftBinCount {
            let frequency = Float(Double(fftIndex) * sampleRate / Double(Self.sampleCount))
            guard let bandIndex = Self.bandIndex(for: frequency) else { continue }
            indices[fftIndex] = bandIndex
            counts[bandIndex] += 1
        }
        fftBandIndices = indices
        bandBinCounts = counts
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    func append(_ sample: Float) {
        history[historyWriteIndex] = min(max(sample.isFinite ? sample : 0, -1), 1)
        historyWriteIndex = (historyWriteIndex + 1) % Self.sampleCount
        receivedSampleCount = min(receivedSampleCount + 1, Self.sampleCount)
    }

    func append(_ samples: UnsafeBufferPointer<Float>) {
        for sample in samples {
            append(sample)
        }
    }

    func makeBucket() -> WaveformBucket? {
        guard receivedSampleCount == Self.sampleCount else { return nil }

        for index in 0..<Self.sampleCount {
            let historyIndex = (historyWriteIndex + index) % Self.sampleCount
            fftInput[index] = history[historyIndex] * window[index]
        }

        fftInput.withUnsafeBufferPointer { input in
            input.baseAddress!.withMemoryRebound(
                to: DSPComplex.self,
                capacity: Self.fftBinCount
            ) { complexInput in
                real.withUnsafeMutableBufferPointer { realBuffer in
                    imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                        var split = DSPSplitComplex(
                            realp: realBuffer.baseAddress!,
                            imagp: imaginaryBuffer.baseAddress!
                        )
                        vDSP_ctoz(
                            complexInput,
                            2,
                            &split,
                            1,
                            vDSP_Length(Self.fftBinCount)
                        )
                        vDSP_fft_zrip(
                            fftSetup,
                            &split,
                            1,
                            Self.log2SampleCount,
                            FFTDirection(FFT_FORWARD)
                        )
                    }
                }
            }
        }

        for index in bandPowers.indices {
            bandPowers[index] = 0
        }
        let amplitudeScale = 2 / windowSum
        let powerScale = amplitudeScale * amplitudeScale
        for fftIndex in 1..<Self.fftBinCount {
            let bandIndex = fftBandIndices[fftIndex]
            guard bandIndex >= 0 else { continue }
            let realValue = real[fftIndex]
            let imaginaryValue = imaginary[fftIndex]
            bandPowers[bandIndex] += (
                realValue * realValue + imaginaryValue * imaginaryValue
            ) * powerScale
        }

        for index in levels.indices {
            levels[index] = 0
        }
        for bandIndex in levels.indices where bandBinCounts[bandIndex] > 0 {
            let amplitude = sqrt(
                bandPowers[bandIndex] / Float(bandBinCounts[bandIndex])
            )
            levels[bandIndex] = Self.normalizedLevel(forAmplitude: amplitude)
        }
        return WaveformBucket(levels: levels)
    }

    static func bandIndex(for frequency: Float) -> Int? {
        guard frequency.isFinite,
              frequency >= WaveformSpectrumProcessor.minimumFrequency,
              frequency <= WaveformSpectrumProcessor.maximumFrequency else { return nil }
        let span = log(
            WaveformSpectrumProcessor.maximumFrequency
                / WaveformSpectrumProcessor.minimumFrequency
        )
        let position = log(frequency / WaveformSpectrumProcessor.minimumFrequency) / span
        return min(
            Int(position * Float(WaveformSpectrumProcessor.columnCount)),
            WaveformSpectrumProcessor.columnCount - 1
        )
    }

    static func normalizedLevel(forAmplitude amplitude: Float) -> Float {
        guard amplitude.isFinite, amplitude > 0 else { return 0 }
        let decibels = 20 * log10(amplitude)
        return min(max((decibels - decibelFloor) / -decibelFloor, 0), 1)
    }
}

final class WaveformCaptureContext: @unchecked Sendable {
    private enum SampleFormat {
        case float32
        case int16

        var byteCount: Int {
            switch self {
            case .float32: MemoryLayout<Float>.size
            case .int16: MemoryLayout<Int16>.size
            }
        }
    }

    let ring: WaveformSampleRing
    private let sampleFormat: SampleFormat
    private let channelCount: Int
    private let isNonInterleaved: Bool
    private let mixedSamples: UnsafeMutablePointer<Float>
    private var acceptsCallbacks: Int32 = 1
    private var activeCallbackCount: Int32 = 0

    init(format: AudioStreamBasicDescription, ring: WaveformSampleRing) throws {
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mSampleRate.isFinite,
              format.mSampleRate > 0,
              (1...2).contains(format.mChannelsPerFrame) else {
            throw AppleMusicWaveformError.unsupportedFormat
        }

        let flags = format.mFormatFlags
        let isNonInterleaved = flags & kAudioFormatFlagIsNonInterleaved != 0
        guard flags & kAudioFormatFlagIsBigEndian == 0,
              flags & kAudioFormatFlagIsAlignedHigh == 0,
              flags & kAudioFormatFlagIsPacked != 0,
              format.mFramesPerPacket > 0 else {
            throw AppleMusicWaveformError.unsupportedFormat
        }

        if format.mBitsPerChannel == 32,
           flags & kAudioFormatFlagIsFloat != 0 {
            sampleFormat = .float32
        } else if format.mBitsPerChannel == 16,
                  flags & kAudioFormatFlagIsSignedInteger != 0 {
            sampleFormat = .int16
        } else {
            throw AppleMusicWaveformError.unsupportedFormat
        }

        let channelCount = Int(format.mChannelsPerFrame)
        let samplesPerFrame = isNonInterleaved ? 1 : channelCount
        let expectedBytesPerFrame = UInt32(sampleFormat.byteCount * samplesPerFrame)
        guard format.mBytesPerFrame == expectedBytesPerFrame,
              format.mBytesPerPacket == expectedBytesPerFrame * format.mFramesPerPacket else {
            throw AppleMusicWaveformError.unsupportedFormat
        }

        self.ring = ring
        self.channelCount = channelCount
        self.isNonInterleaved = isNonInterleaved
        self.mixedSamples = UnsafeMutablePointer.allocate(
            capacity: WaveformSampleRing.maximumBatchCount
        )
    }

    deinit {
        mixedSamples.deallocate()
    }

    func consume(_ inputData: UnsafePointer<AudioBufferList>?) {
        _ = OSAtomicIncrement32Barrier(&activeCallbackCount)
        defer { _ = OSAtomicDecrement32Barrier(&activeCallbackCount) }
        guard OSAtomicAdd32Barrier(0, &acceptsCallbacks) == 1 else { return }
        guard let inputData else { return }
        let mutableList = UnsafeMutablePointer<AudioBufferList>(mutating: inputData)
        let buffers = UnsafeMutableAudioBufferListPointer(mutableList)
        let expectedBufferCount = isNonInterleaved ? channelCount : 1
        guard buffers.count == expectedBufferCount else { return }

        var frameCount = Int.max
        for buffer in buffers {
            let channelCount = Int(buffer.mNumberChannels)
            let expectedChannelCount = isNonInterleaved ? 1 : self.channelCount
            guard channelCount == expectedChannelCount, buffer.mData != nil else { return }
            let sampleCount = Int(buffer.mDataByteSize) / sampleFormat.byteCount
            frameCount = min(frameCount, sampleCount / channelCount)
        }
        guard frameCount != Int.max, frameCount > 0 else { return }

        if case .float32 = sampleFormat,
           buffers.count == 1,
           buffers[0].mNumberChannels == 1,
           let data = buffers[0].mData {
            // process tap 已要求 mono mixdown，Float32 單聲道可直接寫入 ring buffer。
            ring.push(
                UnsafeBufferPointer(
                    start: data.assumingMemoryBound(to: Float.self),
                    count: frameCount
                )
            )
            return
        }

        var batchStart = 0
        while batchStart < frameCount {
            let batchCount = min(
                frameCount - batchStart,
                WaveformSampleRing.maximumBatchCount
            )
            for batchIndex in 0..<batchCount {
                let frameIndex = batchStart + batchIndex
                var frameTotal: Float = 0
                var frameSamples = 0
                for buffer in buffers {
                    guard let data = buffer.mData else { continue }
                    let channelCount = Int(buffer.mNumberChannels)
                    guard channelCount > 0 else { continue }
                    let firstSample = frameIndex * channelCount

                    switch sampleFormat {
                    case .float32:
                        let samples = data.assumingMemoryBound(to: Float.self)
                        for channel in 0..<channelCount {
                            let sample = samples[firstSample + channel]
                            let bounded = sample.isFinite ? min(max(sample, -1), 1) : 0
                            frameTotal += bounded
                            frameSamples += 1
                        }
                    case .int16:
                        let samples = data.assumingMemoryBound(to: Int16.self)
                        for channel in 0..<channelCount {
                            let normalized = Float(samples[firstSample + channel]) / 32_768
                            frameTotal += normalized
                            frameSamples += 1
                        }
                    }
                }

                mixedSamples[batchIndex] = frameSamples > 0
                    ? frameTotal / Float(frameSamples)
                    : 0
            }

            ring.push(
                UnsafeBufferPointer(start: mixedSamples, count: batchCount)
            )
            batchStart += batchCount
        }
    }

    func stopAcceptingCallbacks() {
        _ = OSAtomicCompareAndSwap32Barrier(1, 0, &acceptsCallbacks)
    }

    func waitForCallbacksToFinish() {
        while OSAtomicAdd32Barrier(0, &activeCallbackCount) != 0 {
            sched_yield()
        }
    }
}

final class AppleMusicProcessTapWaveformSource: WaveformSource, @unchecked Sendable {
    private static let preferredBufferFrameCount: UInt32 = 2_048
    private let controlQueue = DispatchQueue(label: "dynasic.waveform.control")
    private let deliveryQueue = DispatchQueue(label: "dynasic.waveform.delivery")

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var context: WaveformCaptureContext?
    private var deliveryTimer: DispatchSourceTimer?
    private var processExitSource: DispatchSourceProcess?
    private var continuation: AsyncStream<WaveformBucket>.Continuation?
    private var activeStream: AsyncStream<WaveformBucket>?
    private var cleanupError: AppleMusicWaveformError?

    func start() async throws -> AsyncStream<WaveformBucket> {
        try await withCheckedThrowingContinuation { continuation in
            controlQueue.async { [self] in
                do {
                    continuation.resume(returning: try startSynchronously())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            controlQueue.async { [self] in
                stopSynchronously()
                continuation.resume()
            }
        }
    }

    private func startSynchronously() throws -> AsyncStream<WaveformBucket> {
        if let activeStream { return activeStream }
        if ioProcID != nil
            || aggregateDeviceID != kAudioObjectUnknown
            || tapID != kAudioObjectUnknown {
            stopSynchronously()
            if let cleanupError {
                throw cleanupError
            }
        }

        let musicProcess = try musicAudioProcess()
        let description = CATapDescription(monoMixdownOfProcesses: [musicProcess.objectID])
        description.name = "dynasic Music waveform"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        do {
            try check(
                AudioHardwareCreateProcessTap(description, &tapID),
                operation: "create process tap"
            )
            let tapUID = try stringProperty(
                objectID: tapID,
                selector: kAudioTapPropertyUID
            )
            let format = try audioFormatProperty(
                objectID: tapID,
                selector: kAudioTapPropertyFormat
            )

            let ring = WaveformSampleRing()
            let context = try WaveformCaptureContext(format: format, ring: ring)
            guard let analyzer = WaveformSpectrumAnalyzer(sampleRate: format.mSampleRate) else {
                throw AppleMusicWaveformError.unsupportedFormat
            }
            self.context = context

            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "dynasic Music waveform",
                kAudioAggregateDeviceUIDKey: "com.siriuskoan.dynasic.waveform.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: true
                ]]
            ]
            try check(
                AudioHardwareCreateAggregateDevice(
                    aggregateDescription as CFDictionary,
                    &aggregateDeviceID
                ),
                operation: "create aggregate device"
            )
            configurePreferredBufferFrameCount(aggregateDeviceID)

            let stream = AsyncStream<WaveformBucket>(bufferingPolicy: .bufferingNewest(64)) {
                self.continuation = $0
            }
            activeStream = stream

            try check(
                AudioDeviceCreateIOProcIDWithBlock(
                    &ioProcID,
                    aggregateDeviceID,
                    nil
                ) { _, inputData, _, _, _ in
                    context.consume(inputData)
                },
                operation: "create IO procedure"
            )
            try check(
                AudioDeviceStart(aggregateDeviceID, ioProcID),
                operation: "start aggregate device"
            )
            startDeliveryTimer(ring: ring, analyzer: analyzer)
            startProcessExitMonitoring(pid: musicProcess.pid)
            return stream
        } catch {
            let startupError = error
            stopSynchronously()
            throw cleanupError ?? startupError
        }
    }

    private func configurePreferredBufferFrameCount(_ deviceID: AudioObjectID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var frameCount = Self.preferredBufferFrameCount

        // 較大的 callback 區塊可降低 IO callback 排程與 ring buffer 發布次數。
        // 私有 aggregate device 不支援設定時，保留 Core Audio 的預設值。
        _ = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &frameCount
        )
    }

    private func stopSynchronously() {
        var firstCleanupError: AppleMusicWaveformError?

        func recordFailure(_ status: OSStatus, operation: String) {
            guard status != noErr, firstCleanupError == nil else { return }
            firstCleanupError = .coreAudio(operation: operation, status: status)
        }

        if aggregateDeviceID != kAudioObjectUnknown, let ioProcID {
            recordFailure(
                AudioDeviceStop(aggregateDeviceID, ioProcID),
                operation: "stop aggregate device"
            )
            context?.stopAcceptingCallbacks()
            context?.waitForCallbacksToFinish()
            let status = AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            recordFailure(status, operation: "destroy IO procedure")
            if status == noErr {
                self.ioProcID = nil
            }
        }

        if ioProcID == nil, aggregateDeviceID != kAudioObjectUnknown {
            let status = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            recordFailure(status, operation: "destroy aggregate device")
            if status == noErr {
                aggregateDeviceID = kAudioObjectUnknown
            }
        }
        if aggregateDeviceID == kAudioObjectUnknown, tapID != kAudioObjectUnknown {
            let status = AudioHardwareDestroyProcessTap(tapID)
            recordFailure(status, operation: "destroy process tap")
            if status == noErr {
                tapID = kAudioObjectUnknown
            }
        }

        processExitSource?.setEventHandler {}
        processExitSource?.cancel()
        processExitSource = nil

        deliveryTimer?.setEventHandler {}
        deliveryTimer?.cancel()
        deliveryTimer = nil
        deliveryQueue.sync {}
        continuation?.finish()
        continuation = nil
        activeStream = nil

        let didDestroyCoreAudioResources = ioProcID == nil
            && aggregateDeviceID == kAudioObjectUnknown
            && tapID == kAudioObjectUnknown
        if didDestroyCoreAudioResources {
            context?.ring.clear()
            context = nil
            cleanupError = nil
        } else {
            cleanupError = firstCleanupError ?? .coreAudio(
                operation: "clean up Core Audio waveform resources",
                status: kAudioHardwareUnspecifiedError
            )
        }
    }

    private func startDeliveryTimer(
        ring: WaveformSampleRing,
        analyzer: WaveformSpectrumAnalyzer
    ) {
        let timer = DispatchSource.makeTimerSource(queue: deliveryQueue)
        var samples = Array(
            repeating: Float.zero,
            count: WaveformSampleRing.maximumBatchCount
        )
        var emptyDeliveryCount = 0
        timer.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            var receivedSamples = false
            samples.withUnsafeMutableBufferPointer { buffer in
                while true {
                    let count = ring.pop(into: buffer)
                    guard count > 0 else { break }
                    analyzer.append(
                        UnsafeBufferPointer(start: buffer.baseAddress, count: count)
                    )
                    receivedSamples = true
                }
            }

            if receivedSamples {
                emptyDeliveryCount = 0
                if let bucket = analyzer.makeBucket() {
                    _ = self.continuation?.yield(bucket)
                }
            } else {
                emptyDeliveryCount += 1
                if emptyDeliveryCount >= 20 {
                    self.continuation?.finish()
                }
            }
        }
        deliveryTimer = timer
        timer.resume()
    }

    private func startProcessExitMonitoring(pid: pid_t) {
        let source = DispatchSource.makeProcessSource(
            identifier: pid,
            eventMask: .exit,
            queue: controlQueue
        )
        source.setEventHandler { [weak self] in
            self?.continuation?.finish()
        }
        processExitSource = source
        source.resume()
    }

    private func musicAudioProcess() throws -> (pid: pid_t, objectID: AudioObjectID) {
        guard let pid = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.Music")
            .first?
            .processIdentifier else {
            throw AppleMusicWaveformError.musicUnavailable
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var qualifier = pid
        var processID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<pid_t>.size),
                &qualifier,
                &size,
                &processID
            ),
            operation: "resolve Music audio process"
        )
        guard processID != kAudioObjectUnknown else {
            throw AppleMusicWaveformError.musicUnavailable
        }
        return (pid, processID)
    }

    private func stringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> CFString {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value),
            operation: "read Core Audio property \(selector)"
        )
        guard let value else {
            throw AppleMusicWaveformError.coreAudio(
                operation: "read Core Audio property \(selector)",
                status: kAudioHardwareUnspecifiedError
            )
        }
        return value.takeRetainedValue()
    }

    private func audioFormatProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value),
            operation: "read Core Audio property \(selector)"
        )
        return value
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status != noErr else { return }
        if status == kAudioDevicePermissionsError {
            throw AppleMusicWaveformError.permissionDenied
        }
        throw AppleMusicWaveformError.coreAudio(operation: operation, status: status)
    }
}

@MainActor
final class WaveformCoordinator {
    private let source: any WaveformSource
    private let timeSource: any MonotonicTimeSource
    private var processor = WaveformSpectrumProcessor()
    private var lifecycleTask: Task<Void, Never>?
    private var consumerTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var lastPublishedAt: TimeInterval?
    private var startBlockedUntilConditionsChange = false
    private var lastShouldCapture = false

    private(set) var state: WaveformCaptureState = .disabled {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }
    var onStateChange: ((WaveformCaptureState) -> Void)?

    init(
        source: any WaveformSource,
        timeSource: any MonotonicTimeSource = ContinuousClockTimeSource()
    ) {
        self.source = source
        self.timeSource = timeSource
    }

    func reconcile(
        enabled: Bool,
        panelVisible: Bool,
        collapsed: Bool,
        playbackState: PlaybackState?
    ) {
        let shouldCapture = enabled
            && panelVisible
            && !collapsed
            && playbackState == .playing

        if shouldCapture != lastShouldCapture {
            startBlockedUntilConditionsChange = false
            lastShouldCapture = shouldCapture
        }

        if shouldCapture {
            guard consumerTask == nil,
                  lifecycleTask == nil,
                  !startBlockedUntilConditionsChange else { return }
            startCapture()
            return
        }

        if enabled, case .unavailable = state,
           consumerTask == nil, lifecycleTask == nil {
            return
        }

        let nextState: WaveformCaptureState
        if enabled, playbackState == .paused {
            nextState = .paused(state.frame)
        } else {
            nextState = .disabled
        }
        stopCapture(nextState: nextState)
    }

    func waitForLifecycleForTesting() async {
        await lifecycleTask?.value
    }

    func shutdown() async {
        lastShouldCapture = false
        startBlockedUntilConditionsChange = false
        stopCapture(nextState: .disabled)
        await lifecycleTask?.value
    }

    private func startCapture() {
        generation &+= 1
        let currentGeneration = generation
        processor = WaveformSpectrumProcessor()
        lastPublishedAt = nil
        state = .starting

        lifecycleTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await source.start()
                guard currentGeneration == generation else { return }
                lifecycleTask = nil
                let emptyFrame = WaveformFrame(
                    levels: Array(repeating: 0, count: WaveformSpectrumProcessor.columnCount)
                )
                state = .running(emptyFrame)
                consume(stream, generation: currentGeneration)
            } catch {
                guard currentGeneration == generation else { return }
                lifecycleTask = nil
                startBlockedUntilConditionsChange = true
                state = .unavailable(Self.unavailableReason(for: error))
            }
        }
    }

    private func consume(
        _ stream: AsyncStream<WaveformBucket>,
        generation: UInt64
    ) {
        consumerTask = Task { [weak self] in
            guard let self else { return }
            for await bucket in stream {
                guard !Task.isCancelled, generation == self.generation else { return }
                let now = self.timeSource.now()
                if let lastPublishedAt = self.lastPublishedAt,
                   now - lastPublishedAt < WaveformSpectrumProcessor.updateInterval * 0.9 {
                    continue
                }
                self.lastPublishedAt = now
                self.state = .running(self.processor.consume(bucket))
            }
            guard !Task.isCancelled, generation == self.generation else { return }
            await self.source.stop()
            guard !Task.isCancelled, generation == self.generation else { return }
            self.consumerTask = nil
            self.startBlockedUntilConditionsChange = true
            self.state = .unavailable(.captureFailed("Audio stream ended"))
        }
    }

    private func stopCapture(nextState: WaveformCaptureState) {
        if consumerTask == nil, lifecycleTask == nil {
            state = nextState
            return
        }

        generation &+= 1
        consumerTask?.cancel()
        consumerTask = nil
        lifecycleTask?.cancel()
        lifecycleTask = Task { [weak self] in
            guard let self else { return }
            await source.stop()
            lifecycleTask = nil
            if lastShouldCapture, !startBlockedUntilConditionsChange {
                startCapture()
            } else {
                state = nextState
            }
        }
    }

    private static func unavailableReason(for error: Error) -> WaveformUnavailableReason {
        guard let error = error as? AppleMusicWaveformError else {
            return .captureFailed(String(describing: error))
        }
        switch error {
        case .permissionDenied:
            return .permissionDenied
        case .musicUnavailable:
            return .musicUnavailable
        case .unsupportedFormat:
            return .unsupportedFormat
        case let .coreAudio(operation, status):
            return .captureFailed("\(operation) failed (\(status))")
        }
    }
}
