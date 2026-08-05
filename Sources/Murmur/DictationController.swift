import Foundation
import SwiftUI
import AppKit

/// Orchestrates the full pipeline:
/// hotkey down → record → hotkey up → transcribe (WhisperKit) →
/// clean (Ollama, with raw fallback) → insert into the frontmost app.
@MainActor
final class DictationController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loadingModel
        case recording
        case transcribing
        case cleaning
        case inserting

        var symbolName: String {
            switch self {
            case .idle: return "mic"
            case .loadingModel: return "arrow.down.circle"
            case .recording: return "mic.fill"
            case .transcribing: return "waveform"
            case .cleaning: return "wand.and.stars"
            case .inserting: return "text.cursor"
            }
        }

        var label: String {
            switch self {
            case .idle: return "Ready — hold Right ⌥ to dictate"
            case .loadingModel: return "Downloading / loading Whisper model…"
            case .recording: return "Recording… release Right ⌥ to finish"
            case .transcribing: return "Transcribing…"
            case .cleaning: return "Cleaning up with Ollama…"
            case .inserting: return "Inserting text…"
            }
        }
    }

    @Published var phase: Phase = .idle
    @Published var errorMessage: String?
    @Published var lastTranscript = ""
    @Published var accessibilityGranted = false
    @Published var microphoneGranted = false

    /// Ignore recordings shorter than this — accidental taps of the hotkey.
    private static let minimumSamples = Int(AudioEngine.sampleRate * 0.5)

    private let hotkey = HotkeyManager()
    private let audio = AudioEngine()
    private let transcriber = WhisperTranscriber()
    private let cleaner = OllamaCleaner()
    private let overlay = RecordingOverlay()

    /// Owns the Ollama model catalog (installed state, background downloads,
    /// warm-up). Injected into the menu so the model dropdown can observe it.
    let ollama = OllamaModelManager()

    init() {
        Settings.register()

        Permissions.requestMicrophone()
        accessibilityGranted = Permissions.promptAccessibility()
        microphoneGranted = Permissions.microphoneGranted

        hotkey.onPress = { [weak self] in self?.hotkeyPressed() }
        hotkey.onRelease = { [weak self] in self?.hotkeyReleased() }
        if !hotkey.start() {
            errorMessage = "Could not install the global hotkey. Grant Accessibility permission, then relaunch Murmur."
        }

        Task { await preloadModel() }

        // Warm up the Ollama cleanup model on launch so the first dictation
        // isn't slowed by a cold model load. Refresh the installed catalog too.
        if Settings.cleanupEnabled {
            ollama.warmUp(Settings.ollamaModel)
        }
        Task { await ollama.refresh() }
    }

    func refreshPermissions() {
        accessibilityGranted = Permissions.accessibilityGranted
        microphoneGranted = Permissions.microphoneGranted
        // If permission arrived after launch, the tap may not exist yet.
        if accessibilityGranted {
            hotkey.start()
        }
    }

    /// Load the Whisper model up front so the first dictation isn't slow.
    private func preloadModel() async {
        phase = .loadingModel
        do {
            try await transcriber.load(model: Settings.whisperModel)
            phase = .idle
        } catch {
            phase = .idle
            errorMessage = "Failed to load Whisper model: \(error.localizedDescription)"
        }
    }

    private func hotkeyPressed() {
        guard phase == .idle else {
            // Model still loading or a previous dictation still processing:
            // tell the user why nothing is being recorded.
            if Settings.overlayEnabled { overlay.show(.notReady) }
            return
        }
        errorMessage = nil
        do {
            try audio.start()
            phase = .recording
            playSound("Tink")
            if Settings.overlayEnabled {
                overlay.show(.listening, level: { [audio] in audio.level })
            }
        } catch {
            errorMessage = "Could not start recording: \(error.localizedDescription)"
        }
    }

    private func hotkeyReleased() {
        // Always dismiss the overlay on release, even when the press was
        // ignored (not-ready state) and no recording is in flight.
        overlay.hide()

        guard phase == .recording else { return }
        let samples = audio.stop()
        playSound("Pop")

        guard samples.count >= Self.minimumSamples else {
            phase = .idle
            return
        }
        Task { await process(samples) }
    }

    private func process(_ samples: [Float]) async {
        do {
            let vocabulary = Settings.vocabularyTerms

            phase = .transcribing
            let raw = try await transcriber.transcribe(
                samples: samples,
                model: Settings.whisperModel,
                vocabulary: vocabulary
            )
            guard !raw.isEmpty else {
                phase = .idle
                return
            }

            // Deterministic vocabulary fix-up before the LLM sees the text,
            // so cleanup never has to guess at spellings.
            var text = VocabularyCorrector(terms: vocabulary).correct(raw)

            if Settings.cleanupEnabled {
                phase = .cleaning
                text = await cleaner.clean(
                    text,
                    model: Settings.ollamaModel,
                    baseURL: Settings.ollamaURL,
                    vocabulary: vocabulary
                )
            }

            lastTranscript = text
            phase = .inserting
            await TextInjector.insert(text)
            phase = .idle
        } catch {
            phase = .idle
            errorMessage = "Transcription failed: \(error.localizedDescription)"
        }
    }

    /// Manual pipeline check without needing Ollama or a hotkey press: inserts a
    /// test string wherever focus is 2 seconds from now.
    func insertTestText() {
        Task {
            try? await Task.sleep(for: .seconds(2))
            await TextInjector.insert("Murmur test insert — text injection is working.")
        }
    }

    private func playSound(_ name: String) {
        guard Settings.soundFeedback else { return }
        NSSound(named: name)?.play()
    }
}
