import SwiftUI
import PDFKit
import FolioCore

/// 1px divider in the web border color.
struct FolioHairline: View {
    var vertical = false
    var body: some View {
        Rectangle().fill(FolioTheme.line)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

/// Small count pill used beside titles and tabs.
struct FolioCountBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)").font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(FolioTheme.badgeInk)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(FolioTheme.badge, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Quiet underline tab row (web sidebar tabs).
struct FolioUnderlineTabs: View {
    struct Item: Identifiable { let id: String; let title: String; var count: Int? = nil }
    let items: [Item]
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 18) {
            ForEach(items) { item in
                let active = item.id == selection
                Button { selection = item.id } label: {
                    HStack(spacing: 6) {
                        Text(item.title).font(.system(size: 13, weight: active ? .semibold : .regular))
                        if let count = item.count { FolioCountBadge(count: count) }
                    }
                    .foregroundStyle(active ? FolioTheme.tabActiveInk : FolioTheme.tabInk)
                    .padding(.bottom, 7)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(active ? FolioTheme.tabActiveLine : .clear).frame(height: 2)
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(active ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) { FolioHairline().opacity(0.7) }
    }
}

/// Uppercase tracked section title with optional count badge.
struct FolioSectionTitle: View {
    let title: String
    var count: Int? = nil
    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(1.6)
                .foregroundStyle(FolioTheme.sectionTitle).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let count { FolioCountBadge(count: count) }
        }
    }
}

/// Left document sidebar: section title, Pages / Outline underline tabs, compact page rows and outline rows.
struct DocumentSidebar: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var reader: ReaderState
    @State private var tab = "pages"
    private static let cache = NSCache<NSString, NSImage>()

    private var pageCount: Int { workspace.document?.pageCount ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FolioSectionTitle(title: tab == "pages" ? "Pages" : "Outline", count: tab == "pages" ? pageCount : nil)
            FolioUnderlineTabs(items: [.init(id: "pages", title: "Pages"), .init(id: "outline", title: "Outline")], selection: $tab)
            if tab == "pages" { pages } else { outline }
        }
        .padding(.horizontal, 15).padding(.top, 22).padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FolioTheme.panelLeft)
    }

    private var pages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(1..<(max(pageCount, 1) + 1), id: \.self) { number in
                        PageRow(workspace: workspace, number: number, thumbnail: thumbnail(number))
                            .id(number)
                    }
                }.padding(.vertical, 2)
            }
            .onChange(of: workspace.page) { _, value in withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(value) } }
            .onAppear { proxy.scrollTo(workspace.page, anchor: .center) }
        }
    }

    private func thumbnail(_ number: Int) -> NSImage? {
        guard let page = workspace.document?.page(at: number - 1) else { return nil }
        let key = "\(workspace.activeID?.uuidString ?? "")-\(number)-\(page.rotation)-\(workspace.revision)" as NSString
        if let cached = Self.cache.object(forKey: key) { return cached }
        let made = page.thumbnail(of: CGSize(width: 70, height: 92), for: .cropBox)
        Self.cache.setObject(made, forKey: key)
        return made
    }

    private struct OutlineRow: Identifiable { let id: Int; let label: String; let depth: Int; let destination: PDFDestination? }

    private var outlineRows: [OutlineRow] {
        guard let root = workspace.document?.outlineRoot else { return [] }
        var rows: [OutlineRow] = []
        func walk(_ node: PDFOutline, _ depth: Int) {
            guard rows.count < 600 else { return }
            for index in 0..<node.numberOfChildren {
                guard let child = node.child(at: index) else { continue }
                rows.append(OutlineRow(id: rows.count, label: child.label ?? "Untitled section", depth: depth,
                                       destination: child.destination ?? (child.action as? PDFActionGoTo)?.destination))
                walk(child, depth + 1)
            }
        }
        walk(root, 0)
        return rows
    }

    @ViewBuilder private var outline: some View {
        let rows = outlineRows
        if rows.isEmpty {
            Text("This PDF has no embedded outline. Use Pages to navigate.")
                .font(.system(size: 12)).foregroundStyle(FolioTheme.muted).padding(.vertical, 8)
            Spacer(minLength: 0)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        Button { if let destination = row.destination { workspace.pdfView?.go(to: destination) } } label: {
                            Text(row.label).font(.system(size: 13)).foregroundStyle(FolioTheme.rowInk).lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .padding(.leading, CGFloat(row.depth) * 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        FolioHairline().opacity(0.45)
                    }
                }
            }
        }
    }
}

private struct PageRow: View {
    @ObservedObject var workspace: Workspace
    let number: Int
    let thumbnail: NSImage?
    @State private var hovering = false

    private var annotated: Bool {
        _ = workspace.revision
        return workspace.document?.page(at: number - 1)?.annotations.contains { PDFEditing.editable($0) } == true
    }

    var body: some View {
        let active = number == workspace.page
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        Button { workspace.go(to: number) } label: {
            HStack(spacing: 11) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let thumbnail { Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit) }
                        else { Color.white }
                    }
                    .frame(width: 35, height: 46).background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(FolioTheme.line, lineWidth: 1))
                    if annotated {
                        RoundedRectangle(cornerRadius: 1).fill(Color(AnnotationPalette.web("yellow"))).frame(width: 9, height: 3)
                            .padding(3).accessibilityHidden(true)
                    }
                }
                Text("Page \(number)").font(.system(size: 13, weight: active ? .medium : .regular))
                    .foregroundStyle(active ? FolioTheme.rowActiveInk : FolioTheme.rowInk)
                Spacer(minLength: 0)
                if workspace.activePaper?.starredPages.contains(number) == true {
                    Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Color(AnnotationPalette.web("yellow")))
                        .accessibilityLabel("Starred")
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(shape.fill(active ? FolioTheme.rowActive : hovering ? FolioTheme.rowHover : .clear))
            .overlay(shape.strokeBorder(active ? FolioTheme.rowActiveLine : .clear))
            .contentShape(shape)
        }.buttonStyle(.plain).onHover { hovering = $0 }
            .accessibilityLabel("Page \(number)").accessibilityAddTraits(active ? .isSelected : [])
    }
}
