/// An sRGB color with a linear-alpha channel, all components in 0…1.
///
/// Components are stored as `Double` and are not premultiplied. Premultiplication
/// happens at the framebuffer boundary (see `VNFramebuffer`, M3a).
public struct VNColor: Sendable, Hashable, Codable {
    /// Red component, 0…1.
    public var red: Double
    /// Green component, 0…1.
    public var green: Double
    /// Blue component, 0…1.
    public var blue: Double
    /// Alpha (opacity) component, 0 = fully transparent, 1 = fully opaque.
    public var alpha: Double

    /// Creates a color from sRGB components.
    ///
    /// Values outside 0…1 are accepted but may produce undefined rendering results.
    @inlinable public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    // MARK: - Named colors

    public static let black   = VNColor(red: 0,   green: 0,   blue: 0)
    public static let white   = VNColor(red: 1,   green: 1,   blue: 1)
    public static let clear   = VNColor(red: 0,   green: 0,   blue: 0,   alpha: 0)
    public static let red     = VNColor(red: 1,   green: 0,   blue: 0)
    public static let green   = VNColor(red: 0,   green: 1,   blue: 0)
    public static let blue    = VNColor(red: 0,   green: 0,   blue: 1)
    public static let yellow  = VNColor(red: 1,   green: 1,   blue: 0)
    public static let cyan    = VNColor(red: 0,   green: 1,   blue: 1)
    public static let magenta = VNColor(red: 1,   green: 0,   blue: 1)
    public static let gray    = VNColor(red: 0.5, green: 0.5, blue: 0.5)

    // MARK: - Derived

    /// Returns the color with alpha multiplied by `factor`.
    @inlinable public func withAlpha(_ a: Double) -> VNColor {
        VNColor(red: red, green: green, blue: blue, alpha: a)
    }

    /// Returns the premultiplied-alpha representation (r*a, g*a, b*a, a).
    @inlinable public var premultiplied: VNColor {
        VNColor(red: red * alpha, green: green * alpha, blue: blue * alpha, alpha: alpha)
    }
}

extension VNColor: CustomStringConvertible {
    public var description: String {
        String(format: "rgba(%.3f, %.3f, %.3f, %.3f)", red, green, blue, alpha)
    }
}
