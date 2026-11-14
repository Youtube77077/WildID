import Foundation
import CoreLocation
import Network
import Security
import SwiftUI

// MARK: - Keychain

/// Stores user-provided secrets (e.g. a personal Xeno-canto API key) in the iOS Keychain.
/// Nothing secret is ever compiled into the app.
enum KeychainStore {
    enum Key: String { case xenoCantoKey = "wildid.xeno-canto.key" }

    static func read(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ key: Key, value: String?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key.rawValue]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

// MARK: - Location

/// A place used to rank species: either the live GPS position or a manually chosen spot.
struct WildPlace: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var name: String
    var countryCode: String?

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    var authorization: CLAuthorizationStatus
    var current: CLLocation?
    var currentPlace: WildPlace?
    /// When set, overrides GPS for species suggestions (like choosing a place on Merlin's map).
    var manualPlace: WildPlace? {
        didSet { persistManual() }
    }

    /// The place WildID should use for suggestions right now.
    var activePlace: WildPlace? { manualPlace ?? currentPlace }

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 200
        if let data = UserDefaults.standard.data(forKey: "manualPlace"),
           let place = try? JSONDecoder().decode(WildPlace.self, from: data) {
            manualPlace = place
        }
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.startUpdatingLocation()
        default: break
        }
    }

    /// Higher accuracy while recording so catches are placed precisely on the map.
    func setPrecise(_ precise: Bool) {
        manager.desiredAccuracy = precise ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
        manager.distanceFilter = precise ? 20 : 200
    }

    private func persistManual() {
        if let manualPlace, let data = try? JSONEncoder().encode(manualPlace) {
            UserDefaults.standard.set(data, forKey: "manualPlace")
        } else {
            UserDefaults.standard.removeObject(forKey: "manualPlace")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedWhenInUse || status == .authorizedAlways { self.manager.startUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            let shouldGeocode = self.current == nil || (self.current!.distance(from: loc) > 1500) || self.currentPlace == nil
            self.current = loc
            if shouldGeocode { await self.reverseGeocode(loc) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func reverseGeocode(_ location: CLLocation) async {
        let name = await Self.placeName(for: location, using: geocoder)
        currentPlace = WildPlace(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                 name: name.name, countryCode: name.country)
    }

    /// "Monnickendam, North Holland" style names.
    static func placeName(for location: CLLocation, using geocoder: CLGeocoder = CLGeocoder()) async -> (name: String, country: String?) {
        do {
            let marks = try await geocoder.reverseGeocodeLocation(location)
            if let m = marks.first {
                let parts = [m.locality ?? m.subAdministrativeArea, m.administrativeArea ?? m.country].compactMap { $0 }
                let name = parts.isEmpty ? (m.name ?? "Unknown place") : parts.joined(separator: ", ")
                return (name, m.isoCountryCode)
            }
        } catch {}
        return (String(format: "%.3f, %.3f", location.coordinate.latitude, location.coordinate.longitude), nil)
    }
}

// MARK: - Connectivity

@MainActor
@Observable
final class Connectivity {
    var isOnline = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isOnline = path.status == .satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "wildid.connectivity"))
    }
}

// MARK: - Settings

enum DetectionSensitivity: String, CaseIterable, Identifiable, Codable {
    case conservative, balanced, sensitive
    var id: String { rawValue }
    var title: String {
        switch self {
        case .conservative: "Conservative"
        case .balanced: "Balanced"
        case .sensitive: "Sensitive"
        }
    }
    var detail: String {
        switch self {
        case .conservative: "Fewer, very confident detections"
        case .balanced: "Recommended for most places"
        case .sensitive: "More detections, more false alarms"
        }
    }
    /// Minimum classifier probability for a species to be shown.
    var threshold: Float {
        switch self {
        case .conservative: 0.70
        case .balanced: 0.50
        case .sensitive: 0.30
        }
    }
}

/// User preferences, persisted in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    var sensitivity: DetectionSensitivity { didSet { save() } }
    var autoAddToWildIndex: Bool { didSet { save() } }
    var newAnimalPopups: Bool { didSet { save() } }
    var haptics: Bool { didSet { save() } }
    var showScientificNames: Bool { didSet { save() } }
    var useLocationFilter: Bool { didSet { save() } }
    var detectNonBirdSounds: Bool { didSet { save() } }
    var hasOnboarded: Bool { didSet { save() } }

    private let defaults = UserDefaults.standard

    init() {
        sensitivity = DetectionSensitivity(rawValue: defaults.string(forKey: "sensitivity") ?? "") ?? .balanced
        autoAddToWildIndex = defaults.object(forKey: "autoAdd") as? Bool ?? true
        newAnimalPopups = defaults.object(forKey: "popups") as? Bool ?? true
        haptics = defaults.object(forKey: "haptics") as? Bool ?? true
        showScientificNames = defaults.object(forKey: "sciNames") as? Bool ?? true
        useLocationFilter = defaults.object(forKey: "locFilter") as? Bool ?? true
        detectNonBirdSounds = defaults.object(forKey: "nonBird") as? Bool ?? true
        hasOnboarded = defaults.bool(forKey: "onboarded")
    }

    private func save() {
        defaults.set(sensitivity.rawValue, forKey: "sensitivity")
        defaults.set(autoAddToWildIndex, forKey: "autoAdd")
        defaults.set(newAnimalPopups, forKey: "popups")
        defaults.set(haptics, forKey: "haptics")
        defaults.set(showScientificNames, forKey: "sciNames")
        defaults.set(useLocationFilter, forKey: "locFilter")
        defaults.set(detectNonBirdSounds, forKey: "nonBird")
        defaults.set(hasOnboarded, forKey: "onboarded")
    }
}
