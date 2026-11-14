import AVFoundation
import CoreLocation
import Foundation
import SwiftUI
import UIKit

/// Fixed-size circular buffer of the most recent samples.
final class SampleRing: @unchecked Sendable {
    private var storage: [Float]
    private var index = 0
    private var _filled = 0
    private let lock = NSLock()
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        storage = [Float](repeating: 0, count: capacity)
    }

    var filled: Int { lock.withLock { _filled } }

    func reset() {
        lock.withLock { index = 0; _filled = 0 }
    }

    func append(_ samples: UnsafeBufferPointer<Float>) {
        lock.withLock {
            for s in samples {
                storage[index] = s
                index = (index + 1) % capacity
            }
            _filled = min(capacity, _filled + samples.count)
        }
    }

    /// The last `capacity` samples in chronological order.
    func snapshot() -> [Float] {
        lock.withLock { Array(storage[index...] + storage[..<index]) }
    }
}

/// Runs on the audio processing queue: buffers audio and schedules BirdNET on overlapping
/// 3 s windows without ever blocking capture (windows are skipped if inference falls behind).
///
/// Windows start every second, so any short call (a bird flying over, a single chip note) lands
/// in two or three overlapping windows. That overlap is what makes a low threshold safe: a quiet,
/// distant animal is accepted at a low score, but it is only added to the Wild Index once it has
/// been heard in at least two windows (see `maybeCatch`), and the location/season filter removes
/// species that don't occur here.
///
/// The audio is deliberately NOT filtered or amplified: BirdNET normalises loudness itself (the
/// same recording scores identically from 0 dB down to −50 dB) and was trained on noisy field
/// recordings, so high-pass filtering or noise subtraction lowered the score of the true species
/// in our tests (tools/eval: a blackbird in strong wind went from 0.175 to 0.07 with a 250 Hz
/// high-pass, and to 0.002 with spectral subtraction).
final class InferencePipeline: @unchecked Sendable {
    static let hop = 48_000   // 1 s at 48 kHz

    let ring = SampleRing(capacity: BirdNETClassifier.windowSamples)
    private let queue = DispatchQueue(label: "wildid.birdnet", qos: .userInitiated)
    private let lock = NSLock()
    private var framesSince = 0
    private var busy = false
    private var classifier: BirdNETClassifier?
    private var threshold: Float = 0.5
    private var useFilter = true
    var onResult: (@Sendable ([BirdNETClassifier.Prediction], TimeInterval, [Float], Float) -> Void)?

    func configure(classifier: BirdNETClassifier?, threshold: Float, useFilter: Bool) {
        lock.withLock {
            self.classifier = classifier
            self.threshold = threshold
            self.useFilter = useFilter
            framesSince = 0
            busy = false
        }
        ring.reset()
    }

    /// Runs `body` on the inference queue (used to update the location filter safely).
    func onInferenceQueue(_ body: @escaping @Sendable () -> Void) { queue.async(execute: body) }

    func feed(_ samples: UnsafeBufferPointer<Float>, endPosition: AVAudioFramePosition) {
        ring.append(samples)
        let job: (BirdNETClassifier, Float, Bool)? = lock.withLock {
            framesSince += samples.count
            guard framesSince >= Self.hop, !busy, let classifier else { return nil }
            framesSince = 0
            busy = true
            return (classifier, threshold, useFilter)
        }
        guard let job else { return }
        guard ring.filled >= BirdNETClassifier.windowSamples else {
            lock.withLock { busy = false }
            return
        }
        let (model, minConfidence, filter) = job
        let window = ring.snapshot()
        let windowStart = Double(endPosition) / AudioCaptureEngine.analysisSampleRate - 3.0
        queue.async { [weak self] in
            let result = (try? window.withUnsafeBufferPointer {
                try model.classifyWithHuman($0, threshold: minConfidence, useLocationFilter: filter)
            }) ?? (predictions: [], human: 0)
            guard let self else { return }
            self.lock.withLock { self.busy = false }
            self.onResult?(Array(result.predictions.prefix(4)), windowStart, window, result.human)
        }
    }
}

