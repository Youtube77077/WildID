import SceneKit
import SwiftUI

extension Rarity {
    var color: Color {
        switch self {
        case .common: Color(red: 0.55, green: 0.60, blue: 0.58)
        case .uncommon: Color(red: 0.27, green: 0.66, blue: 0.40)
        case .rare: Color(red: 0.22, green: 0.50, blue: 0.92)
        case .epic: Color(red: 0.62, green: 0.33, blue: 0.90)
        case .legendary: Color(red: 0.96, green: 0.68, blue: 0.12)
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .legendary:
            LinearGradient(colors: [Color(red: 1.0, green: 0.84, blue: 0.35), Color(red: 0.93, green: 0.52, blue: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            LinearGradient(colors: [color.opacity(0.85), color], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var symbol: String {
        switch self {
        case .common: "circle.fill"
        case .uncommon: "diamond.fill"
        case .rare: "star.fill"
        case .epic: "sparkles"
        case .legendary: "crown.fill"
        }
    }
}

/// Game-style rarity badge used across the app.
struct TierBadge: View {
    let tier: Rarity
    var compact = false
    /// Shows a location arrow: this is the tier near where you are now (live), not a locked one.
    var here = false
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: tier.symbol).font(.system(size: compact ? 8 : 10, weight: .heavy))
            Text(tier.title.uppercased()).font(.system(size: compact ? 9 : 11, weight: .heavy, design: .rounded)).tracking(0.6)
                .lineLimit(1).fixedSize()
            if here { Image(systemName: "location.fill").font(.system(size: compact ? 7 : 9, weight: .heavy)).opacity(0.85) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(tier.gradient, in: Capsule())
        .shadow(color: tier.color.opacity(0.35), radius: 4, y: 2)
    }
}

extension AnimalGroup {
    /// Habitat-themed backdrop for the Wildlings tab (sky, pond, desert, ocean…).
    var habitat: LinearGradient {
        let c: [Color] = switch self {
        case .birds: [Color(red: 0.55, green: 0.80, blue: 0.97), Color(red: 0.80, green: 0.93, blue: 0.82), Color(red: 0.45, green: 0.72, blue: 0.36)]
        case .mammals: [Color(red: 0.62, green: 0.80, blue: 0.62), Color(red: 0.36, green: 0.58, blue: 0.33)]
        case .reptiles: [Color(red: 0.99, green: 0.87, blue: 0.62), Color(red: 0.80, green: 0.58, blue: 0.32)]
        case .amphibians: [Color(red: 0.62, green: 0.88, blue: 0.80), Color(red: 0.20, green: 0.55, blue: 0.48)]
        case .fish, .crustaceans: [Color(red: 0.55, green: 0.85, blue: 0.97), Color(red: 0.10, green: 0.38, blue: 0.68)]
        case .insects: [Color(red: 0.95, green: 0.95, blue: 0.65), Color(red: 0.50, green: 0.74, blue: 0.30)]
        case .arachnids: [Color(red: 0.62, green: 0.52, blue: 0.80), Color(red: 0.25, green: 0.18, blue: 0.40)]
        case .molluscs: [Color(red: 0.90, green: 0.82, blue: 0.86), Color(red: 0.40, green: 0.55, blue: 0.62)]
        case .other: [Color(red: 0.75, green: 0.88, blue: 0.80), Color(red: 0.30, green: 0.55, blue: 0.45)]
        }
        return LinearGradient(colors: c, startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - 3D models

/// Downloads optional 3D models (USDZ) published in the repository's `models3d/` folder.
/// Until a species has a model, the Wildlings tab shows a placeholder.
@MainActor
@Observable
final class Model3DStore {
    static let shared = Model3DStore()
    private(set) var available: Set<String> = []
    private var loadedIndex = false
    private let base = AppConfig.dataBaseURL.replacingOccurrences(of: "/data", with: "/models3d")

    static func slug(_ scientificName: String) -> String {
        scientificName.lowercased().replacingOccurrences(of: " ", with: "_")
    }

    func loadIndex() async {
        guard !loadedIndex, let url = URL(string: "\(base)/index.json") else { return }
        loadedIndex = true
        struct Index: Decodable { let models: [String] }
        if let index = try? await HTTPClient.shared.get(Index.self, from: url, maxAge: 60 * 60 * 12) {
            available = Set(index.models)
        }
    }

    func hasModel(_ scientificName: String) -> Bool { available.contains(Self.slug(scientificName)) }

    /// Local file URL of the model, downloading it once.
    func modelURL(for scientificName: String) async -> URL? {
        let slug = Self.slug(scientificName)
        guard available.contains(slug), let remote = URL(string: "\(base)/\(slug).usdz") else { return nil }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Models3D", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let local = dir.appendingPathComponent("\(slug).usdz")
        if FileManager.default.fileExists(atPath: local.path) { return local }
        guard let (data, response) = try? await URLSession.shared.data(from: remote),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        try? data.write(to: local)
        return local
    }
}

/// Shows the species' 3D model (rotatable) when one exists, otherwise a clean placeholder.
struct PetModelView: View {
    let scientificName: String
    let group: AnimalGroup
    var size: CGFloat = 220
    @State private var modelURL: URL?
    @State private var bob = false

    var body: some View {
        ZStack {
            Ellipse()
                .fill(.black.opacity(0.18))
                .frame(width: size * 0.62, height: size * 0.12)
                .blur(radius: 6)
                .offset(y: size * 0.42)
            if let modelURL {
                SceneModelView(url: modelURL)
                    .frame(width: size, height: size)
            } else {
                ModelPlaceholder(group: group, size: size)
                    .offset(y: bob ? -4 : 4)
            }
        }
        .frame(width: size, height: size)
        .task(id: scientificName) {
            await Model3DStore.shared.loadIndex()
            modelURL = await Model3DStore.shared.modelURL(for: scientificName)
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { bob = true } }
        .accessibilityLabel(modelURL == nil ? "3D model coming soon" : "3D model")
    }
}

/// Placeholder used until a real 3D model is available. Deliberately abstract — no fake model.
struct ModelPlaceholder: View {
    let group: AnimalGroup
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.85), .white.opacity(0.15)], center: .center, startRadius: 4, endRadius: size * 0.45))
                .frame(width: size * 0.78, height: size * 0.78)
            Circle()
                .strokeBorder(.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                .frame(width: size * 0.78, height: size * 0.78)
            VStack(spacing: 6) {
                Image(systemName: group.symbol)
                    .font(.system(size: size * 0.26, weight: .semibold))
                    .foregroundStyle(group.tint.gradient)
                Text("3D MODEL\nCOMING SOON")
                    .font(.system(size: max(8, size * 0.045), weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.black.opacity(0.45))
            }
        }
    }
}

/// SceneKit viewer for USDZ models with auto-rotation and touch rotation.
struct SceneModelView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = .clear
        v.allowsCameraControl = true
        v.autoenablesDefaultLighting = true
        v.antialiasingMode = .multisampling4X
        if let scene = try? SCNScene(url: url) {
            let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 14))
            scene.rootNode.childNodes.forEach { $0.runAction(spin) }
            v.scene = scene
        }
        return v
    }
    func updateUIView(_ uiView: SCNView, context: Context) {}
}

