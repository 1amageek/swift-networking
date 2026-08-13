/// Immutable contiguous byte storage.
///
/// The owner exposes synchronous scoped borrows. A borrowed pointer or `Span`
/// must not escape the accessor closure or cross an `await` boundary.
public struct OwnedBytes: Sendable, Equatable, Hashable {
    private let storage: [UInt8]

    public init() {
        storage = []
    }

    /// Transfers an Array's COW storage into the immutable owner.
    public init(consuming storage: consuming [UInt8]) {
        self.storage = storage
    }

    /// Transfers a ContiguousArray's native COW storage into the canonical
    /// Array owner. The pinned Swift 6.4 toolchain preserves the allocation for
    /// this conversion; pointer-identity tests guard that zero-copy contract.
    public init(consuming storage: consuming ContiguousArray<UInt8>) {
        self.storage = Array(storage)
    }

    public init(copying bytes: Span<UInt8>) {
        var storage = [UInt8]()
        storage.reserveCapacity(bytes.count)
        bytes.bytes.withUnsafeBytes { source in
            storage.append(contentsOf: source)
        }
        self.storage = storage
    }

    public var count: Int {
        storage.count
    }

    public var isEmpty: Bool {
        storage.isEmpty
    }

    public var span: Span<UInt8> {
        @_lifetime(borrow self)
        borrowing get {
            storage.span
        }
    }

    public borrowing func withBorrowedBytes<Result: ~Copyable, Failure: Error>(
        _ body: (Span<UInt8>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        try body(storage.span)
    }

    public subscript(index: Int) -> UInt8 {
        storage[index]
    }

    public func contains(_ range: ByteRange) -> Bool {
        range.endOffset <= storage.count
    }

    @_lifetime(borrow self)
    public func span(in range: ByteRange) throws(ByteError) -> Span<UInt8> {
        guard contains(range) else {
            throw .outOfBounds(
                offset: range.offset,
                requested: range.count,
                available: Swift.max(0, storage.count - range.offset)
            )
        }
        return storage.span.extracting(range.offset..<range.endOffset)
    }
}
