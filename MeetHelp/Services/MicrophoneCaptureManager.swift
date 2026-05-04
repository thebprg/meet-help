import AVFoundation
import Foundation

@MainActor
final class MicrophoneCaptureManager: ObservableObject {
    @Published var isCapturing = false
    @Published var error: String?

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var audioHandler: ((Data) -> Void)?

    func startCapture(audioHandler: @escaping (Data) -> Void) async -> Bool {
        self.audioHandler = audioHandler

        guard await requestPermission() else {
            error = "Microphone permission required. Enable MeetHelp in System Settings > Privacy & Security > Microphone."
            print("[Microphone] Permission denied")
            return false
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Config.audioSampleRate,
            channels: AVAudioChannelCount(Config.audioChannels),
            interleaved: true
        ) else {
            error = "Unable to create microphone output format"
            return false
        }

        self.outputFormat = outputFormat
        converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
            isCapturing = true
            print("[Microphone] Started capturing")
            return true
        } catch {
            self.error = "Failed to start microphone: \(error.localizedDescription)"
            print("[Microphone] Start error: \(error)")
            inputNode.removeTap(onBus: 0)
            return false
        }
    }

    func stopCapture() {
        guard isCapturing else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        outputFormat = nil
        audioHandler = nil
        isCapturing = false
        print("[Microphone] Stopped capturing")
    }

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private nonisolated func handle(_ buffer: AVAudioPCMBuffer) {
        Task { @MainActor in
            guard let data = convert(buffer) else { return }
            audioHandler?(data)
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let converter, let outputFormat else { return nil }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity) else {
            return nil
        }

        var didProvideInput = false
        var conversionError: NSError?

        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            didProvideInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, conversionError == nil else {
            print("[Microphone] Conversion error: \(conversionError?.localizedDescription ?? "unknown")")
            return nil
        }

        guard let channelData = outputBuffer.int16ChannelData else { return nil }
        let frameLength = Int(outputBuffer.frameLength)
        return Data(bytes: channelData[0], count: frameLength * MemoryLayout<Int16>.size)
    }
}
