import SwiftUI
import FolioCore

/// Left navigation panel in the web page-link style: flat panel colour, hairline edge, no system material.
struct LibrarySidebar: View {
    @ObservedObject var workspace: Workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FolioWordmark().padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 16)
            Button(action: workspace.choosePDF) {
                Label("Import PDF", systemImage: "folder").font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(FolioPrimaryButtonStyle()).padding(.horizontal, 15).disabled(workspace.repository == nil)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel("Library")
                    ForEach([LibrarySection.all, .opened, .insights]) { navigation($0) }
                    sectionLabel("Saved work").padding(.top, 14)
                    ForEach([LibrarySection.notes, .starred]) { navigation($0) }
                    if let paper = workspace.activePaper {
                        sectionLabel("In your reader").padding(.top, 14)
                        SidebarRow(title: paper.title, symbol: "book.pages", count: nil, active: workspace.reading) {
                            workspace.reading = true
                        }
                    }
                }.padding(.horizontal, 10).padding(.top, 18)
            }
            Rectangle().fill(FolioTheme.line).frame(height: 1).padding(.horizontal, 15)
            VStack(alignment: .leading, spacing: 4) {
                SidebarRow(title: "Sample paper", symbol: "doc.text", count: nil, active: false, action: workspace.sample)
                    .disabled(workspace.repository == nil)
                SettingsLink { SidebarRowLabel(title: "Settings", symbol: "gearshape", count: nil, active: false, hovering: false) }
                    .buttonStyle(.plain)
                Label("Stored on this Mac", systemImage: "internaldrive").font(.system(size: 11)).foregroundStyle(FolioTheme.muted)
                    .padding(.horizontal, 10).padding(.top, 6)
            }.padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FolioTheme.panelLeft.ignoresSafeArea())
        .overlay(alignment: .trailing) { Rectangle().fill(FolioTheme.line).frame(width: 1).ignoresSafeArea() }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(1.6)
            .foregroundStyle(FolioTheme.sectionTitle).padding(.horizontal, 10).padding(.bottom, 4)
    }

    private func navigation(_ item: LibrarySection) -> some View {
        let count: Int? = item == .all ? workspace.papers.count
            : item == .starred ? workspace.papers.reduce(0) { $0 + $1.starredPages.count } : nil
        return SidebarRow(title: item.rawValue, symbol: item.symbol, count: count,
                          active: workspace.section == item && !workspace.reading) {
            workspace.navigate(to: item)
        }
    }
}

private struct SidebarRowLabel: View {
    let title: String, symbol: String, count: Int?, active: Bool, hovering: Bool
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 13)).frame(width: 18)
            Text(title).font(.system(size: 13)).lineLimit(1)
            Spacer(minLength: 4)
            if let count {
                Text("\(count)").font(.system(size: 12).monospacedDigit()).foregroundStyle(FolioTheme.badgeInk)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(FolioTheme.badge, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .foregroundStyle(active ? FolioTheme.rowActiveInk : FolioTheme.rowInk)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(active ? FolioTheme.rowActive : hovering ? FolioTheme.rowHover : .clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(active ? FolioTheme.rowActiveLine : .clear))
        .contentShape(Rectangle())
    }
}

private struct SidebarRow: View {
    let title: String, symbol: String, count: Int?, active: Bool, action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) { SidebarRowLabel(title: title, symbol: symbol, count: count, active: active, hovering: hovering) }
            .buttonStyle(.plain).onHover { hovering = $0 }
            .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Flat serif wordmark like the web brand: small book glyph and bold accent "folio."
struct FolioWordmark: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "book.closed").font(.system(size: 15, weight: .semibold))
            Text("folio.").font(.custom("Georgia", size: 26).weight(.bold))
        }.foregroundStyle(FolioTheme.accent).accessibilityElement(children: .combine).accessibilityLabel("Folio")
    }
}

/// Filled accent button matching the web primary button (accent bg, on-accent text, radius 7).
struct FolioPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(FolioTheme.onAccent)
            .background(FolioTheme.accent.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// Flat determinate progress bar in the accent colour (system ProgressView ignores tint on macOS).
struct FolioProgressBar: View {
    let value: Double
    var total: Double = 1
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(FolioTheme.line)
                Capsule().fill(FolioTheme.accent)
                    .frame(width: proxy.size.width * min(max(total > 0 ? value / total : 0, 0), 1))
            }
        }.frame(height: 4).accessibilityElement().accessibilityValue("\(Int((total > 0 ? value / total : 0) * 100)) percent")
    }
}
