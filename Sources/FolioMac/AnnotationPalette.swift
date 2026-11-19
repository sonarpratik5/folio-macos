import AppKit

/// Single source of truth for annotation colors: toolbar swatches, the active tool color and the
/// color written into new highlight, underline and text annotations all come from here.
/// Highlight RGB values match Apple's AnnotationKit highlight palette used by Preview.
/// These constants are copied into the app; no private framework is used at runtime.
enum AnnotationPalette {
    static let names = ["yellow", "green", "blue", "pink"]
    static let defaultsKey = "annotationColor"

    static func normalized(_ name: String?) -> String { names.contains(name ?? "") ? name! : "yellow" }

    static func stored(_ defaults: UserDefaults = .standard) -> String { normalized(defaults.string(forKey: defaultsKey)) }
    static func store(_ name: String, _ defaults: UserDefaults = .standard) { defaults.set(normalized(name), forKey: defaultsKey) }

    private static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    /// Preview highlight colors, verified against AKHighlightAppearanceHelper tags 765200–765203
    /// and AKAnnotationTheme.plist on the development Mac (2026-11-15).
    static func swatch(_ name: String) -> NSColor {
        switch name {
        case "green": hex(0x7CC868)
        case "blue": hex(0x69B0F1)
        case "pink": hex(0xFB5C89)
        default: hex(0xFACD5A)
        }
    }

    /// Previous web palette, retained for existing annotation recognition and underline colors.
    private static func legacy(_ name: String) -> NSColor {
        switch name {
        case "green": hex(0xA8D5B1)
        case "blue": hex(0x9BC4F6)
        case "pink": hex(0xF3B1C1)
        default: hex(0xF6D86A)
        }
    }

    /// PDFKit supplies highlight multiply blending; store Preview's opaque RGB without fading.
    static func fill(_ name: String) -> NSColor { swatch(name) }

    /// Underline color (web: solid fill color at .95).
    static func underline(_ name: String) -> NSColor { legacy(name).withAlphaComponent(0.95) }

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

    /// Palette family of an annotation color (Preview fill or either previous web fill); nil if none is close.
    static func name(for color: NSColor) -> String? {
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        func dist(_ o: NSColor) -> CGFloat {
            let o = o.usingColorSpace(.sRGB) ?? o
            return abs(c.redComponent - o.redComponent) + abs(c.greenComponent - o.greenComponent) + abs(c.blueComponent - o.blueComponent)
        }
        func previousFill(_ name: String) -> NSColor {
            let base = legacy(name).usingColorSpace(.sRGB)!
            func lift(_ c: CGFloat) -> CGFloat { 1 - 0.43 * (1 - c) }
            return NSColor(srgbRed: lift(base.redComponent), green: lift(base.greenComponent),
                           blue: lift(base.blueComponent), alpha: 1)
        }
        return names.map { ($0, min(dist(fill($0)), dist(legacy($0)), dist(previousFill($0)))) }.filter { $0.1 < 0.35 }.min { $0.1 < $1.1 }?.0
    }
}
