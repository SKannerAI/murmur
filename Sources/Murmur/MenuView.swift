import SwiftUI

/// The menu-bar popover: status, settings, permissions, and last transcript.
struct MenuView: View {
    @EnvironmentObject private var controller: DictationController

    @AppStorage(Settings.Keys.whisperModel) private var whisperModel = "base.en"
    @AppStorage(Settings.Keys.ollamaModel) private var ollamaModel = "qwen2.5:3b"
    @AppStorage(Settings.Keys.ollamaURL) private var ollamaURL = "http://127.0.0.1:11434"
    @AppStorage(Settings.Keys.cleanupEnabled) private var cleanupEnabled = true
    @AppStorage(Settings.Keys.soundFeedback) private var soundFeedback = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusSection
            Divider()
            settingsSection
            Divider()
            permissionsSection

            if !controller.lastTranscript.isEmpty {
                Divider()
                lastTranscriptSection
            }

            Divider()
            footerSection
        }
        .padding(12)
        .frame(width: 340)
        .onAppear { controller.refreshPermissions() }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: controller.phase.symbolName)
                Text(controller.phase.label)
                    .font(.callout)
            }
            if let error = controller.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Whisper model", selection: $whisperModel) {
                ForEach(Settings.whisperModels, id: \.name) { model in
                    Text(model.label).tag(model.name)
                }
            }
            .pickerStyle(.menu)

            Toggle("LLM cleanup via Ollama", isOn: $cleanupEnabled)

            if cleanupEnabled {
                TextField("Ollama model", text: $ollamaModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                TextField("Ollama URL", text: $ollamaURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            Toggle("Sound feedback", isOn: $soundFeedback)
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            permissionRow(
                name: "Accessibility",
                granted: controller.accessibilityGranted,
                action: Permissions.openAccessibilitySettings
            )
            permissionRow(
                name: "Microphone",
                granted: controller.microphoneGranted,
                action: Permissions.openMicrophoneSettings
            )
        }
    }

    private func permissionRow(name: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
            Text(name)
                .font(.caption)
            Spacer()
            if !granted {
                Button("Open Settings", action: action)
                    .font(.caption)
            }
        }
    }

    private var lastTranscriptSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last dictation")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(controller.lastTranscript)
                .font(.caption)
                .lineLimit(4)
                .textSelection(.enabled)
        }
    }

    private var footerSection: some View {
        HStack {
            Button("Test insert (2s)") { controller.insertTestText() }
                .font(.caption)
            Spacer()
            Button("Quit Murmur") { NSApplication.shared.terminate(nil) }
                .font(.caption)
        }
    }
}
