import AppKit

/// Floating format strip shown only while editing a text box: size -/+, the four annotation colors, bold.
final class InlineFormatStrip: NSVisualEffectView {
    weak var controller: InlineTextController?
    var selectedColor: String? { didSet { rebuildColors() } }
    private let sizeLabel = NSTextField(labelWithString: "16")
    private let boldButton = StripButton()
    private var colorButtons: [(String, StripButton)] = []
    private let stack = NSStackView()

    /// Display colors for the four annotation inks (same palette as Workspace.textInk).
    static let inks: [(name: String, color: NSColor)] = AnnotationPalette.names.map { ($0, AnnotationPalette.ink($0)) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover; blendingMode = .withinWindow; state = .active
        wantsLayer = true
        layer?.cornerRadius = 9; layer?.masksToBounds = true
        layer?.borderWidth = 0.5; layer?.borderColor = NSColor.separatorColor.cgColor
        setAccessibilityLabel("Text formatting")
        stack.orientation = .horizontal; stack.spacing = 4; stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        sizeLabel.alignment = .center
        sizeLabel.widthAnchor.constraint(equalToConstant: 24).isActive = true
        sizeLabel.setAccessibilityLabel("Font size")
        stack.addArrangedSubview(button("minus", "Smaller text", #selector(smaller)))
        stack.addArrangedSubview(sizeLabel)
        stack.addArrangedSubview(button("plus", "Larger text", #selector(larger)))
        stack.addArrangedSubview(divider())
        rebuildColors()
        stack.addArrangedSubview(divider())
        configure(boldButton, symbol: "bold", help: "Bold (⌘B)", action: #selector(bold))
        stack.addArrangedSubview(boldButton)
    }
    required init?(coder: NSCoder) { nil }

    func refresh(size: CGFloat, bold: Bool) {
        sizeLabel.stringValue = "\(Int(size.rounded()))"
        boldButton.isOn = bold
        boldButton.setAccessibilityValue(bold ? "On" : "Off")
    }

    // Swallow clicks on the strip's own background so they never count as "outside" the editor.
    override func mouseDown(with event: NSEvent) {}

    private func button(_ symbol: String, _ help: String, _ action: Selector) -> StripButton {
        let item = StripButton(); configure(item, symbol: symbol, help: help, action: action); return item
    }
    private func configure(_ item: StripButton, symbol: String, help: String, action: Selector) {
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)
        item.toolTip = help; item.setAccessibilityLabel(help)
        item.target = self; item.action = action
        item.widthAnchor.constraint(equalToConstant: 24).isActive = true
        item.heightAnchor.constraint(equalToConstant: 22).isActive = true
    }
    private func divider() -> NSView {
        let box = NSBox(); box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 1).isActive = true
        box.heightAnchor.constraint(equalToConstant: 16).isActive = true
        return box
    }
    private func rebuildColors() {
        guard stack.arrangedSubviews.count > 0 else { return }
        colorButtons.forEach { $0.1.removeFromSuperview() }
        colorButtons = []
        let anchorIndex = stack.arrangedSubviews.count - (boldButton.superview == nil ? 0 : 2)
        for (offset, ink) in Self.inks.enumerated() {
            let item = StripButton()
            let selected = ink.name == selectedColor
            item.image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                ink.color.setFill(); NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).fill()
                if selected { NSColor.controlAccentColor.setStroke(); let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)); ring.lineWidth = 1.5; ring.stroke() }
                return true
            }
            item.toolTip = "\(ink.name.capitalized) text"; item.setAccessibilityLabel("\(ink.name.capitalized) text color")
            item.target = self; item.action = #selector(pickColor(_:)); item.identifier = NSUserInterfaceItemIdentifier(ink.name)
            item.widthAnchor.constraint(equalToConstant: 22).isActive = true
            item.heightAnchor.constraint(equalToConstant: 22).isActive = true
            stack.insertArrangedSubview(item, at: min(anchorIndex + offset, stack.arrangedSubviews.count))
            colorButtons.append((ink.name, item))
        }
    }

    @objc private func smaller() { controller?.stepSize(up: false) }
    @objc private func larger() { controller?.stepSize(up: true) }
    @objc private func bold() { controller?.toggleBold() }
    @objc private func pickColor(_ sender: NSButton) { if let name = sender.identifier?.rawValue { controller?.pickColor(name) } }
}

/// Borderless button that never steals focus from the text editor.
final class StripButton: NSButton {
    var isOn = false { didSet { needsDisplay = true; layer?.backgroundColor = isOn ? NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor : nil } }
    override var acceptsFirstResponder: Bool { false }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false; imagePosition = .imageOnly; bezelStyle = .regularSquare
        wantsLayer = true; layer?.cornerRadius = 5
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { nil }
}
