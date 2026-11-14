import SwiftUI
import FolioCore
import PDFKit

struct LibraryView: View {
    @ObservedObject var workspace: Workspace
    @AppStorage("libraryLayout") private var layout = "list"
    @State private var sortByTitle = false

    private var visible: [PaperRecord] {
        workspace.papers.filter {
            (workspace.libraryQuery.isEmpty || $0.title.localizedCaseInsensitiveContains(workspace.libraryQuery))
                && (workspace.section != .starred || !$0.starredPages.isEmpty)
        }.sorted { sortByTitle ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : $0.lastOpened > $1.lastOpened }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                            .font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                        Text("Your library").font(FolioTheme.heading(36))
                        Text("Your documents and the ideas you’re keeping.").foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 20)
                    TextField("Search paper titles", text: $workspace.libraryQuery)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                        .accessibilityLabel("Search paper titles")
                }
                Divider()
                if workspace.section == .all, workspace.libraryQuery.isEmpty, let paper = visible.first {
                    continueReading(paper)
                }
                HStack {
                    Text(workspace.section.rawValue).font(FolioTheme.heading(24))
                    Text("\(visible.count)").font(.caption).padding(5).background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    Spacer()
                    if workspace.section != .notes {
                        Toggle("Sort by title", isOn: $sortByTitle).toggleStyle(.checkbox)
                        Picker("Layout", selection: $layout) {
                            Image(systemName: "list.bullet").tag("list")
                            Image(systemName: "square.grid.2x2").tag("grid")
                        }.pickerStyle(.segmented).frame(width: 85).labelsHidden()
                    }
                }
                if workspace.papers.isEmpty {
                    VStack(spacing: 20) {
                        EmptyState(symbol: "book.pages", title: "A focused space for reading",
                                   detail: "Import a PDF to start reading, mark a passage, and keep notes beside the text.")
                        HStack {
                            Button("Import a PDF…", action: workspace.choosePDF).buttonStyle(.borderedProminent)
                            Button("Explore the sample", action: workspace.sample).buttonStyle(.bordered)
                        }.disabled(workspace.repository == nil)
                    }.frame(maxWidth: .infinity).padding(.vertical, 50)
                } else if workspace.section == .notes {
                    LibraryNotesView(workspace: workspace, papers: visible)
                } else if visible.isEmpty {
                    EmptyState(symbol: workspace.section.symbol, title: "No matching papers",
                               detail: workspace.section == .starred ? "Star a page in the reader to find it here." : "Try another search.")
                } else if layout == "grid" {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 225, maximum: 320))], spacing: 18) {
                        ForEach(visible) { paper in paperCard(paper) }
                    }
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Text("TITLE"); Spacer(); Text("LAST POSITION").frame(width: 135); Text("STARS").frame(width: 55)
                        }.font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary).padding(16)
                        ForEach(visible) { paper in
                            Divider()
                            Button { workspace.open(paper) } label: {
                                HStack(spacing: 13) {
                                    Image(systemName: "doc.richtext").font(.title2).foregroundStyle(FolioTheme.accent)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(paper.title).fontWeight(.medium).lineLimit(1)
                                        Text("\(paper.pageCount) pages · Local PDF").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("Page \(paper.currentPage) of \(paper.pageCount)").font(.caption).frame(width: 135)
                                    Text("\(paper.starredPages.count)").foregroundStyle(.secondary).frame(width: 55)
                                }.padding(16).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }.background(FolioTheme.card, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(FolioTheme.line))
                }
            }.padding(32)
        }.navigationTitle("Library")
    }

    private func continueReading(_ paper: PaperRecord) -> some View {
        HStack(spacing: 20) {
            Image(systemName: "book.pages").font(.system(size: 32, weight: .ultraLight)).padding(10)
            VStack(alignment: .leading, spacing: 8) {
                Text("CONTINUE READING").font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                Text(paper.title).font(FolioTheme.heading(25)).lineLimit(2)
                Text("Last position · page \(paper.currentPage) of \(paper.pageCount)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Resume reading") { workspace.open(paper) }.buttonStyle(.borderedProminent)
        }.padding(24).background(FolioTheme.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(FolioTheme.line))
    }

    private func paperCard(_ paper: PaperRecord) -> some View {
        Button { workspace.open(paper) } label: {
            VStack(alignment: .leading, spacing: 14) {
                PaperThumbnail(url: workspace.repository!.documentURL(for: paper.id))
                    .frame(maxWidth: .infinity).frame(height: 160).background(FolioTheme.canvas)
                VStack(alignment: .leading, spacing: 12) {
                    Text("LOCAL PDF").font(.system(size: 10, weight: .medium)).tracking(1).foregroundStyle(.secondary)
                    Text(paper.title).font(FolioTheme.heading(21)).lineLimit(2).frame(height: 52, alignment: .top)
                    Text("Page \(paper.currentPage) of \(paper.pageCount)").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Label("Resume reading", systemImage: "arrow.up.right").font(.caption)
                }.padding([.horizontal, .bottom], 16)
            }.background(FolioTheme.card, in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(FolioTheme.line))
        }.buttonStyle(.plain)
    }
}

private struct PaperThumbnail: View {
    let url: URL
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit().padding(15).shadow(radius: 2, y: 2) }
            else { Image(systemName: "doc.text").font(.largeTitle).foregroundStyle(.secondary) }
        }.task(id: url) {
            // Intentionally bounded to visible grid items and page one; add a cache for large libraries.
            image = PDFDocument(url: url)?.page(at: 0)?.thumbnail(of: CGSize(width: 180, height: 220), for: .cropBox)
        }
    }
}

private struct LibraryNotesView: View {
    @ObservedObject var workspace: Workspace
    let papers: [PaperRecord]
    @State private var groups: [(paper: PaperRecord, notes: [PaperNote])] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if groups.isEmpty {
                EmptyState(symbol: "note.text", title: "Keep your thinking beside the source",
                           detail: "Written PDF comments appear here. Add a note in the reader to begin.")
            }
            ForEach(groups, id: \.paper.id) { group in
                Text(group.paper.title).font(FolioTheme.heading(21))
                ForEach(group.notes) { note in
                    Button { workspace.open(group.paper, at: note.page) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(note.body).frame(maxWidth: .infinity, alignment: .leading)
                            Text("Page \(note.page)").font(.caption).foregroundStyle(.secondary)
                        }.padding(18).background(FolioTheme.card, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
            }
        }.task(id: papers) {
            guard let repository = workspace.repository else { return }
            groups = papers.compactMap { paper in
                guard let document = PDFDocument(url: repository.documentURL(for: paper.id)) else { return nil }
                let notes = PDFNotes.read(from: document)
                return notes.isEmpty ? nil : (paper, notes)
            }
        }
    }
}
