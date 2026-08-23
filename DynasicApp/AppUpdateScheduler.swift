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
    private var displayTask: Task<Void, Never>?

    init(
        observationInterval: Duration = .seconds(1),
        clock: any AppUpdateClock = ContinuousAppUpdateClock()
    ) {
        self.observationInterval = observationInterval
        self.clock = clock
    }

    deinit {
        observationTask?.cancel()
        displayTask?.cancel()
    }

    var isRunning: Bool {
        observationTask != nil
    }

    func start(
        observe: @escaping @MainActor () async -> Void,
        refreshDisplay: @escaping @MainActor () async -> Duration
    ) {
        guard observationTask == nil else { return }

        observationTask = Task {
            await observe()
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: observationInterval)
                } catch {
                    break
                }
                await observe()
            }
        }

        displayTask = Task {
            while !Task.isCancelled {
                let nextRefresh = await refreshDisplay()
                do {
                    try await clock.sleep(for: nextRefresh)
                } catch {
                    break
                }
            }
        }
    }

    func stop() {
        observationTask?.cancel()
        observationTask = nil
        displayTask?.cancel()
        displayTask = nil
    }
}
