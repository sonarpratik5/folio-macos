import SwiftUI
import FolioCore
import PDFKit
import AppKit

private struct LibraryNoteEntry: Identifiable {
    let paper: PaperRecord
    let note: PaperNote
    var id: String { "\(paper.id.uuidString)-\(note.id)" }
}

struct LibraryView: View {
    private struct NoteScanKey: Equatable {
        let papers: [UUID]
        let session: UUID
        let revision: Int
    }
    private var noteScanKey: NoteScanKey {
        NoteScanKey(papers: workspace.papers.map(\.id), session: workspace.documentSessionID,
                    revision: workspace.revision)
    }
    @ObservedObject var workspace: Workspace
    var onAsk: ((PaperRecord) -> Void)? = nil
    @AppStorage("libraryLayout") private var layout = "list"
    @AppStorage("librarySort") private var sortRaw = LibrarySortOrder.recentlyOpened.rawValue
    @State private var filter: LibraryFilter = .all
    @State private var renaming: PaperRecord?
    @State private var removing: PaperRecord?
    @State private var details: PaperRecord?
    @State private var pendingAssistant: PaperRecord?
    @State private var notesByPaper: [UUID: [PaperNote]] = [:]
    @State private var annotationCounts: [UUID: Int] = [:]

    private var allNotes: [LibraryNoteEntry] {
        workspace.papers.flatMap { paper in
            (notesByPaper[paper.id] ?? []).map { LibraryNoteEntry(paper: paper, note: $0) }
        }
    }

    private var starredPages: [(paper: PaperRecord, page: Int)] {
        workspace.papers.flatMap { paper in paper.starredPages.sorted().map { (paper, $0) } }
            .sorted { lhs, rhs in
                if lhs.paper.lastOpened != rhs.paper.lastOpened { return lhs.paper.lastOpened > rhs.paper.lastOpened }
                if lhs.paper.title != rhs.paper.title { return lhs.paper.title.localizedStandardCompare(rhs.paper.title) == .orderedAscending }
                return lhs.page < rhs.page
            }
    }

    private var sortOrder: LibrarySortOrder { LibrarySortOrder(rawValue: sortRaw) ?? .recentlyOpened }

    private var visible: [PaperRecord] {
        let sectionOrder: LibrarySortOrder = workspace.section == .opened ? .recentlyOpened : sortOrder
        let result = LibraryOrganizer.apply(
            workspace.libraryPapers.filter { workspace.section != .starred || !$0.starredPages.isEmpty },
            query: workspace.libraryQuery, filter: workspace.section == .all ? filter : .all, order: sectionOrder,
            noteCounts: notesByPaper.mapValues(\.count),
            noteText: notesByPaper.mapValues { $0.map(\.body).joined(separator: "\n") })
        return workspace.section == .opened ? result.sorted { $0.lastVisit! > $1.lastVisit! } : result
    }

