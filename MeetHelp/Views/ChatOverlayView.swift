import AppKit
import SwiftUI

struct ChatOverlayView: View {
    @ObservedObject var transcriptState: TranscriptState
    @ObservedObject var deepgramService: DeepgramService
    
    // Callback for toggling listening state
    var onToggleListening: (() -> Void)?
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
        HStack(spacing: 8) {
            TextField("Ask a question", text: $manualQuestion, axis: .vertical)
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
                onToggleListening?()
            }) {
                Image(systemName: transcriptState.isListening ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(transcriptState.isListening ? .green : .white.opacity(0.72))
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(transcriptState.isListening ? "Pause voice input" : "Start voice input")

            Button(action: submitManualQuestion) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(manualQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .white.opacity(0.35) : .white.opacity(0.9))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(manualQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Submit question")
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

    @StateObject private var scrollController = SlimScrollController()
    @State private var viewportHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0

    private let coordinateSpaceName = "slim-scroll-view"

    var body: some View {
        GeometryReader { outerProxy in
            ScrollView {
                VStack(spacing: 0) {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: SlimScrollOffsetPreferenceKey.self,
                                value: proxy.frame(in: .named(coordinateSpaceName)).minY
                            )
                    }
                    .frame(height: 0)

                    content
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(
                                        key: SlimScrollContentHeightPreferenceKey.self,
                                        value: proxy.size.height
                                    )
                            }
                        )
                }
            }
            .background(SlimScrollViewResolver(controller: scrollController))
            .coordinateSpace(name: coordinateSpaceName)
            .scrollIndicators(.hidden)
            .onAppear {
                viewportHeight = outerProxy.size.height
            }
            .onChange(of: outerProxy.size.height) { newValue in
                viewportHeight = newValue
            }
            .onPreferenceChange(SlimScrollOffsetPreferenceKey.self) { value in
                scrollOffset = max(0, -value)
            }
            .onPreferenceChange(SlimScrollContentHeightPreferenceKey.self) { value in
                contentHeight = value
            }
            .overlay(alignment: .trailing) {
                SlimScrollIndicator(
                    viewportHeight: viewportHeight,
                    contentHeight: contentHeight,
                    scrollOffset: scrollOffset,
                    onScroll: { progress in
                        scrollController.scroll(toProgress: progress)
                    }
                )
                .padding(.vertical, 4)
                .padding(.trailing, 2)
            }
        }
    }
}

private struct SlimScrollIndicator: View {
    let viewportHeight: CGFloat
    let contentHeight: CGFloat
    let scrollOffset: CGFloat
    let onScroll: (CGFloat) -> Void

    private var isScrollable: Bool {
        contentHeight > viewportHeight + 1
    }

    private var thumbHeight: CGFloat {
        guard isScrollable else { return 0 }
        return max(26, viewportHeight * (viewportHeight / contentHeight))
    }

    private var thumbOffset: CGFloat {
        guard isScrollable else { return 0 }
        let maxScroll = max(contentHeight - viewportHeight, 1)
        let maxThumbTravel = max(viewportHeight - thumbHeight - 8, 0)
        return min(max(scrollOffset / maxScroll, 0), 1) * maxThumbTravel
    }

    var body: some View {
        if isScrollable {
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)

                    Rectangle()
                        .fill(Color.white.opacity(0.42))
                        .frame(width: 2, height: thumbHeight)
                        .offset(y: thumbOffset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let availableTravel = max(proxy.size.height - thumbHeight, 1)
                            let progress = min(max((value.location.y - thumbHeight / 2) / availableTravel, 0), 1)
                            onScroll(progress)
                        }
                )
            }
            .frame(width: 8)
        }
    }
}

private final class SlimScrollController: ObservableObject {
    weak var scrollView: NSScrollView?

    func scroll(toProgress progress: CGFloat) {
        guard let scrollView else { return }

        let clipView = scrollView.contentView
        let documentHeight = scrollView.documentView?.bounds.height ?? 0
        let viewportHeight = clipView.bounds.height
        let maxOffset = max(documentHeight - viewportHeight, 0)
        let targetOffset = min(max(progress, 0), 1) * maxOffset

        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: targetOffset))
        scrollView.reflectScrolledClipView(clipView)
    }
}

private struct SlimScrollViewResolver: NSViewRepresentable {
    @ObservedObject var controller: SlimScrollController

    func makeNSView(context: Context) -> ResolverView {
        ResolverView(controller: controller)
    }

    func updateNSView(_ nsView: ResolverView, context: Context) {
        nsView.controller = controller
        nsView.resolveScrollView()
    }

    final class ResolverView: NSView {
        weak var controller: SlimScrollController?

        init(controller: SlimScrollController) {
            self.controller = controller
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            resolveScrollView()
        }

        func resolveScrollView() {
            var view: NSView? = self
            while let current = view {
                if let scrollView = current as? NSScrollView {
                    controller?.scrollView = scrollView
                    return
                }
                view = current.superview
            }
        }
    }
}

private struct SlimScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct SlimScrollContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
