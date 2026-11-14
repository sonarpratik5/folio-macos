import SwiftUI
import FolioCore

/// Paper overview and local skim, displayed only on the library Insights page.
/// State lives in `PaperAIStore`, so it is not cancelled on disappear. AI runs only from the Generate button.
struct GlancePanel: View {
    @State private var abstractExpanded = false
    @ObservedObject var workspace: Workspace
    @ObservedObject var model: PaperAssistantModel
    let paper: PaperRecord
    @AppStorage("folio.assistant.provider") private var providerValue = AssistantProvider.codex.rawValue
    private var provider: AssistantProvider { AssistantProvider(rawValue: providerValue) ?? .codex }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Paper at a glance").font(FolioTheme.heading(26)).accessibilityAddTraits(.isHeader)
                Spacer()
                ProviderSwitch()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    overview
                    Divider()
                    insightsSection
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 12)
            }.scrollIndicators(.automatic)
        }
        .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FolioTheme.panelRight)
        .onAppear { model.load(root: workspace.repository?.root, record: paper); model.loadInsights() }
        .onDisappear { model.cancel() }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Problem, approach & finding").font(FolioTheme.heading(20))
                Text("Three concise ideas, each backed by exact passages.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button(model.snapshot?.overview == nil ? "Generate overview" : "Regenerate") { model.generateOverview(provider: provider) }
                    .buttonStyle(.borderedProminent).disabled(model.busy || model.paper == nil)
                if model.busy { Button("Cancel") { model.cancel() } }
            }
            if model.busy { HStack { ProgressView().controlSize(.small); Text(model.progress).font(.callout).fixedSize(horizontal: false, vertical: true) } }
            if let error = model.error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            if let overview = model.snapshot?.overview {
                Text("\(overview.provider.name) · \(overview.coverage)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                ForEach(overview.cards) { card in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(card.id.capitalized).font(.caption.weight(.semibold)).foregroundStyle(FolioTheme.accent)
                        Text(card.label).font(FolioTheme.heading(18)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        Text(card.explanation).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        ForEach(card.sources) { source in
                            VStack(alignment: .leading, spacing: 6) {
                                Button("Read source · p. \(source.page)") { workspace.open(paper, at: source.page) }.buttonStyle(.link)
                                    .accessibilityLabel("Go to page \(source.page)")
                                Text(source.text).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, alignment: .leading).folioWell()
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).folioCard(padding: 14)
                }
                ForEach(["problem", "approach", "finding"].filter { role in !overview.cards.contains(where: { $0.id == role }) }, id: \.self) { role in
                    Text("\(role.capitalized): not supported by the supplied text.").font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Text("Generate sends the extracted text to \(provider.name). Long papers use distributed excerpts; the saved overview reports its coverage. Unsupported findings are left out.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Skim on this Mac", systemImage: "text.magnifyingglass").font(FolioTheme.heading(18))
                Text("Offline · no AI").font(.caption).padding(.horizontal, 8).padding(.vertical, 3).background(FolioTheme.accent.opacity(0.12), in: Capsule())
            }
            if let insights = model.insights {
                Text("\(insights.words.formatted()) words · about \(insights.minutes) min read").font(.caption).foregroundStyle(.secondary)
                if !insights.abstract.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(insights.abstract).textSelection(.enabled).lineLimit(abstractExpanded ? nil : 6).fixedSize(horizontal: false, vertical: true)
                        if insights.abstract.count > 360 {
                            Button(abstractExpanded ? "Show less" : "Show more") { abstractExpanded.toggle() }.buttonStyle(.link).font(.caption)
                        }
                    }.folioWell(padding: 12)
                }
                if !insights.keywords.isEmpty { GlanceTags(tags: insights.keywords.map(\.term)) }
                if !insights.keySentences.isEmpty {
                    Text("Key sentences").font(.headline)
                    ForEach(insights.keySentences) { item in
                        HStack(alignment: .top, spacing: 10) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.yellow.opacity(0.7)).frame(width: 3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                Button("p. \(item.page)") { workspace.open(paper, at: item.page) }.buttonStyle(.link).font(.caption)
                                    .accessibilityLabel("Go to page \(item.page)")
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else if insights.abstract.isEmpty { Text("No readable prose was found in this PDF’s text layer.").foregroundStyle(.secondary) }
            } else if model.paper == nil { Text("The paper text is unavailable.").foregroundStyle(.secondary) }
            else { HStack { ProgressView().controlSize(.small); Text("Reading the text layer…").foregroundStyle(.secondary) } }
        }
    }
}

/// Wrapping keyword chips that stay inside a narrow column.
private struct GlanceTags: View {
    let tags: [String]
    var body: some View {
        GlanceWrap(spacing: 6) { ForEach(tags, id: \.self) { chip($0) } }
    }
    private func chip(_ text: String) -> some View {
        Text(text).font(.caption).padding(.horizontal, 9).padding(.vertical, 4).background(FolioTheme.accent.opacity(0.12), in: Capsule())
    }
}

private struct GlanceWrap: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(bounds.width, subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        var origins: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height); maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
