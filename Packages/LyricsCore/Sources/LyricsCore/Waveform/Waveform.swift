import Foundation

public struct WaveformBucket: Sendable, Equatable {
    public let levels: [Float]

    public init(levels: [Float]) {
        self.levels = Self.normalizedLevels(levels)
    }

    private static func normalizedLevels(_ levels: [Float]) -> [Float] {
        let retained = levels.prefix(WaveformFrame.levelCount)
            .map { min(max($0.isFinite ? $0 : 0, 0), 1) }
        return retained + Array(
            repeating: 0,
            count: WaveformFrame.levelCount - retained.count
        )
    }
}

public struct WaveformFrame: Sendable, Equatable {
    public static let levelCount = 24

    public let levels: [Float]

    public init(levels: [Float]) {
        let retained = levels.prefix(Self.levelCount)
            .map { min(max($0.isFinite ? $0 : 0, 0), 1) }
        self.levels = retained + Array(repeating: 0, count: Self.levelCount - retained.count)
    }
}

public enum WaveformUnavailableReason: Sendable, Equatable {
    case permissionDenied
    case musicUnavailable
    case unsupportedFormat
    case captureFailed(String)
}

public enum WaveformCaptureState: Sendable, Equatable {
    case disabled
    case starting
    case running(WaveformFrame)
    case paused(WaveformFrame?)
    case unavailable(WaveformUnavailableReason)

    public var frame: WaveformFrame? {
        switch self {
        case let .running(frame), let .paused(frame?):
            return frame
        case .disabled, .starting, .paused(nil), .unavailable:
            return nil
        }
    }
}

public protocol WaveformSource: Sendable {
    func start() async throws -> AsyncStream<WaveformBucket>
    func stop() async
}

public struct WaveformSpectrumProcessor: Sendable {
    public static let columnCount = WaveformFrame.levelCount
    public static let updateInterval: TimeInterval = 0.05
    public static let minimumFrequency: Float = 20
    public static let maximumFrequency: Float = 20_000

    private static let attackDuration: Float = 0.08
    private static let releaseDuration: Float = 0.20

    private var smoothedLevels = Array(repeating: Float.zero, count: Self.columnCount)

    public init() {}

    public mutating func consume(_ bucket: WaveformBucket) -> WaveformFrame {
        for index in smoothedLevels.indices {
            let target = bucket.levels[index]
            let timeConstant = target > smoothedLevels[index]
                ? Self.attackDuration
                : Self.releaseDuration
            let alpha = 1 - exp(-Float(Self.updateInterval) / timeConstant)
            smoothedLevels[index] += alpha * (target - smoothedLevels[index])
        }
        return WaveformFrame(levels: smoothedLevels)
    }
}
