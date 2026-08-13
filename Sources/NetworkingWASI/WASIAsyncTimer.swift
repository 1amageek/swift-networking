#if canImport(WASILibc)

import _Concurrency
import NetworkingTime
import WASILibc

/// A WASI monotonic timer using bounded `poll_oneoff` clock subscriptions.
public struct WASIAsyncTimer: AsyncTimer, Sendable {
    private static let cancellationSliceNanoseconds: UInt64 = 5_000_000
    private let clock = WASIMonotonicClock()

    public init() {}

    public func now() throws(TimeError) -> MonotonicInstant {
        try clock.now()
    }

    public func sleep(until deadline: MonotonicInstant) async throws(TimeError) {
        guard deadline.clockIdentifier == WASIMonotonicClock.clockIdentifier else {
            throw .clockDomainMismatch(
                expected: WASIMonotonicClock.clockIdentifier,
                actual: deadline.clockIdentifier
            )
        }

        while true {
            if Task.isCancelled {
                throw .cancelled
            }
            let current = try now()
            guard current.nanoseconds < deadline.nanoseconds else {
                return
            }
            let remaining = deadline.nanoseconds - current.nanoseconds
            try Self.sleepSlice(
                Swift.min(remaining, Self.cancellationSliceNanoseconds)
            )
            await Task.yield()
        }
    }

    private static func sleepSlice(_ nanoseconds: UInt64) throws(TimeError) {
        var subscription = __wasi_subscription_t()
        subscription.userdata = 0
        subscription.u.tag = __wasi_eventtype_t(0)
        subscription.u.u.clock.id = __wasi_clockid_t(1)
        subscription.u.u.clock.timeout = __wasi_timestamp_t(nanoseconds)
        subscription.u.u.clock.precision = 1
        subscription.u.u.clock.flags = 0

        var event = __wasi_event_t()
        var eventCount: __wasi_size_t = 0
        let result = __wasi_poll_oneoff(&subscription, &event, 1, &eventCount)
        guard result == 0 else {
            throw .backendFailure(code: Int(result))
        }
        guard eventCount == 1 else {
            throw .unavailable
        }
        guard event.error == 0 else {
            throw .backendFailure(code: Int(event.error))
        }
    }
}

#endif
