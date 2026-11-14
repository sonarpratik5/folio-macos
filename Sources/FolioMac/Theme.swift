import SwiftUI

enum FolioTheme {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
    static let background = adaptive(0xF0F3F0, 0x202823)
    static let card = adaptive(0xFFFFFF, 0x2A342E)
    static let ink = adaptive(0x293B34, 0xE2EBE4)
    static let accent = adaptive(0x284E40, 0xA8D5B1)
    static let studioAccent = adaptive(0x416484, 0xACC9E4)
    static let line = adaptive(0xD9DFD3, 0x46534A)
    static let canvas = adaptive(0xDFE5DF, 0x252D28)

    static func heading(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 34, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(FolioTheme.heading(25))
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 370)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(32)
    }
}
