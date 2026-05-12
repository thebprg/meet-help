import Foundation

enum OpenRouterModelCapability {
    case unknown
    case textOnly
    case imageInput
}

struct OpenRouterModelMetadata: Equatable {
    let id: String
    let inputModalities: Set<String>
    let supportedParameters: Set<String>
}

@MainActor
final class OpenRouterModelCatalog: ObservableObject {
    static let shared = OpenRouterModelCatalog()

    @Published private(set) var models: [String: OpenRouterModelMetadata]?

    private let session: URLSession
    private var loadTask: Task<[String: OpenRouterModelMetadata]?, Never>?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    func warm() async {
        _ = await loadIfNeeded()
    }

    func refresh() async {
        _ = await loadIfNeeded(force: true)
    }

    func capability(for model: String) -> OpenRouterModelCapability {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }
        guard let metadata = models?[trimmed] else {
            return models == nil ? .unknown : .textOnly
        }

        return metadata.inputModalities.contains("image") ? .imageInput : .textOnly
    }

    func supportedParameters(for model: String) -> Set<String>? {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return models?[trimmed]?.supportedParameters
    }

    func supportedParametersLoadingIfNeeded(for model: String) async -> Set<String>? {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if models == nil {
            _ = await loadIfNeeded()
        }

        return models?[trimmed]?.supportedParameters
    }

    func imageCapableModelIDsLoadingIfNeeded() async -> Set<String>? {
        let metadata = await loadIfNeeded()
        return metadata?
            .values
            .filter { $0.inputModalities.contains("image") }
            .reduce(into: Set<String>()) { $0.insert($1.id) }
    }

    private func loadIfNeeded(force: Bool = false) async -> [String: OpenRouterModelMetadata]? {
        if !force, let models {
            return models
        }

        if !force, let loadTask {
            return await loadTask.value
        }

        let task = Task { [session] in
            await Self.fetchModels(session: session)
        }

        loadTask = task
        let result = await task.value
        loadTask = nil

        if let result {
            models = result
        }

        return result
    }

    private static func fetchModels(session: URLSession) async -> [String: OpenRouterModelMetadata]? {
        guard let url = URL(string: Config.openRouterModelsURL) else {
            print("[OpenRouter] Invalid models URL.")
            return nil
        }

        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        if !Config.openRouterAPIKey.isEmpty {
            request.addValue("Bearer \(Config.openRouterAPIKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("[OpenRouter] Invalid models response.")
                return nil
            }

            guard httpResponse.statusCode == 200 else {
                print("[OpenRouter] Models request failed with status \(httpResponse.statusCode): \(responseSnippet(from: data))")
                return nil
            }

            let decoded = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
            let metadata = decoded.data.reduce(into: [String: OpenRouterModelMetadata]()) { result, model in
                result[model.id] = OpenRouterModelMetadata(
                    id: model.id,
                    inputModalities: Set(model.architecture.input_modalities),
                    supportedParameters: Set(model.supported_parameters ?? [])
                )
            }

            let imageCount = metadata.values.filter { $0.inputModalities.contains("image") }.count
            print("[OpenRouter] Loaded metadata for \(metadata.count) models; \(imageCount) support image input.")
            return metadata
        } catch {
            if Task.isCancelled { return nil }
            print("[OpenRouter] Models metadata error: \(error.localizedDescription)")
            return nil
        }
    }

    private static func responseSnippet(from data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
        return String(singleLine.prefix(600))
    }
}

private struct OpenRouterModelsResponse: Decodable {
    let data: [Model]

    struct Model: Decodable {
        let id: String
        let architecture: Architecture
        let supported_parameters: [String]?
    }

    struct Architecture: Decodable {
        let input_modalities: [String]
    }
}
