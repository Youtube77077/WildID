import CoreML
import UIKit
import Vision

/// Species-level photo recognition with Google's open AIY Vision classifiers (Apache 2.0),
/// converted to Core ML by tools/models/convert_aiy_vision.py:
///   PhotoBirds   — 965 bird species
///   PhotoInsects — 1,021 insect species
/// Loaded only if the models are bundled; otherwise Photo ID stays at group level.
final class SpeciesPhotoClassifier: @unchecked Sendable {
    struct Guess: Identifiable, Hashable {
        let scientificName: String
        let confidence: Double
        var id: String { scientificName }
    }

    enum Kind: String { case birds = "PhotoBirds", insects = "PhotoInsects" }

    private let model: VNCoreMLModel
    private let labels: [String]

    static func isAvailable(_ kind: Kind) -> Bool {
        Bundle.main.url(forResource: kind.rawValue, withExtension: "mlmodelc") != nil
    }

    static func kind(for group: AnimalGroup) -> Kind? {
        switch group {
        case .birds: return isAvailable(.birds) ? .birds : nil
        case .insects: return isAvailable(.insects) ? .insects : nil
        default: return nil
        }
    }

    init?(kind: Kind) {
        guard let url = Bundle.main.url(forResource: kind.rawValue, withExtension: "mlmodelc"),
              let labelsURL = Bundle.main.url(forResource: "\(kind.rawValue)_Labels", withExtension: "txt"),
              let text = try? String(contentsOf: labelsURL, encoding: .utf8),
              let ml = try? MLModel(contentsOf: url),
              let vn = try? VNCoreMLModel(for: ml) else { return nil }
        model = vn
        labels = text.components(separatedBy: "\n")
    }

    func classify(_ image: UIImage, top: Int = 5) async -> [Guess] {
        guard let cg = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async { [model, labels] in
                let request = VNCoreMLRequest(model: model)
                request.imageCropAndScaleOption = .centerCrop
                do { try VNImageRequestHandler(cgImage: cg, orientation: orientation).perform([request]) }
                catch { cont.resume(returning: []); return }
                guard let obs = request.results?.first as? VNCoreMLFeatureValueObservation,
                      let arr = obs.featureValue.multiArrayValue else { cont.resume(returning: []); return }
                var scores = BirdNETClassifier.floats(arr)
                let sum = scores.reduce(0, +)
                if abs(sum - 1) > 0.05 {   // logits → softmax
                    let m = scores.max() ?? 0
                    let e = scores.map { expf($0 - m) }
                    let t = e.reduce(0, +)
                    scores = e.map { $0 / t }
                }
                let ranked = scores.enumerated()
                    .filter { $0.offset < labels.count && !labels[$0.offset].lowercased().contains("background") }
                    .sorted { $0.element > $1.element }
                    .prefix(top)
                    .map { Guess(scientificName: labels[$0.offset], confidence: Double($0.element)) }
                cont.resume(returning: Array(ranked))
            }
        }
    }
}
