import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreGraphics
import Combine

@MainActor
class AudioCaptureManager: NSObject, ObservableObject {
    @Published var isCapturing = false
    @Published var error: String?
    @Published var permissionGranted = false

    private var stream: SCStream?
    private var streamOutput: AudioStreamOutput?
    private var audioCallback: ((Data) -> Void)?

    // Audio format settings
    private let sampleRate: Double = Config.audioSampleRate
    private let channelCount: Int = Config.audioChannels

    override init() {
        super.init()
    }

    func checkPermission() async -> Bool {
        guard CGPreflightScreenCaptureAccess() else {
            print("[AudioCapture] Screen capture preflight denied, requesting access")
            let granted = CGRequestScreenCaptureAccess()
            permissionGranted = granted
            if !granted {
                self.error = "Screen & System Audio Recording permission required. Enable MeetHelp in System Settings > Privacy & Security > Screen & System Audio Recording, then restart MeetHelp."
            }
            return granted
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            permissionGranted = !content.displays.isEmpty
            print("[AudioCapture] Permission check: \(permissionGranted ? "granted" : "denied")")
            print("[AudioCapture] Found \(content.displays.count) displays")
            for (i, display) in content.displays.enumerated() {
                print("[AudioCapture] Display \(i): \(display.width)x\(display.height) ID:\(display.displayID)")
            }
            return permissionGranted
        } catch {
            print("[AudioCapture] Permission error: \(error)")
            self.error = "Screen Recording permission required. Please grant access in System Settings > Privacy & Security > Screen Recording"
            permissionGranted = false
            return false
        }
    }

    @discardableResult
    func startCapture(audioHandler: @escaping (Data) -> Void) async -> Bool {
        self.audioCallback = audioHandler

        guard await checkPermission() else {
            self.error = "Screen Recording permission not granted. Go to System Settings > Privacy & Security > Screen & System Audio Recording and enable MeetHelp."
            print("[AudioCapture] No permission - cannot start capture")
            return false
        }

        do {
            let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            guard let display = availableContent.displays.first else {
                self.error = "No display available for capture"
                return false
            }

            print("[AudioCapture] Using display: \(display.width)x\(display.height)")

            let filter = SCContentFilter(display: display, excludingWindows: [])

            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = true
            configuration.sampleRate = Int(sampleRate)
            configuration.channelCount = channelCount
            configuration.excludesCurrentProcessAudio = true
            configuration.width = 2
            configuration.height = 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            configuration.showsCursor = false

            let streamDelegate = StreamDelegate()
            stream = SCStream(filter: filter, configuration: configuration, delegate: streamDelegate)

            guard let stream = stream else {
                self.error = "Failed to create capture stream"
                print("[AudioCapture] Stream creation returned nil")
                return false
            }

            streamOutput = AudioStreamOutput(audioHandler: audioHandler)
            try stream.addStreamOutput(streamOutput!, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
            try await stream.startCapture()

            isCapturing = true
            print("[AudioCapture] Started capturing system audio successfully")
            return true

        } catch let error as NSError {
            self.error = "Failed to start capture: \(error.localizedDescription)"
            print("[AudioCapture] Error: \(error)")
            print("[AudioCapture] Error domain: \(error.domain), code: \(error.code)")

            // Common error codes
            if error.code == 1003 {
                self.error = "Screen Recording permission denied. Grant access in System Settings > Privacy & Security > Screen & System Audio Recording, then restart MeetHelp."
            }
            return false
        }
    }

    func stopCapture() async {
        guard let stream = stream else { return }

        do {
            try await stream.stopCapture()
            self.stream = nil
            self.streamOutput = nil
            isCapturing = false
            print("[AudioCapture] Stopped capturing")
        } catch {
            self.error = "Failed to stop capture: \(error.localizedDescription)"
            print("[AudioCapture] Stop error: \(error)")
        }
    }
}

// MARK: - Stream Delegate

class StreamDelegate: NSObject, SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[AudioCapture] Stream stopped with error: \(error)")
    }
}

// MARK: - Audio Stream Output Handler

class AudioStreamOutput: NSObject, SCStreamOutput {
    private let audioHandler: (Data) -> Void
    private var frameCount = 0

    init(audioHandler: @escaping (Data) -> Void) {
        self.audioHandler = audioHandler
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }

        frameCount += 1
        if frameCount % 100 == 1 {
            print("[AudioCapture] Received audio frame #\(frameCount)")
        }

        // Convert CMSampleBuffer to PCM data
        guard let audioData = extractAudioData(from: sampleBuffer) else { return }

        audioHandler(audioData)
    }

    private func extractAudioData(from sampleBuffer: CMSampleBuffer) -> Data? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )

        guard status == kCMBlockBufferNoErr, let pointer = dataPointer else {
            return nil
        }

        // Get audio format to check sample size
        if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {

            let sourceFormat = asbd.pointee

            // If already 16-bit PCM, return directly
            if sourceFormat.mBitsPerChannel == 16 {
                return Data(bytes: pointer, count: length)
            }

            // Convert 32-bit float to 16-bit PCM
            if sourceFormat.mBitsPerChannel == 32 &&
               sourceFormat.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
                return convertFloat32ToInt16(pointer: pointer, length: length)
            }
        }

        return Data(bytes: pointer, count: length)
    }

    private func convertFloat32ToInt16(pointer: UnsafeMutablePointer<Int8>, length: Int) -> Data {
        let floatCount = length / MemoryLayout<Float>.size
        let floatPointer = UnsafeRawPointer(pointer).bindMemory(to: Float.self, capacity: floatCount)

        var int16Data = Data(count: floatCount * MemoryLayout<Int16>.size)

        int16Data.withUnsafeMutableBytes { rawBuffer in
            guard let int16Pointer = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }

            for i in 0..<floatCount {
                let floatValue = floatPointer[i]
                // Clamp and convert
                let clampedValue = max(-1.0, min(1.0, floatValue))
                int16Pointer[i] = Int16(clampedValue * Float(Int16.max))
            }
        }

        return int16Data
    }
}