enum ClipWriter {
    /// Writes mono 48 kHz samples to an AAC (.m4a) file.
    static func write(_ samples: [Float], to url: URL) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioCaptureEngine.analysisSampleRate, channels: 1, interleaved: false)!
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: AudioCaptureEngine.analysisSampleRate,
                                       AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        try file.write(from: buffer)
    }
}

/// A species (or group) heard during the current session.
struct LiveDetection: Identifiable, Equatable {
    enum Source: String { case birdnet, apple }
    let id: String
    var species: SpeciesRef
    var source: Source
    var firstHeard: TimeInterval
    var lastHeard: TimeInterval
    var offsets: [TimeInterval]
    var maxConfidence: Float
    var count: Int
    /// The species was not in the Wild Index when first heard this session.
    var isNewToIndex: Bool
    var newHighlightUntil: Date
    var caught = false
    /// Taxon lookup finished (successfully or not); catches wait for it so they get photo/ID.
    var resolved = false
    var clipFileName: String?
    var lastConfidence: Float
    /// Windows in which a person was also heard; they never count toward a catch.
    var humanCount = 0
    /// Every hit so far came with a human voice/whistle: shown as "possible", never caught.
    var humanFlagged = false

    /// Catch rule: heard in two clean windows (windows overlap, so one real call usually spans
    /// two), or one clean window that is very confident.
    static func canCatch(cleanCount: Int, maxConfidence: Float, threshold: Float, humanFlagged: Bool) -> Bool {
        guard !humanFlagged, cleanCount >= 1 else { return false }
        return cleanCount >= 2 || maxConfidence >= max(0.7, threshold + 0.2)
    }
}

struct SessionSummary: Identifiable {
    let id: UUID
    let startedAt: Date
    let duration: TimeInterval
    let fileURL: URL
    let placeName: String?
    let coordinate: CLLocationCoordinate2D?
    let detections: [LiveDetection]
    var savedRecordingID: UUID?
}

/// Orchestrates a live Sound ID session.
@MainActor
@Observable
final class SoundIDSession {
    enum State: Equatable { case idle, starting, recording, paused, finished }

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var detections: [LiveDetection] = []
    private(set) var statusMessage: String?
    private(set) var modelError: String?
    private(set) var expectedSpeciesCount: Int?
    private(set) var startedAt: Date?
    private(set) var placeName: String?
    var summary: SessionSummary?
    /// Updated every few seconds to drive "hearing now" pulses.
    private(set) var clock = Date()

    let spectrogram = SpectrogramProcessor(seconds: 10)
    private var capture: AudioCaptureEngine?
    private var birdnet: BirdNETClassifier?
    private var apple: AppleSoundClassifier?
    private let pipeline = InferencePipeline()
    private var sessionID = UUID()
    private var liveFileURL: URL?
    private var timer: Timer?
    private var lastBirdNETSpeciesTime: TimeInterval = -100
    /// Session times when Apple's classifier heard a person (speech, whistling, singing…).
    private var appleHumanTimes: [TimeInterval] = []
    /// A person was heard recently (shown in the UI).
    private(set) var humanHeardAt: Date?
    private var locationAppliedToFilter = false

    // Dependencies (set by the view before starting).
    var collection: CollectionManager?
    var location: LocationService?
    var settings: AppSettings?

    var isActive: Bool { state == .recording || state == .paused }