    private var sectionTitle: String {
        switch workspace.section {
        case .all: workspace.selectedFolder.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "All PDFs"
        case .opened: "Recent"
        case .notes: "Notes"
        case .starred: "Starred pages"
        case .insights: "Insights"
        case .conversations: "Conversations"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if workspace.section == .all, workspace.libraryQuery.isEmpty, let paper = workspace.recentPapers.first(where: { workspace.selectedFolder == nil || $0.folderPath == workspace.selectedFolder }) {
                    continueReading(paper)
                }

                if !workspace.papers.isEmpty { controlsRow }

                if workspace.papers.isEmpty && workspace.selectedFolder == nil && workspace.section == .all {
                    emptyLibrary
                } else if workspace.section == .notes {
                    notesSection
                } else if workspace.section == .starred {
                    starredSection
                } else if visible.isEmpty {
                    emptyResults(symbol: workspace.section.symbol, title: "No matching papers",
                                 detail: hasLibraryConstraints ? "Try another title, a phrase from your notes, or clear your filters." : (workspace.section == .opened ? "PDFs you open in the reader appear here." : "Open a folder or import a PDF."))
                } else if layout == "grid" {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 330))], spacing: 18) {
                        ForEach(visible) { paper in paperCard(paper) }
                    }
                } else {
                    paperList
                }
            }
            .frame(maxWidth: 1120, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.top, 34)
            .padding(.bottom, 50)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.visible)
        .navigationTitle(sectionTitle)
        .task(id: noteScanKey) { loadNotes() }
        .sheet(item: $renaming) { paper in
            RenamePaperSheet(paper: paper) { workspace.renamePaper(paper, to: $0) }
        }
        .confirmRemoval(of: $removing) { workspace.removePaper($0) }
        .sheet(item: $details, onDismiss: {
            if let pendingAssistant {
                self.pendingAssistant = nil
                onAsk?(pendingAssistant)
            }
        }) { paper in
            PaperQuickLook(paper: paper, noteCount: notesByPaper[paper.id]?.count ?? 0,
                           onOpen: { workspace.open(paper); details = nil },
                           onAsk: onAsk.map { _ in { pendingAssistant = paper; details = nil } })
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: FolioSpace.l) {
            VStack(alignment: .leading, spacing: 6) {
                Text(sectionTitle).font(FolioTheme.heading(32)).accessibilityAddTraits(.isHeader)
                if let path = workspace.selectedFolder, workspace.section == .all {
                    Text(path).font(.system(size: 11)).foregroundStyle(FolioTheme.muted).lineLimit(1).truncationMode(.middle).help(path)
                    Button("Refresh folder") { workspace.openFolder(URL(fileURLWithPath: path)) }.buttonStyle(.borderless)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 6) {
                    metric(workspace.libraryPapers.count, "paper", "papers")
                    metric(annotationTotal, "annotation", "annotations")
                    metric(starredPages.count, "saved page", "saved pages")
                }
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    TextField(searchPrompt, text: $workspace.libraryQuery)
                        .textFieldStyle(.plain).accessibilityLabel(searchPrompt)
                    if !workspace.libraryQuery.isEmpty {
                        Button { workspace.libraryQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                            .buttonStyle(.plain).accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 13).padding(.vertical, 9).frame(width: 300)
                .background(FolioTheme.card.opacity(0.8), in: Capsule()).overlay(Capsule().strokeBorder(FolioTheme.line.opacity(0.8)))
            }
        }
    }

    private var searchPrompt: String {
        workspace.section == .notes ? "Search notes and paper titles" : "Search titles and note text"
    }

    private var hasLibraryConstraints: Bool {
        !workspace.libraryQuery.isEmpty || (workspace.section == .all && filter != .all)
    }

    private func emptyResults(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            EmptyState(symbol: symbol, title: title, detail: detail)
            if hasLibraryConstraints {
                Button(workspace.section == .all && filter != .all ? "Clear search and filters" : "Clear search") {
                    workspace.libraryQuery = ""
                    if workspace.section == .all { filter = .all }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48)
    }

    private var annotationTotal: Int { annotationCounts.values.reduce(0, +) }

    private func metric(_ count: Int, _ singular: String, _ plural: String) -> some View {
        HStack(spacing: 4) {
            Text("\(count)").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(FolioTheme.ink)
            Text(count == 1 ? singular : plural).font(.system(size: 11)).foregroundStyle(FolioTheme.muted)
        }
        .padding(.horizontal, 2).padding(.vertical, 3)
    }

    /// One aligned row: filter chips (Library only), count, then sort and layout controls.
    private var controlsRow: some View {
        HStack(alignment: .center, spacing: 8) {
            if workspace.section == .all {
                ForEach(LibraryFilter.allCases) { item in
                    Button { filter = item } label: { FolioChip(title: item.rawValue, selected: filter == item) }
                        .buttonStyle(.plain).accessibilityAddTraits(filter == item ? .isSelected : [])
                }
            }
            Text("\(sectionCount) \(sectionCount == 1 ? "item" : "items")").font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary).padding(.leading, 4)
            Spacer()
            if workspace.section == .all || workspace.section == .opened {
                if workspace.section == .all {
                    Menu {
                        ForEach(LibrarySortOrder.allCases) { order in
                            Button { sortRaw = order.rawValue } label: { sortMenuLabel(order.rawValue, selected: sortOrder == order) }
                        }
                    } label: {
                        Label(sortOrder.rawValue, systemImage: "arrow.up.arrow.down")
                            .font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 6)
                            .background(FolioTheme.card.opacity(0.8), in: Capsule())
                            .overlay(Capsule().strokeBorder(FolioTheme.line.opacity(0.7)))
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Sort papers")
                }
                Picker("Layout", selection: $layout) {
                    Image(systemName: "list.bullet").tag("list")
                    Image(systemName: "square.grid.2x2").tag("grid")
                }
                .pickerStyle(.segmented).frame(width: 84).labelsHidden().accessibilityLabel("Library layout")
            }
        }
    }

    @ViewBuilder private func paperMenu(_ paper: PaperRecord) -> some View {
        Button("Insights") { workspace.showInsights(for: paper) }
        Button { workspace.open(paper) } label: { Label("Open", systemImage: "book.pages") }
        if let onAsk { Button { onAsk(paper) } label: { Label("Ask Folio…", systemImage: "sparkles") } }
        Button { details = paper } label: { Label("Details", systemImage: "info.circle") }
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(paper.title, forType: .string)
        } label: { Label("Copy Title", systemImage: "doc.on.doc") }
        Divider()
        Button { renaming = paper } label: { Label("Rename…", systemImage: "pencil") }
        Button { workspace.revealInFinder(paper) } label: { Label("Show Managed Copy in Finder", systemImage: "folder") }
        Divider()
        Button(role: .destructive) { removing = paper } label: { Label("Remove from Library…", systemImage: "trash") }
    }

    private func sortMenuLabel(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
            if selected { Image(systemName: "checkmark") }
        }
    }

    private var sectionCount: Int {
        switch workspace.section {
        case .all, .opened, .insights, .conversations: visible.count
        case .notes: filteredNotes.count
        case .starred: filteredStars.count
        }
    }

    private var filteredNotes: [LibraryNoteEntry] {
        let query = workspace.libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return allNotes.filter { query.isEmpty || $0.paper.title.localizedCaseInsensitiveContains(query) || $0.note.body.localizedCaseInsensitiveContains(query) }
    }

    private var filteredStars: [(paper: PaperRecord, page: Int)] {
        let query = workspace.libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return starredPages.filter { query.isEmpty || $0.paper.title.localizedCaseInsensitiveContains(query) || "page \($0.page)".localizedCaseInsensitiveContains(query) }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 20) {
            EmptyState(symbol: "book.pages", title: "No papers yet",
                       detail: "Open a folder to browse its PDFs, or import a PDF.")
                .frame(maxHeight: 220)
            HStack(spacing: 10) {
                Button(action: workspace.chooseFolder) { Label("Open folder…", systemImage: "folder") }.buttonStyle(FolioPrimaryButtonStyle())
                Button(action: workspace.choosePDF) { Label("Import PDF…", systemImage: "plus") }.buttonStyle(.bordered)
                Button { workspace.showArxivImport = true } label: { Label("Import from arXiv…", systemImage: "arrow.down.doc") }.buttonStyle(.bordered)
            }.controlSize(.large).disabled(workspace.repository == nil)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
        .folioGlass(cornerRadius: FolioRadius.panel + 4)
    }

    private func continueReading(_ paper: PaperRecord) -> some View {
        HStack(spacing: 20) {
            PaperThumbnail(url: workspace.repository!.documentURL(for: paper.id), padding: 0)
                .frame(width: 64, height: 84).background(FolioTheme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(FolioTheme.line))
            VStack(alignment: .leading, spacing: 6) {
                FolioTheme.overline("Continue reading")
                Text(paper.title).font(FolioTheme.heading(23)).lineLimit(2)
                Text("Page \(paper.currentPage) of \(paper.pageCount)  ·  \(paper.starredPages.count) saved \(paper.starredPages.count == 1 ? "page" : "pages")")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                FolioProgressBar(value: Double(paper.currentPage), total: Double(max(paper.pageCount, 1)))
                    .frame(maxWidth: 240).accessibilityLabel("Reading progress")
            }
            Spacer(minLength: 10)
            Button { workspace.open(paper) } label: { Label("Resume", systemImage: "arrow.up.right") }
                .buttonStyle(FolioPrimaryButtonStyle())
            if let onAsk {
                Button { onAsk(paper) } label: { Image(systemName: "sparkles") }
                    .buttonStyle(.bordered).controlSize(.large).help("Ask Folio about this paper")
                    .accessibilityLabel("Ask Folio about \(paper.title)")
            }
            Button { workspace.showInsights(for: paper) } label: { Label("Insights", systemImage: "lightbulb") }
                .buttonStyle(.bordered).controlSize(.large).help("Insights")
        }
        .padding(FolioSpace.m).folioGlass(cornerRadius: FolioRadius.panel)
        .contextMenu { paperMenu(paper) }
    }

    private var paperList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("Document").frame(maxWidth: .infinity, alignment: .leading)
                Text("Last position").frame(width: 115, alignment: .leading)
                Text("Saved").frame(width: 68, alignment: .center)
                Text("").frame(width: 76)
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(FolioTheme.muted)
            .padding(.horizontal, 18).padding(.vertical, 13)
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, paper in
                if index > 0 { Divider().padding(.leading, 18) }
                paperRow(paper)
            }
        }
        .folioGlass(cornerRadius: FolioRadius.panel - 2)
    }

    private func visit(_ paper: PaperRecord) {
        if workspace.section == .opened { workspace.open(paper) }
        else { workspace.showInsights(for: paper) }
    }

    private func paperRow(_ paper: PaperRecord) -> some View {
        HStack(spacing: 14) {
            Button { visit(paper) } label: {
                HStack(spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5).fill(FolioTheme.badge)
                        Image(systemName: "doc.text").font(.system(size: 17, weight: .light)).foregroundStyle(FolioTheme.accent)
                    }.frame(width: 42, height: 48)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(paper.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                        Text(paper.author.map { "\($0)  ·  \(paper.pageCount) pages" } ?? "PDF  ·  \(paper.pageCount) pages")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help("Open \(paper.title)")
            VStack(alignment: .leading, spacing: 3) {
                Text("Page \(paper.currentPage)").font(.system(size: 11, weight: .medium))
                Text(paper.lastOpened.formatted(.relative(presentation: .named))).font(.system(size: 12)).foregroundStyle(FolioTheme.muted)
            }.frame(width: 115, alignment: .leading)
            Text("\(paper.starredPages.count)").font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(paper.starredPages.isEmpty ? FolioTheme.muted : FolioTheme.accent)
                .frame(width: 68, alignment: .center)
            HStack(spacing: 2) {
                Button { workspace.showInsights(for: paper) } label: { Image(systemName: "lightbulb") }
                    .help("Insights").accessibilityLabel("Insights for \(paper.title)")
                Button { workspace.open(paper) } label: { Image(systemName: "arrow.up.right") }
                    .help("Open paper")
            }.buttonStyle(.borderless).foregroundStyle(FolioTheme.accent).frame(width: 76)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .contentShape(Rectangle())
        .contextMenu { paperMenu(paper) }
    }

    private func paperCard(_ paper: PaperRecord) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            ZStack(alignment: .topTrailing) {
                Button { visit(paper) } label: {
                    PaperThumbnail(url: workspace.repository!.documentURL(for: paper.id))
                        .frame(maxWidth: .infinity).frame(height: 150).background(FolioTheme.canvas.opacity(0.62))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).accessibilityLabel("Open \(paper.title)")
                Text("PDF  ·  \(paper.pageCount) PAGES")
                    .font(.system(size: 8, weight: .bold)).tracking(0.8)
                    .padding(.horizontal, 8).padding(.vertical, 6).background(FolioTheme.card, in: Capsule()).overlay(Capsule().strokeBorder(FolioTheme.line)).padding(10)
            }
            VStack(alignment: .leading, spacing: 7) {
                Button { visit(paper) } label: {
                    Text(paper.title).font(FolioTheme.heading(19)).lineLimit(2).frame(maxWidth: .infinity, minHeight: 47, alignment: .topLeading)
                        .multilineTextAlignment(.leading)
                }.buttonStyle(.plain).help("Insights for \(paper.title)")
                HStack {
                    Label("Page \(paper.currentPage)", systemImage: "book.pages")
                    Spacer()
                    if !paper.starredPages.isEmpty { Label("\(paper.starredPages.count)", systemImage: "star.fill").foregroundStyle(FolioTheme.accent) }
                }.font(.system(size: 12)).foregroundStyle(FolioTheme.muted)
                Divider().padding(.top, 2)
                HStack {
                    Button { workspace.open(paper) } label: { Label("Resume", systemImage: "arrow.up.right") }
                        .buttonStyle(.borderless).font(.system(size: 11, weight: .medium)).foregroundStyle(FolioTheme.accent)
                    Spacer()
                    Button { workspace.showInsights(for: paper) } label: { Label("Insights", systemImage: "lightbulb") }
                        .buttonStyle(.borderless).help("Insights")
                }
            }
        }
        .padding(14)
        .folioGlass(cornerRadius: FolioRadius.panel)
        .contextMenu { paperMenu(paper) }
    }

    private var starredSection: some View {
        Group {
            if filteredStars.isEmpty {
                emptyResults(symbol: "star", title: hasLibraryConstraints ? "No matching saved pages" : "Save a page for later",
                             detail: hasLibraryConstraints ? "Try another paper title or page number." : "Star a page in the reader and it will appear here with a direct link back to the source.")
                    .folioGlass(cornerRadius: FolioRadius.panel + 2)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredStars.enumerated()), id: \.offset) { index, item in
                        if index > 0 { Divider().padding(.leading, 18) }
                        Button { workspace.open(item.paper, at: item.page) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "star.fill").font(.system(size: 14)).foregroundStyle(FolioTheme.accent).frame(width: 40, height: 40)
                                    .background(FolioTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.paper.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    Text("Page \(item.page) of \(item.paper.pageCount)").font(.system(size: 12)).foregroundStyle(FolioTheme.muted)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .medium)).foregroundStyle(FolioTheme.accent)
                            }.padding(.horizontal, 18).padding(.vertical, 12).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.folioGlass(cornerRadius: FolioRadius.panel - 2)
            }
        }
    }

    private var notesSection: some View {
        Group {
            if filteredNotes.isEmpty {
                emptyResults(symbol: "note.text", title: hasLibraryConstraints ? "No matching notes" : "Your notes will gather here",
                             detail: "Search can find text inside a written PDF comment as well as its paper title.")
                    .folioGlass(cornerRadius: FolioRadius.panel + 2)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredNotes.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().padding(.leading, 18) }
                        Button { workspace.open(item.paper, at: item.note.page) } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: "quote.opening").font(.system(size: 14)).foregroundStyle(FolioTheme.accent)
                                    .frame(width: 40, height: 40).background(FolioTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(item.note.body).font(.system(size: 12)).lineLimit(3).multilineTextAlignment(.leading)
                                    HStack(spacing: 6) {
                                        Text(item.paper.title).lineLimit(1)
                                        Text("·")
                                        Text("Page \(item.note.page)")
                                    }.font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .medium)).foregroundStyle(FolioTheme.accent)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 13).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.folioGlass(cornerRadius: FolioRadius.panel - 2)
            }
        }
    }

    private static let countedSubtypes: Set<String> = ["Highlight", "Underline", "StrikeOut", "Squiggly", "Text", "FreeText"]

    private func loadNotes() {
        guard let repository = workspace.repository else { notesByPaper = [:]; annotationCounts = [:]; return }
        var notes: [UUID: [PaperNote]] = [:], counts: [UUID: Int] = [:]
        for paper in workspace.papers {
            let document = PDFDocument(url: repository.documentURL(for: paper.id))
            notes[paper.id] = document.map(PDFNotes.read) ?? []
            var total = 0
            if let document {
                for index in 0..<document.pageCount {
                    total += document.page(at: index)?.annotations.filter {
                        Self.countedSubtypes.contains(($0.type ?? "").replacingOccurrences(of: "/", with: ""))
                    }.count ?? 0
                }
            }
            counts[paper.id] = total
        }
        notesByPaper = notes
        annotationCounts = counts
    }
}

