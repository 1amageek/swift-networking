#if canImport(Foundation) && !hasFeature(Embedded)

import Foundation
import NetworkingCore

extension Data {
    /// Copies networking-owned bytes into Foundation storage.
    public init(copying bytes: borrowing OwnedBytes) {
        self = bytes.withBorrowedBytes { span in
            span.bytes.withUnsafeBytes { source in
                guard let baseAddress = source.baseAddress else {
                    return Data()
                }
                return Data(bytes: baseAddress, count: source.count)
            }
        }
    }
}

extension OwnedBytes {
    /// Copies Foundation storage into the canonical networking owner.
    public init(copying data: Data) {
        self.init(consuming: ContiguousArray(data))
    }
}

#endif