// MARK: - Cards

struct XPBar: View {
    let xp: Int
    var height: CGFloat = 8
    var tint: Color = Color(red: 0.36, green: 0.85, blue: 0.62)
    var body: some View {
        let p = XPRules.progress(forXP: xp)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.08))
                Capsule().fill(tint.gradient).frame(width: max(height, geo.size.width * p.fraction))
            }
        }
        .frame(height: height)
    }
}

struct PetCard: View {
    let entry: WildIndexEntry
    @Environment(LocalRarityStore.self) private var localRarity
    var body: some View {
        let tier = localRarity.displayTier(for: entry)
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                entry.group.habitat
                PetModelView(scientificName: entry.scientificName, group: entry.group, size: 120)
                    .padding(.top, 14)
                HStack {
                    Text("Lv \(entry.level)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.35), in: Capsule())
                    Spacer()
                    if entry.isFavorite { Image(systemName: "star.fill").foregroundStyle(.yellow).shadow(radius: 2) }
                }
                .padding(8)
            }
            .frame(height: 150)
            .clipped()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entry.displayName).font(.system(size: 15, weight: .bold, design: .rounded)).lineLimit(1)
                    Spacer(minLength: 2)
                }
                HStack {
                    TierBadge(tier: tier, compact: true, here: localRarity.tier(for: entry) != nil)
                    Spacer()
                    Text("\(entry.xp) XP").font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(Theme.secondaryText)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                XPBar(xp: entry.xp, height: 6)
            }
            .padding(10)
            .background(Theme.card)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(tier.color.opacity(0.6), lineWidth: tier >= .rare ? 2 : 1))
        .shadow(color: tier.color.opacity(tier >= .epic ? 0.35 : 0.1), radius: 8, y: 4)
    }
}

/// Two rarities side by side: live near you now, and the best tier a catch was locked at.
struct RarityPanel: View {
    let entry: WildIndexEntry
    @Environment(LocalRarityStore.self) private var localRarity

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            column(title: "NEAR YOU NOW", symbol: "location.fill") {
                if let here = localRarity.tier(for: entry) {
                    TierBadge(tier: here, here: true)
                    Text(localRarity.placeName ?? "Your location").font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                } else {
                    Text(localRarity.isLoading ? "Checking…" : "Needs location & internet").font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            Divider().frame(height: 54)
            column(title: "BEST CATCH", symbol: "lock.fill") {
                if let best = entry.bestCatch, let tier = best.lockedTier {
                    TierBadge(tier: tier)
                    Text([best.placeName, best.date.wildShort].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                } else {
                    Text("Being checked…").font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func column<C: View>(title: String, symbol: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(Theme.secondaryText)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
