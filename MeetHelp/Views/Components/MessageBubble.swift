import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    let isLatest: Bool
    
    var body: some View {
        Group {
            switch message.role {
            case .interviewer, .starterClue:
                questionView
            case .assistant, .user:
                answerView
            case .system:
                EmptyView()
            }
        }
    }
    
    private var questionView: some View {
        HStack {
            Text(message.content)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.92))
                .lineSpacing(3)
                .lineLimit(3)
                .truncationMode(.head)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(questionBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var answerView: some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(answerAccent)
                .frame(width: 2)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 4) {
                if let reasoning = message.reasoningContent?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !reasoning.isEmpty {
                    ThinkingDisclosure(reasoning: reasoning)
                }

                HStack(alignment: .top, spacing: 0) {
                    MarkdownRenderView(markdown: message.content)

                    Spacer(minLength: 0)
                }
            }
            .padding(.top, 1)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }
    
    private var questionBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.black.opacity(Config.bubbleOpacity))
    }

    private var answerAccent: Color {
        Color(red: 0.24, green: 0.78, blue: 0.62).opacity(0.72)
    }

}

private struct ThinkingDisclosure: View {
    let reasoning: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))

                    Text("Thinking")
                        .font(.system(size: 10, weight: .medium))

                    Spacer(minLength: 0)
                }
                .foregroundColor(.white.opacity(0.48))
                .frame(height: 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                MarkdownRenderView(markdown: reasoning)
                    .padding(.leading, 12)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var dotCount = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
                    .opacity(index <= dotCount ? 1.0 : 0.3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(Config.bubbleOpacity))
        .cornerRadius(8)
        .onReceive(timer) { _ in
            dotCount = (dotCount + 1) % 3
        }
    }
}

// MARK: - Current Transcript View

struct CurrentTranscriptView: View {
    let transcript: String
    
    var body: some View {
        HStack {
            Image(systemName: "waveform")
                .foregroundColor(.orange)
            
            Text(transcript)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(2)
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.2))
        .cornerRadius(6)
    }
}
