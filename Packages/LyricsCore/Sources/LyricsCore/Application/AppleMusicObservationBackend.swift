public protocol AppleMusicObservationBackend: Sendable {
    func snapshot() async throws -> PlaybackSnapshot
}
