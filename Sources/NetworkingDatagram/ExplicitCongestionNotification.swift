public enum ExplicitCongestionNotification: UInt8, Sendable, Hashable {
    case notECT = 0
    case ect1 = 1
    case ect0 = 2
    case congestionExperienced = 3
}
