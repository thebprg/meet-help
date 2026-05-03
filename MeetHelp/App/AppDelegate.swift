import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private static weak var shared: AppDelegate?
    private static let hotKeySignature = OSType(
        UInt32(UInt8(ascii: "M")) << 24 |
        UInt32(UInt8(ascii: "H")) << 16 |
        UInt32(UInt8(ascii: "K")) << 8 |
        UInt32(UInt8(ascii: "Y"))
    )

    private var statusItem: NSStatusItem?
    private var ghostWindowController: GhostWindowController?
    private var settingsWindow: NSWindow?

    private let transcriptState = TranscriptState()
    private let audioManager = AudioCaptureManager()
    private let deepgramService = DeepgramService()
    private let llmService = LLMService()

    private var hotKeyEventHandler: EventHandlerRef?
    private var registeredHotKeys: [UInt32: EventHotKeyRef] = [:]
    private var localKeyMonitor: Any?
    private var globalPeekMonitor: Any?
    private var localPeekMonitor: Any?

    private var isPeeking = false
    private var wasHiddenBeforePeek = false
    private let rightCommandKeyCode: UInt16 = 54
    private var currentSessionID = UUID()
    private var pendingLLMRequests: [LLMRequest] = []
    private var llmTask: Task<Void, Never>?
    private var activeLLMRequestID: UUID?
    private var isProcessingLLMQueue = false

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            Self.shared = self
            NSApp.setActivationPolicy(.accessory)
            setupStatusItem()
            setupGhostWindow()
            setupGlobalHotkey()
        }
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            cancelPendingLLMWork()
            unregisterGlobalHotkeys()
            transcriptState.endTranscriptLog()
            await audioManager.stopCapture()
            deepgramService.disconnect()
        }
    }

    // MARK: - Status Item (Menu Bar)

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "MeetHelp")
            updateStatusItemAppearance()
        }

        let menu = NSMenu()

        let toggleOverlayItem = NSMenuItem(title: "Show Overlay", action: #selector(toggleOverlay), keyEquivalent: "h")
        toggleOverlayItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(toggleOverlayItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Quit MeetHelp", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    private func updateStatusItemAppearance() {
        if let button = statusItem?.button {
            let symbolName = transcriptState.isListening ? "waveform.circle.fill" : "waveform.circle"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "MeetHelp")
        }

        updateOverlayMenuItemTitle()
    }

    private func updateOverlayMenuItemTitle() {
        if let menu = statusItem?.menu,
           let toggleItem = menu.items.first {
            let isVisible = ghostWindowController?.window?.isVisible ?? false
            toggleItem.title = isVisible ? "Hide Overlay" : "Show Overlay"
        }
    }

    // MARK: - Overlay Window

    private func setupGhostWindow() {
        let overlayView = ChatOverlayView(
            transcriptState: transcriptState,
            deepgramService: deepgramService,
            onToggleListening: { [weak self] in
                self?.toggleListening()
            },
            onClearHistory: { [weak self] in
                self?.clearCurrentSession()
            },
            onSubmitQuestion: { [weak self] question in
                self?.submitManualQuestion(question)
            }
        )

        ghostWindowController = GhostWindowController(rootView: overlayView)
        ghostWindowController?.showWindow(nil)

        updateOverlayMenuItemTitle()
    }

    // MARK: - Global Hotkey

    private func setupGlobalHotkey() {
        installHotKeyEventHandler()
        registerGlobalHotkeys()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutSettingsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )

        localKeyMonitor = nil
    }

    private func installHotKeyEventHandler() {
        guard hotKeyEventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr,
                      hotKeyID.signature == AppDelegate.hotKeySignature else {
                    return noErr
                }

                Task { @MainActor in
                    AppDelegate.shared?.handleHotKey(id: hotKeyID.id)
                }

                return noErr
            },
            1,
            &eventType,
            nil,
            &hotKeyEventHandler
        )

        if status != noErr {
            print("[App] Failed to install hotkey handler: \(status)")
        }
    }

    private func registerGlobalHotkeys() {
        unregisterGlobalHotkeys()

        for action in ShortcutAction.allCases {
            let shortcut = action.shortcut
            guard shortcut.carbonModifiers != 0 else { continue }

            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(
                signature: Self.hotKeySignature,
                id: action.hotKeyID
            )

            let status = RegisterEventHotKey(
                UInt32(shortcut.keyCode),
                shortcut.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )

            if status == noErr, let hotKeyRef {
                registeredHotKeys[action.hotKeyID] = hotKeyRef
            } else {
                print("[App] Failed to register shortcut \(action.title): \(status)")
            }
        }
    }

    private func unregisterGlobalHotkeys() {
        for hotKeyRef in registeredHotKeys.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        registeredHotKeys.removeAll()
    }

    @objc private func shortcutSettingsDidChange() {
        registerGlobalHotkeys()
    }

    private func handleHotKey(id: UInt32) {
        guard settingsWindow?.isKeyWindow != true,
              let action = ShortcutAction.action(forHotKeyID: id) else {
            return
        }

        handleShortcut(action)
    }

    private func shortcutAction(for event: NSEvent) -> ShortcutAction? {
        ShortcutAction.allCases.first { action in
            action.shortcut.matches(event)
        }
    }

    private func handleShortcut(_ event: NSEvent) {
        guard let action = shortcutAction(for: event) else { return }

        handleShortcut(action)
    }

    private func handleShortcut(_ action: ShortcutAction) {

        switch action {
        case .toggleOverlay:
            toggleOverlayVisibility()
        case .toggleListening:
            toggleListening()
        case .clearSession:
            clearCurrentSession()
        case .toggleHistory:
            transcriptState.showHistory.toggle()
        case .selectModel1:
            selectOpenRouterModel(index: 1)
        case .selectModel2:
            selectOpenRouterModel(index: 2)
        case .selectModel3:
            selectOpenRouterModel(index: 3)
        case .selectGemini:
            selectGeminiProvider()
        }
    }

    // MARK: - Peek Monitor (Hold right Command to peek)

    private func setupPeekMonitor() {
        globalPeekMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleRightCommandKey(event: event)
            }
        }

        localPeekMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleRightCommandKey(event: event)
            }
            return event
        }
    }

    private func handleRightCommandKey(event: NSEvent) {
        let isRightCommand = event.keyCode == rightCommandKeyCode
        let commandPressed = event.modifierFlags.contains(.command)

        if isRightCommand && commandPressed && !isPeeking {
            if let window = ghostWindowController?.window, !window.isVisible {
                wasHiddenBeforePeek = true
                isPeeking = true
                window.orderFront(nil)
            }
        } else if !commandPressed && isPeeking {
            isPeeking = false
            if wasHiddenBeforePeek {
                ghostWindowController?.window?.orderOut(nil)
                wasHiddenBeforePeek = false
            }
            updateOverlayMenuItemTitle()
        }
    }


    // MARK: - Actions

    @objc private func toggleListeningAction() {
        toggleListening()
    }

    private func toggleListening() {
        if transcriptState.isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    private func startListening() {
        transcriptState.startNewTranscriptLog()

        deepgramService.connect { [weak self] transcript in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                let questionID = self.transcriptState.addInterviewerQuestion(transcript)
                self.enqueueLLMRequest(questionID: questionID, sessionID: self.currentSessionID)
            }
        }

        Task {
            let didStart = await audioManager.startCapture { [weak self] audioData in
                self?.deepgramService.sendAudio(audioData)
            }

            if didStart {
                transcriptState.isListening = true
                updateStatusItemAppearance()
                print("[App] Started listening")
            } else {
                transcriptState.endTranscriptLog()
                deepgramService.disconnect()
                transcriptState.isListening = false
                updateStatusItemAppearance()
                print("[App] Failed to start listening")
            }
        }
    }

    private func stopListening() {
        transcriptState.isListening = false
        updateStatusItemAppearance()

        transcriptState.endTranscriptLog()
        if let logPath = transcriptState.getTranscriptLogPath() {
            print("[App] Transcript saved to: \(logPath)")
        }

        Task {
            await audioManager.stopCapture()
        }

        deepgramService.disconnect()

        print("[App] Stopped listening")
    }

    private func enqueueLLMRequest(questionID: UUID, sessionID: UUID) {
        pendingLLMRequests.append(LLMRequest(questionID: questionID, sessionID: sessionID))
        processNextLLMRequest()
    }

    private func submitManualQuestion(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let questionID = transcriptState.addInterviewerQuestion(trimmed)
        enqueueLLMRequest(questionID: questionID, sessionID: currentSessionID)
    }

    private func processNextLLMRequest() {
        guard !isProcessingLLMQueue, let request = pendingLLMRequests.first else { return }

        isProcessingLLMQueue = true
        activeLLMRequestID = request.id
        transcriptState.isProcessing = true

        llmTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            defer {
                if self.activeLLMRequestID == request.id {
                    self.pendingLLMRequests.removeAll { $0.id == request.id }
                    self.isProcessingLLMQueue = false
                    self.activeLLMRequestID = nil
                    self.transcriptState.isProcessing = !self.pendingLLMRequests.isEmpty
                    self.llmTask = nil
                    self.processNextLLMRequest()
                }
            }

            guard request.sessionID == self.currentSessionID else { return }

            let answerID = self.transcriptState.beginAssistantAnswer(for: request.questionID)
            let messages = self.transcriptState.toLLMMessages(upTo: request.questionID)
            let answer = await self.generateAnswerWithRetries(messages: messages, request: request) { chunk in
                self.transcriptState.updateAssistantAnswer(id: answerID, content: chunk)
            }

            guard request.sessionID == self.currentSessionID, !Task.isCancelled else { return }

            if let answer {
                self.transcriptState.updateAssistantAnswer(id: answerID, content: answer)
            } else {
                let errorMessage = self.llmService.error ?? "LLM request failed after 3 attempts."
                print("[App] LLM failed after 3 attempts: \(errorMessage)")
                self.transcriptState.updateAssistantAnswer(id: answerID, content: "Error: \(errorMessage)")
            }

            self.transcriptState.finishAssistantAnswer(id: answerID)
        }
    }

    private func generateAnswerWithRetries(
        messages: [LLMMessage],
        request: LLMRequest,
        onChunk: @escaping (String) -> Void
    ) async -> String? {
        let maxAttempts = 3

        for attempt in 1...maxAttempts {
            guard request.sessionID == currentSessionID, !Task.isCancelled else { return nil }

            print("[App] Starting LLM streaming attempt \(attempt)/\(maxAttempts)")
            var attemptAnswer = ""
            onChunk("")

            let answer = await llmService.generateAnswerStreaming(messages: messages) { chunk in
                guard request.sessionID == self.currentSessionID, !Task.isCancelled else {
                    return
                }

                attemptAnswer += chunk
                onChunk(attemptAnswer)
            }

            guard request.sessionID == currentSessionID, !Task.isCancelled else { return nil }

            if let answer, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return answer
            }

            let errorMessage = llmService.error ?? "empty response"
            print("[App] LLM streaming attempt \(attempt)/\(maxAttempts) failed: \(errorMessage)")

            if attempt < maxAttempts {
                print("[App] Retrying LLM request...")
            }
        }

        return nil
    }

    private func cancelPendingLLMWork() {
        llmTask?.cancel()
        llmTask = nil
        activeLLMRequestID = nil
        pendingLLMRequests.removeAll()
        isProcessingLLMQueue = false
        transcriptState.isProcessing = false
    }

    private func clearCurrentSession() {
        currentSessionID = UUID()
        cancelPendingLLMWork()
        transcriptState.clearHistory()
        print("[App] Cleared current chat session")
    }

    private func selectOpenRouterModel(index: Int) {
        UserDefaults.standard.set(LLMProvider.openRouter.rawValue, forKey: "llmProvider")
        UserDefaults.standard.set(index, forKey: "selectedOpenRouterModelIndex")
        print("[App] Selected OpenRouter model \(index)")
    }

    private func selectGeminiProvider() {
        UserDefaults.standard.set(LLMProvider.google.rawValue, forKey: "llmProvider")
        print("[App] Selected Gemini provider")
    }

    @objc private func toggleOverlay() {
        toggleOverlayVisibility()
    }

    private func toggleOverlayVisibility() {
        if let window = ghostWindowController?.window {
            if window.isVisible {
                window.orderOut(nil)
            } else {
                window.orderFront(nil)
            }
            updateOverlayMenuItemTitle()
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView(transcriptState: transcriptState)
            let hostingController = NSHostingController(rootView: settingsView)

            settingsWindow = SettingsWindow(contentViewController: hostingController)
            settingsWindow?.title = "MeetHelp Settings"
            settingsWindow?.styleMask = [.titled, .closable, .miniaturizable]
            settingsWindow?.level = .floating
            settingsWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            settingsWindow?.isReleasedWhenClosed = false
            settingsWindow?.center()
        }

        NSApp.setActivationPolicy(.accessory)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.deminiaturize(nil)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()

        DispatchQueue.main.async { [weak self] in
            guard let window = self?.settingsWindow else { return }
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            NSApp.activate(ignoringOtherApps: true)
            window.makeKey()
            window.makeMain()
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

private struct LLMRequest: Identifiable {
    let id = UUID()
    let questionID: UUID
    let sessionID: UUID
}

private final class SettingsWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}
