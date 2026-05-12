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

struct OpenRouterProviderEndpoint: Identifiable, Equatable {
    let id: String
    let name: String
    let providerName: String
    let tag: String
    let quantization: String?
    let promptPrice: Double?
    let completionPrice: Double?
    let cacheReadPrice: Double?
    let cacheWritePrice: Double?
    let latencyP50: Double?
    let throughputP50: Double?
    let uptimeLast30m: Double?
    let supportsImplicitCaching: Bool
    let status: Int?
    let supportedParameters: Set<String>

    var isFree: Bool {
        (promptPrice ?? 0) == 0 && (completionPrice ?? 0) == 0
    }
}

@MainActor
final class OpenRouterModelCatalog: ObservableObject {
    static let shared = OpenRouterModelCatalog()

    @Published private(set) var models: [String: OpenRouterModelMetadata]?
    @Published private(set) var endpointsByModel: [String: [OpenRouterProviderEndpoint]] = [:]

    private let session: URLSession
    private var loadTask: Task<[String: OpenRouterModelMetadata]?, Never>?
    private var endpointTasks: [String: Task<[OpenRouterProviderEndpoint]?, Never>] = [:]

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

    func endpoints(for model: String) -> [OpenRouterProviderEndpoint]? {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return endpointsByModel[trimmed]
    }

    func endpointsLoadingIfNeeded(for model: String, force: Bool = false) async -> [OpenRouterProviderEndpoint]? {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if !force, let endpoints = endpointsByModel[trimmed] {
            return endpoints
        }

        if !force, let endpointTask = endpointTasks[trimmed] {
            return await endpointTask.value
        }

        let task = Task { [session] in
            await Self.fetchEndpoints(model: trimmed, session: session)
        }

        endpointTasks[trimmed] = task
        let result = await task.value
        endpointTasks[trimmed] = nil

        if let result {
            endpointsByModel[trimmed] = result
        }

        return result
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

    private static func fetchEndpoints(model: String, session: URLSession) async -> [OpenRouterProviderEndpoint]? {
        let parts = model.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            print("[OpenRouter] Invalid model id for endpoint lookup: \(model)")
            return nil
        }

        guard let author = parts.first?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let slug = parts.last?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://openrouter.ai/api/v1/models/\(author)/\(slug)/endpoints") else {
            print("[OpenRouter] Invalid endpoints URL for model \(model).")
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
                print("[OpenRouter] Invalid endpoints response for \(model).")
                return nil
            }

            guard httpResponse.statusCode == 200 else {
                print("[OpenRouter] Endpoints request failed for \(model) with status \(httpResponse.statusCode): \(responseSnippet(from: data))")
                return nil
            }

            let decoded = try JSONDecoder().decode(OpenRouterEndpointsResponse.self, from: data)
            let endpoints = decoded.data.endpoints.compactMap { endpoint -> OpenRouterProviderEndpoint? in
                let tag = endpoint.tag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !tag.isEmpty else { return nil }

                return OpenRouterProviderEndpoint(
                    id: tag,
                    name: endpoint.name,
                    providerName: endpoint.provider_name,
                    tag: tag,
                    quantization: endpoint.quantization,
                    promptPrice: endpoint.pricing.promptValue,
                    completionPrice: endpoint.pricing.completionValue,
                    cacheReadPrice: endpoint.pricing.input_cache_readValue,
                    cacheWritePrice: endpoint.pricing.input_cache_writeValue,
                    latencyP50: endpoint.latency_last_30m?.p50,
                    throughputP50: endpoint.throughput_last_30m?.p50,
                    uptimeLast30m: endpoint.uptime_last_30m,
                    supportsImplicitCaching: endpoint.supports_implicit_caching ?? false,
                    status: endpoint.statusValue,
                    supportedParameters: Set(endpoint.supported_parameters ?? [])
                )
            }

            print("[OpenRouter] Loaded \(endpoints.count) providers for \(model).")
            return endpoints
        } catch {
            if Task.isCancelled { return nil }
            print("[OpenRouter] Endpoint metadata error for \(model): \(error.localizedDescription)")
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

private struct OpenRouterEndpointsResponse: Decodable {
    let data: DataObject

    struct DataObject: Decodable {
        let endpoints: [Endpoint]
    }

    struct Endpoint: Decodable {
        let name: String
        let provider_name: String
        let tag: String?
        let quantization: String?
        let pricing: Pricing
        let supported_parameters: [String]?
        let latency_last_30m: Percentiles?
        let throughput_last_30m: Percentiles?
        let uptime_last_30m: Double?
        let supports_implicit_caching: Bool?
        private let status: FlexibleNumber?

        var statusValue: Int? {
            status?.intValue
        }
    }

    struct Percentiles: Decodable {
        let p50: Double?
    }

    struct Pricing: Decodable {
        let prompt: FlexibleNumber?
        let completion: FlexibleNumber?
        let input_cache_read: FlexibleNumber?
        let input_cache_write: FlexibleNumber?

        var promptValue: Double? { prompt?.doubleValue }
        var completionValue: Double? { completion?.doubleValue }
        var input_cache_readValue: Double? { input_cache_read?.doubleValue }
        var input_cache_writeValue: Double? { input_cache_write?.doubleValue }
    }

    struct FlexibleNumber: Decodable {
        let doubleValue: Double?

        var intValue: Int? {
            doubleValue.map(Int.init)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Double.self) {
                doubleValue = value
            } else if let value = try? container.decode(String.self) {
                doubleValue = Double(value)
            } else {
                doubleValue = nil
            }
        }
    }
}
