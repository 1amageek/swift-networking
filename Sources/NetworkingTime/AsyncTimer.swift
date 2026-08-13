import _Concurrency

/// A monotonic clock that can suspend until an absolute deadline on its domain.
public protocol AsyncTimer: MonotonicClock {
    func sleep(until deadline: MonotonicInstant) async throws(TimeError)
}
