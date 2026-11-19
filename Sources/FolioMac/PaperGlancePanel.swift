import SwiftUI
import FolioCore

/// Matches the web ConceptMap's three anchors and click-to-reveal details.
/// The page owns generation/persistence; this view owns only presentation state.
struct GlancePanel: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var model: PaperAssistantModel
    let paper: PaperRecord
    var expanded = false
    @AppStorage("folio.assistant.provider") private var providerValue = AssistantProvider.codex.rawValue
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dismiss) private var dismiss
    @State private var panelWidth: CGFloat = 0
    @State private var selected: String?
    @State private var showSources = false
    @State private var showExpanded = false
    @FocusState private var focusedIdea: String?
    private let roles = ["problem", "approach", "finding"]
    private var provider: AssistantProvider { AssistantProvider(rawValue: providerValue) ?? .codex }
    private var engine: String { provider == .codex ? "Codex" : "Claude" }
    private var overview: AssistantOverview? { model.snapshot?.overview }
    private var border: Color { contrast == .increased ? .primary : Color.secondary.opacity(0.25) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(24)
            if let error = model.error {
                HStack(alignment: .top) {
                    Text(error).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { model.error = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss concept error")
                }.font(.callout).foregroundStyle(.red).padding(16)
            }
            if model.busy {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text(model.progress).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Cancel") { model.cancel() }
                }.padding(16).background(FolioTheme.background)
            }
            if let overview {
                steps(overview, horizontal: panelWidth > 600)
                if let card = overview.cards.first(where: { $0.id == selected }) {
                    details(card).padding(.horizontal, 26).padding(.bottom, 20)
                }
                Text("\(overview.provider == .codex ? "Codex" : "Claude")\(overview.coverage.hasPrefix("Sampled") ? " · Based on excerpts" : "")   ·   Tap an idea to look closer")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 26).padding(.bottom, 19)
            } else if !model.busy {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        Text("Three key ideas, explained by \(engine).").font(.system(size: 14)).foregroundStyle(.secondary)
                        Button { model.generateOverview(provider: provider) } label: {
                            Label("Generate with \(engine)", systemImage: "sparkles")
                        }.buttonStyle(.borderedProminent).disabled(model.paper == nil)
                    }
                    Text("Paper text is sent to \(engine) only when you generate. Saved overviews reopen without another call.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.horizontal, 24).padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(FolioTheme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(border))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { panelWidth = $0 }
        .accessibilityElement(children: .contain).accessibilityLabel("Paper at a glance")
        .onChange(of: overview) { _, value in
            selected = nil; showSources = false
            focusedIdea = roles.first { role in value?.cards.contains(where: { $0.id == role }) == true }
        }
        .sheet(isPresented: $showExpanded) {
            ScrollView {
                GlancePanel(workspace: workspace, model: model, paper: paper, expanded: true).padding(28)
            }.frame(minWidth: 680, idealWidth: 960, minHeight: 480, idealHeight: 650)
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "square.3.layers.3d").font(.system(size: 18, weight: .light))
                .frame(width: 34, height: 34).background(FolioTheme.background, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text("Paper at a glance").font(.system(size: 23, weight: .medium)).accessibilityAddTraits(.isHeader)
                if expanded { Text(paper.title).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            if overview != nil {
                Button { model.generateOverview(provider: provider) } label: { Label("Regenerate", systemImage: "sparkles") }
                    .disabled(model.busy || model.paper == nil)
                    .help("Ask \(engine) to reread the paper and replace this saved overview")
            }
            Button { if expanded { dismiss() } else { showExpanded = true } } label: {
                Image(systemName: expanded ? "xmark" : "arrow.up.left.and.arrow.down.right")
            }.buttonStyle(.plain).accessibilityLabel(expanded ? "Close paper at a glance" : "Expand paper at a glance")
        }
    }

    @ViewBuilder
    private func steps(_ overview: AssistantOverview, horizontal: Bool) -> some View {
        let layout = horizontal ? AnyLayout(HStackLayout(alignment: .top, spacing: 22)) : AnyLayout(VStackLayout(spacing: 12))
        layout {
            ForEach(Array(roles.enumerated()), id: \.element) { index, role in
                let stepLayout = horizontal ? AnyLayout(VStackLayout(spacing: 13)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                stepLayout {
                    Text("\(index + 1)").font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 28, height: 28).background(FolioTheme.card, in: Circle())
                        .overlay(Circle().strokeBorder(border)).padding(.top, horizontal ? 0 : 16)
                        .accessibilityHidden(true)
                    idea(overview.cards.first { $0.id == role }, role: role, index: index, horizontal: horizontal)
                }.frame(maxWidth: .infinity)
            }
        }
        .background {
            GeometryReader { geometry in
                Path { path in
                    if horizontal {
                        let inset = (geometry.size.width + 22) / 6
                        path.move(to: CGPoint(x: inset, y: 14)); path.addLine(to: CGPoint(x: geometry.size.width - inset, y: 14))
                    } else {
                        path.move(to: CGPoint(x: 14, y: 30)); path.addLine(to: CGPoint(x: 14, y: geometry.size.height - 40))
                    }
                }.stroke(border, lineWidth: 1)
            }
        }.padding(.horizontal, horizontal ? 26 : 18).padding(.top, horizontal ? 14 : 8).padding(.bottom, 20)
    }

    private func idea(_ card: AssistantOverview.Card?, role: String, index: Int, horizontal: Bool) -> some View {
        Button {
            selected = selected == role ? nil : role
            showSources = false
        } label: {
            VStack(alignment: .leading, spacing: horizontal ? 10 : 7) {
                Text(role.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                Text(card?.label ?? (overview?.coverage.hasPrefix("Sampled") == true ? "Not found in excerpts" : "Not reported"))
                    .font(.system(size: horizontal ? 16 : 15, weight: card == nil ? .regular : .medium))
                    .foregroundStyle(card == nil ? FolioTheme.muted : FolioTheme.ink)
                    .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
            }.padding(horizontal ? 18 : 16)
                .frame(maxWidth: .infinity, minHeight: horizontal ? 112 : 80, alignment: .topLeading)
                .background(GlanceOutline(variant: index).fill(card == nil ? FolioTheme.card : pastel(index)))
                .overlay(GlanceOutline(variant: index).stroke(selected == role ? FolioTheme.accent : border,
                    style: StrokeStyle(lineWidth: selected == role ? 1.7 : 1, dash: card == nil ? [4, 4] : [])))
                .contentShape(RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(.plain).disabled(card == nil).focused($focusedIdea, equals: role)
            .accessibilityLabel("\(role.capitalized): \(card?.label ?? "Not reported")")
            .accessibilityValue(selected == role ? "Expanded" : "Collapsed")
            .help(card?.label ?? "Not reported")
    }

    private func pastel(_ index: Int) -> Color {
        let light: [(Double, Double, Double)] = [(0.984, 0.937, 0.910), (0.941, 0.925, 0.980), (0.929, 0.961, 0.933)]
        let dark: [(Double, Double, Double)] = [(0.23, 0.19, 0.17), (0.21, 0.19, 0.27), (0.17, 0.23, 0.19)]
        let rgb = (scheme == .dark ? dark : light)[index]
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    private func details(_ card: AssistantOverview.Card) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(card.label).font(.system(size: 16, weight: .medium)).textSelection(.enabled)
                Spacer()
                Button { selected = nil; focusedIdea = card.id } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Close idea details")
            }
            Text(card.explanation).font(.system(size: 14)).lineSpacing(5).foregroundStyle(.secondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("View source", isExpanded: $showSources) {
                ForEach(card.sources) { source in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(source.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Button("Read page \(source.page) ↗") { read(source) }.buttonStyle(.link)
                    }.font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .leading).padding(14).background(FolioTheme.background)
                }
            }.font(.caption).id(card.id)
            if let source = card.sources.first {
                HStack(spacing: 8) {
                    Button { read(source) } label: { Label("Read page \(source.page) ↗", systemImage: "book") }
                    Button {
                        if expanded { dismiss() }
                        workspace.present(.assistant, for: paper, selection: source.text, page: source.page)
                    } label: { Label("Ask about this", systemImage: "bubble") }
                }.controlSize(.small)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(border))
            .accessibilityElement(children: .contain).accessibilityLabel("Selected idea")
    }

    private func read(_ source: AssistantPassage) {
        if expanded { dismiss() }
        workspace.open(paper, at: source.page)
    }
}

/// The web sketch frames use a 300 × 140 coordinate space and quadratic curves.
private struct GlanceOutline: Shape {
    let variant: Int
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let v = CGFloat(variant) * 0.2
        p.move(to: CGPoint(x: 12, y: 2 + v))
        p.addQuadCurve(to: CGPoint(x: 288, y: 2), control: CGPoint(x: 149, y: 1.5 + v))
        p.addQuadCurve(to: CGPoint(x: 298, y: 12), control: CGPoint(x: 298, y: 2.4))
        p.addQuadCurve(to: CGPoint(x: 298, y: 128), control: CGPoint(x: 298.5 - v, y: 70))
        p.addQuadCurve(to: CGPoint(x: 288, y: 138), control: CGPoint(x: 298, y: 138))
        p.addQuadCurve(to: CGPoint(x: 12, y: 138), control: CGPoint(x: 150, y: 138.5 - v))
        p.addQuadCurve(to: CGPoint(x: 2, y: 128), control: CGPoint(x: 2, y: 138))
        p.addQuadCurve(to: CGPoint(x: 2, y: 12), control: CGPoint(x: 1.5 + v, y: 70))
        p.addQuadCurve(to: CGPoint(x: 12, y: 2 + v), control: CGPoint(x: 2, y: 2.4))
        p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX: rect.width / 300, y: rect.height / 140).translatedBy(x: rect.minX, y: rect.minY))
    }
}

/// Wrapping keyword chips that stay inside a narrow column.
struct GlanceTags: View {
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
