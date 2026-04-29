import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var transcriptState: TranscriptState
    @AppStorage("showHistory") private var showHistory = true
    @AppStorage("llmProvider") private var llmProvider = LLMProvider.openRouter.rawValue
    @AppStorage("deepgramAPIKey") private var deepgramAPIKey = ""
    @AppStorage("openRouterAPIKey") private var openRouterAPIKey = ""
    @AppStorage("geminiAPIKey") private var geminiAPIKey = ""
    @AppStorage("openRouterModel1") private var openRouterModel1 = Config.openRouterFreeModel
    @AppStorage("openRouterModel2") private var openRouterModel2 = ""
    @AppStorage("openRouterModel3") private var openRouterModel3 = ""
    @AppStorage("selectedOpenRouterModelIndex") private var selectedOpenRouterModelIndex = 1
    @AppStorage("geminiModel") private var geminiModel = Config.defaultGeminiModel
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyPasteText = ""
    @State private var selectedTab = SettingsTab.api
    @State private var saveMessage = ""
    @State private var shortcutRefreshID = UUID()
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("API").tag(SettingsTab.api)
                Text("General").tag(SettingsTab.general)
                Text("Shortcuts").tag(SettingsTab.shortcuts)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()
            
            switch selectedTab {
            case .api:
                apiTab
            case .general:
                generalTab
            case .shortcuts:
                shortcutsTab
            }
        }
        .frame(width: 500, height: 680)
        .onAppear {
            apiKeyPasteText = currentAPIKeyText
        }
    }

    private var apiTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("API Keys") {
                    VStack(alignment: .leading, spacing: 10) {
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $apiKeyPasteText)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(height: 190)
                                .padding(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                )

                            if apiKeyPasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(apiKeyTemplate)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.6))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 12)
                                    .allowsHitTesting(false)
                            }
                        }

                        HStack {
                            Button("Save API Keys") {
                                saveAPIKeys()
                            }

                            Spacer()

                            if !saveMessage.isEmpty {
                                Text(saveMessage)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Text("Paste all keys at once as KEY=value lines. Omitted lines keep existing saved keys; KEY= clears that key.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }

                GroupBox("LLM Provider") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Provider", selection: $llmProvider) {
                            Text("OpenRouter").tag(LLMProvider.openRouter.rawValue)
                            Text("Google").tag(LLMProvider.google.rawValue)
                        }
                        .pickerStyle(.segmented)

                        Text(providerDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }

                GroupBox("OpenRouter Models") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Selected", selection: $selectedOpenRouterModelIndex) {
                            Text("1").tag(1)
                            Text("2").tag(2)
                            Text("3").tag(3)
                        }
                        .pickerStyle(.segmented)

                        modelField(title: "Model 1", text: $openRouterModel1)
                        modelField(title: "Model 2", text: $openRouterModel2)
                        modelField(title: "Model 3", text: $openRouterModel3)

                        Text("Only OpenRouter model ids ending in :free are used. Shortcuts can switch between these three slots.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }

                GroupBox("Google Backup Model") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Gemini model", text: $geminiModel)
                            .textFieldStyle(.roundedBorder)

                        Text("Used when Google is selected directly or when OpenRouter fails.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }

                GroupBox("API Status") {
                    VStack(spacing: 8) {
                        apiStatusRow(title: "Deepgram", hasValue: !deepgramAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        apiStatusRow(title: "OpenRouter", hasValue: !openRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        apiStatusRow(title: "Google", hasValue: !geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private var generalTab: some View {
        Form {
            Section("Code Context") {
                Text("Paste relevant code before your interview. The AI will reference it when answering questions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $transcriptState.codeContext)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 180)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
            
            Section("Display") {
                Toggle("Show conversation history", isOn: $transcriptState.showHistory)
                
                Text("When off, only the latest answer is shown.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var shortcutsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(ShortcutAction.allCases) { action in
                    ShortcutCaptureRow(action: action) {
                        shortcutRefreshID = UUID()
                    }
                }
            }
            .id(shortcutRefreshID)
            .padding()
        }
    }

    private var apiKeyTemplate: String {
        """
        DEEPGRAM_API_KEY=
        OPENROUTER_API_KEY=
        GEMINI_API_KEY=
        """
    }

    private var currentAPIKeyText: String {
        """
        DEEPGRAM_API_KEY=\(deepgramAPIKey)
        OPENROUTER_API_KEY=\(openRouterAPIKey)
        GEMINI_API_KEY=\(geminiAPIKey)
        """
    }

    private var providerDescription: String {
        switch LLMProvider(rawValue: llmProvider) ?? .openRouter {
        case .openRouter:
            return "Uses the selected OpenRouter model slot. Falls back to Google if OpenRouter fails."
        case .google:
            return "Uses \(Config.geminiModel) from Google AI Studio."
        }
    }

    private func modelField(title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
                .frame(width: 70, alignment: .leading)
            TextField(Config.openRouterFreeModel, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func saveAPIKeys() {
        let parsedKeys = parseAPIKeys(from: apiKeyPasteText)
        var savedCount = 0

        if let value = parsedKeys["DEEPGRAM_API_KEY"] {
            deepgramAPIKey = value
            savedCount += 1
        }

        if let value = parsedKeys["OPENROUTER_API_KEY"] {
            openRouterAPIKey = value
            savedCount += 1
        }

        if let value = parsedKeys["GEMINI_API_KEY"] {
            geminiAPIKey = value
            savedCount += 1
        }

        saveMessage = savedCount == 0 ? "No key lines found" : "Updated \(savedCount) key\(savedCount == 1 ? "" : "s")"
    }

    private func parseAPIKeys(from text: String) -> [String: String] {
        var result: [String: String] = [:]
        let validKeys = Set(["DEEPGRAM_API_KEY", "OPENROUTER_API_KEY", "GEMINI_API_KEY"])

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }

            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            guard validKeys.contains(key) else { continue }

            let value = String(parts[1])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            result[key] = value
        }

        return result
    }

    private func apiStatusRow(title: String, hasValue: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: hasValue ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(hasValue ? .green : .red)
        }
    }
}

private enum SettingsTab {
    case api
    case general
    case shortcuts
}

private struct ShortcutCaptureRow: View {
    let action: ShortcutAction
    let onChange: () -> Void
    @State private var isCapturing = false

    var body: some View {
        HStack {
            Text(action.title)
            Spacer()
            ShortcutRecorderView(
                shortcut: action.shortcut,
                isCapturing: $isCapturing
            ) { shortcut in
                action.shortcut = shortcut
                isCapturing = false
                onChange()
            }
            .frame(width: 150, height: 28)
        }
        .padding(.vertical, 4)
    }
}

private struct ShortcutRecorderView: NSViewRepresentable {
    let shortcut: KeyboardShortcut
    @Binding var isCapturing: Bool
    let onCapture: (KeyboardShortcut) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onBeginCapture = {
            isCapturing = true
        }
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ view: ShortcutRecorderNSView, context: Context) {
        view.onBeginCapture = {
            isCapturing = true
        }
        view.onCapture = onCapture
        view.shortcut = shortcut
        view.isCapturing = isCapturing
        view.needsDisplay = true
    }
}

private final class ShortcutRecorderNSView: NSView {
    var shortcut: KeyboardShortcut?
    var isCapturing = false
    var onBeginCapture: (() -> Void)?
    var onCapture: ((KeyboardShortcut) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isCapturing = true
        onBeginCapture?()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            isCapturing = false
            needsDisplay = true
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !modifiers.isEmpty else { return }

        onCapture?(KeyboardShortcut(keyCode: event.keyCode, modifiers: modifiers))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        (isCapturing ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = isCapturing ? "Press shortcut" : (shortcut?.displayText ?? "Unset")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        let point = NSPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2
        )
        text.draw(at: point, withAttributes: attributes)
    }
}
