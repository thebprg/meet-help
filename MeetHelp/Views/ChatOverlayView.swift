import AppKit
import SwiftUI

struct ChatOverlayView: View {
    @ObservedObject var transcriptState: TranscriptState
    @ObservedObject var deepgramService: DeepgramService
    
    // Callback for toggling listening state
    var onToggleListening: (() -> Void)?
    var onToggleMicrophonePrompt: (() -> Void)?
    var onCaptureScreen: (() -> Void)?
    var onDeletePreviousQuestion: (() -> Void)?
    var onClearHistory: (() -> Void)?
    var onSubmitPendingInterviewerQuestion: (() -> Void)?
    var onSubmitQuestion: ((String) -> Void)?

    @AppStorage("liveSearchEnabled") private var liveSearchEnabled = false
    @AppStorage("youAPIKey") private var youAPIKey = ""
    @AppStorage("manualInterviewerSubmitEnabled") private var manualInterviewerSubmitEnabled = false
    @State private var manualQuestion = ""
    @State private var secondaryToolbarExpanded = false

    private let horizontalMargin: CGFloat = 8

    private var screenCaptureHelpText: String {
        if transcriptState.isAnalyzingScreen {
            return "Analyzing screen"
        }

        if transcriptState.screenContext.isEmpty {
            return "Capture screen context"
        }

        return "Screen context ready. Click to refresh"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with controls
            headerView
            
            // Separator line
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)
            
