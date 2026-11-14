import XCTest
import SwiftData
import CoreLocation
@testable import WildID

final class TaxonomyTests: XCTestCase {
    func testGroupsFromAncestry() {
        XCTAssertEqual(AnimalGroup.from(ancestorIDs: [48460, 1, 2, 355675, 3, 4954]), .birds)
        XCTAssertEqual(AnimalGroup.from(ancestorIDs: [1, 47120, 47158]), .insects)
        XCTAssertEqual(AnimalGroup.from(ancestorIDs: [1, 2, 355675, 40151]), .mammals)
        XCTAssertEqual(AnimalGroup.from(ancestorIDs: [1]), .other)
        XCTAssertEqual(AnimalGroup.from(ancestorIDs: [], iconicName: "Amphibia"), .amphibians)
    }

    func testRarityThresholds() {
        XCTAssertEqual(Rarity.from(localObservations: 5000), .common)
        XCTAssertEqual(Rarity.from(localObservations: 120), .uncommon)
        XCTAssertEqual(Rarity.from(localObservations: 40), .rare)
        XCTAssertEqual(Rarity.from(localObservations: 12), .epic)
        XCTAssertEqual(Rarity.from(localObservations: 0), .legendary)
        XCTAssertEqual(Rarity.from(localObservations: 5000, conservationCode: "EN"), .epic)
        XCTAssertEqual(Rarity.from(localObservations: 5000, conservationCode: "CR"), .legendary)
        XCTAssertEqual(Rarity(storedValue: "veryRare"), .epic)
    }

    func testVisionLabelMatchingUsesWholeWords() {
        XCTAssertEqual(VisionTaxonMap.match(identifier: "domestic_cat")?.taxon, "Felis catus")
        XCTAssertEqual(VisionTaxonMap.match(identifier: "caterpillar")?.taxon, "Lepidoptera")
        XCTAssertEqual(VisionTaxonMap.match(identifier: "mallard_duck")?.taxon, "Anatidae")
        XCTAssertNil(VisionTaxonMap.match(identifier: "bicycle"))
    }

    func testAppleSoundMappingsAreHonest() {
        // Wild categories must be group-level, domestic animals species-level.
        XCTAssertEqual(AppleSoundClassifier.mappings["frog_croak"]?.isGroupLevel, true)
        XCTAssertEqual(AppleSoundClassifier.mappings["owl_hoot"]?.isGroupLevel, true)
        XCTAssertEqual(AppleSoundClassifier.mappings["dog_bark"]?.isGroupLevel, false)
        XCTAssertEqual(AppleSoundClassifier.mappings["dog_bark"]?.scientificName, "Canis familiaris")
    }
}

final class EncyclopediaParsingTests: XCTestCase {
    func testWikipediaSectionsAreMappedToTopics() {
        let extract = """
        The European robin is a small insectivorous passerine bird.

        == Taxonomy ==
        Robins were described by Linnaeus in 1758 and the name has a long history in many languages and texts.

        == Description ==
        The adult European robin is 12.5–14.0 cm long; the male and female are identical in plumage, with an orange breast and face lined by grey.

        == Behaviour and ecology ==
        === Food and feeding ===
        Robins eat invertebrates such as worms and beetles, and also fruit and seeds in winter, often following gardeners.
        === Breeding ===
        Breeding starts in March in Western Europe; the female builds a cup nest and lays four to six eggs that hatch after two weeks.

        == References ==
        Some references here that should never be shown as content because they are citations.
        """
        let a = WikipediaAPI.parse(title: "European robin", url: URL(string: "https://en.wikipedia.org/wiki/European_robin")!, extract: extract)
        XCTAssertTrue(a.summary.hasPrefix("The European robin"))
        let topics = Set(a.sections.map(\.topic))
        XCTAssertTrue(topics.contains(.description))
        XCTAssertTrue(topics.contains(.diet))
        XCTAssertTrue(topics.contains(.reproduction))
        XCTAssertFalse(a.sections.contains { $0.text.contains("citations") })
    }