private struct PaperQuickLook: View {
    let paper: PaperRecord
    let noteCount: Int
    let onOpen: () -> Void
    var onAsk: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "doc.text.image").font(.system(size: 25, weight: .light)).foregroundStyle(FolioTheme.accent)
                    .frame(width: 58, height: 66).background(FolioTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 7) {
                    FolioTheme.overline("Paper details")
                    Text(paper.title).font(FolioTheme.heading(24)).fixedSize(horizontal: false, vertical: true)
                    Text("Local PDF · \(paper.pageCount) pages").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).help("Close details")
            }
            HStack(spacing: 0) {
                detailMetric("LAST POSITION", "Page \(paper.currentPage) of \(paper.pageCount)")
                detailMetric("STARRED PAGES", "\(paper.starredPages.count)")
                detailMetric("WRITTEN NOTES", "\(noteCount)")
            }.padding(.vertical, 14).folioGlass(cornerRadius: 15)
            HStack(spacing: 10) {
                Button(action: onOpen) { Label("Resume reading", systemImage: "book.pages") }
                    .buttonStyle(FolioPrimaryButtonStyle()).controlSize(.large)
                if let onAsk {
                    Button(action: onAsk) { Label("Ask Folio", systemImage: "sparkles") }
                        .buttonStyle(.bordered).controlSize(.large)
                }
                Spacer()
            }
        }
        .padding(26).frame(width: 540).folioSheetBackground()
    }

    private func detailMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 8, weight: .bold)).tracking(0.9).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .medium))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 13)
    }
}

struct PaperThumbnail: View {
    let url: URL
    var padding: CGFloat = 15
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit().padding(padding).shadow(color: .black.opacity(padding > 0 ? 0.08 : 0), radius: 3, y: 1) }
            else { Image(systemName: "doc.text").font(.largeTitle.weight(.ultraLight)).foregroundStyle(.secondary) }
        }.task(id: url) {
            // Intentionally bounded to visible grid items and page one; add a cache for large libraries.
            image = PDFDocument(url: url)?.page(at: 0)?.thumbnail(of: CGSize(width: 180, height: 220), for: .cropBox)
        }
    }
}
