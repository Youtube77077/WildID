import CoreLocation
import Foundation

/// "My offline animals": species whose page data, photos and a few reference sounds are kept on
/// the device so they open without a connection (like downloading a pack before a trip).
@MainActor
@Observable
final class OfflineStore {
    static let shared = OfflineStore()

    private(set) var saved: [SpeciesRef] = []
    private(set) var downloading: Set<String> = []
    private var soundMap: [String: String] = [:]   // remote URL -> local file name

    private let listKey = "offlineSpecies"
    private let soundsKey = "offlineSounds"

    static var soundsDirectory: URL {
        let url = FileStore.appSupport.appendingPathComponent("OfflineSounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: listKey),
           let list = try? JSONDecoder().decode([SpeciesRef].self, from: data) { saved = list }
        soundMap = UserDefaults.standard.dictionary(forKey: soundsKey) as? [String: String] ?? [:]
    }

    func isSaved(_ species: SpeciesRef) -> Bool { saved.contains { $0.id == species.id } }

    /// Local copy of a reference sound if it was downloaded.
    func localURL(for remote: URL) -> URL? {
        guard let name = soundMap[remote.absoluteString] else { return nil }
        let url = Self.soundsDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var totalSize: Int64 { FileStore.directorySize(Self.soundsDirectory) }

    func download(_ species: SpeciesRef, model: SpeciesProfileModel, near coordinate: CLLocationCoordinate2D?) async {
        guard !downloading.contains(species.id) else { return }
        downloading.insert(species.id)
        defer { downloading.remove(species.id) }
        // The page model fetches through HTTPClient, which stores every response on disk.
        await model.load(species, near: coordinate)
        for photo in model.photos.prefix(6) {
            if let url = photo.sized("large") { _ = await ImagePipeline.shared.image(for: url, maxPixel: 1400) }
            if let url = photo.sized("small") { _ = await ImagePipeline.shared.image(for: url, maxPixel: 240) }
        }
        for sound in model.sounds.prefix(3) where localURL(for: sound.url) == nil {
            let ext = sound.url.pathExtension.isEmpty ? "mp3" : sound.url.pathExtension
            let name = "\(UUID().uuidString).\(ext)"
            var request = URLRequest(url: sound.url)
            request.setValue(HTTPClient.userAgent, forHTTPHeaderField: "User-Agent")
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                try? data.write(to: Self.soundsDirectory.appendingPathComponent(name))
                soundMap[sound.url.absoluteString] = name
            }
        }
        var ref = model.taxon.map(SpeciesRef.init(taxon:)) ?? species
        ref.isGroupLevel = species.isGroupLevel
        if !isSaved(ref) { saved.append(ref) }
        persist()
    }

    func remove(_ species: SpeciesRef) {
        saved.removeAll { $0.id == species.id }
        persist()
    }

    func removeAllSounds() {
        try? FileManager.default.removeItem(at: Self.soundsDirectory)
        soundMap = [:]
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: listKey) }
        UserDefaults.standard.set(soundMap, forKey: soundsKey)
    }
}
