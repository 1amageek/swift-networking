public enum DatagramOverflowPolicy: Sendable, Hashable {
    case dropNewest
    case dropOldest
    case failTransport
}
