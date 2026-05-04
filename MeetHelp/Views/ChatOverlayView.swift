import AppKit
import SwiftUI

struct ChatOverlayView: View {
    @ObservedObject var transcriptState: TranscriptState
    @ObservedObject var deepgramService: DeepgramService
    
    // Callback for toggling listening state
    var onToggleListening: (() -> Void)?
    var onToggleMicrophonePrompt: (() -> Void)?
    var onClearHistory: (() -> Void)?
    var onSubmitQuestion: ((String) -> Void)?

    @State private var manualQuestion = ""

    private let horizontalMargin: CGFloat = 8
    
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
        ZStack {
            WindowDragRegion()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 10) {
                // Clickable status indicator (toggles listening)
                Button(action: {
                    onToggleListening?()
                }) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(transcriptState.isListening ? Color.green : Color.red.opacity(0.8))
                            .frame(width: 10, height: 10)
                            .shadow(color: transcriptState.isListening ? .green.opacity(0.6) : .clear, radius: 4)
                        
                        Text(transcriptState.isListening ? "In-use" : "Paused")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Click to toggle listening (⌘⇧L)")
                
                Spacer()
                
                // Toggle history mode
                Button(action: {
                    transcriptState.showHistory.toggle()
                }) {
                    Image(systemName: transcriptState.showHistory ? "rectangle.stack.fill" : "rectangle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help(transcriptState.showHistory ? "Show single answer" : "Show history")
                
                // Clear history
                Button(action: {
                    onClearHistory?()
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Clear history")
            }
            .padding(.horizontal, horizontalMargin)
            .padding(.vertical, 8)
        }
        .frame(height: 40)
        .background(Color(nsColor: Config.headerBackgroundColor))
    }
    
    // MARK: - History View
    
    private var historyView: some View {
        ScrollViewReader { proxy in
            SlimScrollView {
                LazyVStack(spacing: 10) {
                    if !deepgramService.currentTranscript.isEmpty {
                        MessageBubble(
                            message: ChatMessage(role: .interviewer, content: deepgramService.currentTranscript),
                            isLatest: true
                        )
                        .id("live-transcript")
                    }

                    ForEach(visibleTurns) { turn in
                        VStack(alignment: .leading, spacing: 8) {
                            MessageBubble(
                                message: processMessage(turn.question),
                                isLatest: turn.id == visibleTurns.first?.id
                            )

                            if let answer = turn.answer {
                                MessageBubble(
                                    message: processMessage(answer),
                                    isLatest: turn.id == visibleTurns.first?.id
                                )
                            }
                        }
                        .id(turn.id)
                    }
                }
                .padding(.horizontal, horizontalMargin)
                .padding(.vertical, 8)
            }
            .onChange(of: transcriptState.messages.count) { _ in
                if let newestTurn = visibleTurns.first {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(newestTurn.id, anchor: .top)
                    }
                }
            }
            .onChange(of: visibleTurns.first?.answer?.content) { _ in
                if let newestTurn = visibleTurns.first {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(newestTurn.id, anchor: .top)
                    }
                }
            }
            .onChange(of: deepgramService.currentTranscript) { _ in
                guard !deepgramService.currentTranscript.isEmpty else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("live-transcript", anchor: .top)
                }
            }
        }
    }
    
    // MARK: - Single Answer View (NOW SCROLLABLE)
    
    private var singleAnswerView: some View {
        SlimScrollView {
            VStack {
                if !deepgramService.currentTranscript.isEmpty {
                    MessageBubble(
                        message: ChatMessage(role: .interviewer, content: deepgramService.currentTranscript),
                        isLatest: true
                    )
                        .padding(.horizontal, horizontalMargin)
                        .padding(.top, 8)
                }

                if let lastAnswer = lastAssistantMessage {
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
        let questions = transcriptState.messages.filter { $0.role == .interviewer }
        let answers = transcriptState.messages.filter { $0.role == .assistant }

        return questions.reversed().map { question in
            ConversationTurn(
                id: question.id,
                question: question,
                answer: answers.first { $0.relatedQuestionID == question.id }
            )
        }
    }
    
    private var lastAssistantMessage: ChatMessage? {
        transcriptState.messages.last { $0.role == .assistant }
    }
    
    /// Process message content to strip <think> tags
    private func processMessage(_ message: ChatMessage) -> ChatMessage {
        let cleanedContent = stripThinkTags(from: message.content)
        return ChatMessage(
            id: message.id,
            role: message.role,
            content: cleanedContent,
            timestamp: message.timestamp,
            relatedQuestionID: message.relatedQuestionID
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
            window?.performDrag(with: event)
        }
    }
}
