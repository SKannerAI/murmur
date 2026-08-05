import Foundation

/// Talks to the local Ollama server about the cleanup model: which models are
/// installed (`/api/tags`), pulling missing ones in the background with progress
/// (`/api/pull`), and warming up the active model so the first cleanup is fast
/// (`/api/generate` with an empty prompt loads it into memory).
@MainActor
final class OllamaModelManager: ObservableObject {
    /// Names of models the Ollama server reports as installed.
    @Published private(set) var installed: Set<String> = []
    /// In-flight pulls: model name → progress (0…1).
    @Published private(set) var downloading: [String: Double] = [:]
    /// Non-fatal status surfaced in the menu (e.g. server unreachable).
    @Published private(set) var status: String?

    func isInstalled(_ model: String) -> Bool { installed.contains(model) }
    func isDownloading(_ model: String) -> Bool { downloading[model] != nil }
    func progress(_ model: String) -> Double { downloading[model] ?? 0 }

    /// Refresh the installed set from `GET /api/tags`.
    func refresh() async {
        do {
            let url = Settings.ollamaURL.appendingPathComponent("api/tags")
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                status = "Ollama not reachable"
                return
            }
            let tags = try JSONDecoder().decode(TagsResponse.self, from: data)
            installed = Set(tags.models.map(\.name))
            status = nil
        } catch {
            status = "Ollama not running"
        }
    }

    /// Pull a model in the background, streaming progress from `POST /api/pull`.
    func download(_ model: String) {
        guard downloading[model] == nil else { return }
        downloading[model] = 0
        Task {
            do {
                var request = URLRequest(url: Settings.ollamaURL.appendingPathComponent("api/pull"))
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(PullRequest(name: model, stream: true))

                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    finish(model, error: "Download failed")
                    return
                }
                for try await line in bytes.lines {
                    guard let data = line.data(using: .utf8),
                          let update = try? JSONDecoder().decode(PullProgress.self, from: data)
                    else { continue }
                    if let total = update.total, let completed = update.completed, total > 0 {
                        downloading[model] = Double(completed) / Double(total)
                    }
                }
                downloading[model] = nil
                await refresh()
            } catch {
                finish(model, error: "Download failed: \(error.localizedDescription)")
            }
        }
    }

    /// Load the model into memory so the first cleanup after launch isn't slow.
    func warmUp(_ model: String) {
        Task {
            var request = URLRequest(url: Settings.ollamaURL.appendingPathComponent("api/generate"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(WarmUpRequest(model: model))
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    private func finish(_ model: String, error: String) {
        downloading[model] = nil
        status = error
    }

    // MARK: - Wire types

    private struct TagsResponse: Decodable {
        struct Model: Decodable { let name: String }
        let models: [Model]
    }

    private struct PullRequest: Encodable {
        let name: String
        let stream: Bool
    }

    private struct PullProgress: Decodable {
        let status: String
        let total: Int?
        let completed: Int?
    }

    private struct WarmUpRequest: Encodable {
        let model: String
        let prompt = ""
        let stream = false
        let keepAlive = "30m"

        enum CodingKeys: String, CodingKey {
            case model, prompt, stream
            case keepAlive = "keep_alive"
        }
    }
}
