import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum OpenRouterModelCapability {
    case unknown
    case textOnly
    case imageInput
}

final class ScreenAnalysisService: ObservableObject {
    @Published var error: String?
    @Published private(set) var openRouterImageInputModels: Set<String>?

    private let session: URLSession
    private var providerCooldownUntil: [LLMProvider: Date] = [:]
    private let providerCooldownDuration: TimeInterval = 60

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
    }

    func captureScreen(excluding window: NSWindow?) -> Data? {
        guard hasScreenCaptureAccess() else { return nil }

        let image = capturedImage(excluding: window)
        guard let image else {
            error = "Unable to capture screen. Check Screen Recording permission."
            print("[ScreenAnalysis] Screen capture failed.")
            return nil
        }

        guard let data = jpegData(from: image) else {
            error = "Unable to encode screen capture."
            print("[ScreenAnalysis] Screen capture encoding failed.")
            return nil
        }

        error = nil
        print("[ScreenAnalysis] Captured screen image: \(data.count) bytes.")
        return data
    }

    func analyzeScreen(imageData: Data) async -> String? {
        let base64Image = imageData.base64EncodedString()
        let selectedProvider = Config.selectedLLMProvider
        let providers = providerAttemptSequence(primary: selectedProvider)
        let maxAttempts = 3

        for provider in providers {
            guard !Task.isCancelled else { return nil }

            if provider != selectedProvider {
                print("[ScreenAnalysis] Using fallback image provider: \(provider.displayName)")
            } else {
                print("[ScreenAnalysis] Using selected image provider: \(provider.displayName)")
            }

            for attempt in 1...maxAttempts {
                guard !Task.isCancelled else { return nil }

                print("[ScreenAnalysis] Starting \(provider.displayName) image analysis attempt \(attempt)/\(maxAttempts).")
                if let result = await analyzeWithProvider(provider, base64Image: base64Image) {
                    markProviderHealthy(provider)
                    return result
                }

                print("[ScreenAnalysis] \(provider.displayName) image analysis attempt \(attempt)/\(maxAttempts) failed: \(error ?? "unknown error")")
                if attempt < maxAttempts {
                    print("[ScreenAnalysis] Retrying \(provider.displayName) image analysis...")
                }
            }

            markProviderUnhealthy(provider)
            if provider == selectedProvider {
                print("[ScreenAnalysis] \(provider.displayName) image analysis failed after \(maxAttempts) attempts; falling back to \(provider.fallbackProvider.displayName).")
            }
        }

        return nil
    }

    func warmOpenRouterModelCapabilities() async {
        guard openRouterImageInputModels == nil else { return }

        if let models = await fetchOpenRouterImageInputModels() {
            openRouterImageInputModels = models
        }
    }

    func openRouterCapability(for model: String) -> OpenRouterModelCapability {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }
        guard let openRouterImageInputModels else { return .unknown }

        return openRouterImageInputModels.contains(trimmed) ? .imageInput : .textOnly
    }

    private func analyzeWithOpenRouter(base64Image: String) async -> String? {
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

        let model = await openRouterVisionModel()
        print("[ScreenAnalysis] Using OpenRouter image input model: \(model)")

        let body = OpenRouterVisionRequest(
            model: model,
            imageURL: "data:image/jpeg;base64,\(base64Image)"
        )

        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return await fail("Invalid OpenRouter image response.")
            }

            guard httpResponse.statusCode == 200 else {
                return await fail("OpenRouter image request failed with status \(httpResponse.statusCode): \(responseSnippet(from: data))")
            }

            let decoded: OpenRouterVisionResponse
            do {
                decoded = try JSONDecoder().decode(OpenRouterVisionResponse.self, from: data)
            } catch {
                return await fail("Failed to decode OpenRouter image response: \(error.localizedDescription). Body: \(responseSnippet(from: data))")
            }

            let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !content.isEmpty else {
                return await fail("OpenRouter image response was empty. Body: \(responseSnippet(from: data))")
            }

            await MainActor.run { self.error = nil }
            return content
        } catch {
            if Task.isCancelled { return nil }
            return await fail("OpenRouter image error: \(error.localizedDescription)")
        }
    }

    private func analyzeWithGemini(base64Image: String) async -> String? {
        guard !Config.geminiAPIKey.isEmpty else {
            return await fail("Gemini API key is missing. Add it in Settings.")
        }

        var components = URLComponents(string: Config.geminiImageURL)
        components?.queryItems = [URLQueryItem(name: "key", value: Config.geminiAPIKey)]

        guard let url = components?.url else {
            return await fail("Invalid Gemini image API URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = GeminiVisionRequest(base64Image: base64Image)

        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return await fail("Invalid Gemini image response.")
            }

            guard httpResponse.statusCode == 200 else {
                return await fail("Gemini image request failed with status \(httpResponse.statusCode): \(responseSnippet(from: data))")
            }

            let decoded: GeminiVisionResponse
            do {
                decoded = try JSONDecoder().decode(GeminiVisionResponse.self, from: data)
            } catch {
                return await fail("Failed to decode Gemini image response: \(error.localizedDescription). Body: \(responseSnippet(from: data))")
            }

            let content = decoded.candidates.first?.content.parts.compactMap(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !content.isEmpty else {
                return await fail("Gemini image response was empty. Body: \(responseSnippet(from: data))")
            }

            await MainActor.run { self.error = nil }
            return content
        } catch {
            if Task.isCancelled { return nil }
            return await fail("Gemini image error: \(error.localizedDescription)")
        }
    }

    private func analyzeWithProvider(_ provider: LLMProvider, base64Image: String) async -> String? {
        switch provider {
        case .openRouter:
            return await analyzeWithOpenRouter(base64Image: base64Image)
        case .google:
            return await analyzeWithGemini(base64Image: base64Image)
        }
    }

    @MainActor
    private func fail(_ message: String) -> String? {
        error = message
        print("[ScreenAnalysis] \(message)")
        return nil
    }

    private func openRouterVisionModel() async -> String {
        let selectedModel = Config.selectedOpenRouterModel
        guard await openRouterModelSupportsImageInput(selectedModel) else {
            return Config.openRouterImageModel
        }

        return selectedModel
    }

    private func providerAttemptSequence(primary: LLMProvider) -> [LLMProvider] {
        let fallback = primary.fallbackProvider
        if isProviderInCooldown(primary) {
            print("[ScreenAnalysis] Selected image provider \(primary.displayName) is cooling down; using \(fallback.displayName) first.")
            return [fallback, primary]
        }

        return [primary, fallback]
    }

    private func isProviderInCooldown(_ provider: LLMProvider) -> Bool {
        guard let cooldownUntil = providerCooldownUntil[provider] else { return false }
        if Date() < cooldownUntil {
            return true
        }

        providerCooldownUntil[provider] = nil
        return false
    }

    private func markProviderHealthy(_ provider: LLMProvider) {
        providerCooldownUntil[provider] = nil
    }

    private func markProviderUnhealthy(_ provider: LLMProvider) {
        providerCooldownUntil[provider] = Date().addingTimeInterval(providerCooldownDuration)
        print("[ScreenAnalysis] Marked \(provider.displayName) image provider unhealthy for \(Int(providerCooldownDuration)) seconds.")
    }

    private func openRouterModelSupportsImageInput(_ model: String) async -> Bool {
        if let openRouterImageInputModels {
            return openRouterImageInputModels.contains(model)
        }

        guard let models = await fetchOpenRouterImageInputModels() else {
            print("[ScreenAnalysis] Could not load OpenRouter model metadata; using configured image model.")
            return false
        }

        openRouterImageInputModels = models
        return models.contains(model)
    }

    private func fetchOpenRouterImageInputModels() async -> Set<String>? {
        guard let url = URL(string: Config.openRouterModelsURL) else {
            print("[ScreenAnalysis] Invalid OpenRouter models URL.")
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
                print("[ScreenAnalysis] Invalid OpenRouter models response.")
                return nil
            }

            guard httpResponse.statusCode == 200 else {
                print("[ScreenAnalysis] OpenRouter models request failed with status \(httpResponse.statusCode): \(responseSnippet(from: data))")
                return nil
            }

            let decoded = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
            let imageInputModels = decoded.data
                .filter { $0.architecture.input_modalities.contains("image") }
                .map(\.id)

            print("[ScreenAnalysis] Loaded \(imageInputModels.count) OpenRouter image-capable models.")
            return Set(imageInputModels)
        } catch {
            if Task.isCancelled { return nil }
            print("[ScreenAnalysis] OpenRouter models metadata error: \(error.localizedDescription)")
            return nil
        }
    }

    private func jpegData(from cgImage: CGImage) -> Data? {
        let maxDimension: CGFloat = 1600
        let sourceWidth = cgImage.width
        let sourceHeight = cgImage.height
        let scale = min(1, maxDimension / CGFloat(max(sourceWidth, sourceHeight)))
        let targetWidth = max(1, Int(CGFloat(sourceWidth) * scale))
        let targetHeight = max(1, Int(CGFloat(sourceHeight) * scale))

        let encodedImage: CGImage
        if scale < 1 {
            guard let resized = resizedImage(cgImage, width: targetWidth, height: targetHeight) else {
                print("[ScreenAnalysis] Failed to resize screen capture before encoding.")
                return nil
            }
            encodedImage = resized
        } else {
            encodedImage = cgImage
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            print("[ScreenAnalysis] Failed to create JPEG image destination.")
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.72
        ]

        CGImageDestinationAddImage(destination, encodedImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            print("[ScreenAnalysis] Failed to finalize JPEG image destination.")
            return nil
        }

        return data as Data
    }

    private func resizedImage(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private func hasScreenCaptureAccess() -> Bool {
        guard !CGPreflightScreenCaptureAccess() else { return true }

        print("[ScreenAnalysis] Requesting Screen Recording permission.")
        guard CGRequestScreenCaptureAccess() else {
            error = "Screen Recording permission is required. Enable MeetHelp in System Settings > Privacy & Security > Screen & System Audio Recording, then restart MeetHelp."
            print("[ScreenAnalysis] \(error ?? "Screen Recording permission denied.")")
            return false
        }

        return true
    }

    private func capturedImage(excluding window: NSWindow?) -> CGImage? {
        if let displayImage = CGDisplayCreateImage(CGMainDisplayID()) {
            return displayImage
        }

        if let window {
            if let image = CGWindowListCreateImage(
                .null,
                .optionOnScreenBelowWindow,
                CGWindowID(window.windowNumber),
                [.bestResolution]
            ) {
                return image
            }
        }

        if let image = CGWindowListCreateImage(
            .null,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) {
            return image
        }

        return nil
    }

    private func responseSnippet(from data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
        return String(singleLine.prefix(600))
    }
}

