public protocol MonotonicClock: Sendable {
    func now() throws(TimeError) -> MonotonicInstant
}