    func testWikidataFormatting() {
        XCTAssertEqual(WikidataAPI.format(lo: 0.016, hi: 0.022, kind: "mass"), "16 g – 22 g")
        XCTAssertEqual(WikidataAPI.format(lo: 0.14, hi: 0.14, kind: "length"), "14 cm")
        XCTAssertEqual(WikidataAPI.format(lo: 1.6, hi: 1.6, kind: "time"), "1.6 years")
    }
}

final class BirdNETTests: XCTestCase {
    private var bundle: Bundle { Bundle(for: BirdNETTests.self) }

    func testBirdNETWeekCalendar() {
        let cal = Calendar(identifier: .gregorian)
        func d(_ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: m, day: day))! }
        XCTAssertEqual(BirdNETClassifier.birdnetWeek(for: d(1, 1)), 1)
        XCTAssertEqual(BirdNETClassifier.birdnetWeek(for: d(11, 14)), 42)
        XCTAssertEqual(BirdNETClassifier.birdnetWeek(for: d(12, 31)), 48)
    }

    /// The Swift re-implementation must match TensorFlow's meta-model input encoding.
    func testMetaEncodingMatchesTensorFlowReference() throws {
        guard let url = bundle.url(forResource: "meta_encoding_reference", withExtension: "json") else {
            throw XCTSkip("Reference file not generated yet (run the 'Convert models' workflow).")
        }
        struct Ref: Decodable { let queries: [[Double]]; let encodings: [[Double]] }
        let ref = try JSONDecoder().decode(Ref.self, from: Data(contentsOf: url))
        for (q, expected) in zip(ref.queries, ref.encodings) {
            let swift = BirdNETClassifier.metaEncoding(latitude: q[0], longitude: q[1], week: Int(q[2]))
            XCTAssertEqual(swift.count, expected.count)
            let maxDiff = zip(swift, expected).map { abs(Double($0) - $1) }.max() ?? 1
            XCTAssertLessThan(maxDiff, 1e-4, "query \(q)")
        }
    }

    /// End-to-end: the bundled Core ML model identifies a real Eurasian Blackbird recording
    /// (iNaturalist observation 110684075, © Codrin Bucur, CC BY).
    func testCoreMLModelIdentifiesRealBlackbirdRecording() throws {
        guard BirdNETClassifier.isAvailable,
              let url = bundle.url(forResource: "birdnet_input", withExtension: "f32") else {
            throw XCTSkip("BirdNET model not bundled in this build.")
        }
        let data = try Data(contentsOf: url)
        let samples: [Float] = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        XCTAssertEqual(samples.count, BirdNETClassifier.windowSamples)
        let classifier = try BirdNETClassifier()
        XCTAssertEqual(classifier.labels.count, 6522)
        let predictions = try samples.withUnsafeBufferPointer {
            try classifier.classify($0, threshold: 0.3, useLocationFilter: false)
        }
        XCTAssertEqual(predictions.first?.label.scientificName, "Turdus merula")
        XCTAssertGreaterThan(predictions.first?.confidence ?? 0, 0.5)
    }

    /// Why Sound ID doesn't amplify: the model ignores loudness. The same blackbird scores the
    /// same at full scale and 50 dB quieter.
    func testQuietCallScoresLikeLoudCall() throws {
        guard BirdNETClassifier.isAvailable,
              let url = bundle.url(forResource: "birdnet_input", withExtension: "f32") else {
            throw XCTSkip("BirdNET model not bundled in this build.")
        }
        let data = try Data(contentsOf: url)
        let clean: [Float] = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let classifier = try BirdNETClassifier()
        func blackbird(_ x: [Float]) throws -> Float {
            try x.withUnsafeBufferPointer { try classifier.classify($0, threshold: 0.01, useLocationFilter: false) }
                .first { $0.label.scientificName == "Turdus merula" }?.confidence ?? 0
        }
        let loud = try blackbird(clean)
        let quiet = try blackbird(clean.map { $0 * 0.003 })
        XCTAssertEqual(quiet, loud, accuracy: 0.05)
    }

    /// A faint blackbird (peak 0.05) buried under strong wind rumble and hiss is still the top
    /// suggestion, with a score above the default "Sensitive" threshold.
    func testFaintBlackbirdInWindIsStillIdentified() throws {
        guard BirdNETClassifier.isAvailable,
              let url = bundle.url(forResource: "birdnet_input", withExtension: "f32") else {
            throw XCTSkip("BirdNET model not bundled in this build.")
        }
        let data = try Data(contentsOf: url)
        let clean: [Float] = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let peak = clean.map(abs).max() ?? 1
        // Deterministic "wind": low-passed random walk (energy mostly below 100 Hz) + light hiss.
        var seed: UInt32 = 12345
        func rand() -> Float { seed = seed &* 1_664_525 &+ 1_013_904_223; return Float(seed >> 8) / Float(1 << 24) * 2 - 1 }
        var wind: Float = 0
        let noisy: [Float] = clean.map { s in
            wind = 0.9995 * wind + 0.02 * rand()
            return s / peak * 0.05 + 0.6 * wind + 0.002 * rand()
        }
        let classifier = try BirdNETClassifier()
        let predictions = try noisy.withUnsafeBufferPointer { try classifier.classify($0, threshold: 0.01, useLocationFilter: false) }
        print("Faint blackbird in wind — top: \(predictions.prefix(3).map { "\($0.label.commonName) \($0.confidence)" })")
        XCTAssertEqual(predictions.first?.label.scientificName, "Turdus merula")
        XCTAssertGreaterThanOrEqual(predictions.first?.confidence ?? 0, DetectionSensitivity.sensitive.threshold)
    }

    /// The location/season model expects blackbirds in North Holland in November and
    /// rules out a tropical species there.
    func testMetaModelFiltersByPlaceAndWeek() throws {
        guard BirdNETClassifier.isAvailable else { throw XCTSkip("BirdNET model not bundled.") }
        let classifier = try BirdNETClassifier()
        guard let occ = try classifier.occurrenceScores(latitude: 52.46, longitude: 5.03, week: 46) else {
            throw XCTSkip("Meta model not bundled.")
        }
        let blackbird = classifier.labels.firstIndex { $0.scientificName == "Turdus merula" }!
        XCTAssertGreaterThan(occ[blackbird], 0.3)
        if let bayWren = classifier.labels.firstIndex(where: { $0.scientificName == "Cantorchilus nigricapillus" }) {
            XCTAssertLessThan(occ[bayWren], BirdNETClassifier.metaThreshold)
        }
    }
}

