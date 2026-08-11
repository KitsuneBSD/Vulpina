/// Porter-Duff compositing operators.
public enum VNBlendMode: Sendable, Hashable {
    case sourceOver
    case copy
    case sourceIn
    case sourceOut
    case sourceAtop
    case destinationOver
    case destinationIn
    case destinationOut
    case destinationAtop
    case xor
    case plusLighter
    case clear
}
