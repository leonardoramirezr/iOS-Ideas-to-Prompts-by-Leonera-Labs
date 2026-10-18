import AVFoundation
import Observation

/// Reproduce la grabación de una idea.
@Observable
@MainActor
final class AudioPlayer {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var loadedURL: URL?
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    func load(_ url: URL) {
        guard loadedURL != url else { return }
        stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        loadedURL = url
        duration = player?.duration ?? 0
        currentTime = 0
    }

    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        guard let player else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        player.play()
        isPlaying = true
        startProgress()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        progressTask?.cancel()
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        currentTime = 0
        isPlaying = false
        progressTask?.cancel()
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    private func startProgress() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let player = self.player else { return }
                if !player.isPlaying {
                    // Terminó la reproducción.
                    self.isPlaying = false
                    self.currentTime = 0
                    return
                }
                self.currentTime = player.currentTime
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}
