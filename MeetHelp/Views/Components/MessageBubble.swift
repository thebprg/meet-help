import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    let isLatest: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Role indicator
            roleIndicator
            
            // Message content
            VStack(alignment: .leading, spacing: 6) {
                Text(roleLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(roleColor)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Text(message.content)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white)
                    .lineSpacing(4)
                    .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
            }
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(bubbleBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(roleColor.opacity(0.25), lineWidth: 1)
        )
        .scaleEffect(isLatest ? 1.0 : 0.98)
        .opacity(isLatest ? 1.0 : 0.8)
    }
    
    private var roleIndicator: some View {
        Circle()
            .fill(roleColor)
            .frame(width: 10, height: 10)
            .padding(.top, 4)
            .shadow(color: roleColor.opacity(0.4), radius: 3)
    }
    
    private var bubbleBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.black.opacity(Config.bubbleOpacity))
    }
    
    private var roleLabel: String {
        switch message.role {
        case .interviewer:
            return "Question"
        case .assistant, .user:
            return "Answer"
        case .system:
            return "System"
        }
    }
    
    private var roleColor: Color {
        switch message.role {
        case .interviewer:
            return Color(red: 1.0, green: 0.6, blue: 0.2) // Warm orange
        case .assistant, .user:
            return Color(red: 0.3, green: 0.85, blue: 0.5) // Fresh green
        case .system:
            return .gray
        }
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
