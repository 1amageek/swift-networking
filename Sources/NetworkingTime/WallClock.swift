public protocol WallClock: Sendable {
    func now() throws(TimeError) -> UnixInstant
}
