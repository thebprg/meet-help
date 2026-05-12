import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static weak var shared: AppDelegate?
    private static let hotKeySignature = OSType(
        UInt32(UInt8(ascii: "M")) << 24 |
        UInt32(UInt8(ascii: "H")) << 16 |
        UInt32(UInt8(ascii: "K")) << 8 |
        UInt32(UInt8(ascii: "Y"))
    )

    private var statusItem: NSStatusItem?
    private var mainStatusMenu: NSMenu?
    private var appearanceStatusMenu: NSMenu?
    private var ghostWindowController: GhostWindowController?
    private var followUpWindowController: GhostWindowController?
    private var settingsWindow: NSWindow?
    private weak var overlayOpacitySlider: NSSlider?

    private let transcriptState = TranscriptState()
    private let audioManager = AudioCaptureManager()
    private let deepgramService = DeepgramService()
    private let microphoneManager = MicrophoneCaptureManager()
    private let microphoneDeepgramService = DeepgramService()
    private let llmService = LLMService()
    private let youSearchService = YouSearchService()
    private let screenAnalysisService = ScreenAnalysisService()

    private var hotKeyEventHandler: EventHandlerRef?
    private var registeredHotKeys: [UInt32: EventHotKeyRef] = [:]
    private var globalShortcutMonitor: Any?
    private var localShortcutMonitor: Any?
    private var lastShortcutHandledAt: [String: Date] = [:]
    private var quitConfirmationWindow: NSWindow?
    private var quitConfirmationTask: Task<Void, Never>?
    private var quitShortcutConfirmationExpiresAt: Date?
    private var isRecordingShortcut = false

    private var currentSessionID = UUID()
    private var pendingLLMRequests: [LLMRequest] = []
    private var llmTask: Task<Void, Never>?
    private var screenAnalysisTask: Task<Void, Never>?
    private var activeLLMRequestID: UUID?
    private var isProcessingLLMQueue = false
    private var microphoneStopTask: Task<Void, Never>?
    private var providerCooldownUntil: [LLMProvider: Date] = [:]
    private let providerCooldownDuration: TimeInterval = 60
    private var followUpModeCancellable: AnyCancellable?
    private var mainWindowFrameObservers: [NSObjectProtocol] = []

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            Self.shared = self
            NSApp.setActivationPolicy(.accessory)
            setupStatusItem()
            setupGhostWindow()
            observeFollowUpMode()
            setupGlobalHotkey()
            warmOpenRouterModelCapabilities()
        }
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            cancelPendingLLMWork()
            quitConfirmationTask?.cancel()
            unregisterGlobalHotkeys()
            removeShortcutMonitors()
            removeMainWindowFrameObservers()
            followUpModeCancellable?.cancel()
            transcriptState.endTranscriptLog()
            await audioManager.stopCapture()
            microphoneManager.stopCapture()
            deepgramService.disconnect()
            microphoneDeepgramService.disconnect()
        }
    }

    // MARK: - Status Item (Menu Bar)

    private func warmOpenRouterModelCapabilities() {
        Task {
            await OpenRouterModelCatalog.shared.warm()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "MeetHelp")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            updateStatusItemAppearance()
        }

        let menu = makeMainStatusMenu()
        let appearanceMenu = makeAppearanceStatusMenu()
        mainStatusMenu = menu
        appearanceStatusMenu = appearanceMenu
    }

    private func makeMainStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let toggleOverlayItem = NSMenuItem(title: "Show Overlay", action: #selector(toggleOverlay), keyEquivalent: "")
        toggleOverlayItem.target = self
        menu.addItem(toggleOverlayItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit MeetHelp", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func makeAppearanceStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(makeOverlayAppearanceMenuItem())
        return menu
    }

    private func makeOverlayAppearanceMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 42))

        let backgroundLabel = appearanceSliderLabel("Background")

        let slider = NSSlider(value: Config.overlayOpacity, minValue: 0.2, maxValue: 0.95, target: self, action: #selector(overlayOpacityChanged(_:)))
        slider.controlSize = .small
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        overlayOpacitySlider = slider

        container.addSubview(backgroundLabel)
        container.addSubview(slider)

        NSLayoutConstraint.activate([
            backgroundLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            backgroundLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            backgroundLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 5),

            slider.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            slider.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            slider.topAnchor.constraint(equalTo: backgroundLabel.bottomAnchor, constant: 1)
        ])

        item.view = container
        return item
    }

    private func appearanceSliderLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            showMainStatusMenu()
            return
        }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showAppearanceStatusMenu()
        } else {
            showMainStatusMenu()
        }
    }

    private func showMainStatusMenu() {
        guard let button = statusItem?.button, let menu = mainStatusMenu else { return }
        updateOverlayMenuItemTitle()
        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    private func showAppearanceStatusMenu() {
        guard let button = statusItem?.button, let menu = appearanceStatusMenu else { return }
        overlayOpacitySlider?.doubleValue = Config.overlayOpacity
        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    func menuWillOpen(_ menu: NSMenu) {
        overlayOpacitySlider?.doubleValue = Config.overlayOpacity
    }

    @objc private func overlayOpacityChanged(_ sender: NSSlider) {
        Config.overlayOpacity = sender.doubleValue
        NotificationCenter.default.post(name: .overlayAppearanceDidChange, object: nil)
    }

    private func updateStatusItemAppearance() {
        if let button = statusItem?.button {
            let symbolName = transcriptState.isListening ? "waveform.circle.fill" : "waveform.circle"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "MeetHelp")
        }

        updateOverlayMenuItemTitle()
    }

    private func updateOverlayMenuItemTitle() {
        if let menu = mainStatusMenu,
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
            onToggleMicrophonePrompt: { [weak self] in
                self?.toggleMicrophonePrompt()
            },
            onCaptureScreen: { [weak self] in
                self?.captureScreenContext()
            },
            onDeletePreviousQuestion: { [weak self] in
                self?.deletePreviousQuestion()
            },
            onClearHistory: { [weak self] in
                self?.clearCurrentSession()
            },
            onSubmitPendingInterviewerQuestion: { [weak self] in
                self?.submitPendingInterviewerQuestion()
            },
            onSubmitQuestion: { [weak self] question in
                self?.submitManualQuestion(question)
            }
        )

        ghostWindowController = GhostWindowController(rootView: overlayView)
        ghostWindowController?.showWindow(nil)
        installMainWindowFrameObservers()

        updateOverlayMenuItemTitle()
    }

    private func observeFollowUpMode() {
        followUpModeCancellable = transcriptState.$isFollowUpModeEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if isEnabled {
                        self.showFollowUpWindow()
                    } else {
                        self.hideFollowUpWindow()
                    }
                }
            }
    }

    private func showFollowUpWindow() {
        guard ghostWindowController?.window?.isVisible == true else { return }

        if followUpWindowController == nil {
            let followUpView = FollowUpOverlayView(
                transcriptState: transcriptState,
                deepgramService: deepgramService,
                onClose: { [weak self] in
                    self?.transcriptState.setFollowUpMode(false)
                }
            )

            followUpWindowController = GhostWindowController(
                rootView: followUpView,
                contentRect: followUpWindowFrame()
            )
        }

        positionFollowUpWindow()
        followUpWindowController?.window?.orderFront(nil)
    }

    private func hideFollowUpWindow() {
        followUpWindowController?.window?.orderOut(nil)
    }

    private func positionFollowUpWindow() {
        guard let window = followUpWindowController?.window else { return }
        window.setFrame(followUpWindowFrame(), display: true, animate: false)
    }

    private func followUpWindowFrame() -> NSRect {
        guard let mainWindow = ghostWindowController?.window else {
            return NSRect(x: 80, y: 80, width: 420, height: Config.defaultWindowHeight)
        }

        let mainFrame = mainWindow.frame
        let visibleFrame = mainWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? mainFrame
        let gap: CGFloat = 10
        let desiredWidth = min(max(mainFrame.width * 0.72, 360), 480)
        let rightSpace = max(0, visibleFrame.maxX - mainFrame.maxX - gap)
        let leftSpace = max(0, mainFrame.minX - visibleFrame.minX - gap)
        let useRight = rightSpace >= desiredWidth || rightSpace >= leftSpace
        let availableWidth = useRight ? rightSpace : leftSpace
        let width = max(Config.minWindowWidth, min(desiredWidth, max(availableWidth, Config.minWindowWidth)))
        let x = useRight
            ? min(mainFrame.maxX + gap, visibleFrame.maxX - width)
            : max(visibleFrame.minX, mainFrame.minX - gap - width)
        let height = min(mainFrame.height, visibleFrame.height)
        let y = min(max(mainFrame.minY, visibleFrame.minY), visibleFrame.maxY - height)

        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func installMainWindowFrameObservers() {
        removeMainWindowFrameObservers()
        guard let window = ghostWindowController?.window else { return }

        let names: [Notification.Name] = [
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
            NSWindow.didEndLiveResizeNotification
        ]

        mainWindowFrameObservers = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.positionFollowUpWindow()
                }
            }
        }
    }

    private func removeMainWindowFrameObservers() {
        mainWindowFrameObservers.forEach(NotificationCenter.default.removeObserver)
        mainWindowFrameObservers.removeAll()
    }

    // MARK: - Global Hotkey

    private func setupGlobalHotkey() {
        installHotKeyEventHandler()
        registerGlobalHotkeys()
        installShortcutMonitorFallback()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutSettingsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutRecorderCaptureDidBegin),
            name: .shortcutRecorderCaptureDidBegin,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutRecorderCaptureDidEnd),
            name: .shortcutRecorderCaptureDidEnd,
            object: nil
        )

    }

    private func installShortcutMonitorFallback() {
        guard globalShortcutMonitor == nil, localShortcutMonitor == nil else { return }

        globalShortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleShortcutEventFallback(event)
            }
        }

        localShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleShortcutEventFallback(event)
            }
            return event
        }
    }

    private func removeShortcutMonitors() {
        if let globalShortcutMonitor {
            NSEvent.removeMonitor(globalShortcutMonitor)
            self.globalShortcutMonitor = nil
        }

        if let localShortcutMonitor {
            NSEvent.removeMonitor(localShortcutMonitor)
            self.localShortcutMonitor = nil
        }
    }

    private func installHotKeyEventHandler() {
        guard hotKeyEventHandler == nil else { return }

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

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

                let eventKind = GetEventKind(event)
                Task { @MainActor in
                    AppDelegate.shared?.handleHotKey(
                        id: hotKeyID.id,
                        isPressed: eventKind == UInt32(kEventHotKeyPressed)
                    )
                }

                return noErr
            },
            eventTypes.count,
            &eventTypes,
            nil,
            &hotKeyEventHandler
        )

        if status != noErr {
            print("[App] Failed to install hotkey handler: \(status)")
        }
    }

    private func registerGlobalHotkeys() {
        guard !isRecordingShortcut else { return }

        unregisterGlobalHotkeys()

        for action in ShortcutAction.allCases {
            let shortcut = action.shortcut
            guard !shortcut.isUnset, shortcut.carbonModifiers != 0 else { continue }

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
        guard !isRecordingShortcut else { return }
        registerGlobalHotkeys()
    }

    @objc private func shortcutRecorderCaptureDidBegin() {
        isRecordingShortcut = true
        unregisterGlobalHotkeys()
        lastShortcutHandledAt.removeAll()
    }

    @objc private func shortcutRecorderCaptureDidEnd() {
        isRecordingShortcut = false
        lastShortcutHandledAt.removeAll()
        registerGlobalHotkeys()
    }

    private func handleHotKey(id: UInt32, isPressed: Bool) {
        guard !isRecordingShortcut,
              let action = ShortcutAction.action(forHotKeyID: id),
              shouldAllowShortcutWhileSettingsIsFocused(action) else {
            return
        }

        if action == .holdMicrophonePrompt {
            guard shouldHandleShortcut(action, isPressed: isPressed) else { return }
            if isPressed {
                startMicrophonePrompt()
            } else {
                stopMicrophonePromptAndSubmit()
            }
            return
        }

        guard isPressed else { return }
        guard shouldHandleShortcut(action, isPressed: true) else { return }
        handleShortcut(action)
    }

    private func handleShortcutEventFallback(_ event: NSEvent) {
        guard !isRecordingShortcut,
              event.type == .keyDown || event.type == .keyUp,
              !event.isARepeat,
              let action = ShortcutAction.allCases.first(where: { $0.shortcut.matches(event) }),
              shouldAllowShortcutWhileSettingsIsFocused(action) else {
            return
        }

        if action == .holdMicrophonePrompt {
            guard shouldHandleShortcut(action, isPressed: event.type == .keyDown) else { return }
            if event.type == .keyDown {
                startMicrophonePrompt()
            } else {
                stopMicrophonePromptAndSubmit()
            }
            return
        }

        guard event.type == .keyDown else { return }
        guard shouldHandleShortcut(action, isPressed: true) else { return }
        handleShortcut(action)
    }

    private func shouldHandleShortcut(_ action: ShortcutAction, isPressed: Bool) -> Bool {
        let now = Date()
        let debounceKey = "\(action.rawValue):\(isPressed ? "down" : "up")"
        if let last = lastShortcutHandledAt[debounceKey],
           now.timeIntervalSince(last) < 0.12 {
            return false
        }

        lastShortcutHandledAt[debounceKey] = now
        return true
    }

    private func shouldAllowShortcutWhileSettingsIsFocused(_ action: ShortcutAction) -> Bool {
        guard settingsWindow?.isKeyWindow == true else { return true }
        return action == .toggleSettings || action == .quitApp
    }

    private func handleShortcut(_ action: ShortcutAction) {

        switch action {
        case .toggleOverlay:
            toggleOverlayVisibility()
        case .toggleListening:
            toggleListening()
        case .clearSession:
            clearCurrentSession()
        case .deletePreviousQuestion:
            deletePreviousQuestion()
        case .toggleHistory:
            transcriptState.showHistory.toggle()
        case .toggleSettings:
            toggleSettingsWindow()
        case .quitApp:
            requestShortcutQuitConfirmation()
        case .selectModel1:
            selectOpenRouterModel(index: 1)
        case .selectModel2:
            selectOpenRouterModel(index: 2)
        case .selectModel3:
            selectOpenRouterModel(index: 3)
        case .selectGemini:
            selectGeminiProvider()
        case .holdMicrophonePrompt:
            break
        case .selectModel0:
            selectOpenRouterModel(index: 0)
        case .submitInterviewerTranscript:
            submitPendingInterviewerQuestion()
        case .toggleFollowUpMode:
            transcriptState.toggleFollowUpMode()
        }
    }

    // MARK: - Actions

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

                if Config.manualInterviewerSubmitEnabled {
                    self.transcriptState.appendPendingInterviewerTranscript(transcript)
                    print("[App] Buffered interviewer transcript for manual submit")
                } else {
                    self.submitInterviewerQuestion(transcript)
                }
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

    private func toggleMicrophonePrompt() {
        if transcriptState.isRecordingMicPrompt {
            stopMicrophonePromptAndSubmit()
        } else {
            startMicrophonePrompt()
        }
    }

    private func startMicrophonePrompt() {
        guard !transcriptState.isRecordingMicPrompt else { return }

        microphoneStopTask?.cancel()
        microphoneStopTask = nil
        transcriptState.micPromptTranscript = ""

        microphoneDeepgramService.connect(
            onTranscriptUpdate: { [weak self] transcript in
                Task { @MainActor [weak self] in
                    self?.transcriptState.micPromptTranscript = transcript
                }
            },
            onUtteranceEnd: { [weak self] transcript in
                Task { @MainActor [weak self] in
                    self?.transcriptState.micPromptTranscript = transcript
                }
            }
        )

        Task {
            let didStart = await microphoneManager.startCapture { [weak self] audioData in
                self?.microphoneDeepgramService.sendAudio(audioData)
            }

            if didStart {
                transcriptState.isRecordingMicPrompt = true
                print("[App] Started microphone prompt")
            } else {
                microphoneDeepgramService.disconnect()
                transcriptState.isRecordingMicPrompt = false
                print("[App] Failed to start microphone prompt")
            }
        }
    }

    private func stopMicrophonePromptAndSubmit() {
        guard transcriptState.isRecordingMicPrompt else { return }

        transcriptState.isRecordingMicPrompt = false
        microphoneManager.stopCapture()
        microphoneDeepgramService.requestFinalize()

        microphoneStopTask?.cancel()
        microphoneStopTask = Task { @MainActor [weak self] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }

            let transcript = self.microphoneDeepgramService.finishCurrentUtterance()
            self.microphoneDeepgramService.disconnect()

            let prompt = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            self.transcriptState.micPromptTranscript = prompt

            guard !prompt.isEmpty else {
                print("[App] Microphone prompt was empty")
                return
            }

            self.submitManualQuestion(prompt)
            self.transcriptState.micPromptTranscript = ""
            print("[App] Submitted microphone prompt")
        }
    }

    private func enqueueLLMRequest(questionID: UUID, sessionID: UUID) {
        pendingLLMRequests.append(LLMRequest(questionID: questionID, sessionID: sessionID))
        processNextLLMRequest()
    }

    private func submitInterviewerQuestion(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let questionID = transcriptState.addInterviewerQuestion(trimmed)
        enqueueLLMRequest(questionID: questionID, sessionID: currentSessionID)
    }

    private func submitPendingInterviewerQuestion() {
        let pendingTranscript = transcriptState.pendingInterviewerTranscript
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let liveTranscript = deepgramService.finishCurrentUtterance()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let combinedTranscript = [pendingTranscript, liveTranscript]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !combinedTranscript.isEmpty else {
            print("[App] No pending interviewer transcript to submit")
            return
        }

        transcriptState.clearPendingInterviewerTranscript()
        submitInterviewerQuestion(combinedTranscript)
        print("[App] Submitted pending interviewer transcript")
    }

    private func submitManualQuestion(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let questionID = transcriptState.addStarterClue(trimmed)
        enqueueLLMRequest(questionID: questionID, sessionID: currentSessionID)
    }

    private func captureScreenContext() {
        guard !transcriptState.isAnalyzingScreen else {
            print("[App] Screen capture ignored; analysis is already running.")
            return
        }

        print("[App] Screen capture button clicked.")

        guard let imageData = screenAnalysisService.captureScreen(excluding: ghostWindowController?.window) else {
            transcriptState.screenContext = ""
            print("[App] Screen capture failed: \(screenAnalysisService.error ?? "unknown error")")
            return
        }

        let sessionID = currentSessionID
        transcriptState.isAnalyzingScreen = true
        print("[App] Screen captured (\(imageData.count) bytes). Starting image analysis with \(Config.selectedLLMProvider.displayName).")

        screenAnalysisTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if sessionID == self.currentSessionID {
                    self.transcriptState.isAnalyzingScreen = false
                }
                if self.screenAnalysisTask != nil {
                    self.screenAnalysisTask = nil
                }
            }

            let description = await self.screenAnalysisService.analyzeScreen(imageData: imageData)
            guard sessionID == self.currentSessionID, !Task.isCancelled else {
                print("[App] Ignored screen analysis result from an old session.")
                return
            }

            if let description {
                self.transcriptState.screenContext = description
                print("[App] Updated screen context from explicit capture (\(description.count) characters).")
            } else {
                let error = self.screenAnalysisService.error ?? "screen analysis failed"
                self.transcriptState.screenContext = ""
                print("[App] Screen analysis failed: \(error)")
            }
        }
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

            if self.transcriptState.isAnalyzingScreen, let screenAnalysisTask = self.screenAnalysisTask {
                print("[App] Waiting for screen analysis before building LLM context.")
                await screenAnalysisTask.value
            }

            guard request.sessionID == self.currentSessionID, !Task.isCancelled else { return }

            let liveSearchContext = await self.liveSearchContextIfNeeded(for: request.questionID)
            let answerID = self.transcriptState.beginAssistantAnswer(for: request.questionID)
            let messages = self.transcriptState.toLLMMessages(
                upTo: request.questionID,
                liveSearchContext: liveSearchContext
            )
            print("[App] Built LLM context. Screen context characters: \(self.transcriptState.screenContext.count), live search characters: \(liveSearchContext?.count ?? 0)")
            let answer = await self.generateAnswerWithRetries(
                messages: messages,
                request: request,
                onChunk: { chunk in
                    self.transcriptState.updateAssistantAnswer(id: answerID, content: chunk)
                },
                onReasoning: { reasoning in
                    self.transcriptState.updateAssistantReasoning(id: answerID, content: reasoning)
                }
            )

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

    private func liveSearchContextIfNeeded(for questionID: UUID) async -> String? {
        guard Config.liveSearchEnabled else { return nil }

        guard !Config.youAPIKey.isEmpty else {
            print("[LiveSearch] Skipped: YOU_API_KEY is missing.")
            return nil
        }

        guard let query = transcriptState.content(for: questionID)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty else {
            print("[LiveSearch] Skipped: no query text found for triggering question.")
            return nil
        }

        let rewriteMessages = transcriptState.toLLMMessages(upTo: questionID)
        let searchQuery = await llmService.generateSearchQuery(messages: rewriteMessages, fallbackQuery: query) ?? query
        print("[LiveSearch] Searching You.com for query: \(searchQuery)")
        let context = await youSearchService.searchContext(for: searchQuery)
        if let context {
            print("[LiveSearch] Added search context (\(context.count) characters).")
        } else {
            print("[LiveSearch] Search failed or returned no usable context: \(youSearchService.error ?? "unknown error")")
        }
        return context
    }

    private func generateAnswerWithRetries(
        messages: [LLMMessage],
        request: LLMRequest,
        onChunk: @escaping (String) -> Void,
        onReasoning: @escaping (String) -> Void
    ) async -> String? {
        let maxAttempts = 3
        let selectedProvider = Config.selectedLLMProvider
        let providers = providerAttemptSequence(primary: selectedProvider)

        for provider in providers {
            guard request.sessionID == currentSessionID, !Task.isCancelled else { return nil }

            if provider != selectedProvider {
                print("[App] Using fallback LLM provider: \(provider.displayName)")
            } else if isProviderInCooldown(provider) {
                print("[App] Retrying selected provider despite cooldown because fallback also failed: \(provider.displayName)")
            } else {
                print("[App] Using selected LLM provider: \(provider.displayName)")
            }

            for attempt in 1...maxAttempts {
                guard request.sessionID == currentSessionID, !Task.isCancelled else { return nil }

                print("[App] Starting \(provider.displayName) LLM streaming attempt \(attempt)/\(maxAttempts)")
                var attemptAnswer = ""
                onChunk("")
                onReasoning("")

                let answer = await llmService.generateAnswerStreaming(
                    provider: provider,
                    messages: messages,
                    onChunk: { chunk in
                        guard request.sessionID == self.currentSessionID, !Task.isCancelled else {
                            return
                        }

                        attemptAnswer += chunk
                        onChunk(attemptAnswer)
                    },
                    onReasoning: { fullReasoning in
                        guard request.sessionID == self.currentSessionID, !Task.isCancelled else {
                            return
                        }

                        onReasoning(fullReasoning)
                    }
                )

                guard request.sessionID == currentSessionID, !Task.isCancelled else { return nil }

                if let answer, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    markProviderHealthy(provider)
                    return answer
                }

                let errorMessage = llmService.error ?? "empty response"
                print("[App] \(provider.displayName) LLM streaming attempt \(attempt)/\(maxAttempts) failed: \(errorMessage)")

                if attempt < maxAttempts {
                    print("[App] Retrying \(provider.displayName) LLM request...")
                }
            }

            markProviderUnhealthy(provider)
            if provider == selectedProvider {
                print("[App] \(provider.displayName) failed after \(maxAttempts) attempts; falling back to \(provider.fallbackProvider.displayName).")
            }
        }

        return nil
    }

    private func providerAttemptSequence(primary: LLMProvider) -> [LLMProvider] {
        let fallback = primary.fallbackProvider
        if isProviderInCooldown(primary) {
            print("[App] Selected provider \(primary.displayName) is cooling down; using \(fallback.displayName) first.")
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
        print("[App] Marked \(provider.displayName) unhealthy for \(Int(providerCooldownDuration)) seconds.")
    }

    private func cancelPendingLLMWork() {
        llmTask?.cancel()
        screenAnalysisTask?.cancel()
        llmTask = nil
        screenAnalysisTask = nil
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

    private func deletePreviousQuestion() {
        guard let deletedQuestionID = transcriptState.deletePreviousQuestion() else {
            print("[App] No previous question to delete")
            return
        }

        let activeRequestWasDeleted = pendingLLMRequests.contains {
            $0.id == activeLLMRequestID && $0.questionID == deletedQuestionID
        }

        pendingLLMRequests.removeAll { $0.questionID == deletedQuestionID }

        if activeRequestWasDeleted {
            llmTask?.cancel()
            llmTask = nil
            activeLLMRequestID = nil
            isProcessingLLMQueue = false
            transcriptState.isProcessing = !pendingLLMRequests.isEmpty
            processNextLLMRequest()
        } else {
            transcriptState.isProcessing = isProcessingLLMQueue || !pendingLLMRequests.isEmpty
        }

        print("[App] Deleted previous question")
    }

    private func selectOpenRouterModel(index: Int) {
        let normalizedIndex = min(max(index, 0), 3)
        UserDefaults.standard.set(LLMProvider.openRouter.rawValue, forKey: "llmProvider")
        UserDefaults.standard.set(normalizedIndex, forKey: "selectedOpenRouterModelIndex")
        print("[App] Selected OpenRouter model \(normalizedIndex)")
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
                hideFollowUpWindow()
            } else {
                window.orderFront(nil)
                if transcriptState.isFollowUpModeEnabled {
                    showFollowUpWindow()
                }
            }
            updateOverlayMenuItemTitle()
        }
    }

    @objc private func openSettings() {
        showSettingsWindow()
    }

    private func toggleSettingsWindow() {
        guard let settingsWindow, settingsWindow.isVisible else {
            showSettingsWindow()
            return
        }

        settingsWindow.orderOut(nil)
    }

    private func showSettingsWindow() {
        if settingsWindow == nil {
            let settingsView = SettingsView(
                transcriptState: transcriptState,
                screenAnalysisService: screenAnalysisService
            )
            let hostingController = NSHostingController(rootView: settingsView)

            settingsWindow = SettingsWindow(contentViewController: hostingController)
            settingsWindow?.title = "MeetHelp Settings"
            settingsWindow?.styleMask = [.titled, .closable, .miniaturizable]
            settingsWindow?.level = .floating
            settingsWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            settingsWindow?.sharingType = .none
            settingsWindow?.isReleasedWhenClosed = false
        }

        positionSettingsWindowOnOverlayScreen()
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

    private func requestShortcutQuitConfirmation() {
        let now = Date()
        if let expiresAt = quitShortcutConfirmationExpiresAt, now < expiresAt {
            quitShortcutConfirmationExpiresAt = nil
            hideQuitConfirmationPopup()
            quitApp()
            return
        }

        showQuitConfirmationPopup()
        quitShortcutConfirmationExpiresAt = now.addingTimeInterval(3)

        quitConfirmationTask?.cancel()
        quitConfirmationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.quitShortcutConfirmationExpiresAt = nil
            self?.hideQuitConfirmationPopup()
        }
    }

    private func showQuitConfirmationPopup() {
        if quitConfirmationWindow == nil {
            let popup = QuitConfirmationView()
            let hostingController = NSHostingController(rootView: popup)
            let window = QuitConfirmationWindow(contentViewController: hostingController)
            window.setContentSize(NSSize(width: 330, height: 82))
            quitConfirmationWindow = window
        }

        positionQuitConfirmationPopup()
        quitConfirmationWindow?.orderFrontRegardless()
    }

    private func positionQuitConfirmationPopup() {
        guard let window = quitConfirmationWindow,
              let screenFrame = overlayScreenVisibleFrame() else { return }

        let size = window.frame.size
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height - 52
        )
        window.setFrameOrigin(origin)
    }

    private func positionSettingsWindowOnOverlayScreen() {
        guard let settingsWindow,
              let screenFrame = overlayScreenVisibleFrame() else { return }

        let size = settingsWindow.frame.size
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        )
        settingsWindow.setFrameOrigin(origin)
    }

    private func overlayScreenVisibleFrame() -> NSRect? {
        if let screen = ghostWindowController?.window?.screen {
            return screen.visibleFrame
        }

        if let overlayFrame = ghostWindowController?.window?.frame,
           let screen = NSScreen.screens.max(by: {
               $0.frame.intersection(overlayFrame).area < $1.frame.intersection(overlayFrame).area
           }) {
            return screen.visibleFrame
        }

        return NSScreen.main?.visibleFrame
    }

    private func hideQuitConfirmationPopup() {
        quitConfirmationTask?.cancel()
        quitConfirmationTask = nil
        quitConfirmationWindow?.orderOut(nil)
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

private final class QuitConfirmationWindow: NSPanel {
    init(contentViewController: NSViewController) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 330, height: 82),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.contentViewController = contentViewController
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        self.sharingType = .none
        self.isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

private struct QuitConfirmationView: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "power.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.red.opacity(0.92))

            VStack(alignment: .leading, spacing: 4) {
                Text("Press quit shortcut again")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.96))
                Text("Confirmation expires in 3 seconds.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.72))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(1)
    }
}

private extension NSRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}
