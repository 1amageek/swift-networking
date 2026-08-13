public enum TLSEncryptionLevel: Sendable, Hashable, CaseIterable {
    case initial
    case earlyData
    case handshake
    case application
}
