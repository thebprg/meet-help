import Foundation

class LLMService: ObservableObject {
    @Published var isProcessing = false
    @Published var error: String?

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    func generateAnswerStreaming(
        provider: LLMProvider,
        messages: [LLMMessage],
        onChunk: @escaping (String) -> Void,
        onReasoning: @escaping (String) -> Void = { _ in }
    ) async -> String? {
        switch provider {
        case .openRouter:
            return await generateOpenRouterAnswerStreaming(messages: messages, onChunk: onChunk, onReasoning: onReasoning)
        case .google:
            return await generateGeminiAnswerStreaming(messages: messages, onChunk: onChunk)
        }
    }

    func generateSearchQuery(messages: [LLMMessage], fallbackQuery: String) async -> String? {
        guard !Config.openRouterAPIKey.isEmpty else {
            return await fail("OpenRouter API key is missing. Add it in Settings.")
        }

        guard let url = URL(string: Config.openRouterAPIURL) else {
            return await fail("Invalid OpenRouter API URL.")
        }

        let model = Config.openRouterSearchModel
        let context = messages
            .suffix(8)
            .map { "\($0.role): \($0.content)" }
            .joined(separator: "\n\n")

        let rewriteMessages = [
            LLMMessage(
                role: "system",
                content: """
                Rewrite noisy meeting transcripts or user starter clues into one concise web search query.
                Return only the search query. No quotes, no markdown, no explanation.
                Prefer named entities, technologies, error messages, dates, product names, and the user's actual information need.
                Keep it under 18 words.
                """
            ),
            LLMMessage(
                role: "user",
                content: """
                Recent context:
                \(context)

                Latest input:
                \(fallbackQuery)

                Search query:
                """
            )
        ]

        let supportedParameters = await OpenRouterModelCatalog.shared.supportedParametersLoadingIfNeeded(for: model)
        let requestBody = ChatCompletionRequest(
            messages: rewriteMessages,
            stream: false,
            model: model,
            options: Config.openRouterSearchOptions,
            supportedParameters: supportedParameters
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(Config.openRouterAPIKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("MeetHelp", forHTTPHeaderField: "X-Title")

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            return await fail("Failed to encode OpenRouter search-query request: \(error.localizedDescription)")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return await fail("Invalid OpenRouter search-query response.")
            }

            guard httpResponse.statusCode == 200 else {
                return await fail("OpenRouter search-query request failed with status \(httpResponse.statusCode).")
            }

            let decoded = try JSONDecoder().decode(OpenRouterCompletionResponse.self, from: data)
            let query = decoded.choices.first?.message.content?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`")) ?? ""

            guard !query.isEmpty else {
                return await fail("OpenRouter search-query model returned an empty query.")
            }

            return String(query.prefix(240))
        } catch {
            if Task.isCancelled { return nil }
            return await fail("OpenRouter search-query error: \(error.localizedDescription)")
        }
    }

    private func generateOpenRouterAnswerStreaming(
        messages: [LLMMessage],
        onChunk: @escaping (String) -> Void,
        onReasoning: @escaping (String) -> Void
    ) async -> String? {
        guard !Config.openRouterAPIKey.isEmpty else {
            return await fail("OpenRouter API key is missing. Add it in Settings.")
        }

        guard let url = URL(string: Config.openRouterAPIURL) else {
            return await fail("Invalid OpenRouter API URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(Config.openRouterAPIKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("MeetHelp", forHTTPHeaderField: "X-Title")

        let model = Config.selectedOpenRouterModel
        let supportedParameters = await OpenRouterModelCatalog.shared.supportedParametersLoadingIfNeeded(for: model)
        let requestBody = ChatCompletionRequest(
            messages: messages,
            stream: true,
            model: model,
            options: Config.selectedOpenRouterOptions,
            supportedParameters: supportedParameters
        )

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            return await fail("Failed to encode OpenRouter request: \(error.localizedDescription)")
        }

        await MainActor.run {
            self.isProcessing = true
            self.error = nil
        }

        do {
            let (bytes, response) = try await session.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return await fail("Invalid OpenRouter streaming response.")
            }

            guard httpResponse.statusCode == 200 else {
                return await fail("OpenRouter streaming request failed with status \(httpResponse.statusCode).")
            }

            var fullAnswer = ""
            var fullReasoning = ""
            for try await line in bytes.lines {
                try Task.checkCancellation()

                guard line.hasPrefix("data: ") else { continue }

                let json = String(line.dropFirst(6))
                if json == "[DONE]" { break }

                if let data = json.data(using: .utf8),
                   let chunk = try? JSONDecoder().decode(OpenRouterStreamChunk.self, from: data),
                   let delta = chunk.choices.first?.delta {
                    let reasoning = delta.reasoningText
                    if !reasoning.isEmpty {
                        fullReasoning = Self.mergedReasoning(existing: fullReasoning, incoming: reasoning)
                        let reasoningSnapshot = fullReasoning
                        await MainActor.run {
                            onReasoning(reasoningSnapshot)
                        }
                    }

                    if let content = delta.content {
                        fullAnswer += content
                        await MainActor.run {
                            onChunk(content)
                        }
                    }
                }
            }

            await MainActor.run { self.isProcessing = false }
            return fullAnswer
        } catch {
            if Task.isCancelled {
                await MainActor.run { self.isProcessing = false }
                return nil
            }

            return await fail("OpenRouter streaming error: \(error.localizedDescription)")
        }
    }

    private static func mergedReasoning(existing: String, incoming: String) -> String {
        guard !incoming.isEmpty else { return existing }
        guard !existing.isEmpty else { return incoming }

        if incoming.hasPrefix(existing) {
            return incoming
        }

        if existing.hasSuffix(incoming) {
            return existing
        }

        let maxOverlap = min(existing.count, incoming.count)
        if maxOverlap > 0 {
            for overlap in stride(from: maxOverlap, through: 1, by: -1) {
                let existingSuffix = existing.suffix(overlap)
                let incomingPrefix = incoming.prefix(overlap)
                if existingSuffix == incomingPrefix {
                    return existing + incoming.dropFirst(overlap)
                }
            }
        }

        return existing + incoming
    }

    private func generateGeminiAnswerStreaming(
        messages: [LLMMessage],
        onChunk: @escaping (String) -> Void
    ) async -> String? {
        guard !Config.geminiAPIKey.isEmpty else {
            return await fail("Gemini API key is missing. Add it in Settings.")
        }

        var components = URLComponents(string: Config.geminiStreamURL)
        components?.queryItems = [
            URLQueryItem(name: "key", value: Config.geminiAPIKey),
            URLQueryItem(name: "alt", value: "sse")
        ]

        guard let url = components?.url else {
            return await fail("Invalid Gemini API URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(GeminiRequest(messages: messages))
        } catch {
            return await fail("Failed to encode Gemini request: \(error.localizedDescription)")
        }

        await MainActor.run {
            self.isProcessing = true
            self.error = nil
        }

        do {
            let (bytes, response) = try await session.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return await fail("Invalid Gemini streaming response.")
            }

            guard httpResponse.statusCode == 200 else {
                return await fail("Gemini streaming request failed with status \(httpResponse.statusCode).")
            }

            var fullAnswer = ""
            for try await line in bytes.lines {
                try Task.checkCancellation()

                guard line.hasPrefix("data: ") else { continue }

                let json = String(line.dropFirst(6))
                if let data = json.data(using: .utf8),
                   let chunk = try? JSONDecoder().decode(GeminiStreamChunk.self, from: data) {
                    let content = chunk.candidates.first?.content.parts.compactMap(\.text).joined() ?? ""
                    guard !content.isEmpty else { continue }

                    fullAnswer += content
                    await MainActor.run {
                        onChunk(content)
                    }
                }
            }

            await MainActor.run { self.isProcessing = false }
            return fullAnswer
        } catch {
            if Task.isCancelled {
                await MainActor.run { self.isProcessing = false }
                return nil
            }

            return await fail("Gemini streaming error: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func fail(_ message: String) -> String? {
        isProcessing = false
        error = message
        print("[LLM] \(message)")
        return nil
    }
}

private struct OpenRouterStreamChunk: Codable {
    let choices: [Choice]

    struct Choice: Codable {
        let delta: Delta

        struct Delta: Codable {
            let content: String?
            let reasoning: String?
            let reasoning_content: String?
            let reasoning_details: [ReasoningDetail]?

            var reasoningText: String {
                let rawText = reasoning_content ?? reasoning ?? reasoning_details?.compactMap(\.displayText).joined()
                guard let rawText else { return "" }

                let visibleText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !visibleText.isEmpty, visibleText != "[REDACTED]" else { return "" }

                return rawText
            }
        }

        struct ReasoningDetail: Codable {
            let type: String?
            let text: String?
            let summary: String?

            var displayText: String? {
                text ?? summary
            }
        }
    }
}

private struct OpenRouterCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }
}

private struct GeminiRequest: Encodable {
    let systemInstruction: GeminiContent?
    let contents: [GeminiContent]
    let generationConfig: GenerationConfig

    init(messages: [LLMMessage]) {
        let systemText = messages
            .filter { $0.role == "system" }
            .map(\.content)
            .joined(separator: "\n\n")

        self.systemInstruction = systemText.isEmpty ? nil : GeminiContent(
            role: nil,
            parts: [GeminiPart(text: systemText)]
        )

        self.contents = messages.compactMap { message in
            guard message.role != "system" else { return nil }

            let role = message.role == "assistant" ? "model" : "user"
            return GeminiContent(role: role, parts: [GeminiPart(text: message.content)])
        }

        self.generationConfig = GenerationConfig(
            temperature: 0.7,
            topP: 1.0,
            maxOutputTokens: 4096
        )
    }

    struct GenerationConfig: Encodable {
        let temperature: Double
        let topP: Double
        let maxOutputTokens: Int
    }
}

private struct GeminiContent: Codable {
    let role: String?
    let parts: [GeminiPart]

    enum CodingKeys: String, CodingKey {
        case role
        case parts
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encode(parts, forKey: .parts)
    }
}

private struct GeminiPart: Codable {
    let text: String?
}

private struct GeminiStreamChunk: Decodable {
    let candidates: [Candidate]

    struct Candidate: Decodable {
        let content: GeminiContent
    }
}

final class YouSearchService: ObservableObject {
    @Published var error: String?

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        self.session = URLSession(configuration: config)
    }

    func searchContext(for query: String) async -> String? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }

        guard !Config.youAPIKey.isEmpty else {
            return await fail("YOU_API_KEY is missing. Add it in Settings.")
        }

        guard var components = URLComponents(string: Config.youSearchURL) else {
            return await fail("Invalid You.com Search API URL.")
        }

        components.queryItems = [
            URLQueryItem(name: "query", value: trimmedQuery),
            URLQueryItem(name: "count", value: "5")
        ]

        guard let url = components.url else {
            return await fail("Invalid You.com search query URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(Config.youAPIKey, forHTTPHeaderField: "X-API-Key")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return await fail("Invalid You.com search response.")
            }

            guard httpResponse.statusCode == 200 else {
                return await fail("You.com search failed with status \(httpResponse.statusCode).")
            }

            let decoded = try JSONDecoder().decode(YouSearchResponse.self, from: data)
            let context = decoded.llmContext(limit: 5)

            guard !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return await fail("You.com search returned no usable snippets.")
            }

            await MainActor.run {
                self.error = nil
            }
            return context
        } catch {
            if Task.isCancelled { return nil }
            return await fail("You.com search error: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func fail(_ message: String) -> String? {
        error = message
        print("[LiveSearch] \(message)")
        return nil
    }
}

private struct YouSearchResponse: Decodable {
    let results: Results?

    struct Results: Decodable {
        let web: [SearchResult]?
        let news: [SearchResult]?
    }

    struct SearchResult: Decodable {
        let url: String?
        let title: String?
        let description: String?
        let snippets: [String]?
        let snippet: String?
        let publishedDate: String?

        enum CodingKeys: String, CodingKey {
            case url
            case title
            case description
            case snippets
            case snippet
            case publishedDate = "published_date"
        }

        var contextText: String {
            var pieces: [String] = []
            if let description, !description.isEmpty {
                pieces.append(description)
            }
            if let snippet, !snippet.isEmpty {
                pieces.append(snippet)
            }
            if let snippets {
                pieces.append(contentsOf: snippets.filter { !$0.isEmpty })
            }
            return pieces
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func llmContext(limit: Int) -> String {
        var entries: [(section: String, result: SearchResult)] = []

        if let web = results?.web {
            entries.append(contentsOf: web.map { ("Web", $0) })
        }
        if let news = results?.news {
            entries.append(contentsOf: news.map { ("News", $0) })
        }

        let formatted = entries
            .prefix(limit)
            .enumerated()
            .compactMap { index, entry -> String? in
                let result = entry.result
                let title = result.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Untitled"
                let url = result.url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let context = result.contextText
                guard !context.isEmpty || !url.isEmpty else { return nil }

                var lines = ["\(index + 1). [\(entry.section)] \(title)"]
                if !url.isEmpty {
                    lines.append("URL: \(url)")
                }
                if let publishedDate = result.publishedDate, !publishedDate.isEmpty {
                    lines.append("Published: \(publishedDate)")
                }
                if !context.isEmpty {
                    lines.append("Snippet: \(context)")
                }
                return lines.joined(separator: "\n")
            }

        guard !formatted.isEmpty else { return "" }

        return """
        Use this live web context only when it is relevant to the user's question. Prefer cited facts from these results for current or external information.

        \(formatted.joined(separator: "\n\n"))
        """
    }
}
