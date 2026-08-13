import NetworkingCore

/// An opaque owned ALPN protocol identifier.
public struct TLSApplicationProtocol: Sendable, Hashable {
    private let bytes: OwnedBytes

    public init(bytes: consuming ContiguousArray<UInt8>) throws(TLSVocabularyError) {
        guard !bytes.isEmpty, bytes.count <= UInt8.max else {
            throw .invalidLength(actual: bytes.count)
        }
        self.bytes = OwnedBytes(consuming: bytes)
    }

    public var byteCount: Int {
        bytes.count
    }

    public borrowing func withBytes<Result: ~Copyable, Failure: Error>(
        _ body: (Span<UInt8>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        try bytes.withBorrowedBytes(body)
    }
}
