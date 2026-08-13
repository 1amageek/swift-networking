public enum DatagramOperation: Sendable, Hashable {
    case bind
    case send
    case receive
    case shutdown
    case multicast
}
