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
        onChunk: @escaping (String) -> Void
    ) async -> String? {
        switch provider {
        case .openRouter:
            return await generateOpenRouterAnswerStreaming(messages: messages, onChunk: onChunk)
        case .google:
            return await generateGeminiAnswerStreaming(messages: messages, onChunk: onChunk)
        }
    }

    private func generateOpenRouterAnswerStreaming(
        messages: [LLMMessage],
        onChunk: @escaping (String) -> Void
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

        let requestBody = ChatCompletionRequest(messages: messages, stream: true)

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
            for try await line in bytes.lines {
                try Task.checkCancellation()

                guard line.hasPrefix("data: ") else { continue }

                let json = String(line.dropFirst(6))
                if json == "[DONE]" { break }

                if let data = json.data(using: .utf8),
                   let chunk = try? JSONDecoder().decode(OpenRouterStreamChunk.self, from: data),
                   let content = chunk.choices.first?.delta.content {
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

            return await fail("OpenRouter streaming error: \(error.localizedDescription)")
        }
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
        }
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
