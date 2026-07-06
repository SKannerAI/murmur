import Foundation
import WhisperKit

/// Local speech-to-text via WhisperKit (CoreML, runs on the Apple Neural Engine/GPU).
/// Models download once from HuggingFace on first use and are cached locally;
/// after that, transcription is fully offline.
actor WhisperTranscriber {
    enum TranscriberError: LocalizedError {
        case modelNotLoaded

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded: return "Whisper model is not loaded."
            }
        }
    }

    private var whisperKit: WhisperKit?
    private var loadedModel: String?

    /// Load (or switch to) the given model. No-op if it is already loaded.
    func load(model: String) async throws {
        if whisperKit != nil, loadedModel == model { return }
        whisperKit = nil
        loadedModel = nil
        let config = WhisperKitConfig(model: model)
        whisperKit = try await WhisperKit(config)
        loadedModel = model
    }

    /// Transcribe 16 kHz mono Float32 samples to text.
    ///
    /// When `vocabulary` is non-empty it is fed to the decoder as prompt
    /// tokens (Whisper conditions on them as if they were preceding context),
    /// biasing recognition toward those spellings before any post-correction.
    func transcribe(samples: [Float], model: String, vocabulary: [String] = []) async throws -> String {
        try await load(model: model)
        guard let whisperKit else { throw TranscriberError.modelNotLoaded }

        var options = DecodingOptions()
        if !vocabulary.isEmpty, let tokenizer = whisperKit.tokenizer {
            let prompt = "Glossary: " + vocabulary.joined(separator: ", ") + "."
            let promptTokens = tokenizer.encode(text: " " + prompt)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            if !promptTokens.isEmpty {
                options.promptTokens = promptTokens
                options.usePrefillPrompt = true
            }
        }

        let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
        let raw = results.map(\.text).joined(separator: " ")
        return Self.stripAnnotations(raw)
    }

    /// Whisper emits bracketed noise annotations on silence/noise
    /// ("[BLANK_AUDIO]", "[Music]", …). Strip them so they never reach the LLM
    /// or get pasted.
    static func stripAnnotations(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