            // Main content area - BOTH modes are now scrollable
            if transcriptState.showHistory {
                // Scrollable history mode
                historyView
            } else {
                // Single answer mode - NOW SCROLLABLE
                singleAnswerView
            }
            
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)

            composerView
        }
        .background(Color.clear)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 0) {
            primaryToolbar

            if secondaryToolbarExpanded {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)

                secondaryToolbar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color(nsColor: Config.headerBackgroundColor))
        .animation(.easeOut(duration: 0.16), value: secondaryToolbarExpanded)
    }

    private var primaryToolbar: some View {
        HStack(spacing: 10) {
            headerIconButton(
                systemName: transcriptState.isListening ? "pause.fill" : "play.fill",
                isActive: transcriptState.isListening,
                activeColor: .green,
                help: transcriptState.isListening ? "Pause listening" : "Start listening"
            ) {
                onToggleListening?()
            }

            WindowDragRegion()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            headerIconButton(
                systemName: transcriptState.isFollowUpModeEnabled ? "rectangle.split.2x1.fill" : "rectangle.split.2x1",
                isActive: transcriptState.isFollowUpModeEnabled,
                activeColor: .yellow.opacity(0.95),
                help: transcriptState.isFollowUpModeEnabled ? "Follow-up mode on" : "Follow-up mode off"
            ) {
                transcriptState.toggleFollowUpMode()
            }

            if manualInterviewerSubmitEnabled {
                headerIconButton(
                    systemName: "paperplane.circle.fill",
                    isActive: hasSubmittableInterviewerTranscript,
                    isEnabled: hasSubmittableInterviewerTranscript,
                    activeColor: .white.opacity(0.9),
                    help: "Submit buffered interviewer transcript"
                ) {
                    onSubmitPendingInterviewerQuestion?()
                }
            }

            headerIconButton(
                systemName: liveSearchEnabled ? "magnifyingglass.circle.fill" : "magnifyingglass.circle",
                isActive: liveSearchEnabled,
                isEnabled: !youAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                activeColor: .green,
                help: liveSearchHelpText
            ) {
                liveSearchEnabled.toggle()
            }

            headerIconButton(
                systemName: transcriptState.isAnalyzingScreen ? "camera.viewfinder" : "viewfinder",
                isActive: transcriptState.isAnalyzingScreen || !transcriptState.screenContext.isEmpty,
                isEnabled: !transcriptState.isAnalyzingScreen,
                activeColor: .green,
                help: screenCaptureHelpText
            ) {
                onCaptureScreen?()
            }

            headerIconButton(
                systemName: secondaryToolbarExpanded ? "chevron.up.circle.fill" : "chevron.down.circle",
                isActive: secondaryToolbarExpanded,
                help: secondaryToolbarExpanded ? "Hide more controls" : "Show more controls"
            ) {
                secondaryToolbarExpanded.toggle()
            }
        }
        .padding(.horizontal, horizontalMargin)
        .frame(height: 40)
    }

    private var secondaryToolbar: some View {
        HStack(spacing: 8) {
            Button(action: {
                manualInterviewerSubmitEnabled.toggle()
            }) {
                Text(manualInterviewerSubmitEnabled ? "Manual" : "Auto")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(manualInterviewerSubmitEnabled ? .yellow.opacity(0.95) : .white.opacity(0.76))
                    .frame(width: 66, height: 24)
                    .background(Color.white.opacity(manualInterviewerSubmitEnabled ? 0.14 : 0.06))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(manualInterviewerSubmitEnabled ? "Manual interviewer submit is on" : "Auto interviewer submit is on")

            headerIconButton(
                systemName: transcriptState.showHistory ? "rectangle.stack.fill" : "rectangle.fill",
                isActive: transcriptState.showHistory,
                help: transcriptState.showHistory ? "Show single answer" : "Show history"
            ) {
                transcriptState.showHistory.toggle()
            }

            headerIconButton(
                systemName: "minus.circle",
                isActive: false,
                isEnabled: canDeletePreviousQuestion,
                help: "Delete previous question"
            ) {
                onDeletePreviousQuestion?()
            }

            headerIconButton(
                systemName: "trash",
                isActive: false,
                activeColor: .red.opacity(0.9),
                help: "Clear history"
            ) {
                onClearHistory?()
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, horizontalMargin)
        .frame(height: 34)
    }

    private func headerIconButton(
        systemName: String,
        isActive: Bool,
        isEnabled: Bool = true,
        activeColor: Color = .white.opacity(0.9),
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(
                    !isEnabled
                        ? .white.opacity(0.3)
                        : (isActive ? activeColor : .white.opacity(0.72))
                )
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(isActive ? 0.14 : 0.06))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help)
    }

    private var liveSearchHelpText: String {
        if youAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Add YOU_API_KEY in Settings to use live search"
        }

        return liveSearchEnabled ? "Live search on" : "Live search off"
    }
    
    // MARK: - History View
    
    @ViewBuilder
    private var historyView: some View {
        ScrollViewReader { proxy in
            SlimScrollView {
                turnsStack(
                    turns: displayedTurns,
                    showsLiveTranscript: !transcriptState.isFollowUpModeEnabled,
                    emptyText: "Waiting for questions..."
                )
            }
            .onChange(of: transcriptState.messages.count) { _ in
                guard !transcriptState.isFollowUpModeEnabled,
                      let newestTurn = displayedTurns.first else {
                    return
                }

                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(newestTurn.id, anchor: .top)
                }
            }
        }
    }

    private var displayedTurns: [ConversationTurn] {
        transcriptState.isFollowUpModeEnabled ? mainVisibleTurns : visibleTurns
    }

    private var followUpVisibleTurns: [ConversationTurn] {
        visibleTurns.filter { isFollowUpTurn($0) }
    }

    private func isFollowUpTurn(_ turn: ConversationTurn) -> Bool {
        guard transcriptState.isFollowUpModeEnabled,
              let followUpStartedAt = transcriptState.followUpStartedAt else {
            return false
        }

        return turn.question.timestamp > followUpStartedAt
    }

    private var mainVisibleTurns: [ConversationTurn] {
        visibleTurns.filter { !isFollowUpTurn($0) }
    }

    private var latestVisibleAssistantMessage: ChatMessage? {
        if transcriptState.isFollowUpModeEnabled {
            let mainQuestionIDs = Set(mainVisibleTurns.map(\.question.id))
            return transcriptState.messages.last {
                $0.role == .assistant &&
                    $0.relatedQuestionID.map { mainQuestionIDs.contains($0) } == true
            }
        }

        return transcriptState.messages.last { $0.role == .assistant }
    }

    private var normalHistoryView: some View {
        ScrollViewReader { proxy in
            SlimScrollView {
                turnsStack(
                    turns: visibleTurns,
                    showsLiveTranscript: true,
                    emptyText: "Waiting for questions..."
                )
            }
            .onChange(of: transcriptState.messages.count) { _ in
                if let newestTurn = visibleTurns.first {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(newestTurn.id, anchor: .top)
                    }
                }
            }
        }
    }

    private func turnsStack(
        turns: [ConversationTurn],
        showsLiveTranscript: Bool,
        emptyText: String
    ) -> some View {
        LazyVStack(spacing: 10) {
            if showsLiveTranscript, !displayedInterviewerTranscript.isEmpty {
                MessageBubble(
                    message: ChatMessage(role: .interviewer, content: displayedInterviewerTranscript),
                    isLatest: true
                )
                .id("live-transcript")
            }

            if turns.isEmpty && !(showsLiveTranscript && !displayedInterviewerTranscript.isEmpty) {
                Text(emptyText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.38))
                    .frame(maxWidth: .infinity, minHeight: 52)
            }

            ForEach(turns) { turn in
                turnView(turn: turn, isLatest: turn.id == turns.first?.id)
                    .id(turn.id)
            }
        }
        .padding(.horizontal, horizontalMargin)
        .padding(.vertical, 8)
    }

    private func turnView(turn: ConversationTurn, isLatest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            MessageBubble(
                message: processMessage(turn.question),
                isLatest: isLatest
            )

            if let answer = turn.answer {
                answerDivider

                MessageBubble(
                    message: processMessage(answer),
                    isLatest: isLatest
                )
            }
        }
    }

    private var answerDivider: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color(red: 0.24, green: 0.78, blue: 0.62).opacity(0.45))
                .frame(width: 18, height: 1)

            Rectangle()
                .fill(Color(red: 0.24, green: 0.78, blue: 0.62).opacity(0.10))
                .frame(height: 1)
        }
        .padding(.horizontal, 4)
        .padding(.top, 1)
    }
    
    // MARK: - Single Answer View (NOW SCROLLABLE)
    
    private var singleAnswerView: some View {
        SlimScrollView {
            VStack {
                if !transcriptState.isFollowUpModeEnabled, !displayedInterviewerTranscript.isEmpty {
                    MessageBubble(
                        message: ChatMessage(role: .interviewer, content: displayedInterviewerTranscript),
                        isLatest: true
                    )
                        .padding(.horizontal, horizontalMargin)
                        .padding(.top, 8)
                }

                if let lastAnswer = latestVisibleAssistantMessage {
                    MessageBubble(message: processMessage(lastAnswer), isLatest: true)
                        .padding(.horizontal, horizontalMargin)
                        .padding(.vertical, 8)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                } else {
                    VStack(spacing: 8) {
                        Spacer()
                            .frame(height: 60)
                        
                        Image(systemName: "waveform.badge.mic")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.3))
                        
                        Text("Waiting for questions...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                        
                        Spacer()
                            .frame(height: 60)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    // MARK: - Processing View
    
    private var processingView: some View {
        HStack(spacing: 8) {
            TypingIndicator()
            
            Text("Generating answer...")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            
            Spacer()
        }
    }

    private var composerView: some View {
        VStack(spacing: 6) {
            if !transcriptState.micPromptTranscript.isEmpty {
                HStack {
                    Text(transcriptState.micPromptTranscript)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.78))
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 8) {
                TextField("Ask a starter clue", text: $manualQuestion, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .lineLimit(1...3)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .onSubmit {
                        submitManualQuestion()
                    }

                if transcriptState.isProcessing {
                    TypingIndicator()
                        .padding(.trailing, 2)
                }

                Button(action: {
                    onToggleMicrophonePrompt?()
                }) {
                    Image(systemName: transcriptState.isRecordingMicPrompt ? "mic.fill" : "mic")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(transcriptState.isRecordingMicPrompt ? .green : .white.opacity(0.72))
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(transcriptState.isRecordingMicPrompt ? "Stop microphone starter clue" : "Start microphone starter clue")

                Button(action: submitManualQuestion) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(manualQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .white.opacity(0.35) : .white.opacity(0.9))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .disabled(manualQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Submit starter clue")
            }
        }
        .padding(.horizontal, horizontalMargin)
        .padding(.vertical, 7)
        .background(Color(nsColor: Config.headerBackgroundColor).opacity(0.9))
    }

    private func submitManualQuestion() {
        let question = manualQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        manualQuestion = ""
        onSubmitQuestion?(question)
    }
    
    // MARK: - Helpers
    
    private var visibleTurns: [ConversationTurn] {
        let questions = transcriptState.messages.filter { $0.role == .interviewer || $0.role == .starterClue }
        let answers = transcriptState.messages.filter { $0.role == .assistant }

        return questions.reversed().map { question in
            ConversationTurn(
                id: question.id,
                question: question,
                answer: answers.first { $0.relatedQuestionID == question.id }
            )
        }
    }

    private var canDeletePreviousQuestion: Bool {
        transcriptState.canDeletePreviousQuestion
    }

    private var hasSubmittableInterviewerTranscript: Bool {
        !displayedInterviewerTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayedInterviewerTranscript: String {
        let liveTranscript = deepgramService.currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard manualInterviewerSubmitEnabled else { return liveTranscript }

        let pendingTranscript = transcriptState.pendingInterviewerTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if pendingTranscript.isEmpty {
            return liveTranscript
        }

        if liveTranscript.isEmpty {
            return pendingTranscript
        }

        return pendingTranscript + " " + liveTranscript
    }
    
    /// Process message content to strip <think> tags
    private func processMessage(_ message: ChatMessage) -> ChatMessage {
        let cleanedContent = stripThinkTags(from: message.content)
        return ChatMessage(
            id: message.id,
            role: message.role,
            content: cleanedContent,
            timestamp: message.timestamp,
            relatedQuestionID: message.relatedQuestionID,
            reasoningContent: message.reasoningContent
        )
    }
    
    /// Remove <think>...</think> tags and their content from LLM output
    /// Also handles partial/unclosed think tags when output is truncated
    private func stripThinkTags(from content: String) -> String {
        var result = content
        
        // First, try to match complete <think>...</think> blocks
        let completePattern = "<think>[\\s\\S]*?</think>"
        if let regex = try? NSRegularExpression(pattern: completePattern, options: [.caseInsensitive]) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        
        // Then, handle unclosed <think> tags (partial output where closing tag is missing)
        if let openTagRange = result.range(of: "<think>", options: .caseInsensitive) {
            result = String(result[..<openTagRange.lowerBound])
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct FollowUpOverlayView: View {
    @ObservedObject var transcriptState: TranscriptState
    @ObservedObject var deepgramService: DeepgramService
    var onClose: (() -> Void)?

    @AppStorage("manualInterviewerSubmitEnabled") private var manualInterviewerSubmitEnabled = false

    private let horizontalMargin: CGFloat = 8

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)

            SlimScrollView {
                turnsStack
            }
        }
        .background(Color.clear)
    }

    private var headerView: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.split.2x1.fill")
                    .font(.system(size: 11, weight: .semibold))

                Text("Follow-up")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.yellow.opacity(0.88))

            WindowDragRegion()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: {
                onClose?()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.62))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Close follow-up mode")
        }
        .padding(.horizontal, horizontalMargin)
        .padding(.vertical, 8)
        .frame(height: 40)
        .background(Color(nsColor: Config.headerBackgroundColor))
    }

    private var turnsStack: some View {
        LazyVStack(spacing: 10) {
            if !displayedInterviewerTranscript.isEmpty {
                MessageBubble(
                    message: ChatMessage(role: .interviewer, content: displayedInterviewerTranscript),
                    isLatest: true
                )
            }

            if followUpVisibleTurns.isEmpty && displayedInterviewerTranscript.isEmpty {
                Text("Follow-up questions will appear here")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.38))
                    .frame(maxWidth: .infinity, minHeight: 72)
            }

            ForEach(followUpVisibleTurns) { turn in
                VStack(alignment: .leading, spacing: 7) {
                    MessageBubble(
                        message: processMessage(turn.question),
                        isLatest: turn.id == followUpVisibleTurns.first?.id
                    )

                    if let answer = turn.answer {
                        answerDivider

                        MessageBubble(
                            message: processMessage(answer),
                            isLatest: turn.id == followUpVisibleTurns.first?.id
                        )
                    }
                }
            }
        }
        .padding(.horizontal, horizontalMargin)
        .padding(.vertical, 8)
    }

    private var answerDivider: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color(red: 0.24, green: 0.78, blue: 0.62).opacity(0.45))
                .frame(width: 18, height: 1)

            Rectangle()
                .fill(Color(red: 0.24, green: 0.78, blue: 0.62).opacity(0.10))
                .frame(height: 1)
        }
        .padding(.horizontal, 4)
        .padding(.top, 1)
    }

    private var followUpVisibleTurns: [ConversationTurn] {
        guard let followUpStartedAt = transcriptState.followUpStartedAt else { return [] }
        return visibleTurns.filter { $0.question.timestamp > followUpStartedAt }
    }

    private var visibleTurns: [ConversationTurn] {
        let questions = transcriptState.messages.filter { $0.role == .interviewer || $0.role == .starterClue }
        let answers = transcriptState.messages.filter { $0.role == .assistant }

        return questions.reversed().map { question in
            ConversationTurn(
                id: question.id,
                question: question,
                answer: answers.first { $0.relatedQuestionID == question.id }
            )
        }
    }

    private var displayedInterviewerTranscript: String {
        let liveTranscript = deepgramService.currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard manualInterviewerSubmitEnabled else { return liveTranscript }

        let pendingTranscript = transcriptState.pendingInterviewerTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if pendingTranscript.isEmpty {
            return liveTranscript
        }

        if liveTranscript.isEmpty {
            return pendingTranscript
        }

        return pendingTranscript + " " + liveTranscript
    }

    private func processMessage(_ message: ChatMessage) -> ChatMessage {
        let cleanedContent = stripThinkTags(from: message.content)
        return ChatMessage(
            id: message.id,
            role: message.role,
            content: cleanedContent,
            timestamp: message.timestamp,
            relatedQuestionID: message.relatedQuestionID,
            reasoningContent: message.reasoningContent
        )
    }

    private func stripThinkTags(from content: String) -> String {
        var result = content

        let completePattern = "<think>[\\s\\S]*?</think>"
        if let regex = try? NSRegularExpression(pattern: completePattern, options: [.caseInsensitive]) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        if let openTagRange = result.range(of: "<think>", options: .caseInsensitive) {
            result = String(result[..<openTagRange.lowerBound])
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ConversationTurn: Identifiable {
    let id: UUID
    let question: ChatMessage
    let answer: ChatMessage?
}

private struct SlimScrollView<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
        }
        .scrollIndicators(.automatic)
    }
}

private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> DragRegionView {
        DragRegionView()
    }

    func updateNSView(_ nsView: DragRegionView, context: Context) {}

    final class DragRegionView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeKey()
            (window as? GhostWindow)?.notifyUserFrameInteraction()
            window?.performDrag(with: event)
        }
    }
}
