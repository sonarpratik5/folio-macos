import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "system"

    @AppStorage("dimPDFInDarkMode") private var dimPDF = true

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Dim PDF pages in dark mode", isOn: $dimPDF)
                Picker("Color mode", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            }
            Section("Local library") {
                Text("Imported PDFs and annotations are saved in this Mac’s library. Original files stay unchanged.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                Text("Folio for Mac")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).scrollContentBackground(.hidden).background(FolioBackdrop())
        .tint(FolioTheme.accent)
    }
}
