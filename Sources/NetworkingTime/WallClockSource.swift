/// A provider-independent wall-clock value.
///
/// The concrete clock is captured once at a dependency-injection boundary. Calls
/// preserve the original typed failure contract and do not fall back to another
/// time source.
public struct WallClockSource: WallClock, Sendable {
    private let read: @Sendable () throws(TimeError) -> UnixInstant

    public init<Clock: WallClock>(_ clock: Clock) {
        self.read = { () throws(TimeError) -> UnixInstant in
            try clock.now()
        }
    }

    public func now() throws(TimeError) -> UnixInstant {
        try read()
    }
}
