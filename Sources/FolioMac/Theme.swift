import SwiftUI

/// Flat web-style surface: card fill, 1px hairline, small radius, very subtle shadow (no system glass).
private struct FolioGlassModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(cornerRadius, FolioRadius.card), style: .continuous)
        content
            .background(shape.fill(FolioTheme.card))
            .overlay { shape.strokeBorder(FolioTheme.line, lineWidth: 1) }
            .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    }
}

struct FolioBackdrop: View {
    var body: some View {
        FolioTheme.background.ignoresSafeArea()
    }
}

extension View {
    func folioGlass(cornerRadius: CGFloat = 18) -> some View {
        modifier(FolioGlassModifier(cornerRadius: cornerRadius))
    }
}

enum FolioTheme {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
    // Web Folio palette. Light = web light; dark = neutral charcoal (not green-tinted).
    static let background = adaptive(0xF8F9F6, 0x1F2022)
    static let card = adaptive(0xFFFFFF, 0x27282A)
    static let ink = adaptive(0x293B34, 0xE3E5E8)
    static let accent = adaptive(0x284E40, 0xC4C6CA)
    static let line = adaptive(0xD9DFD3, 0x3A3C3F)
    static let canvas = adaptive(0xF0F2EC, 0x1F2022)
    static let muted = adaptive(0x88928B, 0x8A8F97)
    static let strip = adaptive(0xFAFBF8, 0x27282A)
    static let footer = adaptive(0xF8FAF5, 0x27282A)
    static let panelLeft = adaptive(0xFCFDFB, 0x262729)
    static let panelRight = adaptive(0xFDFEFB, 0x252628)
    static let field = adaptive(0xF3F5EF, 0x1F2022)
    static let fieldLine = adaptive(0xE6E9E1, 0x3A3C3F)
    static let sectionTitle = adaptive(0x929B90, 0x8A8F97)
    static let rowHover = adaptive(0xF0F3ED, 0x2F3032)
    static let rowActive = adaptive(0xEDF3E9, 0x333437)
    static let rowActiveLine = adaptive(0xDDE6D5, 0x45474B)
    static let rowActiveInk = adaptive(0x3B5B42, 0xE3E5E8)
    static let rowInk = adaptive(0x7E887C, 0x9A9EA6)
    static let badge = adaptive(0xEEF2E9, 0x333437)
    static let badgeInk = adaptive(0x899584, 0x9A9EA6)
    static let eyebrow = adaptive(0xA0A895, 0x80858D)
    static let panelTitle = adaptive(0x3D573C, 0xDADCE0)
    static let tabInk = adaptive(0xA0AA94, 0x80858D)
    static let tabActiveInk = adaptive(0x465F3E, 0xE3E5E8)
    static let tabActiveLine = adaptive(0x67815B, 0xC4C6CA)
    static let quoteInk = adaptive(0x56634C, 0xC9CCD1)
    static let noteInk = adaptive(0x929D86, 0x9A9EA6)
    static let cardLine = adaptive(0xE6E9DF, 0x3A3C3F)
    static let selectionCard = adaptive(0xF6F8F1, 0x2B2C2F)
    static let selectionCardLine = adaptive(0xD9E3D0, 0x3F4144)
    static let tipBox = adaptive(0xF2F5EC, 0x222326)
    static let tipLine = adaptive(0xE7ECDD, 0x353739)
    static let emptyHeading = adaptive(0x7D8C70, 0xA5A9B0)
    static let pageShadow = Color.black.opacity(0.14)
    /// Toolbar icons: web idle gray; hover wash; active pill with a quiet tint and darker glyph.
    static let iconIdle = adaptive(0x7B887F, 0xA3A7AE)
    static let iconDisabled = adaptive(0xBCC4BE, 0x55585E)
    static let onAccent = adaptive(0xFFFFFF, 0x1F2022)
    static let iconHover = adaptive(0xE9EEE7, 0x333437)
    static let iconActiveBg = adaptive(0xE7EEE6, 0x3A3C40)
    static let iconActiveInk = adaptive(0x35553D, 0xE3E5E8)

    static func heading(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 34, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(FolioTheme.heading(25))
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 370)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(32)
    }
}

// MARK: - Shared design tokens

/// Spacing scale (points). Use these instead of ad-hoc paddings.
enum FolioSpace {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 14
    static let l: CGFloat = 22
    static let xl: CGFloat = 34
}

/// Corner radii. Controls use `control`, quiet cards `card`, hero/glass panels `panel`.
enum FolioRadius {
    static let control: CGFloat = 7
    static let card: CGFloat = 9
    static let panel: CGFloat = 9
}

extension FolioTheme {
    static let error = adaptive(0xB3382C, 0xFF9C8F)
    static let warning = adaptive(0x9A6A12, 0xF2C46D)
    /// Section label above a group (small caps, tracked).
    static func overline(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .bold)).tracking(1.1).foregroundStyle(accent)
    }
}

extension View {
    /// Quiet opaque card: solid card fill, hairline border. For content inside sheets and inspectors.
    func folioCard(radius: CGFloat = FolioRadius.card, fill: Color = FolioTheme.card, padding: CGFloat = FolioSpace.m) -> some View {
        self.padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(FolioTheme.line.opacity(0.8)))
    }

    /// Inset well (editor/code/quote background) that sits inside a card.
    func folioWell(radius: CGFloat = FolioRadius.control, padding: CGFloat = 10) -> some View {
        self.padding(padding)
            .background(FolioTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Standard sheet surface: backdrop gradient that falls back to a flat colour under Reduce Transparency.
    func folioSheetBackground() -> some View {
        background(FolioBackdrop())
    }
}

/// Serif title with optional subtitle and trailing accessory; used as the header of every sheet and section.
struct FolioHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var size: CGFloat = 26
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(alignment: .top, spacing: FolioSpace.m) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(FolioTheme.heading(size)).accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: FolioSpace.m)
            trailing()
        }
    }
}
extension FolioHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, size: CGFloat = 26) {
        self.init(title: title, subtitle: subtitle, size: size, trailing: { EmptyView() })
    }
}

/// Pill used for filters and small tags.
struct FolioChip: View {
    let title: String
    var symbol: String? = nil
    var selected = false
    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .medium)) }
            Text(title).font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(selected ? FolioTheme.accent.opacity(0.16) : FolioTheme.card.opacity(0.7), in: Capsule())
        .overlay(Capsule().strokeBorder(selected ? FolioTheme.accent.opacity(0.5) : FolioTheme.line.opacity(0.7)))
        .foregroundStyle(selected ? FolioTheme.accent : FolioTheme.ink)
    }
}

/// Inline status banner: info / warning / error.
struct FolioNotice: View {
    enum Tone { case info, warning, error }
    let text: String
    var tone: Tone = .info
    private var color: Color { tone == .error ? FolioTheme.error : tone == .warning ? FolioTheme.warning : FolioTheme.accent }
    private var symbol: String { tone == .error ? "exclamationmark.circle.fill" : tone == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill" }
    var body: some View {
        Label { Text(text).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            icon: { Image(systemName: symbol).foregroundStyle(color) }
            .padding(FolioSpace.m)
            .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: FolioRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: FolioRadius.card, style: .continuous).strokeBorder(color.opacity(0.25)))
    }
}

/// Primary (filled forest) button for custom surfaces; system `.borderedProminent` is used elsewhere.
struct FolioSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(FolioTheme.card.opacity(configuration.isPressed ? 1 : 0.8), in: Capsule())
            .overlay(Capsule().strokeBorder(FolioTheme.line.opacity(0.8)))
            .foregroundStyle(FolioTheme.ink)
    }
}
