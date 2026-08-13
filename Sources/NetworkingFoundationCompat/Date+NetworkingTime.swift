#if canImport(Foundation) && !hasFeature(Embedded)

import Foundation
import NetworkingTime

extension Date {
    public init(_ instant: UnixInstant) {
        let seconds = TimeInterval(instant.secondsSinceUnixEpoch)
        let fraction = TimeInterval(instant.nanoseconds) / 1_000_000_000
        self.init(timeIntervalSince1970: seconds + fraction)
    }

    public func networkingUnixInstant() throws(TimeError) -> UnixInstant {
        let value = timeIntervalSince1970
        guard value.isFinite else {
            throw .backendValueOutOfRange
        }
        let secondsValue = value.rounded(.down)
        guard secondsValue >= TimeInterval(Int64.min),
              secondsValue <= TimeInterval(Int64.max),
              let seconds = Int64(exactly: secondsValue) else {
            throw .backendValueOutOfRange
        }
        let fraction = value - secondsValue
        let nanosValue = (fraction * 1_000_000_000).rounded()
        guard nanosValue >= 0, nanosValue < 1_000_000_000,
              let nanoseconds = UInt32(exactly: nanosValue) else {
            throw .backendValueOutOfRange
        }
        return try UnixInstant(
            secondsSinceUnixEpoch: seconds,
            nanoseconds: nanoseconds
        )
    }
}

#endif
