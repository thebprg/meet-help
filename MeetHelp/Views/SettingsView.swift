import SwiftUI
import AppKit

extension Notification.Name {
    static let shortcutRecorderCaptureDidBegin = Notification.Name("MeetHelp.shortcutRecorderCaptureDidBegin")
    static let shortcutRecorderCaptureDidEnd = Notification.Name("MeetHelp.shortcutRecorderCaptureDidEnd")
}

struct SettingsView: View {
    @ObservedObject var transcriptState: TranscriptState
    @ObservedObject var screenAnalysisService: ScreenAnalysisService
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
    @AppStorage("openRouterImageModel") private var openRouterImageModel = Config.defaultOpenRouterImageModel
    @AppStorage("geminiImageModel") private var geminiImageModel = Config.defaultGeminiImageModel
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
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            
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
            Task {
                await screenAnalysisService.warmOpenRouterModelCapabilities()
            }
        }
    }

    private var apiTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                settingsGroup("API Keys") {
                    VStack(alignment: .leading, spacing: 12) {
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
                    }
                }

                settingsGroup("LLM Provider") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Provider", selection: $llmProvider) {
                            Text("OpenRouter").tag(LLMProvider.openRouter.rawValue)
                            Text("Google").tag(LLMProvider.google.rawValue)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                switch selectedProvider {
                case .openRouter:
                    settingsGroup("OpenRouter Models") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Selected", selection: $selectedOpenRouterModelIndex) {
                                Text("1").tag(1)
                                Text("2").tag(2)
                                Text("3").tag(3)
                            }
                            .pickerStyle(.segmented)

                            modelField(title: "Model 1", text: $openRouterModel1, capability: openRouterCapability(for: openRouterModel1))
                            modelField(title: "Model 2", text: $openRouterModel2, capability: openRouterCapability(for: openRouterModel2))
                            modelField(title: "Model 3", text: $openRouterModel3, capability: openRouterCapability(for: openRouterModel3))
                            modelField(title: "Image", text: $openRouterImageModel, placeholder: Config.defaultOpenRouterImageModel, capability: openRouterCapability(for: openRouterImageModel))
                        }
                    }

                case .google:
                    settingsGroup("Gemini Model") {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Gemini model", text: $geminiModel)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.large)
                                .frame(height: 34)

                            modelField(title: "Image", text: $geminiImageModel, placeholder: Config.defaultGeminiImageModel)

                            Text("Also used as fallback when OpenRouter fails.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                settingsGroup("API Status") {
                    VStack(spacing: 10) {
                        apiStatusRow(title: "Deepgram", hasValue: !deepgramAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        apiStatusRow(title: "OpenRouter", hasValue: !openRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        apiStatusRow(title: "Google", hasValue: !geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .scrollIndicators(.hidden)
    }

    private var generalTab: some View {
        Form {
            Section {
                TextEditor(text: $transcriptState.codeContext)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 180)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            } header: {
                sectionHeader("Code Context")
            }
            
            Section {
                Toggle("Show conversation history", isOn: $transcriptState.showHistory)
                    .padding(.vertical, 2)
            } header: {
                sectionHeader("Display")
            }
        }
        .formStyle(.grouped)
        .scrollIndicators(.hidden)
    }

    private var shortcutsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(ShortcutAction.allCases) { action in
                    ShortcutCaptureRow(action: action) {
                        shortcutRefreshID = UUID()
                    }
                }
            }
            .id(shortcutRefreshID)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
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

    private var selectedProvider: LLMProvider {
        LLMProvider(rawValue: llmProvider) ?? .openRouter
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            content()
                .padding(.top, 8)
                .padding(.bottom, 2)
        } label: {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.bottom, 4)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.primary)
            .padding(.bottom, 6)
    }

    private func modelField(
        title: String,
        text: Binding<String>,
        placeholder: String = Config.openRouterFreeModel,
        capability: OpenRouterModelCapability? = nil
    ) -> some View {
        HStack {
            Text(title)
                .frame(width: 70, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .frame(height: 34)

            if let capability {
                capabilityBadge(capability)
            }
        }
        .padding(.vertical, 3)
    }

    private func openRouterCapability(for model: String) -> OpenRouterModelCapability? {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return screenAnalysisService.openRouterCapability(for: trimmed)
    }

    private func capabilityBadge(_ capability: OpenRouterModelCapability) -> some View {
        HStack(spacing: 5) {
            switch capability {
            case .imageInput:
                capabilityIcon(label: "Text input", icon: "text.alignleft", color: .secondary)
                capabilityIcon(label: "Image input", icon: "photo", color: .green)
            case .textOnly:
                capabilityIcon(label: "Text input", icon: "text.alignleft", color: .secondary)
            case .unknown:
                capabilityIcon(label: "Checking capability", icon: "clock", color: .orange)
            }
        }
        .frame(width: 58, alignment: .leading)
    }

    private func capabilityIcon(label: String, icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(color)
            .frame(width: 24, height: 22)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .accessibilityLabel(label)
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
                for otherAction in ShortcutAction.allCases where otherAction != action && otherAction.shortcut == shortcut {
                    KeyboardShortcut.disableSavedShortcut(for: otherAction)
                }
                action.shortcut = shortcut
                isCapturing = false
                onChange()
            }
            .frame(width: 150, height: 28)
        }
        .padding(.vertical, 6)
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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

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
        NotificationCenter.default.post(name: .shortcutRecorderCaptureDidBegin, object: nil)
        onBeginCapture?()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }

        captureShortcut(from: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isCapturing else {
            return super.performKeyEquivalent(with: event)
        }

        captureShortcut(from: event)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard isCapturing else { return }
        needsDisplay = true
    }

    private func captureShortcut(from event: NSEvent) {
        if event.keyCode == 53 {
            isCapturing = false
            NotificationCenter.default.post(name: .shortcutRecorderCaptureDidEnd, object: nil)
            needsDisplay = true
            return
        }

        let modifiers = event.modifierFlags.normalizedShortcutModifiers
        guard isAllowedShortcutKey(event.keyCode, modifiers: modifiers) else {
            NSSound.beep()
            return
        }

        onCapture?(KeyboardShortcut(keyCode: event.keyCode, modifiers: modifiers))
        isCapturing = false
        NotificationCenter.default.post(name: .shortcutRecorderCaptureDidEnd, object: nil)
        needsDisplay = true
    }

    private func isAllowedShortcutKey(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        if !modifiers.isEmpty {
            return true
        }

        return (96...103).contains(keyCode) ||
            keyCode == 109 ||
            keyCode == 111 ||
            keyCode == 118 ||
            keyCode == 120 ||
            keyCode == 122
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
