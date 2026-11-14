import CoreML
import Foundation

/// One class of the BirdNET V2.4 label set ("Genus species_Common Name").
struct BirdNETLabel {
    let scientificName: String
    let commonName: String
    /// Non-event classes such as "Engine", "Human vocal", "Siren".
    let isNonEvent: Bool
}

/// Runs the BirdNET V2.4 acoustic model (6,522 classes; mostly birds plus some frogs, insects
/// and mammals) on 3-second windows of 48 kHz mono audio, and the BirdNET meta-model that
/// estimates which species occur at a location in a given week.
///
/// Model: BirdNET V2.4 © Cornell Lab of Ornithology & Chemnitz University of Technology,
/// CC BY-NC-SA 4.0 — converted to Core ML by `tools/models/convert_birdnet.py`.
final class BirdNETClassifier: @unchecked Sendable {
    static let windowSamples = 144_000          // 3 s × 48 kHz
    static let metaThreshold: Float = 0.03      // BirdNET's default species-filter threshold

    let labels: [BirdNETLabel]
    private let audioModel: MLModel
    private let metaModel: MLModel?
    private let input: MLMultiArray
    private let lock = NSLock()

    /// Occurrence probability per class for the current place/week (nil = no filter).
    private(set) var occurrence: [Float]?

    struct Prediction {
        let index: Int
        let label: BirdNETLabel
        let confidence: Float
        let occurrence: Float?
    }

    enum LoadError: LocalizedError {
        case missingModel, missingLabels
        var errorDescription: String? {
            switch self {
            case .missingModel: "The BirdNET species model is not included in this build. Run the 'Convert models' workflow (see README)."
            case .missingLabels: "BirdNET labels are missing from this build."
            }
        }
    }

    static var isAvailable: Bool {
        Bundle.main.url(forResource: "BirdNETAudio", withExtension: "mlmodelc") != nil
    }

