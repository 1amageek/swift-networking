#if canImport(Darwin) || canImport(Glibc) || canImport(Musl)

import _Concurrency
import NetworkingTime

/// A cancellation-aware POSIX timer using the `CLOCK_MONOTONIC` domain.
public struct POSIXAsyncTimer: AsyncTimer, Sendable {
    private let clock = POSIXMonotonicClock()

    public init() {}

    public func now() throws(TimeError) -> MonotonicInstant {
        try clock.now()
    }

    public func sleep(until deadline: MonotonicInstant) async throws(TimeError) {
        guard deadline.clockIdentifier == POSIXMonotonicClock.clockIdentifier else {
            throw .clockDomainMismatch(
                expected: POSIXMonotonicClock.clockIdentifier,
                actual: deadline.clockIdentifier
            )
        }
        if Task.isCancelled {
            throw .cancelled
        }
        while true {
            if Task.isCancelled {
                throw .cancelled
            }
            let current = try now().nanoseconds
            guard current < deadline.nanoseconds else {
                return
            }
            let remaining = deadline.nanoseconds - current
            do {
                // Swift Concurrency parks the task in the runtime timer queue;
                // no pthread is allocated per waiter. Re-reading CLOCK_MONOTONIC
                // after every wake preserves this timer's absolute clock domain.
                try await Task<Never, Never>.sleep(nanoseconds: remaining)
            } catch is CancellationError {
                throw .cancelled
            } catch {
                // The concurrency runtime does not expose a platform error code
                // for an unexpected timer failure.
                throw .backendFailure(code: -1)
            }
        }
    }
}

#endif
