/// End-cap style for stroked open paths.
public enum VNLineCap: Sendable, Hashable {
    case butt    // flat cut at endpoint
    case round   // semicircle centred at endpoint
    case square  // flat cut extended by half the line width
}

/// Corner-join style for stroked paths.
public enum VNLineJoin: Sendable, Hashable {
    case miter   // pointed join; falls back to bevel when ratio > miterLimit
    case round   // circular arc
    case bevel   // flat triangle
}