    init() throws {
        guard let audioURL = Bundle.main.url(forResource: "BirdNETAudio", withExtension: "mlmodelc") else { throw LoadError.missingModel }
        guard let labelsURL = Bundle.main.url(forResource: "BirdNET_Labels_en", withExtension: "txt"),
              let text = try? String(contentsOf: labelsURL, encoding: .utf8) else { throw LoadError.missingLabels }
        labels = text.split(whereSeparator: \.isNewline).map { line in
            let parts = line.split(separator: "_", maxSplits: 1).map(String.init)
            let sci = parts.first ?? String(line)
            let common = parts.count > 1 ? parts[1] : sci
            return BirdNETLabel(scientificName: sci, commonName: common, isNonEvent: sci == common || !sci.contains(" "))
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        audioModel = try MLModel(contentsOf: audioURL, configuration: config)
        if let metaURL = Bundle.main.url(forResource: "BirdNETMeta", withExtension: "mlmodelc") {
            let metaConfig = MLModelConfiguration()
            metaConfig.computeUnits = .cpuOnly
            metaModel = try? MLModel(contentsOf: metaURL, configuration: metaConfig)
        } else {
            metaModel = nil
        }
        input = try MLMultiArray(shape: [1, NSNumber(value: Self.windowSamples)], dataType: .float32)
    }

    /// BirdNET's 48-week calendar: four "weeks" per month.
    static func birdnetWeek(for date: Date) -> Int {
        let cal = Calendar(identifier: .gregorian)
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        return (month - 1) * 4 + min(4, Int(ceil(Double(day) / 7.0)))
    }

    /// The 144-value input encoding of BirdNET's meta-model, re-implemented from its graph
    /// (see tools/models/reports/meta_encoding_graph.json; verified against TensorFlow in tests):
    /// for v in [(lat+90)/180, (lon+180)/360, (week-1)/48]: √2·sin(2πv + kπ/48), k = 0..47.
    /// The week block is zeroed for week ≤ 0 or ≥ 49 (BirdNET uses -1 for "all year").
    static func metaEncoding(latitude: Double, longitude: Double, week: Int) -> [Float] {
        let values = [(latitude + 90) / 180, (longitude + 180) / 360, Double(week - 1) / 48]
        let weekMask: Double = (week > 0 && week < 49) ? 1 : 0
        var out = [Float]()
        out.reserveCapacity(144)
        for (i, v) in values.enumerated() {
            let mask = i == 2 ? weekMask : 1
            for k in 0..<48 {
                out.append(Float(mask * 2.0.squareRoot() * sin(2 * Double.pi * v + Double(k) * Double.pi / 48)))
            }
        }
        return out
    }

    /// Runs the meta-model directly (exposed for tests).
    func occurrenceScores(latitude: Double, longitude: Double, week: Int) throws -> [Float]? {
        guard let metaModel else { return nil }
        let inputs = metaModel.modelDescription.inputDescriptionsByName
        let provider: MLDictionaryFeatureProvider
        if inputs["features"] != nil {
            let enc = Self.metaEncoding(latitude: latitude, longitude: longitude, week: week)
            let arr = try MLMultiArray(shape: [1, 144], dataType: .float32)
            let p = arr.dataPointer.bindMemory(to: Float.self, capacity: 144)
            for i in 0..<144 { p[i] = enc[i] }
            provider = try MLDictionaryFeatureProvider(dictionary: ["features": MLFeatureValue(multiArray: arr)])
        } else {
            let arr = try MLMultiArray(shape: [1, 3], dataType: .float32)
            arr[0] = NSNumber(value: Float(latitude))
            arr[1] = NSNumber(value: Float(longitude))
            arr[2] = NSNumber(value: Float(week))
            provider = try MLDictionaryFeatureProvider(dictionary: ["location": MLFeatureValue(multiArray: arr)])
        }
        let out = try metaModel.prediction(from: provider)
        guard let scores = out.featureValue(for: "occurrence")?.multiArrayValue else { return nil }
        return Self.floats(scores)
    }

    /// Updates the location/season filter. Pass nil to disable filtering.
    func updateLocation(latitude: Double?, longitude: Double?, date: Date) {
        guard let latitude, let longitude, let metaModel else {
            lock.withLock { occurrence = nil }
            return
        }
        _ = metaModel
        do {
            let values = try occurrenceScores(latitude: latitude, longitude: longitude, week: Self.birdnetWeek(for: date))
            lock.withLock { occurrence = values?.count == labels.count ? values : nil }
        } catch {
            lock.withLock { occurrence = nil }
        }
    }

    /// Number of species expected at the current place and week (for UI context).
    var expectedSpeciesCount: Int? {
        lock.withLock { occurrence?.filter { $0 >= Self.metaThreshold }.count }
    }

    /// Classifies exactly `windowSamples` samples. Returns predictions above `threshold`,
    /// sorted by confidence. Species unlikely at the current place/week are dropped unless the
    /// acoustic evidence is overwhelming (≥ 0.9).
    func classify(_ samples: UnsafeBufferPointer<Float>, threshold: Float, useLocationFilter: Bool) throws -> [Prediction] {
        precondition(samples.count == Self.windowSamples)
        let out: MLFeatureProvider = try lock.withLock {
            let dst = input.dataPointer.bindMemory(to: Float.self, capacity: Self.windowSamples)
            dst.update(from: samples.baseAddress!, count: Self.windowSamples)
            return try audioModel.prediction(from: MLDictionaryFeatureProvider(dictionary: ["audio": MLFeatureValue(multiArray: input)]))
        }
        guard let scores = out.featureValue(for: "scores")?.multiArrayValue else { return [] }
        let logits = Self.floats(scores)
        let occ = lock.withLock { useLocationFilter ? occurrence : nil }
        var results: [Prediction] = []
        for (i, logit) in logits.enumerated() where i < labels.count {
            let p = 1 / (1 + expf(-logit))   // BirdNET outputs logits; sigmoid with sensitivity 1.0
            guard p >= threshold else { continue }
            let o = occ?[i]
            if let o, o < Self.metaThreshold, p < 0.9 { continue }
            results.append(Prediction(index: i, label: labels[i], confidence: p, occurrence: o))
        }
        return results.sorted { $0.confidence > $1.confidence }
    }

    static func floats(_ array: MLMultiArray) -> [Float] {
        let n = array.count
        switch array.dataType {
        case .float32:
            let p = array.dataPointer.bindMemory(to: Float.self, capacity: n)
            return Array(UnsafeBufferPointer(start: p, count: n))
        case .double:
            let p = array.dataPointer.bindMemory(to: Double.self, capacity: n)
            return UnsafeBufferPointer(start: p, count: n).map(Float.init)
        default:
            return (0..<n).map { array[$0].floatValue }
        }
    }
}
