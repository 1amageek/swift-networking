/// Nanoseconds on one explicitly identified monotonic clock domain.
public struct MonotonicInstant: Sendable, Hashable {
    public let clockIdentifier: UInt64
    public let nanoseconds: UInt64

    public init(clockIdentifier: UInt64, nanoseconds: UInt64) {
        self.clockIdentifier = clockIdentifier
        self.nanoseconds = nanoseconds
    }

    public func durationNanoseconds(
        since earlier: MonotonicInstant
    ) throws(TimeError) -> UInt64 {
        guard clockIdentifier == earlier.clockIdentifier else {
            throw .clockDomainMismatch(
                expected: clockIdentifier,
                actual: earlier.clockIdentifier
            )
        }
        guard nanoseconds >= earlier.nanoseconds else {
            throw .movedBackwards
        }
        return nanoseconds - earlier.nanoseconds
    }

    public func advanced(byNanoseconds delta: UInt64) throws(TimeError) -> Self {
        let (value, overflow) = nanoseconds.addingReportingOverflow(delta)
        guard !overflow else {
            throw .arithmeticOverflow
        }
        return Self(clockIdentifier: clockIdentifier, nanoseconds: value)
    }
}
