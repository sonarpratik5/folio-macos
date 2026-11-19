import SwiftUI

// Internal render-fixture override; normal app behavior always follows macOS settings.
private struct FolioOpaqueSurfacesKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var folioOpaqueSurfaces: Bool {
        get { self[FolioOpaqueSurfacesKey.self] }
        set { self[FolioOpaqueSurfacesKey.self] = newValue }
    }
}

/// Readable content surfaces stay opaque; glass belongs to navigation and controls.
private struct FolioGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(FolioTheme.card))
            .overlay { shape.strokeBorder(contrast == .increased ? FolioTheme.muted : FolioTheme.line, lineWidth: 1) }
            .shadow(color: FolioTheme.surfaceShadow, radius: 10, x: 0, y: 3)
    }
}

/// A single regular-glass layer per functional region, with a macOS 14/15 material fallback.
private struct FolioChromeModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.folioOpaqueSurfaces) private var forceOpaque
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                if forceOpaque || reduceTransparency || contrast == .increased {
                    shape.fill(FolioTheme.panelLeft)
                } else {
                    material(shape)
                }
            }
            .overlay { shape.strokeBorder(contrast == .increased ? FolioTheme.muted : FolioTheme.glassEdge, lineWidth: 1) }
    }
    @ViewBuilder private func material(_ shape: RoundedRectangle) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.regularMaterial).overlay(shape.fill(FolioTheme.panelLeft.opacity(0.55)))
        }
        #else
        shape.fill(.regularMaterial).overlay(shape.fill(FolioTheme.panelLeft.opacity(0.55)))
        #endif
    }
}

private struct FolioSidebarModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.folioOpaqueSurfaces) private var forceOpaque
    func body(content: Content) -> some View {
        content.background {
            if forceOpaque || reduceTransparency || contrast == .increased {
                FolioTheme.panelLeft
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
    }
}

struct FolioBackdrop: View {
    var body: some View {
        FolioTheme.background.ignoresSafeArea().allowsHitTesting(false)
    }
}

extension View {
    // Existing call sites use this for content cards, deliberately without Liquid Glass.
    func folioGlass(cornerRadius: CGFloat = FolioRadius.panel) -> some View {
        modifier(FolioGlassModifier(cornerRadius: cornerRadius))
    }
    func folioSidebar() -> some View { modifier(FolioSidebarModifier()) }
    func folioChrome(cornerRadius: CGFloat = 0) -> some View {
        modifier(FolioChromeModifier(cornerRadius: cornerRadius))
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
    // Neutral native surfaces; color is reserved for actions and selection.
    static let background = adaptive(0xF5F5F7, 0x1C1C1E)
    static let card = adaptive(0xFFFFFF, 0x2C2C2E)
    static let ink = adaptive(0x1D1D1F, 0xF5F5F7)
    static let accent = adaptive(0x0057C2, 0x90BEFF)
    static let line = adaptive(0xDADDE3, 0x48484D)
    static let canvas = adaptive(0xECEEF2, 0x161618)
    static let muted = adaptive(0x60646C, 0xB9BBC3)
    static let strip = adaptive(0xF9F9FB, 0x2C2C2E)
    static let footer = adaptive(0xF5F5F7, 0x242426)
    static let panelLeft = adaptive(0xF0F1F4, 0x29292D)
    static let panelRight = adaptive(0xFAFAFC, 0x242426)
    static let field = adaptive(0xF0F1F4, 0x1C1C1E)
    static let fieldLine = adaptive(0xB5BAC4, 0x737680)
    static let sectionTitle = muted
    static let rowHover = adaptive(0xE6E8EE, 0x39393E)
    static let rowActive = adaptive(0xDFEAFB, 0x2C4160)
    static let rowActiveLine = adaptive(0x9BBBE5, 0x6D91C5)
    static let rowActiveInk = adaptive(0x164A91, 0xE3EEFF)
    static let rowInk = adaptive(0x42464F, 0xD6D7DD)
    static let badge = adaptive(0xE7E9EE, 0x393940)
    static let badgeInk = adaptive(0x515762, 0xD6D9E1)
    static let eyebrow = muted
    static let panelTitle = ink
    static let tabInk = muted
    static let tabActiveInk = accent
    static let tabActiveLine = accent
    static let quoteInk = adaptive(0x42464F, 0xD6D9E1)
    static let noteInk = muted
    static let cardLine = line
    static let selectionCard = adaptive(0xEFF4FC, 0x28364C)
    static let selectionCardLine = adaptive(0xB8CCEA, 0x587499)
    static let tipBox = adaptive(0xF0F1F4, 0x303035)
    static let tipLine = line
    static let emptyHeading = muted
    static let pageShadow = Color.black.opacity(0.16)
    static let iconIdle = adaptive(0x42464F, 0xE0E1E7)
    static let iconDisabled = adaptive(0x969BA5, 0x787C86)
    static let onAccent = adaptive(0xFFFFFF, 0x112744)
    static let iconHover = rowHover
    static let iconActiveBg = rowActive
    static let iconActiveInk = rowActiveInk
    static let glassEdge = adaptive(0xFFFFFF, 0x858590).opacity(0.24)
    static let surfaceShadow = Color.black.opacity(0.025)

    static func heading(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
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
    static let control: CGFloat = 10
    static let card: CGFloat = 12
    static let panel: CGFloat = 16
}

extension FolioTheme {
    static let error = adaptive(0xB3382C, 0xFF9C8F)
    static let warning = adaptive(0x9A6A12, 0xF2C46D)
    /// Quiet section label above a content group.
    static func overline(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(muted)
    }
}

extension View {
    /// Quiet opaque card: solid card fill, hairline border. For content inside sheets and inspectors.
    func folioCard(radius: CGFloat = FolioRadius.card, fill: Color = FolioTheme.card, padding: CGFloat = FolioSpace.m) -> some View {
        self.padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(FolioTheme.line))
    }

    /// Inset well (editor/code/quote background) that sits inside a card.
    func folioWell(radius: CGFloat = FolioRadius.control, padding: CGFloat = 10) -> some View {
        self.padding(padding)
            .background(FolioTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Neutral sheet surface shared with the workspace.
    func folioSheetBackground() -> some View {
        background(FolioBackdrop())
    }
}

/// System title with optional subtitle and trailing accessory; used as the header of every sheet and section.
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
        .background(selected ? FolioTheme.accent.opacity(0.16) : FolioTheme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(selected ? FolioTheme.accent.opacity(0.5) : FolioTheme.line))
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

/// Secondary control with an opaque fill and a clearly defined boundary.
struct FolioSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(configuration.isPressed ? FolioTheme.rowHover : FolioTheme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(FolioTheme.line))
            .foregroundStyle(FolioTheme.ink)
    }
}
