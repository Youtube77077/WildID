import AVFoundation
import Foundation

/// Single shared player for reference sounds (streamed), catch clips and saved recordings.
@MainActor
@Observable
final class AudioPlayer {
    static let shared = AudioPlayer()

    /// Set while Sound ID is listening: playing sounds then would be picked up by the
    /// microphone (and playback can disturb wildlife), so it's blocked.
    var recordingActive = false
    private(set) var blockedMessage: String?

    private(set) var currentID: String?
    private(set) var isPlaying = false
    private(set) var progress: Double = 0
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    func toggle(id: String, url: URL) {
        if currentID == id {
            isPlaying ? pause() : resume()
            return
        }
        play(id: id, url: url)
    }

    func play(id: String, url: URL, from start: TimeInterval = 0) {
        guard !recordingActive else {
            blockedMessage = "Stop Sound ID to play sounds — the microphone would hear them."
            return
        }
        blockedMessage = nil
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        currentID = id
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, let item = self.player?.currentItem else { return }
                let d = item.duration.seconds
                self.duration = d.isFinite ? d : 0
                self.currentTime = t.seconds
                self.progress = self.duration > 0 ? t.seconds / self.duration : 0
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isPlaying = false
                self?.progress = 1
            }
        }
        if start > 0 { p.seek(to: CMTime(seconds: start, preferredTimescale: 600)) }
        p.play()
        isPlaying = true
    }

    func seek(to seconds: TimeInterval) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
        if !isPlaying { resume() }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func resume() {
        if progress >= 1 { player?.seek(to: .zero); progress = 0 }
        player?.play()
        isPlaying = true
    }

    func stop() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        player?.pause()
        player = nil
        currentID = nil
        isPlaying = false
        progress = 0
        currentTime = 0
    }

    func isPlayingItem(_ id: String) -> Bool { currentID == id && isPlaying }
}
