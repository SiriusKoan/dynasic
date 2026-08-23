import Foundation

@MainActor
final class AppUpdateScheduler {
    private let observationInterval: Duration
    private let displayInterval: Duration
    private var observationTask: Task<Void, Never>?
    private var displayTask: Task<Void, Never>?

    init(
        observationInterval: Duration = .seconds(1),
        displayInterval: Duration = .milliseconds(100)
    ) {
        self.observationInterval = observationInterval
        self.displayInterval = displayInterval
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
        refreshDisplay: @escaping @MainActor () async -> Void
    ) {
        guard observationTask == nil else { return }

        let clock = ContinuousClock()
        observationTask = Task {
            var nextObservation = clock.now
            while !Task.isCancelled {
                do {
                    try await clock.sleep(until: nextObservation)
                } catch {
                    break
                }
                await observe()
                nextObservation += observationInterval
                if nextObservation < clock.now {
                    nextObservation = clock.now + observationInterval
                }
            }
        }

        displayTask = Task {
            while !Task.isCancelled {
                await refreshDisplay()
                do {
                    try await clock.sleep(for: displayInterval)
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
