import AVFoundation
import Observation

/// Graba la idea en WAV (16 kHz, mono), un formato que aceptan todos los proveedores.
@Observable
@MainActor
final class AudioRecorder {
    enum State {
        case idle
        case recording
        case paused
    }

    static let levelCount = 40

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var levels = [Double](repeating: 0, count: AudioRecorder.levelCount)
    var permissionDenied = false
    var errorMessage: String?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var fileName: String?
    @ObservationIgnored private var meterTask: Task<Void, Never>?

    private static let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16_000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
    ]

    func start() async {
        guard state == .idle else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            permissionDenied = true
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)

            Storage.prepareDirectories()
            let name = UUID().uuidString + ".wav"
            let recorder = try AVAudioRecorder(url: Storage.recordingURL(name), settings: Self.settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                errorMessage = "No se pudo iniciar la grabación."
                return
            }
            self.recorder = recorder
            fileName = name
            elapsed = 0
            state = .recording
            startMetering()
        } catch {
            errorMessage = "No se pudo iniciar la grabación: \(error.localizedDescription)"
        }
    }

    func pause() {
        guard state == .recording else { return }
        recorder?.pause()
        state = .paused
    }

    func resume() {
        guard state == .paused, let recorder else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        if recorder.record() {
            state = .recording
        }
    }

    /// Detiene la grabación y devuelve el archivo y su duración.
    func finish() -> (fileName: String, duration: TimeInterval)? {
        guard let recorder, let fileName else { return nil }
        let duration = max(recorder.currentTime, elapsed)
        recorder.stop()
        reset()
        return (fileName, duration)
    }

    func discard() {
        recorder?.stop()
        recorder?.deleteRecording()
        reset()
    }

    private func reset() {
        meterTask?.cancel()
        meterTask = nil
        recorder = nil
        fileName = nil
        state = .idle
        levels = [Double](repeating: 0, count: Self.levelCount)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    private func tick() {
        guard let recorder else { return }
        // Una llamada o Siri interrumpen la grabación: se muestra como pausa.
        if state == .recording, !recorder.isRecording {
            state = .paused
        }
        guard state == .recording else { return }
        elapsed = recorder.currentTime
        recorder.updateMeters()
        let power = Double(recorder.averagePower(forChannel: 0))
        levels.removeFirst()
        levels.append(min(1, max(0, (power + 50) / 50)))
    }
}