private let screenAnalysisPrompt = """
Analyze this screen capture for use as context in a live meeting assistant.

Return a dense but compact structured description:
- visible text/OCR with approximate placement and hierarchy
- UI layout, tables, code blocks, diagrams, charts, images, or slides
- important numbers, labels, entities, errors, and relationships
- any details that would help answer questions about the visible screen

Do not answer a meeting question. Only describe the screen contents.
"""

private struct OpenRouterVisionRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double = 0.2
    let max_tokens: Int = 2500

    init(model: String, imageURL: String) {
        self.model = model
        self.messages = [
            Message(role: "user", content: [
                ContentPart(type: "text", text: screenAnalysisPrompt, image_url: nil),
                ContentPart(type: "image_url", text: nil, image_url: ImageURL(url: imageURL))
            ])
        ]
    }

    struct Message: Encodable {
        let role: String
        let content: [ContentPart]
    }

    struct ContentPart: Encodable {
        let type: String
        let text: String?
        let image_url: ImageURL?
    }

    struct ImageURL: Encodable {
        let url: String
    }
}

private struct OpenRouterVisionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}

private struct OpenRouterModelsResponse: Decodable {
    let data: [Model]

    struct Model: Decodable {
        let id: String
        let architecture: Architecture
    }

    struct Architecture: Decodable {
        let input_modalities: [String]
    }
}

private struct GeminiVisionRequest: Encodable {
    let contents: [GeminiVisionContent]
    let generationConfig: GenerationConfig

    init(base64Image: String) {
        self.contents = [
            GeminiVisionContent(parts: [
                GeminiVisionPart(text: screenAnalysisPrompt, inlineData: nil),
                GeminiVisionPart(text: nil, inlineData: InlineData(mimeType: "image/jpeg", data: base64Image))
            ])
        ]
        self.generationConfig = GenerationConfig(temperature: 0.2, topP: 1.0, maxOutputTokens: 2500)
    }

    struct GenerationConfig: Encodable {
        let temperature: Double
        let topP: Double
        let maxOutputTokens: Int
    }
}

private struct GeminiVisionContent: Codable {
    let parts: [GeminiVisionPart]
}

private struct GeminiVisionPart: Codable {
    let text: String?
    let inlineData: InlineData?
}

private struct InlineData: Codable {
    let mimeType: String
    let data: String
}

private struct GeminiVisionResponse: Decodable {
    let candidates: [Candidate]

    struct Candidate: Decodable {
        let content: GeminiVisionContent
    }
}
