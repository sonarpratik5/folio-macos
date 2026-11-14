import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Color mode", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Text("Folio uses one calm green and neutral palette, with glass surfaces that adapt to your color mode.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("AI assistant") {
                AISettingsView()
            }
            Section("Local library") {
                Text("PDFs are copied into ~/Library/Application Support/FolioMac/Documents. Notes and marks save to those copies. Reading positions and stars stay in library.json.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Your web library is separate. Import PDFs here to begin; browser drafts and chats are not migrated.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text("Folio for Mac · Native SwiftUI + PDFKit starter")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).scrollContentBackground(.hidden).background(FolioBackdrop())
        .tint(FolioTheme.accent)
    }
}
