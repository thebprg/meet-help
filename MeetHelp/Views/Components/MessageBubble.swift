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
        .scaleEffect(isLatest ? 1.0 : 0.98)
        .opacity(isLatest ? 1.0 : 0.8)
    }
    
    private var questionView: some View {
        HStack {
            Text(message.content)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.92))
                .lineSpacing(3)
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
        HStack(alignment: .top, spacing: 0) {
            MarkdownRenderView(markdown: message.content)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }
    
    private var questionBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.black.opacity(Config.bubbleOpacity))
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
