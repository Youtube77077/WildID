import AVFoundation
import Foundation

/// Single shared player for reference sounds (streamed), catch clips and saved recordings.
///
/// Local files (catch clips, saved recordings, downloaded sounds) play through `AVAudioPlayer`,
/// which starts instantly and reports an exact position; only remote reference sounds stream
/// through `AVPlayer`. Views that need a smooth playhead read `liveTime` every frame instead of
/// waiting for the 10 Hz `currentTime` updates.
@MainActor
@Observable
final class AudioPlayer: NSObject, AVAudioPlayerDelegate {
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

    @ObservationIgnored private var local: AVAudioPlayer?
    @ObservationIgnored private var remote: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var ticker: Timer?

    /// Exact position right now (for display-rate playheads).
    var liveTime: TimeInterval {
        if let local { return local.currentTime }
        if let remote { let t = remote.currentTime().seconds; return t.isFinite ? t : 0 }
        return 0
    }

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
        let source = url.isFileURL ? url : (OfflineStore.shared.localURL(for: url) ?? url)
        currentID = id
        if source.isFileURL, let p = try? AVAudioPlayer(contentsOf: source) {
            p.delegate = self
            p.prepareToPlay()
            p.currentTime = min(max(0, start), max(0, p.duration - 0.05))
            local = p
            duration = p.duration
            p.play()
        } else {
            let item = AVPlayerItem(url: source)
            item.preferredForwardBufferDuration = 2
            let p = AVPlayer(playerItem: item)
            p.automaticallyWaitsToMinimizeStalling = false
            remote = p
            timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let d = self.remote?.currentItem?.duration.seconds, d.isFinite else { return }
                    self.duration = d
                }
            }
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finished() }
            }
            if start > 0 { p.seek(to: CMTime(seconds: start, preferredTimescale: 600)) }
            p.play()
        }
        isPlaying = true
        startTicker()
    }

    func seek(to seconds: TimeInterval) {
        if let local {
            local.currentTime = min(max(0, seconds), local.duration)
        } else {
            remote?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        currentTime = seconds
        if !isPlaying { resume() }
    }

    func pause() {
        local?.pause()
        remote?.pause()
        isPlaying = false
        tick()
    }

    func resume() {
        if progress >= 0.999 {
            local?.currentTime = 0
            remote?.seek(to: .zero)
            progress = 0
        }
        local?.play()
        remote?.play()
        isPlaying = true
        startTicker()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        if let timeObserver { remote?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        local?.stop()
        local = nil
        remote?.pause()
        remote = nil
        currentID = nil
        isPlaying = false
        progress = 0
        currentTime = 0
        duration = 0
    }

    func isPlayingItem(_ id: String) -> Bool { currentID == id && isPlaying }

    // MARK: Internals

    /// Light 10 Hz updates for labels and scrubbers (playheads use `liveTime`).
    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        let t = liveTime
        currentTime = t
        progress = duration > 0 ? min(1, t / duration) : 0
        if !isPlaying { ticker?.invalidate(); ticker = nil }
    }

    private func finished() {
        isPlaying = false
        progress = 1
        currentTime = duration
        ticker?.invalidate()
        ticker = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finished() }
    }
}
