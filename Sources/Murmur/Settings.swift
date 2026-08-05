import Foundation

/// UserDefaults-backed settings, shared between the SwiftUI views (@AppStorage)
/// and the pipeline (plain reads). One source of truth for keys and defaults.
enum Settings {
    enum Keys {
        static let whisperModel = "whisperModel"
        static let ollamaModel = "ollamaModel"
        static let ollamaURL = "ollamaURL"
        static let cleanupEnabled = "cleanupEnabled"
        static let soundFeedback = "soundFeedback"
        static let overlayEnabled = "overlayEnabled"
        static let vocabulary = "vocabulary"
    }

    static let defaults: [String: Any] = [
        Keys.whisperModel: "base.en",
        Keys.ollamaModel: "qwen2.5:3b",
        Keys.ollamaURL: "http://127.0.0.1:11434",
        Keys.cleanupEnabled: true,
        Keys.soundFeedback: true,
        Keys.overlayEnabled: true,
        Keys.vocabulary: "",
    ]

    /// WhisperKit model names selectable in the UI.
    /// "large-v3-v20240930" is Whisper large-v3-turbo in the WhisperKit model repo.
    static let whisperModels: [(name: String, label: String)] = [
        ("tiny.en", "tiny.en — fastest (~75 MB)"),
        ("base.en", "base.en — balanced (~140 MB)"),
        ("small.en", "small.en — accurate (~460 MB)"),
        ("large-v3-v20240930", "large-v3-turbo — best (~950 MB)"),
    ]

    /// Ollama cleanup models offered in the menu. Any others the server already
    /// has installed are merged into the dropdown at runtime.
    static let ollamaModels: [(name: String, label: String)] = [
        ("qwen2.5:3b", "Qwen2.5 3B — default (~1.9 GB)"),
        ("llama3.2:3b", "Llama 3.2 3B (~2.0 GB)"),
        ("gemma2:2b", "Gemma 2 2B — smallest (~1.6 GB)"),
        ("qwen2.5:7b", "Qwen2.5 7B — most accurate (~4.7 GB)"),
    ]

    static func register() {
        UserDefaults.standard.register(defaults: defaults)
    }

    /// Where WhisperKit model files are downloaded and cached. Application
    /// Support is used deliberately: Documents/Desktop/Downloads are all
    /// TCC-protected and would trigger a macOS access prompt on first write.
    static var modelDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Murmur", isDirectory: true)
    }

    static var whisperModel: String {
        UserDefaults.standard.string(forKey: Keys.whisperModel) ?? "base.en"
    }

    static var ollamaModel: String {
        UserDefaults.standard.string(forKey: Keys.ollamaModel) ?? "qwen2.5:3b"
    }

    static var ollamaURL: URL {
        let raw = UserDefaults.standard.string(forKey: Keys.ollamaURL) ?? "http://127.0.0.1:11434"
        return URL(string: raw) ?? URL(string: "http://127.0.0.1:11434")!
    }

    static var cleanupEnabled: Bool {
        UserDefaults.standard.bool(forKey: Keys.cleanupEnabled)
    }

    static var soundFeedback: Bool {
        UserDefaults.standard.bool(forKey: Keys.soundFeedback)
    }

    static var overlayEnabled: Bool {
        UserDefaults.standard.bool(forKey: Keys.overlayEnabled)
    }

    /// Custom vocabulary: newline- or comma-separated terms, deduped
    /// case-insensitively, order preserved.
    static var vocabularyTerms: [String] {
        let raw = UserDefaults.standard.string(forKey: Keys.vocabulary) ?? ""
        var seen = Set<String>()
        return raw
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}
