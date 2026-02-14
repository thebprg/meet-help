import SwiftUI

struct SettingsView: View {
    @ObservedObject var transcriptState: TranscriptState
    @AppStorage("showHistory") private var showHistory = true
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            Form {
                // Code Context Section
                Section("Code Context") {
                    Text("Paste relevant code before your interview. The AI will reference it when answering questions.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $transcriptState.codeContext)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 150)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }
                
                // Display Settings
                Section("Display") {
                    Toggle("Show conversation history", isOn: $transcriptState.showHistory)
                    
                    Text("When off, only the latest answer is shown.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Keyboard Shortcuts Info
                Section("Keyboard Shortcuts") {
                    HStack {
                        Text("Toggle Listening")
                        Spacer()
                        Text("⌘⇧L")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                // API Status
                Section("API Status") {
                    HStack {
                        Text("Deepgram")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    
                    HStack {
                        Text("Cerebras")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 450, height: 500)
    }
}
