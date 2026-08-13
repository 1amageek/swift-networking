#if !hasFeature(Embedded)

import _Concurrency

/// A native standard-library timer backed by `ContinuousClock`.
public struct ContinuousAsyncTimer: AsyncTimer, Sendable {
    private static let clockIdentifier: UInt64 = 0x4E45_5457_434F_4E54
    private static let origin = ContinuousClock.now

    public init() {}

    public func now() throws(TimeError) -> MonotonicInstant {
        // Force the shared origin to initialize before sampling the current time.
        // Reversing this order can produce a negative duration on the first call
        // because Swift evaluates the left operand before lazily initializing the
        // static property used by the right operand.
        let origin = Self.origin
        let current = ContinuousClock.now
        let elapsed = current - origin
        let components = elapsed.components
        guard components.seconds >= 0, components.attoseconds >= 0 else {
            throw .movedBackwards
        }
        guard let seconds = UInt64(exactly: components.seconds) else {
            throw .backendValueOutOfRange
        }
        let nanosecondRemainder = UInt64(components.attoseconds / 1_000_000_000)
        guard seconds <= (UInt64.max - nanosecondRemainder) / 1_000_000_000 else {
            throw .arithmeticOverflow
        }
        return MonotonicInstant(
            clockIdentifier: Self.clockIdentifier,
            nanoseconds: seconds * 1_000_000_000 + nanosecondRemainder
        )
    }

    public func sleep(until deadline: MonotonicInstant) async throws(TimeError) {
        guard deadline.clockIdentifier == Self.clockIdentifier else {
            throw .clockDomainMismatch(
                expected: Self.clockIdentifier,
                actual: deadline.clockIdentifier
            )
        }
        let current = try now()
        guard deadline.nanoseconds > current.nanoseconds else {
            return
        }
        let wait = deadline.nanoseconds - current.nanoseconds
        do {
            // The nanosecond runtime timer is cancellation-aware on every
            // supported native executor. The generic Clock overload did not
            // promptly resume after sibling-task cancellation in the pinned
            // Swift 6.4 snapshot, which could turn a completed protocol event
            // into a false deadline result while a task group waited for it.
            try await Task<Never, Never>.sleep(nanoseconds: wait)
        } catch {
            throw .cancelled
        }
    }
}

#endif
