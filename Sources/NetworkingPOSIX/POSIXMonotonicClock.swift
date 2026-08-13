#if canImport(Darwin) || canImport(Glibc) || canImport(Musl)

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

import NetworkingTime

public struct POSIXMonotonicClock: MonotonicClock, Sendable {
    public static let clockIdentifier: UInt64 = 0x4E45_5457_504F_5349

    public init() {}

    public func now() throws(TimeError) -> MonotonicInstant {
        var value = timespec()
        let result = clock_gettime(CLOCK_MONOTONIC, &value)
        guard result == 0 else {
            throw .backendFailure(code: Int(errno))
        }
        guard let seconds = UInt64(exactly: value.tv_sec),
              let nanoseconds = UInt64(exactly: value.tv_nsec),
              nanoseconds < 1_000_000_000 else {
            throw .backendValueOutOfRange
        }
        guard seconds <= (UInt64.max - nanoseconds) / 1_000_000_000 else {
            throw .arithmeticOverflow
        }
        return MonotonicInstant(
            clockIdentifier: Self.clockIdentifier,
            nanoseconds: seconds * 1_000_000_000 + nanoseconds
        )
    }
}

#endif
