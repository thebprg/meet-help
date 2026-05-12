import SwiftUI
import AppKit

extension Notification.Name {
    static let shortcutRecorderCaptureDidBegin = Notification.Name("MeetHelp.shortcutRecorderCaptureDidBegin")
    static let shortcutRecorderCaptureDidEnd = Notification.Name("MeetHelp.shortcutRecorderCaptureDidEnd")
    static let overlayAppearanceDidChange = Notification.Name("MeetHelp.overlayAppearanceDidChange")
}

struct SettingsView: View {
    @ObservedObject var transcriptState: TranscriptState
    @ObservedObject var screenAnalysisService: ScreenAnalysisService
    @ObservedObject private var appLog = AppLogStore.shared
    @ObservedObject private var openRouterCatalog = OpenRouterModelCatalog.shared
    @AppStorage("showHistory") private var showHistory = true
    @AppStorage("llmProvider") private var llmProvider = LLMProvider.openRouter.rawValue
    @AppStorage("deepgramAPIKey") private var deepgramAPIKey = ""
    @AppStorage("openRouterAPIKey") private var openRouterAPIKey = ""
    @AppStorage("geminiAPIKey") private var geminiAPIKey = ""
    @AppStorage("youAPIKey") private var youAPIKey = ""
    @AppStorage("openRouterSearchModel") private var openRouterSearchModel = Config.defaultOpenRouterSearchModel
    @AppStorage("openRouterModel1") private var openRouterModel1 = Config.openRouterFreeModel
    @AppStorage("openRouterModel2") private var openRouterModel2 = ""
    @AppStorage("openRouterModel3") private var openRouterModel3 = ""
    @AppStorage("selectedOpenRouterModelIndex") private var selectedOpenRouterModelIndex = 1
    @AppStorage("geminiModel") private var geminiModel = Config.defaultGeminiModel
    @AppStorage("openRouterImageModel") private var openRouterImageModel = Config.defaultOpenRouterImageModel
    @AppStorage("geminiImageModel") private var geminiImageModel = Config.defaultGeminiImageModel
    @AppStorage("manualInterviewerSubmitEnabled") private var manualInterviewerSubmitEnabled = false
    @AppStorage("openRouterFreeModeEnabled") private var openRouterFreeModeEnabled = true
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyPasteText = ""
    @State private var selectedTab = SettingsTab.api
    @State private var saveMessage = ""
    @State private var shortcutRefreshID = UUID()
    @State private var openRouterOptionDrafts: [String: OpenRouterRequestOptions] = [:]
    @State private var openRouterProviderDrafts: [String: String] = [:]
    @State private var expandedProviderSelectors: Set<String> = []
    @State private var selectedOpenRouterModelPanel = 1
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("API").tag(SettingsTab.api)
                Text("General").tag(SettingsTab.general)
                Text("Shortcuts").tag(SettingsTab.shortcuts)
                Text("Debug").tag(SettingsTab.debug)
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
            case .debug:
                debugTab
            }
        }
        .frame(width: 620, height: 680)
        .onAppear {
            apiKeyPasteText = currentAPIKeyText
            selectedOpenRouterModelPanel = normalizedOpenRouterModelPanel(selectedOpenRouterModelIndex)
            Task {
                await screenAnalysisService.warmOpenRouterModelCapabilities()
            }
        }
    }

    private var apiTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                apiSectionTitle("API Keys")

                ZStack(alignment: .topLeading) {
                    NoWrapTextEditor(text: $apiKeyPasteText)
                        .frame(height: 132)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.65), lineWidth: 1.5)
                        )

                    if apiKeyPasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(apiKeyTemplate)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 13)
                            .allowsHitTesting(false)
                    }
                }

                HStack(spacing: 12) {
                    Button("Save keys") {
                        saveAPIKeys()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    if !saveMessage.isEmpty {
                        Text(saveMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                apiSectionTitle("LLM Provider")

                Picker("Provider", selection: $llmProvider) {
                    Text("OpenRouter").tag(LLMProvider.openRouter.rawValue)
                    Text("Google").tag(LLMProvider.google.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                apiSectionTitle(selectedProvider == .openRouter ? "Models" : "Gemini Model")

                switch selectedProvider {
                case .openRouter:
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Free model mode", isOn: $openRouterFreeModeEnabled)
                            .font(.system(size: 13, weight: .medium))
                            .help("When enabled, MeetHelp only uses free OpenRouter models and free provider endpoints.")

                        Picker("Model", selection: $selectedOpenRouterModelPanel) {
                            Text("0").tag(0)
                            Text("1").tag(1)
                            Text("2").tag(2)
                            Text("3").tag(3)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .onChange(of: selectedOpenRouterModelPanel) { value in
                            selectedOpenRouterModelPanel = normalizedOpenRouterModelPanel(value)
                            selectedOpenRouterModelIndex = selectedOpenRouterModelPanel
                        }
                        .onChange(of: selectedOpenRouterModelIndex) { value in
                            selectedOpenRouterModelPanel = normalizedOpenRouterModelPanel(value)
                        }

                        openRouterSelectedModelPanel
                        openRouterImageModelPanel
                    }

                case .google:
                    apiInnerPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            labeledTextField(title: "Text", text: $geminiModel, placeholder: Config.defaultGeminiModel)
                            labeledTextField(title: "Image", text: $geminiImageModel, placeholder: Config.defaultGeminiImageModel)
                            Text("Also used as fallback when OpenRouter fails.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                apiSectionTitle("API Status")

                apiInnerPanel {
                    VStack(spacing: 10) {
                        apiStatusRow(title: "Deepgram", hasValue: !deepgramAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        apiStatusRow(title: "OpenRouter", hasValue: !openRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        apiStatusRow(title: "Google", hasValue: !geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        apiStatusRow(title: "You.com", hasValue: !youAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                Toggle("Manually submit interviewer transcript", isOn: $manualInterviewerSubmitEnabled)
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

    private var debugTab: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Backend Output")
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appLog.combinedText, forType: .string)
                }
                .disabled(appLog.entries.isEmpty)

                Button("Clear") {
                    appLog.clear()
                }
                .disabled(appLog.entries.isEmpty)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        if appLog.entries.isEmpty {
                            Text("No debug output yet.")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        } else {
                            ForEach(appLog.entries) { entry in
                                Text(debugLine(for: entry))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(color(for: entry.message))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(entry.id)
                            }
                        }
                    }
                    .padding(10)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .onChange(of: appLog.entries.count) { _ in
                    guard let lastID = appLog.entries.last?.id else { return }
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    private var apiKeyTemplate: String {
        """
        DEEPGRAM_API_KEY=
        OPENROUTER_API_KEY=
        GEMINI_API_KEY=
        YOU_API_KEY=
        """
    }

    private var currentAPIKeyText: String {
        """
        DEEPGRAM_API_KEY=\(deepgramAPIKey)
        OPENROUTER_API_KEY=\(openRouterAPIKey)
        GEMINI_API_KEY=\(geminiAPIKey)
        YOU_API_KEY=\(youAPIKey)
        """
    }

    private var selectedProvider: LLMProvider {
        LLMProvider(rawValue: llmProvider) ?? .openRouter
    }

    @ViewBuilder
    private var openRouterSelectedModelPanel: some View {
        switch selectedOpenRouterModelPanel {
        case 0:
            openRouterActiveModelPanel(
                title: "Model 0",
                text: $openRouterSearchModel,
                optionsKey: "search",
                placeholder: Config.defaultOpenRouterSearchModel,
                description: "Also used for search query generation while live search is turned on."
            )
        case 1:
            openRouterActiveModelPanel(title: "Model 1", text: $openRouterModel1, optionsKey: "model1")
        case 2:
            openRouterActiveModelPanel(title: "Model 2", text: $openRouterModel2, optionsKey: "model2")
        case 3:
            openRouterActiveModelPanel(title: "Model 3", text: $openRouterModel3, optionsKey: "model3")
        default:
            openRouterActiveModelPanel(title: "Model 1", text: $openRouterModel1, optionsKey: "model1")
        }
    }

    private var openRouterImageModelPanel: some View {
        apiInnerPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Image Model")
                    .font(.system(size: 15, weight: .semibold))

                labeledTextField(
                    title: "Image",
                    text: $openRouterImageModel,
                    placeholder: Config.defaultOpenRouterImageModel,
                    capability: openRouterCapability(for: openRouterImageModel)
                )

                Text("Used only when the selected OpenRouter text model cannot accept image input.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func openRouterActiveModelPanel(
        title: String,
        text: Binding<String>,
        optionsKey: String,
        placeholder: String = Config.openRouterFreeModel,
        description: String? = nil
    ) -> some View {
        let model = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)

        return apiInnerPanel {
            VStack(alignment: .leading, spacing: 14) {
                labeledTextField(
                    title: title,
                    text: text,
                    placeholder: placeholder,
                    capability: openRouterCapability(for: text.wrappedValue)
                )

                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                openRouterProviderPicker(model: model, optionsKey: optionsKey)

                Divider()

                Text("Options")
                    .font(.system(size: 15, weight: .semibold))

                if model.isEmpty {
                    Text("Add a model ID to edit its options.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    openRouterOptionsEditor(
                        model: model,
                        options: openRouterOptionsBinding(forKey: optionsKey),
                        supportedParameters: openRouterSupportedParameters(for: model, optionsKey: optionsKey)
                    )
                    .onAppear {
                        loadOpenRouterOptionsDraftIfNeeded(forKey: optionsKey)
                    }
                }
            }
        }
    }

    private func apiSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 24, weight: .semibold))
            .foregroundColor(.primary)
            .padding(.top, 2)
    }

    private func apiInnerPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.65), lineWidth: 1.5)
        )
    }

    private func labeledTextField(
        title: String,
        text: Binding<String>,
        placeholder: String,
        capability: OpenRouterModelCapability? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 58, alignment: .leading)

            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .frame(height: 34)
                .frame(maxWidth: .infinity)

            if let capability {
                capabilityBadge(capability)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func openRouterProviderPicker(model: String, optionsKey: String) -> some View {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            EmptyView()
        } else {
            let endpoints = openRouterCatalog.endpoints(for: trimmed)
            let visibleEndpoints = providerEndpointsForDisplay(endpoints ?? [])
            let providerBinding = openRouterProviderBinding(forKey: optionsKey)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Provider")
                        .font(.system(size: 15, weight: .semibold))

                    Spacer()

                    Text(providerCountText(visibleEndpoints.count))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button {
                        Task {
                            await openRouterCatalog.endpointsLoadingIfNeeded(for: trimmed, force: true)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Refresh providers")
                }

                if endpoints == nil {
                    Text("Loading providers...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .task(id: trimmed) {
                            _ = await openRouterCatalog.endpointsLoadingIfNeeded(for: trimmed)
                        }
                } else if visibleEndpoints.isEmpty {
                    Text(openRouterFreeModeEnabled ? "No free providers reported for this model." : "No providers reported for this model.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    providerSelectionDisclosure(
                        endpoints: visibleEndpoints,
                        optionsKey: optionsKey,
                        selectedTag: providerBinding.wrappedValue,
                        onSelect: { providerBinding.wrappedValue = $0 }
                    )
                }
            }
            .onAppear {
                loadOpenRouterProviderDraftIfNeeded(forKey: optionsKey)
            }
        }
    }

    private func providerEndpointsForDisplay(_ endpoints: [OpenRouterProviderEndpoint]) -> [OpenRouterProviderEndpoint] {
        let filtered = openRouterFreeModeEnabled ? endpoints.filter(\.isFree) : endpoints
        return filtered.sorted { lhs, rhs in
            let lhsStatus = lhs.status ?? Int.max
            let rhsStatus = rhs.status ?? Int.max
            if lhsStatus != rhsStatus { return lhsStatus < rhsStatus }

            let lhsCost = (lhs.promptPrice ?? 0) + (lhs.completionPrice ?? 0)
            let rhsCost = (rhs.promptPrice ?? 0) + (rhs.completionPrice ?? 0)
            if lhsCost != rhsCost { return lhsCost < rhsCost }

            let lhsLatency = lhs.latencyP50 ?? .greatestFiniteMagnitude
            let rhsLatency = rhs.latencyP50 ?? .greatestFiniteMagnitude
            if lhsLatency != rhsLatency { return lhsLatency < rhsLatency }

            return (lhs.throughputP50 ?? 0) > (rhs.throughputP50 ?? 0)
        }
    }

    private func providerCountText(_ count: Int) -> String {
        count == 1 ? "1 provider" : "\(count) providers"
    }

    private func providerSelectionDisclosure(
        endpoints: [OpenRouterProviderEndpoint],
        optionsKey: String,
        selectedTag: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        let expanded = providerSelectorExpandedBinding(forKey: optionsKey)

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                expanded.wrappedValue.toggle()
            } label: {
                HStack(spacing: 8) {
                    providerSelectionLabel(endpoints: endpoints, selectedTag: selectedTag)

                    Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded.wrappedValue {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        providerAutoChoiceRow(isSelected: selectedTag.isEmpty) {
                            onSelect("")
                        }

                        ForEach(endpoints) { endpoint in
                            providerChoiceRow(
                                endpoint: endpoint,
                                isSelected: selectedTag == endpoint.tag
                            ) {
                                onSelect(endpoint.tag)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
                .frame(maxHeight: 280)
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
        )
        .accentColor(.secondary)
    }

    private func providerSelectorExpandedBinding(forKey key: String) -> Binding<Bool> {
        Binding(
            get: { expandedProviderSelectors.contains(key) },
            set: { isExpanded in
                if isExpanded {
                    expandedProviderSelectors.insert(key)
                } else {
                    expandedProviderSelectors.remove(key)
                }
            }
        )
    }

    private func providerSelectionLabel(endpoints: [OpenRouterProviderEndpoint], selectedTag: String) -> some View {
        let selectedEndpoint = selectedTag.isEmpty
            ? endpoints.first
            : endpoints.first(where: { $0.tag == selectedTag })

        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: selectedTag.isEmpty ? "sparkles" : "server.rack")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 16)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 6) {
                Text(providerSelectionTitle(endpoints: endpoints, selectedTag: selectedTag))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let selectedEndpoint {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 5)], spacing: 5) {
                        providerMetricChip("In", priceText(selectedEndpoint.promptPrice))
                        providerMetricChip("Out", priceText(selectedEndpoint.completionPrice))
                        providerMetricChip("Cache", priceText(selectedEndpoint.cacheReadPrice))
                        providerMetricChip("Lat", wholeMetricText(selectedEndpoint.latencyP50, suffix: " ms"))
                        providerMetricChip("Speed", wholeMetricText(selectedEndpoint.throughputP50, suffix: "/s"))
                        providerMetricChip("Up", wholeMetricText(selectedEndpoint.uptimeLast30m, suffix: "%"))
                    }
                } else {
                    Text(providerSelectionSubtitle(endpoints: endpoints, selectedTag: selectedTag))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func providerSelectionTitle(endpoints: [OpenRouterProviderEndpoint], selectedTag: String) -> String {
        guard !selectedTag.isEmpty else { return "Auto best provider" }
        guard let endpoint = endpoints.first(where: { $0.tag == selectedTag }) else {
            return "Selected provider unavailable"
        }
        return providerDisplayName(endpoint)
    }

    private func providerSelectionSubtitle(endpoints: [OpenRouterProviderEndpoint], selectedTag: String) -> String {
        if selectedTag.isEmpty {
            guard let endpoint = endpoints.first else { return "No provider selected" }
            return providerCompactMetrics(endpoint)
        }

        guard let endpoint = endpoints.first(where: { $0.tag == selectedTag }) else {
            return "Provider no longer available"
        }

        return providerCompactMetrics(endpoint)
    }

    private func providerDisplayName(_ endpoint: OpenRouterProviderEndpoint) -> String {
        var pieces = [endpoint.providerName]
        if let quantization = endpoint.quantization?.trimmingCharacters(in: .whitespacesAndNewlines),
           !quantization.isEmpty {
            pieces.append(quantization)
        }
        return pieces.joined(separator: " / ")
    }

    private func providerAutoChoiceRow(isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto best")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text("Best route from the current provider list.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    private func providerChoiceRow(
        endpoint: OpenRouterProviderEndpoint,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 16)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(providerDisplayName(endpoint))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Text(endpoint.tag)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        providerStatusPill(endpoint.isFree ? "Free" : "Paid", color: endpoint.isFree ? .green : .orange)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 5)], spacing: 5) {
                        providerMetricChip("In", priceText(endpoint.promptPrice))
                        providerMetricChip("Out", priceText(endpoint.completionPrice))
                        providerMetricChip("Cache", priceText(endpoint.cacheReadPrice))
                        providerMetricChip("Lat", wholeMetricText(endpoint.latencyP50, suffix: " ms"))
                        providerMetricChip("Speed", wholeMetricText(endpoint.throughputP50, suffix: "/s"))
                        providerMetricChip("Up", wholeMetricText(endpoint.uptimeLast30m, suffix: "%"))
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    private func providerMetricChip(_ title: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func providerStatusPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func providerCompactMetrics(_ endpoint: OpenRouterProviderEndpoint) -> String {
        [
            endpoint.isFree ? "Free" : "Paid",
            "in \(priceText(endpoint.promptPrice))",
            "out \(priceText(endpoint.completionPrice))",
            "cache \(priceText(endpoint.cacheReadPrice))",
            "lat \(wholeMetricText(endpoint.latencyP50, suffix: " ms"))",
            "speed \(wholeMetricText(endpoint.throughputP50, suffix: "/s"))",
            "up \(wholeMetricText(endpoint.uptimeLast30m, suffix: "%"))"
        ].joined(separator: " · ")
    }

    private func priceText(_ value: Double?) -> String {
        guard let value else { return "-" }
        if value == 0 { return "$0" }
        let perMillion = value * 1_000_000
        if perMillion >= 0.01 {
            return "$" + String(format: "%.2f/M", perMillion)
        }
        return "$" + String(format: "%.6f", value)
    }

    private func metricText(_ value: Double?, suffix: String) -> String {
        guard let value else { return "-" }
        return String(format: "%.2f", value) + suffix
    }

    private func wholeMetricText(_ value: Double?, suffix: String) -> String {
        guard let value else { return "-" }
        return String(format: "%.0f", value) + suffix
    }

    private func debugLine(for entry: AppLogEntry) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return "[\(formatter.string(from: entry.timestamp))] \(entry.message)"
    }

    private func color(for message: String) -> Color {
        let lowercased = message.lowercased()
        if lowercased.contains("error") ||
            lowercased.contains("failed") ||
            lowercased.contains("denied") ||
            lowercased.contains("missing") {
            return .red
        }

        if lowercased.contains("retry") ||
            lowercased.contains("ignored") ||
            lowercased.contains("fallback") ||
            lowercased.contains("permission") {
            return .orange
        }

        if lowercased.contains("started") ||
            lowercased.contains("updated") ||
            lowercased.contains("captured") ||
            lowercased.contains("saved") ||
            lowercased.contains("succeeded") {
            return .green
        }

        return .primary
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
                .frame(maxWidth: .infinity)

            if let capability {
                capabilityBadge(capability)
            }
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
    }

    private func openRouterCapability(for model: String) -> OpenRouterModelCapability? {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return openRouterCatalog.capability(for: trimmed)
    }

    private func openRouterSupportedParameters(for model: String) -> Set<String>? {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return openRouterCatalog.supportedParameters(for: trimmed)
    }

    private func openRouterSupportedParameters(for model: String, optionsKey: String) -> Set<String>? {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let selectedTag = Config.openRouterProviderTag(forSlot: optionsKey)
        if !selectedTag.isEmpty,
           let endpoints = openRouterCatalog.endpoints(for: trimmed),
           let endpoint = providerEndpointsForDisplay(endpoints).first(where: { $0.tag == selectedTag }) {
            return endpoint.supportedParameters
        }

        return openRouterCatalog.supportedParameters(for: trimmed)
    }

    private func openRouterModelEditor(title: String, text: Binding<String>, optionsKey: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            modelField(title: title, text: text, capability: openRouterCapability(for: text.wrappedValue))

            let trimmed = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                DisclosureGroup("Options") {
                    VStack(alignment: .leading, spacing: 10) {
                        openRouterOptionsEditor(
                            model: trimmed,
                            options: openRouterOptionsBinding(forKey: optionsKey),
                            supportedParameters: openRouterSupportedParameters(for: trimmed, optionsKey: optionsKey)
                        )
                    }
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.leading, 70)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            loadOpenRouterOptionsDraftIfNeeded(forKey: optionsKey)
        }
        .onChange(of: text.wrappedValue) { newValue in
            loadOpenRouterOptionsDraftIfNeeded(forKey: optionsKey)
        }
    }

    private func openRouterOptionsEditor(
        model: String,
        options: Binding<OpenRouterRequestOptions>,
        supportedParameters: Set<String>?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let supportedParameters {
                if supportedParameters.isEmpty {
                    Text("No configurable options were reported for this model.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    reasoningOptionRows(options: options)
                } else {
                    reasoningOptionRows(options: options)

                    if supportedParameters.contains("max_tokens") {
                        intOptionRow(
                            title: "Max tokens",
                            isEnabled: optionBinding(options, \.maxTokensEnabled),
                            value: optionBinding(options, \.maxTokens),
                            range: 1...32768,
                            step: 256
                        )
                    }

                    if supportedParameters.contains("temperature") {
                        doubleOptionRow(
                            title: "Temperature",
                            isEnabled: optionBinding(options, \.temperatureEnabled),
                            value: optionBinding(options, \.temperature),
                            range: 0...2,
                            step: 0.1
                        )
                    }

                    if supportedParameters.contains("top_p") {
                        doubleOptionRow(
                            title: "Top P",
                            isEnabled: optionBinding(options, \.topPEnabled),
                            value: optionBinding(options, \.topP),
                            range: 0...1,
                            step: 0.05
                        )
                    }

                    if supportedParameters.contains("frequency_penalty") {
                        doubleOptionRow(
                            title: "Frequency penalty",
                            isEnabled: optionBinding(options, \.frequencyPenaltyEnabled),
                            value: optionBinding(options, \.frequencyPenalty),
                            range: -2...2,
                            step: 0.1
                        )
                    }

                    if supportedParameters.contains("presence_penalty") {
                        doubleOptionRow(
                            title: "Presence penalty",
                            isEnabled: optionBinding(options, \.presencePenaltyEnabled),
                            value: optionBinding(options, \.presencePenalty),
                            range: -2...2,
                            step: 0.1
                        )
                    }
                }
            } else if openRouterCatalog.models == nil {
                Text("Loading available options...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("This model was not found in OpenRouter metadata.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func intOptionRow(
        title: String,
        isEnabled: Binding<Bool>,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(width: 118, alignment: .leading)

            Toggle("", isOn: isEnabled)
                .labelsHidden()

            TextField("", value: value, formatter: integerFormatter)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(width: 82)
                .disabled(!isEnabled.wrappedValue)

            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
                .disabled(!isEnabled.wrappedValue)

            Spacer(minLength: 0)
        }
        .font(.caption)
        .frame(maxWidth: .infinity)
    }

    private func doubleOptionRow(
        title: String,
        isEnabled: Binding<Bool>,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(width: 118, alignment: .leading)

            Toggle("", isOn: isEnabled)
                .labelsHidden()

            Slider(value: value, in: range, step: step)
                .frame(maxWidth: .infinity)
                .disabled(!isEnabled.wrappedValue)

            TextField("", value: value, formatter: decimalFormatter)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(width: 64)
                .disabled(!isEnabled.wrappedValue)
        }
        .font(.caption)
        .frame(maxWidth: .infinity)
    }

    private func reasoningOptionRows(options: Binding<OpenRouterRequestOptions>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Reasoning")
                    .frame(width: 118, alignment: .leading)

                Picker("Reasoning", selection: optionBinding(options, \.reasoningEffort)) {
                    ForEach(OpenRouterReasoningEffort.allCases) { effort in
                        Text(effort.displayName).tag(effort)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)
            }

            if options.wrappedValue.reasoningEffort != .providerDefault &&
                options.wrappedValue.reasoningEffort != .none {
                intOptionRow(
                    title: "Reasoning tokens",
                    isEnabled: optionBinding(options, \.reasoningMaxTokensEnabled),
                    value: optionBinding(options, \.reasoningMaxTokens),
                    range: 1...32768,
                    step: 256
                )
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openRouterOptionsBinding(forKey key: String) -> Binding<OpenRouterRequestOptions> {
        return Binding(
            get: {
                openRouterOptionDrafts[key] ?? Config.openRouterOptions(forSlot: key)
            },
            set: { newOptions in
                let normalizedOptions = newOptions.normalized
                openRouterOptionDrafts[key] = normalizedOptions
                Config.setOpenRouterOptions(normalizedOptions, forSlot: key)
            }
        )
    }

    private func openRouterProviderBinding(forKey key: String) -> Binding<String> {
        Binding(
            get: {
                openRouterProviderDrafts[key] ?? Config.openRouterProviderTag(forSlot: key)
            },
            set: { newProviderTag in
                openRouterProviderDrafts[key] = newProviderTag
                Config.setOpenRouterProviderTag(newProviderTag, forSlot: key)
            }
        )
    }

    private func optionBinding<Value>(
        _ options: Binding<OpenRouterRequestOptions>,
        _ keyPath: WritableKeyPath<OpenRouterRequestOptions, Value>
    ) -> Binding<Value> {
        Binding(
            get: { options.wrappedValue[keyPath: keyPath] },
            set: { newValue in
                var updated = options.wrappedValue
                updated[keyPath: keyPath] = newValue
                options.wrappedValue = updated.normalized
            }
        )
    }

    private func normalizedOpenRouterModel(_ model: String) -> String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedOpenRouterModelIndex(_ index: Int) -> Int {
        min(max(index, 0), 3)
    }

    private func normalizedOpenRouterModelPanel(_ index: Int) -> Int {
        min(max(index, 0), 3)
    }

    private func loadOpenRouterOptionsDraftIfNeeded(forKey key: String) {
        guard !key.isEmpty, openRouterOptionDrafts[key] == nil else { return }
        openRouterOptionDrafts[key] = Config.openRouterOptions(forSlot: key)
    }

    private func loadOpenRouterProviderDraftIfNeeded(forKey key: String) {
        guard !key.isEmpty, openRouterProviderDrafts[key] == nil else { return }
        openRouterProviderDrafts[key] = Config.openRouterProviderTag(forSlot: key)
    }

    private var integerFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.maximum = 32768
        return formatter
    }

    private var decimalFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
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

        if let value = parsedKeys["YOU_API_KEY"] {
            youAPIKey = value
            savedCount += 1
        }

        saveMessage = savedCount == 0 ? "No key lines found" : "Updated \(savedCount) key\(savedCount == 1 ? "" : "s")"
    }

    private func parseAPIKeys(from text: String) -> [String: String] {
        var result: [String: String] = [:]
        let validKeys = Set(["DEEPGRAM_API_KEY", "OPENROUTER_API_KEY", "GEMINI_API_KEY", "YOU_API_KEY"])

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
    case debug
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

private struct NoWrapTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 6, height: 6)

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = false
            textContainer.heightTracksTextView = false
            textContainer.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            textContainer.lineFragmentPadding = 0
        }

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            textView.string = text
        }

        if textView.delegate == nil {
            textView.delegate = context.coordinator
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: NSTextView?

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
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
