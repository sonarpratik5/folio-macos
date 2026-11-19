import SwiftUI
import FolioCore

/// Native material sidebar with readable selected rows and opaque accessibility fallback.
struct LibrarySidebar: View {
    @ObservedObject var workspace: Workspace

    var body: some View {
        let counts = folderCounts
        VStack(alignment: .leading, spacing: 0) {
            FolioWordmark().padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 16)
            Button(action: workspace.chooseFolder) {
                Label("Open folder", systemImage: "folder").font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(FolioPrimaryButtonStyle()).padding(.horizontal, 15).disabled(workspace.repository == nil)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel("Folders")
                    ForEach(workspace.folders, id: \.self) { path in
                        SidebarRow(title: URL(fileURLWithPath: path).lastPathComponent, symbol: "folder",
                                   count: counts[path, default: 0],
                                   active: workspace.selectedFolder == path && workspace.section == .all && !workspace.reading) {
                            workspace.selectFolder(path)
                        }
                        .padding(.leading, CGFloat(workspace.folders.filter { path.hasPrefix($0 + "/") }.count) * 10)
                        .help(path)
                        .contextMenu {
                            Button("Refresh folder") { workspace.openFolder(URL(fileURLWithPath: path)) }
                        }
                    }
                    if workspace.folders.isEmpty {
                        Text("Open a folder to browse its PDFs.").font(.system(size: 12)).foregroundStyle(FolioTheme.muted).padding(.horizontal, 10).padding(.vertical, 6)
                    }
                    sectionLabel("Quick access").padding(.top, 14)
                    navigation(.opened)
                    ForEach(Array(workspace.recentPapers.filter { $0.title != "A guide to reading research" }.prefix(5))) { paper in
                        SidebarRow(title: paper.title, symbol: "doc.richtext", count: nil,
                                   active: workspace.reading && workspace.activeID == paper.id) { workspace.open(paper) }
                            .help("Resume \(paper.title)")
                    }
                    ForEach([LibrarySection.all, .insights]) { navigation($0) }
                    sectionLabel("Saved work").padding(.top, 14)
                    ForEach([LibrarySection.notes, .starred, .conversations]) { navigation($0) }

                }.padding(.horizontal, 10).padding(.top, 18)
            }
            Rectangle().fill(FolioTheme.line).frame(height: 1).padding(.horizontal, 15)
            VStack(alignment: .leading, spacing: 4) {
                SettingsLink { SidebarRowLabel(title: "Settings", symbol: "gearshape", count: nil, active: false, hovering: false) }
                    .buttonStyle(.plain)
                Label("Stored on this Mac", systemImage: "internaldrive").font(.system(size: 11)).foregroundStyle(FolioTheme.muted)
                    .padding(.horizontal, 10).padding(.top, 6)
            }.padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .folioSidebar()

    }

    private var folderCounts: [String: Int] {
        let folders = Set(workspace.folders)
        var counts: [String: Int] = [:]
        for paper in workspace.papers {
            guard let path = paper.folderPath else { continue }
            counts[path, default: 0] += 1
            var parent = URL(fileURLWithPath: path).deletingLastPathComponent()
            while parent.path != path {
                if folders.contains(parent.path) { counts[parent.path, default: 0] += 1 }
                let next = parent.deletingLastPathComponent()
                if next == parent { break }
                parent = next
            }
        }
        return counts
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold))
            .foregroundStyle(FolioTheme.sectionTitle).padding(.horizontal, 10).padding(.bottom, 4)
    }

    private func navigation(_ item: LibrarySection) -> some View {
        let count: Int? = item == .all ? workspace.papers.count
            : item == .starred ? workspace.papers.reduce(0) { $0 + $1.starredPages.count } : nil
        return SidebarRow(title: item.rawValue, symbol: item.symbol, count: count,
                          active: workspace.section == item && !workspace.reading && (item != .all || workspace.selectedFolder == nil)) {
            workspace.navigate(to: item)
        }
    }
}

private struct SidebarRowLabel: View {
    let title: String, symbol: String, count: Int?, active: Bool, hovering: Bool
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 13)).frame(width: 18)
            Text(title).font(.system(size: 14)).lineLimit(1)
            Spacer(minLength: 4)
            if let count {
                Text("\(count)").font(.system(size: 12).monospacedDigit()).foregroundStyle(FolioTheme.badgeInk)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(FolioTheme.badge, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .foregroundStyle(active ? FolioTheme.rowActiveInk : FolioTheme.rowInk)
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(active ? FolioTheme.rowActive : hovering ? FolioTheme.rowHover : .clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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

/// Folio keeps its editorial serif wordmark within the native navigation shell.
struct FolioWordmark: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "book.closed").font(.system(size: 15, weight: .semibold))
            Text("folio.").font(.system(size: 24, weight: .bold, design: .rounded))
        }.foregroundStyle(FolioTheme.ink).accessibilityElement(children: .combine).accessibilityLabel("Folio")
    }
}

/// Solid accent action with a contrasting label in either color mode.
struct FolioPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12).padding(.vertical, 9)
            .foregroundStyle(FolioTheme.onAccent)
            .background(FolioTheme.accent.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
