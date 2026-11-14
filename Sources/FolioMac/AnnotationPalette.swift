import AppKit

/// Single source of truth for annotation colors: toolbar swatches, the active tool color and the
/// color written into new highlight, underline and text annotations all come from here.
/// Values are the web app's: highlight fills drawn at opacity .43 with multiply blending,
/// underlines in the same color, and darker inks for free text.
enum AnnotationPalette {
    static let names = ["yellow", "green", "blue", "pink"]
    static let defaultsKey = "annotationColor"
    /// Web highlight opacity (multiply).
    static let highlightOpacity: CGFloat = 0.43

    static func normalized(_ name: String?) -> String { names.contains(name ?? "") ? name! : "yellow" }

    static func stored(_ defaults: UserDefaults = .standard) -> String { normalized(defaults.string(forKey: defaultsKey)) }
    static func store(_ name: String, _ defaults: UserDefaults = .standard) { defaults.set(normalized(name), forKey: defaultsKey) }

    private static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    /// Web fill color (swatches, card borders, dots).
    static func web(_ name: String) -> NSColor {
        switch name {
        case "green": hex(0xA8D5B1)
        case "blue": hex(0x9BC4F6)
        case "pink": hex(0xF3B1C1)
        default: hex(0xF6D86A)
        }
    }

    /// Color stored on highlight annotations. PDFKit multiplies the stored color over the page, so this is
    /// the web fill already composited at .43 on white: on a white page it renders exactly like the web.
    static func fill(_ name: String) -> NSColor {
        let base = web(name).usingColorSpace(.sRGB) ?? web(name)
        func lift(_ c: CGFloat) -> CGFloat { 1 - highlightOpacity * (1 - c) }
        return NSColor(srgbRed: lift(base.redComponent), green: lift(base.greenComponent), blue: lift(base.blueComponent), alpha: 1)
    }

    /// Underline color (web: solid fill color at .95).
    static func underline(_ name: String) -> NSColor { web(name).withAlphaComponent(0.95) }

    /// Ink used for free-text annotations (web text inks; red for the pink family).
    static func ink(_ name: String) -> NSColor {
        switch name {
        case "green": hex(0x1E8A3E)
        case "blue": hex(0x1F66D1)
        case "pink": hex(0xD1174A)
        default: hex(0xA87800)
        }
    }

    /// Color a user sees for a highlight of this family on a white PDF page.
    static func rendered(_ name: String) -> NSColor { fill(name) }

    /// Palette family of an annotation color (stored fill, web fill, or a legacy fill); nil if none is close.
    static func name(for color: NSColor) -> String? {
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        func dist(_ o: NSColor) -> CGFloat {
            let o = o.usingColorSpace(.sRGB) ?? o
            return abs(c.redComponent - o.redComponent) + abs(c.greenComponent - o.greenComponent) + abs(c.blueComponent - o.blueComponent)
        }
        return names.map { ($0, min(dist(fill($0)), dist(web($0)))) }.filter { $0.1 < 0.35 }.min { $0.1 < $1.1 }?.0
    }
}
