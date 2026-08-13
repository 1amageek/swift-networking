#if canImport(WASILibc)

import NetworkingTime
import WASILibc

public struct WASIMonotonicClock: MonotonicClock, Sendable {
    public static let clockIdentifier: UInt64 = 0x4E45_5457_5741_5349

    public init() {}

    public func now() throws(TimeError) -> MonotonicInstant {
        var ticks: __wasi_timestamp_t = 0
        let result = __wasi_clock_time_get(__wasi_clockid_t(1), 1, &ticks)
        guard result == 0 else {
            throw .backendFailure(code: Int(result))
        }
        return MonotonicInstant(
            clockIdentifier: Self.clockIdentifier,
            nanoseconds: UInt64(ticks)
        )
    }
}

public struct WASIWallClock: WallClock, Sendable {
    public init() {}

    public func now() throws(TimeError) -> UnixInstant {
        var ticks: __wasi_timestamp_t = 0
        let result = __wasi_clock_time_get(__wasi_clockid_t(0), 1, &ticks)
        guard result == 0 else {
            throw .backendFailure(code: Int(result))
        }
        let seconds = ticks / 1_000_000_000
        guard let canonicalSeconds = Int64(exactly: seconds) else {
            throw .backendValueOutOfRange
        }
        return try UnixInstant(
            secondsSinceUnixEpoch: canonicalSeconds,
            nanoseconds: UInt32(ticks % 1_000_000_000)
        )
    }
}

#endif
