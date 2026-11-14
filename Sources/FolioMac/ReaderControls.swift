import SwiftUI
import PDFKit
import FolioCore

/// Toolbar icon button: primary-label glyph, hover wash, and an accent pill with a contrasting glyph when active.
struct ReaderIconStyle: ButtonStyle {
    var active = false
    var size: CGFloat = 30
    func makeBody(configuration: Configuration) -> some View {
        IconBody(configuration: configuration, active: active, size: size)
    }
    struct IconBody: View {
        let configuration: ButtonStyleConfiguration
        let active: Bool
        let size: CGFloat
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false
        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
            configuration.label
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(!enabled ? FolioTheme.iconDisabled : active ? FolioTheme.iconActiveInk : FolioTheme.iconIdle)
                .frame(width: size, height: size)
                .background(shape.fill(active ? FolioTheme.iconActiveBg : (hovering && enabled) || configuration.isPressed ? FolioTheme.iconHover : .clear))
                .contentShape(shape)
                .opacity(configuration.isPressed ? 0.8 : 1)
                .onHover { hovering = $0 }
        }
    }
}

/// Compact search field with match count and previous/next, living in the reader toolbar.
struct ReaderSearchField: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var reader: ReaderState
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundStyle(FolioTheme.muted).font(.system(size: 11))
            TextField("Search", text: $reader.query).textFieldStyle(.plain).focused($focused).frame(width: 118)
                .onSubmit {
                    NSApp.currentEvent?.modifierFlags.contains(.shift) == true ? reader.previousMatch() : reader.nextMatch()
                    focused = true
                }
                .onExitCommand { reader.clearSearch(); focused = false; workspace.pdfView.map { $0.window?.makeFirstResponder($0) } }
                .accessibilityLabel("Search in PDF")
            if !reader.query.isEmpty {
                Text(reader.matchLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                Button { reader.previousMatch() } label: { Image(systemName: "chevron.up") }
                    .disabled(!reader.hasMatches).help("Previous match (⇧⌘G)").accessibilityLabel("Previous match")
                Button { reader.nextMatch() } label: { Image(systemName: "chevron.down") }
                    .disabled(!reader.hasMatches).help("Next match (⌘G)").accessibilityLabel("Next match")
                Button { reader.clearSearch() } label: { Image(systemName: "xmark.circle.fill") }
                    .help("Clear search (Esc)").accessibilityLabel("Clear search")
            }
        }
        .buttonStyle(.borderless).font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 8).frame(height: 26)
        .background(FolioTheme.field, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(focused ? FolioTheme.accent.opacity(0.6) : FolioTheme.fieldLine))
        .help("Search this PDF (⌘F)")
        .onChange(of: reader.focusSearchTick) { _, _ in focused = true }
        .onChange(of: workspace.showFind) { _, shown in
            if shown { focused = true; workspace.showFind = false }
        }
    }
}

/// Zoom stepper, fit/rotate/layout menu.
struct ReaderViewControls: View {
    @ObservedObject var reader: ReaderState

    var body: some View {
        HStack(spacing: 2) {
            Button { reader.zoomOut() } label: { Image(systemName: "minus") }
                .help("Zoom out (⌘−)").accessibilityLabel("Zoom out")
            Menu {
                Button("Fit Width") { reader.setFit(.width) }
                Button("Fit Page") { reader.setFit(.page) }
                Button("Actual Size") { reader.setFit(.actual) }
                Divider()
                Button("Rotate Left") { reader.rotate(by: -90) }
                Button("Rotate Right") { reader.rotate(by: 90) }
                Divider()
                Picker("Page Layout", selection: Binding(get: { reader.layout }, set: reader.setLayout)) {
                    ForEach(ReaderLayout.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }.pickerStyle(.inline)
            } label: {
                Text("\(reader.zoomPercent)%").font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(FolioTheme.iconIdle).frame(minWidth: 38)
            }.menuStyle(.borderlessButton).fixedSize().help("Fit, rotate and page layout").accessibilityLabel("Zoom, fit and layout")
            Button { reader.zoomIn() } label: { Image(systemName: "plus") }
                .help("Zoom in (⌘+)").accessibilityLabel("Zoom in")
            FolioHairline(vertical: true).frame(height: 14).padding(.horizontal, 4)
            Button { reader.setFit(reader.fit == .width ? .page : .width) } label: {
                Image(systemName: reader.fit == .width ? "arrow.up.and.down.text.horizontal" : "arrow.left.and.right")
            }.help(reader.fit == .width ? "Fit page (⌘8)" : "Fit width (⌘9)").accessibilityLabel("Toggle fit width and fit page")
            Button { reader.rotate(by: 90) } label: { Image(systemName: "rotate.right") }
                .help("Rotate view right (⌥⌘R). The PDF file is not changed.").accessibilityLabel("Rotate view right")
        }.buttonStyle(ReaderIconStyle(size: 28))
    }
}