final class AudioDSPTests: XCTestCase {
    /// A pure 3 kHz tone must light up the spectrogram row for 3 kHz.
    func testSpectrogramLocatesToneFrequency() {
        let p = SpectrogramProcessor(seconds: 2)
        let sr = AudioCaptureEngine.analysisSampleRate
        let tone = (0..<Int(sr * 1.5)).map { Float(0.5 * sin(2 * Double.pi * 3000 * Double($0) / sr)) }
        tone.withUnsafeBufferPointer { p.append($0) }
        XCTAssertGreaterThan(p.totalColumns, 50)
        var pixels = [UInt8](repeating: 0, count: p.rows * p.capacity)
        let lut = (0..<256).map { UInt8($0) }   // identity: brightness = intensity
        _ = p.snapshot(into: &pixels, lut: lut)
        let lastColumn = p.capacity - 1
        var bestRow = 0, bestValue: UInt8 = 0
        for row in 0..<p.rows {
            let v = pixels[row * p.capacity + lastColumn]
            if v > bestValue { bestValue = v; bestRow = row }
        }
        let bin = p.rows - 1 - bestRow
        let hz = Double(bin) * sr / Double(SpectrogramProcessor.fftSize)
        XCTAssertEqual(hz, 3000, accuracy: 100)
        XCTAssertGreaterThan(bestValue, 100)
    }

    func testClipWriterRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clip-test.m4a")
        try? FileManager.default.removeItem(at: url)
        let samples = (0..<48_000 * 2).map { Float(0.3 * sin(Double($0) / 10)) }
        try ClipWriter.write(samples, to: url)
        XCTAssertGreaterThan(FileStore.size(of: url), 1000)
        let back = PlaybackSpectrogramModel.read(url: url, from: 0, seconds: 3) ?? []
        XCTAssertEqual(Double(back.count) / 48_000, 2, accuracy: 0.2)
    }

    func testSampleRingKeepsLatestWindow() {
        let ring = SampleRing(capacity: 5)
        [1, 2, 3, 4, 5, 6, 7].map(Float.init).withUnsafeBufferPointer { ring.append($0) }
        XCTAssertEqual(ring.snapshot(), [3, 4, 5, 6, 7])
        XCTAssertEqual(ring.filled, 5)
    }
}

