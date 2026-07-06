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
    }

    static let defaults: [String: Any] = [
        Keys.whisperModel: "base.en",
        Keys.ollamaModel: "qwen2.5:3b",
        Keys.ollamaURL: "http://127.0.0.1:11434",
        Keys.cleanupEnabled: true,
        Keys.soundFeedback: true,
        Keys.overlayEnabled: true,
    ]

    /// WhisperKit model names selectable in the UI.
    /// "large-v3-v20240930" is Whisper large-v3-turbo in the WhisperKit model repo.
    static let whisperModels: [(name: String, label: String)] = [
        ("tiny.en", "tiny.en — fastest (~75 MB)"),
        ("base.en", "base.en — balanced (~140 MB)"),
        ("small.en", "small.en — accurate (~460 MB)"),
        ("large-v3-v20240930", "large-v3-turbo — best (~950 MB)"),
    ]

    static func register() {
        UserDefaults.standard.register(defaults: defaults)
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
}