    func start() async {
        guard state == .idle || state == .finished else { return }
        state = .starting
        statusMessage = nil
        guard await AudioCaptureEngine.requestPermission() else {
            state = .idle
            statusMessage = "Microphone access is off. Enable it in Settings › WildID to use Sound ID."
            return
        }
        if let old = liveFileURL, summary?.savedRecordingID == nil { try? FileManager.default.removeItem(at: old) }
        liveFileURL = nil
        detections = []
        summary = nil
        elapsed = 0
        lastBirdNETSpeciesTime = -100
        appleHumanTimes = []
        humanHeardAt = nil
        sessionID = UUID()
        spectrogram.reset()

        if birdnet == nil {
            // Loading the ~25 MB model takes a moment; keep it off the main thread.
            let result = await Task.detached(priority: .userInitiated) { () -> Result<BirdNETClassifier, Error> in
                Result { try BirdNETClassifier() }
            }.value
            switch result {
            case .success(let model): birdnet = model; modelError = nil
            case .failure(let error): modelError = error.localizedDescription
            }
        }
        location?.setPrecise(true)
        location?.start()
        applyLocationFilter()

        let engine = AudioCaptureEngine()
        pipeline.configure(classifier: birdnet, threshold: settings?.sensitivity.threshold ?? 0.15,
                           useFilter: settings?.useLocationFilter ?? true)
        pipeline.onResult = { @Sendable [weak self] predictions, windowStart, window, human in
            Task { @MainActor in self?.handleBirdNET(predictions, windowStart: windowStart, samples: window, human: human) }
        }
        var appleClassifier: AppleSoundClassifier? = nil
        if settings?.detectNonBirdSounds ?? true {
            appleClassifier = try? AppleSoundClassifier(format: engine.analysisFormat,
                                                        confidenceScale: settings?.sensitivity.appleConfidenceScale ?? 0.85)
            appleClassifier?.onDetection = { @Sendable [weak self] d in
                Task { @MainActor in self?.handleApple(d) }
            }
            appleClassifier?.onHuman = { @Sendable [weak self] time in
                Task { @MainActor in self?.appleHumanTimes.append(time) }
            }
        }
        apple = appleClassifier
        engine.onBuffer = Self.bufferHandler(spectrogram: spectrogram, pipeline: pipeline, apple: appleClassifier)
        engine.onAutoStop = { @Sendable [weak self] message in
            Task { @MainActor in
                self?.statusMessage = message
                self?.stop()
            }
        }
        engine.onInterruption = { @Sendable [weak self] began in
            Task { @MainActor in
                guard let self else { return }
                self.statusMessage = began ? "Paused by another app or a call." : nil
                if let c = self.capture { self.state = c.isPaused ? .paused : .recording }
            }
        }
        let url = FileStore.liveDirectory.appendingPathComponent("\(sessionID.uuidString).m4a")
        do {
            try engine.start(writingTo: url)
        } catch {
            state = .idle
            statusMessage = "Couldn't start recording: \(error.localizedDescription)"
            return
        }
        capture = engine
        liveFileURL = url
        startedAt = Date()
        placeName = location?.activePlace?.name
        state = .recording
        AudioPlayer.shared.stop()
        AudioPlayer.shared.recordingActive = true
        UIApplication.shared.isIdleTimerDisabled = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { @Sendable [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let capture else { return }
        elapsed = capture.recordedDuration
        clock = Date()
        if placeName == nil { placeName = location?.activePlace?.name }
        if !locationAppliedToFilter { applyLocationFilter() }
    }

    private func applyLocationFilter() {
        guard let birdnet else { return }
        let place = location?.current.map { WildPlace(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude, name: "") } ?? location?.activePlace
        let useFilter = settings?.useLocationFilter ?? true
        guard useFilter, let place else {
            birdnet.updateLocation(latitude: nil, longitude: nil, date: Date())
            expectedSpeciesCount = nil
            return
        }
        locationAppliedToFilter = true
        let lat = place.latitude, lon = place.longitude
        pipeline.onInferenceQueue { [weak self] in
            birdnet.updateLocation(latitude: lat, longitude: lon, date: Date())
            let count = birdnet.expectedSpeciesCount
            Task { @MainActor in self?.expectedSpeciesCount = count }
        }
    }

    func pause() {
        capture?.pause()
        if capture?.isPaused == true { state = .paused }
    }

    func resume() {
        do { try capture?.resume(); state = .recording; statusMessage = nil }
        catch { statusMessage = "Couldn't resume: \(error.localizedDescription)" }
    }

    func stop() {
        guard let capture, isActive else { return }
        timer?.invalidate()
        timer = nil
        let duration = capture.stop()
        apple?.finish()
        self.capture = nil
        UIApplication.shared.isIdleTimerDisabled = false
        AudioPlayer.shared.recordingActive = false
        location?.setPrecise(false)
        locationAppliedToFilter = false
        elapsed = duration
        state = .finished
        if let url = liveFileURL, let startedAt {
            summary = SessionSummary(id: sessionID, startedAt: startedAt, duration: duration, fileURL: url,
                                     placeName: placeName, coordinate: location?.current?.coordinate ?? location?.activePlace?.coordinate,
                                     detections: detections.sorted { $0.firstHeard < $1.firstHeard })
        }
    }

    /// Discards the session audio (catches stay in the Wild Index).
    func discard() {
        if let url = liveFileURL { try? FileManager.default.removeItem(at: url) }
        liveFileURL = nil
        summary = nil
        state = .idle
        detections = []
        elapsed = 0
    }

    /// Moves the session audio into permanent storage and records detections.
    @discardableResult
    func save(title: String? = nil) -> SavedRecording? {
        guard let summary, let collection, summary.savedRecordingID == nil else { return nil }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HHmm"
        let fileName = "WildID \(df.string(from: summary.startedAt)) \(summary.id.uuidString.prefix(4)).m4a"
        let dest = FileStore.recordingsDirectory.appendingPathComponent(fileName)
        do {
            try FileManager.default.moveItem(at: summary.fileURL, to: dest)
        } catch {
            statusMessage = "Couldn't save the recording: \(error.localizedDescription)"
            return nil
        }
        let titleText = title ?? (summary.placeName.map { "Sound ID • \($0)" } ?? "Sound ID session")
        let rec = SavedRecording(id: summary.id, title: titleText, startedAt: summary.startedAt, duration: summary.duration,
                                 fileName: fileName, fileSize: FileStore.size(of: dest),
                                 coordinate: summary.coordinate, placeName: summary.placeName)
        collection.context.insert(rec)
        for d in summary.detections {
            let rd = RecordingDetection(scientificName: d.species.scientificName, commonName: d.species.commonName,
                                        taxonID: d.species.taxonID, photoURL: d.species.photoURL, group: d.species.group,
                                        offsets: d.offsets, maxConfidence: Double(d.maxConfidence), isGroupLevel: d.species.isGroupLevel)
            collection.context.insert(rd)
            rd.recording = rec
        }
        try? collection.context.save()
        self.summary?.savedRecordingID = rec.id
        liveFileURL = nil
        return rec
    }

    // MARK: - Audio processing (processing queue)

    /// Built in a nonisolated context so the closure never inherits main-actor isolation.
    private nonisolated static func bufferHandler(spectrogram: SpectrogramProcessor, pipeline: InferencePipeline,
                                                  apple: AppleSoundClassifier?) -> (AVAudioPCMBuffer, AVAudioFramePosition) -> Void {
        return { buffer, position in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            spectrogram.append(samples)
            apple?.analyze(buffer, at: position)
            pipeline.feed(samples, endPosition: position + AVAudioFramePosition(buffer.frameLength))
        }
    }

    // MARK: - Detection handling (main actor)

    private func handleBirdNET(_ predictions: [BirdNETClassifier.Prediction], windowStart: TimeInterval, samples: [Float], human: Float) {
        guard isActive else { return }
        appleHumanTimes.removeAll { $0 < windowStart - 10 }
        let humanWindow = BirdNETClassifier.isHumanWindow(birdnetHuman: human, appleHumanTimes: appleHumanTimes, windowStart: windowStart)
        if humanWindow { humanHeardAt = Date() }
        for p in predictions {
            var sci = p.label.scientificName
            var common = p.label.commonName
            if p.label.isNonEvent {
                guard sci == "Dog" else { continue }
                sci = "Canis familiaris"; common = "Domestic Dog"
            }
            lastBirdNETSpeciesTime = windowStart + 3
            register(scientificName: sci, commonName: common, group: .birds, groupLevel: false,
                     confidence: p.confidence, time: max(0, windowStart), source: .birdnet, clipSamples: samples,
                     humanNearby: humanWindow)
        }
    }

    private func handleApple(_ d: AppleSoundClassifier.Detection) {
        guard isActive else { return }
        if d.mapping.isGroupLevel {
            guard settings?.detectNonBirdSounds ?? true else { return }
            // Don't show a generic "Birds" row while BirdNET is naming the species.
            if d.mapping.scientificName == "Aves" && d.time - lastBirdNETSpeciesTime < 8 { return }
            if d.mapping.group == .birds && d.time - lastBirdNETSpeciesTime < 4 { return }
        }
        let clip = d.mapping.isGroupLevel ? nil : pipeline.ring.snapshot()
        let humanWindow = appleHumanTimes.contains { abs($0 - d.time) < 2 }
        register(scientificName: d.mapping.scientificName, commonName: d.mapping.commonName, group: d.mapping.group,
                 groupLevel: d.mapping.isGroupLevel, confidence: Float(d.confidence), time: d.time, source: .apple, clipSamples: clip,
                 humanNearby: humanWindow)
    }

    private func register(scientificName: String, commonName: String, group: AnimalGroup, groupLevel: Bool,
                          confidence: Float, time: TimeInterval, source: LiveDetection.Source, clipSamples: [Float]?,
                          humanNearby: Bool = false) {
        let key = scientificName.lowercased()
        if let i = detections.firstIndex(where: { $0.id == key }) {
            var d = detections[i]
            d.count += 1
            if humanNearby { d.humanCount += 1 } else { d.humanFlagged = false }
            d.lastHeard = max(d.lastHeard, time)
            d.lastConfidence = confidence
            if confidence > d.maxConfidence { d.maxConfidence = confidence }
            if let last = d.offsets.last, time - last < 2.5 { } else { d.offsets.append(time) }
            detections[i] = d
            maybeCatch(id: key, clipSamples: clipSamples)
            return
        }
        let ref = SpeciesRef(scientificName: scientificName, commonName: commonName, group: group, isGroupLevel: groupLevel)
        let isNew = !groupLevel && !(collection?.contains(scientificName) ?? false)
        var d = LiveDetection(id: key, species: ref, source: source, firstHeard: time, lastHeard: time, offsets: [time],
                              maxConfidence: confidence, count: 1, isNewToIndex: isNew,
                              newHighlightUntil: Date().addingTimeInterval(groupLevel || humanNearby ? 0 : 8), lastConfidence: confidence)
        d.humanCount = humanNearby ? 1 : 0
        d.humanFlagged = humanNearby
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            detections.insert(d, at: 0)
        }
        if settings?.haptics ?? true, !groupLevel, !humanNearby { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        Task {
            let resolved = await TaxonResolver.shared.resolve(scientificName: scientificName, fallbackCommonName: commonName,
                                                              fallbackGroup: group, isGroupLevel: groupLevel)
            if let i = detections.firstIndex(where: { $0.id == key }) {
                detections[i].species = resolved
                detections[i].resolved = true
            }
            maybeCatch(id: key, clipSamples: clipSamples)
        }
    }

    /// Auto-adds a species to the Wild Index once the evidence is solid: heard in two windows
    /// (windows overlap, so even one short call usually spans two), or one confident window.
    private func maybeCatch(id: String, clipSamples: [Float]?) {
        guard let i = detections.firstIndex(where: { $0.id == id }) else { return }
        let d = detections[i]
        guard d.resolved, !d.caught, !d.species.isGroupLevel, settings?.autoAddToWildIndex ?? true, let collection else { return }
        // Only windows without a person talking, whistling or singing count, so imitations
        // can't add animals to the Wild Index.
        guard LiveDetection.canCatch(cleanCount: d.count - d.humanCount, maxConfidence: d.maxConfidence, threshold: settings?.sensitivity.threshold ?? 0.15,
                                     humanFlagged: d.humanFlagged) else { return }
        detections[i].caught = true

        var clipName: String? = nil
        if let clipSamples {
            let name = "\(UUID().uuidString).m4a"
            clipName = name
            let url = FileStore.clipsDirectory.appendingPathComponent(name)
            DispatchQueue.global(qos: .utility).async { try? ClipWriter.write(clipSamples, to: url) }
            detections[i].clipFileName = name
        }
        let place = location?.currentPlace ?? location?.activePlace
        let coordinate = location?.current?.coordinate ?? place?.coordinate
        collection.addCatch(d.species, method: .sound, confidence: Double(d.maxConfidence), place: place,
                            coordinate: coordinate, date: Date(), clipFileName: clipName, recordingID: sessionID,
                            verifiedFix: location?.verifiedFix)
    }
}
