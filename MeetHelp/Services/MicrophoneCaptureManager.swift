import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

@MainActor
final class MicrophoneCaptureManager: ObservableObject {
    @Published var isCapturing = false
    @Published var error: String?

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var audioHandler: ((Data) -> Void)?
    private var previousDefaultInputDeviceID: AudioDeviceID?

    func startCapture(audioHandler: @escaping (Data) -> Void) async -> Bool {
        self.audioHandler = audioHandler

        guard await requestPermission() else {
            error = "Microphone permission required. Enable MeetHelp in System Settings > Privacy & Security > Microphone."
            print("[Microphone] Permission denied")
            return false
        }

        guard let inputDevice = preferredInputDevice() else {
            error = "No non-Bluetooth microphone input found. Select the Mac built-in microphone in System Settings to avoid Bluetooth call-mode audio."
            print("[Microphone] Refusing to start on Bluetooth-only input to avoid call-mode audio.")
            return false
        }

        let startingDefaultInputDeviceID = currentDefaultInputDeviceID()
        previousDefaultInputDeviceID = startingDefaultInputDeviceID

        if startingDefaultInputDeviceID != inputDevice.id {
            guard setDefaultInputDevice(inputDevice) else {
                error = "Unable to switch microphone input away from Bluetooth. Select a built-in microphone in System Settings."
                print("[Microphone] Failed to switch default input before starting; aborting to avoid call-mode audio.")
                return false
            }

            try? await Task.sleep(nanoseconds: 300_000_000)

            guard currentDefaultInputDeviceID() == inputDevice.id else {
                error = "Unable to confirm selected microphone input. Select a built-in microphone in System Settings."
                print("[Microphone] Default input did not switch to \(inputDevice.name); aborting capture.")
                previousDefaultInputDeviceID = nil
                return false
            }
        } else {
            previousDefaultInputDeviceID = nil
        }

        let captureEngine = AVAudioEngine()
        engine = captureEngine

        let inputNode = captureEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("[Microphone] Using input device: \(inputDevice.name), format: \(inputFormat)")

        guard inputFormat.channelCount > 0 else {
            error = "Selected microphone has no readable input channels."
            print("[Microphone] Selected input has no channels; aborting capture.")
            tearDownEngineAndRestoreInput()
            return false
        }

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
            captureEngine.prepare()
            try captureEngine.start()
            isCapturing = true
            print("[Microphone] Started capturing")
            return true
        } catch {
            self.error = "Failed to start microphone: \(error.localizedDescription)"
            print("[Microphone] Start error: \(error)")
            tearDownEngineAndRestoreInput()
            return false
        }
    }

    func stopCapture() {
        guard isCapturing || engine != nil else { return }

        tearDownEngineAndRestoreInput()
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

    private func preferredInputDevice() -> AudioInputDevice? {
        let devices = availableInputDevices()
        guard !devices.isEmpty else { return nil }

        if let builtIn = devices.first(where: { $0.isLikelyBuiltIn }) {
            return builtIn
        }

        if let nonBluetooth = devices.first(where: { !$0.isBluetooth }) {
            return nonBluetooth
        }

        print("[Microphone] Only Bluetooth input devices found; using system default.")
        return nil
    }

    private func tearDownEngineAndRestoreInput() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engine.reset()
        }

        engine = nil
        converter = nil
        outputFormat = nil
        audioHandler = nil

        if let previousDefaultInputDeviceID {
            if deviceTransportType(for: previousDefaultInputDeviceID).isBluetoothTransport {
                print("[Microphone] Leaving default input on non-Bluetooth device instead of restoring Bluetooth call-mode input.")
            } else {
                setDefaultInputDevice(id: previousDefaultInputDeviceID)
            }
            self.previousDefaultInputDeviceID = nil
        }
    }

    private func availableInputDevices() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(), count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            return []
        }

        return deviceIDs.compactMap { deviceID in
            guard inputChannelCount(for: deviceID) > 0 else { return nil }

            let name = deviceName(for: deviceID)
            let transportType = deviceTransportType(for: deviceID)
            return AudioInputDevice(id: deviceID, name: name, transportType: transportType)
        }
    }

    private func inputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr else {
            return 0
        }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListPointer.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferListPointer) == noErr else {
            return 0
        }

        let audioBufferList = bufferListPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let unsafeBufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
        return unsafeBufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func deviceName(for deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &name)
        guard status == noErr, let name else { return "Unknown Input" }
        return name as String
    }

    private func deviceTransportType(for deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &transportType)
        return status == noErr ? transportType : 0
    }

    private func currentDefaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID()
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        return status == noErr ? deviceID : nil
    }

    @discardableResult
    private func setDefaultInputDevice(_ device: AudioInputDevice) -> Bool {
        let didSet = setDefaultInputDevice(id: device.id)
        if didSet {
            print("[Microphone] Temporarily selected default input: \(device.name)")
        }
        return didSet
    }

    @discardableResult
    private func setDefaultInputDevice(id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var mutableID = id
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &mutableID
        )

        if status != noErr {
            print("[Microphone] Failed to set default input device: \(status)")
        }
        return status == noErr
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

private struct AudioInputDevice {
    let id: AudioDeviceID
    let name: String
    let transportType: UInt32

    var isBluetooth: Bool {
        transportType.isBluetoothTransport
    }

    var isLikelyBuiltIn: Bool {
        let lowercasedName = name.lowercased()
        return !isBluetooth &&
            (
                lowercasedName.contains("built-in") ||
                lowercasedName.contains("macbook") ||
                lowercasedName.contains("imac") ||
                lowercasedName.contains("studio display")
            )
    }
}

private extension UInt32 {
    var isBluetoothTransport: Bool {
        self == kAudioDeviceTransportTypeBluetooth ||
            self == kAudioDeviceTransportTypeBluetoothLE
    }
}
