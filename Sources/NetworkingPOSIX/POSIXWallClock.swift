#if canImport(Darwin) || canImport(Glibc) || canImport(Musl)

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

import NetworkingTime

public struct POSIXWallClock: WallClock, Sendable {
    public init() {}

    public func now() throws(TimeError) -> UnixInstant {
        var value = timespec()
        let result = clock_gettime(CLOCK_REALTIME, &value)
        guard result == 0 else {
            throw .backendFailure(code: Int(errno))
        }
        guard let seconds = Int64(exactly: value.tv_sec),
              let nanoseconds = UInt32(exactly: value.tv_nsec),
              nanoseconds < 1_000_000_000 else {
            throw .backendValueOutOfRange
        }
        return try UnixInstant(
            secondsSinceUnixEpoch: seconds,
            nanoseconds: nanoseconds
        )
    }
}

#endif
