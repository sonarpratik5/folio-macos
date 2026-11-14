import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("design") private var design = "classic"
    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Color mode", selection: $appearance) {
                    Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
                Picker("Accent", selection: $design) {
                    Text("Classic · forest green").tag("classic")
                    Text("Studio · slate blue").tag("studio")
                }
            }
            Section("Local library") {
                Text("PDFs are copied into ~/Library/Application Support/FolioMac/Documents. Notes and marks save to those copies. Reading positions and stars stay in library.json.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Your web library is separate. Import PDFs here to begin; browser drafts and chats are not migrated.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text("Folio for Mac · Native SwiftUI + PDFKit starter").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
