import SwiftUI
import FolioCore
import PDFKit

private struct LibraryNoteEntry: Identifiable {
    let paper: PaperRecord
    let note: PaperNote
    var id: String { "\(paper.id.uuidString)-\(note.id)" }
}

struct LibraryView: View {
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
        return LibraryOrganizer.apply(
            workspace.papers.filter { workspace.section != .starred || !$0.starredPages.isEmpty },
            query: workspace.libraryQuery, filter: workspace.section == .all ? filter : .all, order: sectionOrder,
            noteCounts: notesByPaper.mapValues(\.count),
            noteText: notesByPaper.mapValues { $0.map(\.body).joined(separator: "\n") })
    }

    private var sectionTitle: String {
        switch workspace.section {
        case .all: "Library"
        case .opened: "Recently opened"
        case .notes: "Notes from your reading"
        case .starred: "Starred pages"
        case .insights: "Insights"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if workspace.section == .all, workspace.libraryQuery.isEmpty, let paper = workspace.papers.max(by: { $0.lastOpened < $1.lastOpened }) {
                    continueReading(paper)
                }

                if !workspace.papers.isEmpty { controlsRow }

                if workspace.papers.isEmpty {
                    emptyLibrary
                } else if workspace.section == .notes {
                    notesSection
                } else if workspace.section == .starred {
                    starredSection
                } else if visible.isEmpty {
                    EmptyState(symbol: workspace.section.symbol, title: "No matching papers",
                               detail: workspace.libraryQuery.isEmpty ? "Import a PDF to begin building your library." : "Try another title or a phrase from one of your notes.")
                        .padding(.vertical, 48)
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
        .navigationTitle("Library")
        .task(id: workspace.papers) { loadNotes() }
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
                FolioTheme.overline(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                Text(sectionTitle).font(FolioTheme.heading(38)).accessibilityAddTraits(.isHeader)
                Text(sectionSubtitle).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 6) {
                    metric(workspace.papers.count, "paper", "papers")
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

    private var annotationTotal: Int { annotationCounts.values.reduce(0, +) }

    private func metric(_ count: Int, _ singular: String, _ plural: String) -> some View {
        HStack(spacing: 4) {
            Text("\(count)").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(FolioTheme.ink)
            Text(count == 1 ? singular : plural).font(.system(size: 11)).foregroundStyle(FolioTheme.muted)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(FolioTheme.badge, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(FolioTheme.line.opacity(0.6)))
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
        case .all, .opened, .insights: visible.count
        case .notes: filteredNotes.count
        case .starred: filteredStars.count
        }
    }

    private var sectionSubtitle: String {
        switch workspace.section {
        case .all: "A quiet place for the questions worth following."
        case .opened: "Pick up where your last reading session left off."
        case .notes: "Written comments you left beside the source."
        case .starred: "Pages you marked for another look."
        case .insights: "Understand a paper before reading."
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
            EmptyState(symbol: "book.pages", title: "A focused space for reading",
                       detail: "Import a PDF, or drop one anywhere in this window, to start reading, mark a passage and keep notes beside the text.")
                .frame(maxHeight: 220)
            HStack(spacing: 10) {
                Button(action: workspace.choosePDF) { Label("Import a PDF…", systemImage: "plus") }.buttonStyle(FolioPrimaryButtonStyle())
                Button { workspace.showArxivImport = true } label: { Label("Import from arXiv…", systemImage: "arrow.down.doc") }.buttonStyle(.bordered)
                Button(action: workspace.sample) { Label("Explore the sample", systemImage: "book.closed") }.buttonStyle(.bordered)
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
                Text("DOCUMENT").frame(maxWidth: .infinity, alignment: .leading)
                Text("LAST POSITION").frame(width: 115, alignment: .leading)
                Text("SAVED").frame(width: 68, alignment: .center)
                Text("").frame(width: 76)
            }
            .font(.system(size: 9, weight: .bold)).tracking(1.05).foregroundStyle(.tertiary)
            .padding(.horizontal, 18).padding(.vertical, 13)
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, paper in
                if index > 0 { Divider().padding(.leading, 18) }
                paperRow(paper)
            }
        }
        .folioGlass(cornerRadius: FolioRadius.panel - 2)
    }

    private func paperRow(_ paper: PaperRecord) -> some View {
        HStack(spacing: 14) {
            Button { workspace.open(paper) } label: {
                HStack(spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5).fill(FolioTheme.badge)
                        Image(systemName: "doc.text").font(.system(size: 17, weight: .light)).foregroundStyle(FolioTheme.accent)
                    }.frame(width: 42, height: 48)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(paper.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text(paper.author.map { "\($0)  ·  \(paper.pageCount) pages" } ?? "PDF  ·  \(paper.pageCount) pages")
                            .font(.system(size: 10, weight: .medium)).tracking(0.4).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help("Open \(paper.title)")
            VStack(alignment: .leading, spacing: 3) {
                Text("Page \(paper.currentPage)").font(.system(size: 11, weight: .medium))
                Text(paper.lastOpened.formatted(.relative(presentation: .named))).font(.system(size: 10)).foregroundStyle(.secondary)
            }.frame(width: 115, alignment: .leading)
            Text("\(paper.starredPages.count)").font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(paper.starredPages.isEmpty ? FolioTheme.ink.opacity(0.42) : FolioTheme.accent)
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
                PaperThumbnail(url: workspace.repository!.documentURL(for: paper.id))
                    .frame(maxWidth: .infinity).frame(height: 150).background(FolioTheme.canvas.opacity(0.62))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text("PDF  ·  \(paper.pageCount) PAGES")
                    .font(.system(size: 8, weight: .bold)).tracking(0.8)
                    .padding(.horizontal, 8).padding(.vertical, 6).background(FolioTheme.card, in: Capsule()).overlay(Capsule().strokeBorder(FolioTheme.line)).padding(10)
            }
            VStack(alignment: .leading, spacing: 7) {
                Button { details = paper } label: {
                    Text(paper.title).font(FolioTheme.heading(19)).lineLimit(2).frame(maxWidth: .infinity, minHeight: 47, alignment: .topLeading)
                        .multilineTextAlignment(.leading)
                }.buttonStyle(.plain).help("Paper details")
                HStack {
                    Label("Page \(paper.currentPage)", systemImage: "book.pages")
                    Spacer()
                    if !paper.starredPages.isEmpty { Label("\(paper.starredPages.count)", systemImage: "star.fill").foregroundStyle(FolioTheme.accent) }
                }.font(.system(size: 10)).foregroundStyle(.secondary)
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
                EmptyState(symbol: "star", title: "Save a page for later", detail: "Star a page in the reader and it will appear here with a direct link back to the source.")
                    .padding(.vertical, 48).folioGlass(cornerRadius: FolioRadius.panel + 2)
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
                                    Text("Page \(item.page) of \(item.paper.pageCount)").font(.system(size: 10)).foregroundStyle(.secondary)
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
                EmptyState(symbol: "note.text", title: "Your notes will gather here", detail: "Search can find text inside a written PDF comment as well as its paper title.")
                    .padding(.vertical, 48).folioGlass(cornerRadius: FolioRadius.panel + 2)
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

private struct PaperThumbnail: View {
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
