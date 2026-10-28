import Foundation

protocol AppUpdateClock: Sendable {
    func sleep(for duration: Duration) async throws
}

struct ContinuousAppUpdateClock: AppUpdateClock {
    private let clock = ContinuousClock()

    func sleep(for duration: Duration) async throws {
        try await clock.sleep(for: duration)
    }
}

@MainActor
final class AppUpdateScheduler {
    private let observationInterval: Duration
    private let clock: any AppUpdateClock
    private var observationTask: Task<Void, Never>?
    private var lyricTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var lyricsUpdatesTask: Task<Void, Never>?
    private var refreshLyrics: (@MainActor () async -> Duration?)?

    init(
        observationInterval: Duration = .seconds(1),
        clock: any AppUpdateClock = ContinuousAppUpdateClock()
    ) {
        self.observationInterval = observationInterval
        self.clock = clock
    }

    deinit {
        observationTask?.cancel()
        lyricTask?.cancel()
        progressTask?.cancel()
        lyricsUpdatesTask?.cancel()
    }

    var isRunning: Bool {
        observationTask != nil
    }

    func start(
        observe: @escaping @MainActor () async -> Void,
        refreshLyrics: @escaping @MainActor () async -> Duration?,
        refreshProgress: @escaping @MainActor () async -> Bool,
        lyricsUpdates: @escaping @Sendable () async -> AsyncStream<Void>
    ) {
        guard observationTask == nil else { return }
        self.refreshLyrics = refreshLyrics

        observationTask = Task { [weak self, clock, observationInterval] in
            while !Task.isCancelled {
                await observe()
                guard !Task.isCancelled else { return }
                self?.rescheduleLyrics()
                self?.restartProgress(refreshProgress)
                do {
                    try await clock.sleep(for: observationInterval)
                } catch {
                    break
                }
            }
        }

        lyricsUpdatesTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            let updates = await lyricsUpdates()
            for await _ in updates {
                guard !Task.isCancelled else { return }
                self?.rescheduleLyrics()
            }
        }
    }

    func rescheduleLyrics() {
        lyricTask?.cancel()
        guard isRunning, let refreshLyrics else { return }
        lyricTask = Task { [clock] in
            while !Task.isCancelled {
                guard let delay = await refreshLyrics(), !Task.isCancelled else { return }
                do {
                    try await clock.sleep(for: delay)
                } catch {
                    return
                }
            }
        }
    }

    private func restartProgress(_ refresh: @escaping @MainActor () async -> Bool) {
        progressTask?.cancel()
        progressTask = Task { [clock] in
            while !Task.isCancelled {
                guard await refresh(), !Task.isCancelled else { return }
                do {
                    try await clock.sleep(for: .milliseconds(500))
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        observationTask?.cancel()
        observationTask = nil
        lyricTask?.cancel()
        lyricTask = nil
        progressTask?.cancel()
        progressTask = nil
        lyricsUpdatesTask?.cancel()
        lyricsUpdatesTask = nil
        refreshLyrics = nil
    }
}
