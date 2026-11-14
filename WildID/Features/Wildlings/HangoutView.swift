import SwiftUI

/// Hang out with a Wildling in its own little scene: see it up close, feed it, pet it and start
/// today's game. The meadow is a simple drawn placeholder until a 3D scenery model
/// (`models3d/scene_meadow.usdz`) is published; the Wildling uses its 3D model when available
/// and the "3D model coming soon" placeholder until then.
struct HangoutView: View {
    let entry: WildIndexEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionManager.self) private var collection
    @Environment(LocalRarityStore.self) private var localRarity
    @State private var sceneURL: URL?
    @State private var hop = false
    @State private var hearts: [Heart] = []
    @State private var flyingFood = false
    @State private var playing = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var message: String?

    struct Heart: Identifiable { let id = UUID(); let x: CGFloat }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                scenery(size: geo.size)
                // The Wildling, standing in the meadow.
                PetModelView(scientificName: entry.scientificName, group: entry.group, size: min(geo.size.width * 0.72, 300))
                    .offset(y: hop ? geo.size.height * 0.06 - 40 : geo.size.height * 0.06)
                    .onTapGesture { pet() }
                    .accessibilityLabel("Pet \(entry.displayName)")
                ForEach(hearts) { h in
                    Image(systemName: "heart.fill").font(.system(size: 26)).foregroundStyle(.pink)
                        .offset(x: h.x, y: -geo.size.height * 0.12)
                        .transition(.asymmetric(insertion: .scale.combined(with: .opacity),
                                                removal: .move(edge: .top).combined(with: .opacity)))
                }
                if flyingFood {
                    Image(systemName: "takeoutbag.and.cup.and.straw.fill").font(.system(size: 34)).foregroundStyle(.orange)
                        .transition(.move(edge: .bottom).combined(with: .scale))
                        .offset(y: geo.size.height * 0.1)
                }
                VStack {
                    nameplate
                    Spacer()
                    if let message {
                        Text(message).font(.system(size: 15, weight: .bold, design: .rounded))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .transition(.opacity)
                    }
                    actions
                }
                .padding(.horizontal, 16)
                .padding(.top, geo.safeAreaInsets.top + 8)
                .padding(.bottom, geo.safeAreaInsets.bottom + 12)
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38).background(.black.opacity(0.35), in: Circle())
            }
            .padding(.leading, 16).padding(.top, 6)
            .accessibilityLabel("Close")
        }
        .sheet(isPresented: $playing) { GameHostView(entry: entry) }
        .alert("Nickname", isPresented: $renaming) {
            TextField(entry.commonName, text: $newName)
            Button("Save") { collection.rename(entry, to: newName) }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            await Model3DStore.shared.loadIndex()
            sceneURL = await Model3DStore.shared.modelURL(for: "scene meadow")
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private func scenery(size: CGSize) -> some View {
        if let sceneURL {
            SceneModelView(url: sceneURL)
        } else {
            // Placeholder meadow (simple shapes) until the 3D scenery arrives.
            Canvas { ctx, s in
                ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .linearGradient(
                    Gradient(colors: [Color(red: 0.45, green: 0.68, blue: 0.92), Color(red: 0.78, green: 0.88, blue: 0.95)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height * 0.45)))
                let horizon = s.height * 0.42
                for (i, color) in [Color(red: 0.42, green: 0.6, blue: 0.62), Color(red: 0.36, green: 0.58, blue: 0.45)].enumerated() {
                    var hill = Path()
                    hill.move(to: CGPoint(x: 0, y: horizon + CGFloat(i) * 18))
                    for x in stride(from: 0.0, through: Double(s.width), by: 12) {
                        let y = horizon + CGFloat(i) * 18 - CGFloat(sin(x / (90 + Double(i) * 40) + Double(i)) * 22 + 20)
                        hill.addLine(to: CGPoint(x: x, y: y))
                    }
                    hill.addLine(to: CGPoint(x: s.width, y: s.height)); hill.addLine(to: CGPoint(x: 0, y: s.height)); hill.closeSubpath()
                    ctx.fill(hill, with: .color(color))
                }
                ctx.fill(Path(CGRect(x: 0, y: horizon + 30, width: s.width, height: s.height)), with: .linearGradient(
                    Gradient(colors: [Color(red: 0.46, green: 0.7, blue: 0.36), Color(red: 0.3, green: 0.55, blue: 0.25)]),
                    startPoint: CGPoint(x: 0, y: horizon + 30), endPoint: CGPoint(x: 0, y: s.height)))
                // Trees on the horizon.
                for (i, x) in [0.08, 0.22, 0.78, 0.93].enumerated() {
                    let cx = s.width * x, base = horizon + 26 + CGFloat(i % 2) * 8
                    ctx.fill(Path(CGRect(x: cx - 5, y: base - 30, width: 10, height: 34)), with: .color(Color(red: 0.4, green: 0.28, blue: 0.18)))
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - 34, y: base - 92, width: 68, height: 74)), with: .color(Color(red: 0.24, green: 0.48, blue: 0.24)))
                }
                // Grass tufts and little flowers (fixed positions so they don't jump).
                var rng = GameRandom(seed: 7)
                for _ in 0..<60 {
                    let x = CGFloat(rng.unit()) * s.width, y = horizon + 50 + CGFloat(rng.unit()) * (s.height - horizon - 60)
                    var tuft = Path()
                    for dx in [-5.0, 0, 5] { tuft.move(to: CGPoint(x: x + dx, y: y)); tuft.addLine(to: CGPoint(x: x + dx * 1.6, y: y - 12)) }
                    ctx.stroke(tuft, with: .color(Color(red: 0.25, green: 0.5, blue: 0.2)), lineWidth: 2)
                    if rng.unit() < 0.3 {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 16, width: 6, height: 6)), with: .color(rng.unit() < 0.5 ? .white : .yellow))
                    }
                }
            }
        }
    }

    private var nameplate: some View {
        let tier = localRarity.displayTier(for: entry)
        return VStack(spacing: 6) {
            Button { newName = entry.nickname ?? ""; renaming = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: entry.group.symbol).font(.system(size: 13, weight: .bold))
                    Text(entry.displayName).font(.system(size: 22, weight: .heavy, design: .rounded)).lineLimit(1)
                    Text("·").opacity(0.6)
                    Text("Lv \(entry.level)").font(.system(size: 18, weight: .heavy, design: .rounded))
                    Image(systemName: "pencil").font(.system(size: 12, weight: .bold)).opacity(0.7)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(.black.opacity(0.35), in: Capsule())
            }
            .accessibilityLabel("\(entry.displayName), level \(entry.level). Rename")
            HStack(spacing: 6) {
                if entry.nickname != nil { Text(entry.commonName).font(.caption.weight(.semibold)).foregroundStyle(.white) }
                TierBadge(tier: tier, compact: true, here: localRarity.tier(for: entry) != nil)
                if entry.isHappy { Label("Happy", systemImage: "heart.fill").font(.caption2.weight(.bold)).foregroundStyle(.pink) }
            }
            XPBar(xp: entry.xp, height: 6).frame(width: 180)
        }
        .padding(.top, 34)
    }

    private var actions: some View {
        HStack(spacing: 14) {
            actionButton(symbol: "takeoutbag.and.cup.and.straw.fill", title: "Feed (\(entry.food))", tint: .orange, enabled: entry.food > 0) { feed() }
            actionButton(symbol: "hand.wave.fill", title: "Pet", tint: .pink, enabled: true) { pet() }
            actionButton(symbol: entry.canPlayToday ? "gamecontroller.fill" : "moon.zzz.fill",
                         title: entry.canPlayToday ? "Play" : "Played", tint: Theme.moss, enabled: true) { playing = true }
        }
    }

    private func actionButton(symbol: String, title: String, tint: Color, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 26, weight: .bold)).foregroundStyle(tint)
                    .frame(width: 66, height: 66)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                Text(title).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }
            .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }

    // MARK: Interactions

    private func pet() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) { hop = true }
        withAnimation(.easeOut(duration: 0.3)) { hearts.append(Heart(x: CGFloat.random(in: -60...60))) }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { hop = false }
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation(.easeIn(duration: 0.4)) { if !hearts.isEmpty { hearts.removeFirst() } }
        }
    }

    private func feed() {
        guard collection.feed(entry) else { return }
        withAnimation(.spring(response: 0.4)) { flyingFood = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            withAnimation(.easeOut(duration: 0.2)) { flyingFood = false }
            pet()
            withAnimation { message = "\(entry.displayName) loved it! +\(PlayRules.feedXP) XP" }
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { message = nil }
        }
    }
}
