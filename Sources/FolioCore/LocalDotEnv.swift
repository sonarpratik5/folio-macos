import Foundation

/// Read local credentials without exporting them to child processes or copying them into the bundle.
public enum LocalDotEnv {
    /// Load only the native project's dotenv; never search sibling repositories or bundle secrets.
    /// The build-bundle location also works when Finder supplies an unrelated working directory.
    public static func value(_ name: String, directory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                                 bundleURL: URL = Bundle.main.bundleURL,
                                 configuredPath: String? = Bundle.main.object(forInfoDictionaryKey: "FolioEnvironmentFile") as? String) -> String? {
        // Local builds retain only the file path, so copying the app does not copy credentials.
        var candidates: [URL] = []
        if let configuredPath, configuredPath.hasPrefix("/") { candidates.append(URL(fileURLWithPath: configuredPath)) }
        candidates.append(directory.appendingPathComponent(".env"))
        let buildDirectory = bundleURL.deletingLastPathComponent()
        if buildDirectory.lastPathComponent == ".build" {
            candidates.append(buildDirectory.deletingLastPathComponent().appendingPathComponent(".env"))
        }
        for url in candidates {
            if let text = try? String(contentsOf: url, encoding: .utf8), let key = value(name, from: text) { return key }
        }
        return nil
    }
    public static func value(_ name: String, from text: String) -> String? {
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard line.hasPrefix(name), let eq = line.firstIndex(of: "="),
                  line[..<eq].trimmingCharacters(in: .whitespaces) == name else { continue }
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if let quote = value.first, quote == "\"" || quote == "'", let end = value.dropFirst().firstIndex(of: quote) {
                value = String(value[value.index(after: value.startIndex)..<end])
            } else if let hash = value.range(of: " #") { value = String(value[..<hash.lowerBound]) }
            value = value.trimmingCharacters(in: .whitespaces)
            if !value.isEmpty, !value.hasPrefix("paste-") { return value }
        }
        return nil
    }
}
