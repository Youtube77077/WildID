import AVFoundation
import Foundation

/// Captures microphone audio, converts it to a 48 kHz mono analysis stream and streams it to an
/// AAC file on disk (so a 3 hour session never has to fit in memory).
///
/// Threading: the input tap delivers buffers on an internal AVAudioEngine thread. We immediately
/// hop to `processingQueue` where conversion, file writing and analysis callbacks happen.
final class AudioCaptureEngine: @unchecked Sendable {
    static let analysisSampleRate: Double = 48_000
    static let maxDuration: TimeInterval = 3 * 60 * 60   // 3 hours

    let analysisFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: analysisSampleRate,
                                       channels: 1, interleaved: false)!

    /// Called on `processingQueue` with each converted buffer and the absolute frame position
    /// (frames since the session started, excluding paused time).
    var onBuffer: ((AVAudioPCMBuffer, AVAudioFramePosition) -> Void)?
    /// Called on the main queue when capture stops for a reason other than `stop()`.
    var onAutoStop: ((String) -> Void)?
    var onInterruption: ((Bool) -> Void)?

    let processingQueue = DispatchQueue(label: "wildid.audio.processing", qos: .userInitiated)
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var file: AVAudioFile?
    private(set) var framesWritten: AVAudioFramePosition = 0
    private(set) var isRunning = false
    private(set) var isPaused = false
    private var observers: [NSObjectProtocol] = []

    var recordedDuration: TimeInterval { Double(framesWritten) / Self.analysisSampleRate }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start(writingTo url: URL) throws {
        let session = AVAudioSession.sharedInstance()
        // `.measurement` disables voice processing / automatic gain so animal sounds keep their
        // natural spectrum, which matters for identification.
        try session.setCategory(.record, mode: .measurement, options: [.allowBluetooth])
        try? session.setPreferredSampleRate(Self.analysisSampleRate)
        try? session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true, options: [])

        // AAC, 48 kHz mono, 64 kbps ≈ 28 MB per hour.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Self.analysisSampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        framesWritten = 0
        try installTapAndStart()
        isRunning = true
        isPaused = false
        observeSession()
    }

    private func installTapAndStart() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(domain: "WildID", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone input is available."])
        }
        converter = (inputFormat == analysisFormat) ? nil : AVAudioConverter(from: inputFormat, to: analysisFormat)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let copy = Self.copy(buffer) else { return }
            self.processingQueue.async { self.handle(copy) }
        }
        engine.prepare()
        try engine.start()
    }

    /// The engine may reuse its tap buffer, so take a private copy before leaving the tap.
    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let out = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        out.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        if let src = buffer.floatChannelData, let dst = out.floatChannelData {
            for c in 0..<channels { dst[c].update(from: src[c], count: Int(buffer.frameLength)) }
        } else if let src = buffer.int16ChannelData, let dst = out.int16ChannelData {
            for c in 0..<channels { dst[c].update(from: src[c], count: Int(buffer.frameLength)) }
        } else {
            return nil
        }
        return out
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        guard isRunning, !isPaused else { return }
        guard let out = convert(buffer) else { return }
        do { try file?.write(from: out) } catch { }
        let position = framesWritten
        framesWritten += AVAudioFramePosition(out.frameLength)
        onBuffer?(out, position)
        if recordedDuration >= Self.maxDuration {
            DispatchQueue.main.async { self.onAutoStop?("Reached the 3 hour limit — recording stopped.") }
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = analysisFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64)
        guard let out = AVAudioPCMBuffer(pcmFormat: analysisFormat, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && out.frameLength > 0 ? out : nil
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        engine.pause()
    }

    func resume() throws {
        guard isRunning, isPaused else { return }
        try AVAudioSession.sharedInstance().setActive(true)
        try engine.start()
        isPaused = false
    }

    /// Stops capture and closes the file. Returns the number of seconds recorded.
    @discardableResult
    func stop() -> TimeInterval {
        guard isRunning else { return recordedDuration }
        isRunning = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        processingQueue.sync { self.file = nil }   // flushes and closes the AAC file
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return recordedDuration
    }

    private func observeSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                self.pause()
                self.onInterruption?(true)
            case .ended:
                let opts = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init) ?? []
                if opts.contains(.shouldResume) { try? self.resume() }
                self.onInterruption?(false)
            @unknown default: break
            }
        })
        // A headset being plugged in/out changes the input format: rebuild the tap.
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.isRunning else { return }
            let wasPaused = self.isPaused
            try? self.installTapAndStart()
            if wasPaused { self.engine.pause() }
        })
    }
}