@MainActor
final class CollectionTests: XCTestCase {
    func testCatchesAreUniquePerSpeciesAndGroupLevelIsIgnored() throws {
        let schema = Schema([WildIndexEntry.self, Catch.self, SavedRecording.self, RecordingDetection.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let settings = AppSettings()
        settings.newAnimalPopups = false
        let manager = CollectionManager(context: container.mainContext, toasts: ToastCenter(), settings: settings)
        let robin = SpeciesRef(scientificName: "Erithacus rubecula", commonName: "European Robin", group: .birds)
        let first = manager.addCatch(robin, method: .sound, confidence: 0.9, place: nil, coordinate: nil, announce: false)
        let second = manager.addCatch(robin, method: .photo, confidence: nil, place: nil, coordinate: nil, announce: false)
        XCTAssertEqual(first?.isNew, true)
        XCTAssertEqual(second?.isNew, false)
        XCTAssertEqual(manager.speciesCount(), 1)
        XCTAssertEqual(manager.entry(for: "erithacus rubecula")?.catches.count, 2)
        XCTAssertEqual(manager.entry(for: "Erithacus rubecula")?.methods, [.sound, .photo])
        let frogs = SpeciesRef(scientificName: "Anura", commonName: "Frogs & toads", group: .amphibians, isGroupLevel: true)
        XCTAssertNil(manager.addCatch(frogs, method: .sound, confidence: 0.8, place: nil, coordinate: nil, announce: false))
        XCTAssertEqual(manager.speciesCount(), 1)
    }

    func testAchievementsDeriveFromIndex() throws {
        let schema = Schema([WildIndexEntry.self, Catch.self, SavedRecording.self, RecordingDetection.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let settings = AppSettings()
        let manager = CollectionManager(context: container.mainContext, toasts: ToastCenter(), settings: settings)
        manager.addCatch(SpeciesRef(scientificName: "Turdus merula", commonName: "Eurasian Blackbird", group: .birds),
                         method: .sound, confidence: 0.8, place: nil, coordinate: nil, announce: false)
        let entries = try container.mainContext.fetch(FetchDescriptor<WildIndexEntry>())
        let list = AchievementEngine.compute(entries: entries)
        XCTAssertEqual(list.first { $0.id == "species-1" }?.unlocked, true)
        XCTAssertEqual(list.first { $0.id == "first-birds" }?.unlocked, true)
        XCTAssertEqual(list.first { $0.id == "first-mammals" }?.unlocked, false)
    }
}


@MainActor
final class GameRulesTests: XCTestCase {
    private func makeManager() throws -> (CollectionManager, ModelContainer) {
        let schema = Schema([WildIndexEntry.self, Catch.self, SavedRecording.self, RecordingDetection.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let settings = AppSettings()
        settings.newAnimalPopups = false
        settings.haptics = false
        return (CollectionManager(context: container.mainContext, toasts: ToastCenter(), settings: settings), container)
    }

    func testLevelCurve() {
        XCTAssertEqual(XPRules.level(forXP: 0), 1)
        XCTAssertEqual(XPRules.level(forXP: 74), 1)
        XCTAssertEqual(XPRules.level(forXP: 75), 2)
        XCTAssertEqual(XPRules.level(forXP: 750), 5)
        XCTAssertEqual(XPRules.level(forXP: 3375), 10)
        XCTAssertEqual(XPRules.level(forXP: 10_000_000), XPRules.maxLevel)
    }

    func testRepeatCatchesCannotBeFarmed() throws {
        let (m, c) = try makeManager()
        _ = c
        let fox = SpeciesRef(scientificName: "Vulpes vulpes", commonName: "Red Fox", group: .mammals)
        let first = m.addCatch(fox, method: .sound, confidence: 0.9, place: nil, coordinate: nil, announce: false)
        XCTAssertEqual(first?.entry.xp, XPRules.firstCatchXP(.common))
        // Immediately again: inside the 1 hour cooldown → no XP, but the catch is still logged.
        m.addCatch(fox, method: .sound, confidence: 0.9, place: nil, coordinate: nil, announce: false)
        let entry = try XCTUnwrap(m.entry(for: "Vulpes vulpes"))
        XCTAssertEqual(entry.catches.count, 2)
        XCTAssertEqual(entry.xp, XPRules.firstCatchXP(.common))
    }

    func testCooldownAndDailyCap() throws {
        let (m, c) = try makeManager()
        _ = c
        let robin = SpeciesRef(scientificName: "Erithacus rubecula", commonName: "European Robin", group: .birds)
        m.addCatch(robin, method: .sound, confidence: 0.9, place: nil, coordinate: nil, announce: false)
        let entry = try XCTUnwrap(m.entry(for: "Erithacus rubecula"))
        // Pretend the earlier catch was rewarded 2 hours ago, so the cooldown has passed.
        entry.catches.forEach { $0.awardedAt = Date().addingTimeInterval(-7200) }
        let now = Date()
        XCTAssertEqual(XPRules.award(method: .sound, tier: .common, isFirst: false, previous: entry.catches, now: now), XPRules.repeatXP(.common))
        XCTAssertEqual(XPRules.award(method: .manual, tier: .common, isFirst: false, previous: entry.catches, now: now), 5)
        // Three rewarded repeats today → the fourth earns nothing.
        let ctx = c.mainContext
        for h in [5, 4, 3] {
            let extra = Catch(date: now, coordinate: nil, placeName: nil, countryCode: nil, method: .sound, confidence: 0.9)
            extra.xpAwarded = 20
            extra.awardedAt = Calendar.current.startOfDay(for: now).addingTimeInterval(Double(h) * 60)
            ctx.insert(extra)
            extra.entry = entry
        }
        XCTAssertEqual(XPRules.award(method: .sound, tier: .common, isFirst: false, previous: entry.catches, now: now), 0)
    }

    func testNicknameAndBackupRoundTrip() throws {
        let (m, c) = try makeManager()
        let heron = SpeciesRef(scientificName: "Ardea cinerea", commonName: "Grey Heron", group: .birds)
        m.addCatch(heron, method: .photo, confidence: nil, place: nil, coordinate: nil, announce: false)
        let entry = try XCTUnwrap(m.entry(for: "Ardea cinerea"))
        m.rename(entry, to: "  Sir Stilts  ")
        XCTAssertEqual(entry.displayName, "Sir Stilts")
        // The snapshot survives encoding exactly as it is stored in the Keychain…
        let packed = try XCTUnwrap(BackupStore.pack(BackupStore.makeBackup(context: c.mainContext)))
        let backup = try XCTUnwrap(BackupStore.unpack(packed))
        XCTAssertEqual(backup.entries.first?.nickname, "Sir Stilts")
        XCTAssertEqual(backup.entries.first?.catches.count, 1)
        // …and restores into an empty store, as after reinstalling the app.
        let schema = Schema([WildIndexEntry.self, Catch.self, SavedRecording.self, RecordingDetection.self])
        let fresh = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        XCTAssertEqual(BackupStore.restore(backup, into: fresh.mainContext), 1)
        let restored = try fresh.mainContext.fetch(FetchDescriptor<WildIndexEntry>())
        XCTAssertEqual(restored.first?.displayName, "Sir Stilts")
        XCTAssertEqual(restored.first?.xp, entry.xp)
        XCTAssertEqual(restored.first?.catches.count, 1)
        // The Keychain itself is only reachable from a signed app (unsigned CI test hosts get
        // errSecMissingEntitlement), so the Keychain round trip is checked when available.
        let store = BackupStore.shared
        store.backupNow(context: c.mainContext)
        if let fromKeychain = store.loadBackup() {
            XCTAssertEqual(fromKeychain.entries.first?.nickname, "Sir Stilts")
            store.deleteBackup()
        }
    }
}
