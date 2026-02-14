import AppKit
import SwiftUI
import Carbon.HIToolbox

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var ghostWindowController: GhostWindowController?
    private var settingsWindow: NSWindow?
    
    // Shared state
    private let transcriptState = TranscriptState()
    private let audioManager = AudioCaptureManager()
    private let deepgramService = DeepgramService()
    private let cerebrasService = CerebrasService()
    
    // Hotkey monitoring
    private var eventMonitor: Any?
    
    // Peek feature - hold right Command key to peek when hidden
    private var isPeeking = false
    private var wasHiddenBeforePeek = false
    
    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            setupStatusItem()
            setupGhostWindow()
            setupGlobalHotkey()
            setupPeekMonitor()
        }
    }
    
    nonisolated func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
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
        
        // Toggle overlay visibility (Ctrl+Option+H)
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
        
        // Update toggle overlay menu item title
        updateOverlayMenuItemTitle()
    }
    
    private func updateOverlayMenuItemTitle() {
        if let menu = statusItem?.menu,
           let toggleItem = menu.items.first {
            let isVisible = ghostWindowController?.window?.isVisible ?? false
            toggleItem.title = isVisible ? "Hide Overlay" : "Show Overlay"
        }
    }
    
    // MARK: - Ghost Window
    
    private func setupGhostWindow() {
        let overlayView = ChatOverlayView(
            transcriptState: transcriptState,
            deepgramService: deepgramService,
            cerebrasService: cerebrasService,
            onToggleListening: { [weak self] in
                self?.toggleListening()
            }
        )
        
        ghostWindowController = GhostWindowController(rootView: overlayView)
        ghostWindowController?.showWindow(nil)
        
        // Update menu item to reflect initial window state
        updateOverlayMenuItemTitle()
    }
    
    // MARK: - Global Hotkey
    
    private func setupGlobalHotkey() {
        // Monitor for Ctrl+Option+H globally (toggle overlay)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Check for Ctrl+Option+H (keyCode 4 is 'H')
            if event.modifierFlags.contains([.control, .option]) && event.keyCode == 4 {
                Task { @MainActor [weak self] in
                    self?.toggleOverlayVisibility()
                }
            }
        }
        
        // Also monitor local events (when app is focused)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.control, .option]) && event.keyCode == 4 {
                Task { @MainActor [weak self] in
                    self?.toggleOverlayVisibility()
                }
                return nil // Consume the event
            }
            return event
        }
    }
    
    // MARK: - Peek Monitor (Hold right Command to peek)
    
    private func setupPeekMonitor() {
        // Right Command keyCode is 54, Left Command is 55
        let rightCommandKeyCode: UInt16 = 54
        
        // Monitor for key down (right Command pressed)
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleRightCommandKey(event: event, rightCommandKeyCode: rightCommandKeyCode)
            }
        }
        
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleRightCommandKey(event: event, rightCommandKeyCode: rightCommandKeyCode)
            }
            return event
        }
    }
    
    private func handleRightCommandKey(event: NSEvent, rightCommandKeyCode: UInt16) {
        // Check if right Command key specifically
        let isRightCommand = event.keyCode == rightCommandKeyCode
        let commandPressed = event.modifierFlags.contains(.command)
        
        if isRightCommand && commandPressed && !isPeeking {
            // Right Command pressed - start peeking if overlay is hidden
            if let window = ghostWindowController?.window, !window.isVisible {
                wasHiddenBeforePeek = true
                isPeeking = true
                window.orderFront(nil)
            }
        } else if !commandPressed && isPeeking {
            // Command released while peeking - hide overlay
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
        transcriptState.isListening = true
        updateStatusItemAppearance()
        
        // Start transcript logging
        transcriptState.startNewTranscriptLog()
        
        // Connect to Deepgram
        deepgramService.connect { [weak self] transcript in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                // Utterance ended - send to LLM
                self.transcriptState.addInterviewerQuestion(transcript)
                self.processWithLLM(transcript: transcript)
            }
        }
        
        // Start audio capture
        Task {
            await audioManager.startCapture { [weak self] audioData in
                self?.deepgramService.sendAudio(audioData)
            }
        }
        
        print("[App] Started listening")
    }
    
    private func stopListening() {
        transcriptState.isListening = false
        updateStatusItemAppearance()
        
        // End transcript logging
        transcriptState.endTranscriptLog()
        if let logPath = transcriptState.getTranscriptLogPath() {
            print("[App] Transcript saved to: \(logPath)")
        }
        
        // Stop audio capture
        Task {
            await audioManager.stopCapture()
        }
        
        // Disconnect from Deepgram
        deepgramService.disconnect()
        
        print("[App] Stopped listening")
    }
    
    private func processWithLLM(transcript: String) {
        Task { @MainActor in
            transcriptState.isProcessing = true
            
            let messages = transcriptState.toCerebrasMessages()
            
            if let answer = await cerebrasService.generateAnswer(messages: messages) {
                // Add assistant's answer to display
                transcriptState.addAssistantAnswer(answer)
                
                // Note: We no longer append as user message since we're not showing "You Said"
                // The conversation context is maintained through the assistant messages
            }
            
            transcriptState.isProcessing = false
        }
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
            
            settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow?.title = "MeetHelp Settings"
            settingsWindow?.styleMask = [.titled, .closable]
            settingsWindow?.center()
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
