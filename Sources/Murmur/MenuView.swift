import SwiftUI

/// The menu-bar popover: status, settings, permissions, and last transcript.
struct MenuView: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var ollama: OllamaModelManager

    @AppStorage(Settings.Keys.whisperModel) private var whisperModel = "base.en"
    @AppStorage(Settings.Keys.ollamaModel) private var ollamaModel = "qwen2.5:3b"
    @AppStorage(Settings.Keys.ollamaURL) private var ollamaURL = "http://127.0.0.1:11434"
    @AppStorage(Settings.Keys.cleanupEnabled) private var cleanupEnabled = true
    @AppStorage(Settings.Keys.soundFeedback) private var soundFeedback = true
    @AppStorage(Settings.Keys.overlayEnabled) private var overlayEnabled = true
    @AppStorage(Settings.Keys.vocabulary) private var vocabularyRaw = ""

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
        .task { await ollama.refresh() }
    }

    /// Curated cleanup models plus any others the server already has installed,
    /// and the current selection so it's always present even if unknown.
    private var ollamaModelOptions: [String] {
        var names = Settings.ollamaModels.map(\.name)
        for name in ollama.installed.sorted() where !names.contains(name) {
            names.append(name)
        }
        if !names.contains(ollamaModel) { names.append(ollamaModel) }
        return names
    }

    private func ollamaLabel(for name: String) -> String {
        let base = Settings.ollamaModels.first { $0.name == name }?.label ?? name
        return ollama.isInstalled(name) ? "\(base)  ✓" : base
    }

    /// Install state / background-download control for the selected model.
    @ViewBuilder
    private var ollamaModelStatus: some View {
        if ollama.isDownloading(ollamaModel) {
            HStack(spacing: 6) {
                ProgressView(value: ollama.progress(ollamaModel))
                Text("\(Int(ollama.progress(ollamaModel) * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else if ollama.isInstalled(ollamaModel) {
            Label("Installed", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            HStack {
                Text("Not installed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Download") { ollama.download(ollamaModel) }
                    .font(.caption)
            }
        }
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
                Picker("Ollama model", selection: $ollamaModel) {
                    ForEach(ollamaModelOptions, id: \.self) { name in
                        Text(ollamaLabel(for: name)).tag(name)
                    }
                }
                .pickerStyle(.menu)

                ollamaModelStatus

                TextField("Ollama URL", text: $ollamaURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            Toggle("Recording overlay", isOn: $overlayEnabled)
            Toggle("Sound feedback", isOn: $soundFeedback)

            DisclosureGroup("Custom vocabulary (\(Settings.vocabularyTerms.count))") {
                VStack(alignment: .leading, spacing: 4) {
                    TextEditor(text: $vocabularyRaw)
                        .font(.caption.monospaced())
                        .frame(height: 76)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary))
                    Text("Names, acronyms, jargon — one per line or comma-separated. Applied to recognition, spelling fix-up, and cleanup.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            .font(.callout)
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
