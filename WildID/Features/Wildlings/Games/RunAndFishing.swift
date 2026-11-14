import SwiftUI

// MARK: - Wildling Run

@MainActor
@Observable
final class RunModel {
    var size: CGSize = .zero
    var tick = 0
    var playerY: CGFloat = 0          // height above the ground
    var vy: CGFloat = 0
    var obstacles: [CGRect] = []      // x, width, height (y unused)
    var crumbs: [CGPoint] = []        // x, height above ground
    var distance: CGFloat = 0
    var crumbsEaten = 0
    var elapsed: Double = 0
    var over = false
    private var spawnIn: Double = 1.2
    private var crumbIn: Double = 2.0
    private var rng = GameRandom(seed: UInt64(Date().timeIntervalSince1970))

    let radius: CGFloat = 26
    var ground: CGFloat { size.height * 0.78 }
    var playerX: CGFloat { size.width * 0.22 }
    var speed: CGFloat { 300 + CGFloat(elapsed) * 9 }
    /// Metres run (crumbs add a 10 m bonus each).
    var score: Int { Int(distance / 45) + crumbsEaten * 10 }

    func jump() {
        guard !over, playerY <= 0.5 else { return }
        vy = 840
    }

    func step(_ dt: Double) {
        guard !over, size.width > 0 else { return }
        let dt = CGFloat(dt)
        elapsed += Double(dt)
        distance += speed * dt
        vy -= 2300 * dt
        playerY = max(0, playerY + vy * dt)
        if playerY == 0 { vy = 0 }
        obstacles = obstacles.map { $0.offsetBy(dx: -speed * dt, dy: 0) }.filter { $0.maxX > -20 }
        crumbs = crumbs.map { CGPoint(x: $0.x - speed * dt, y: $0.y) }.filter { $0.x > -20 }
        spawnIn -= Double(dt)
        if spawnIn <= 0 {
            let w = 26 + CGFloat(rng.unit()) * 20, h = 30 + CGFloat(rng.unit()) * 32
            obstacles.append(CGRect(x: size.width + 30, y: 0, width: w, height: h))
            spawnIn = max(0.7, 1.7 - elapsed / 60) * (0.75 + rng.unit() * 0.6)
        }
        crumbIn -= Double(dt)
        if crumbIn <= 0 {
            crumbs.append(CGPoint(x: size.width + 20, y: 60 + CGFloat(rng.unit()) * 90))
            crumbIn = 1.6 + rng.unit() * 1.6
        }
        let center = CGPoint(x: playerX, y: ground - radius - playerY)
        for o in obstacles {
            let rect = CGRect(x: o.minX, y: ground - o.height, width: o.width, height: o.height).insetBy(dx: 4, dy: 4)
            let nx = max(rect.minX, min(center.x, rect.maxX)), ny = max(rect.minY, min(center.y, rect.maxY))
            if hypot(center.x - nx, center.y - ny) < radius * 0.9 { over = true }
        }
        crumbs.removeAll { c in
            let hit = hypot(center.x - c.x, center.y - (ground - c.y)) < radius + 10
            if hit { crumbsEaten += 1 }
            return hit
        }
        if score >= WildGame.run.target { over = true }
        tick += 1
    }
}

struct RunGameView: View {
    let sprite: GameSprite
    let onFinish: (Int) -> Void
    @State private var model = RunModel()
    @State private var loop = GameLoop()

    var body: some View {
        let m = model
        let _ = m.tick
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Canvas { ctx, size in
                    ctx.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .linearGradient(Gradient(colors: [Color(red: 0.62, green: 0.84, blue: 0.98), Color(red: 0.86, green: 0.95, blue: 0.9)]),
                                                   startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                    // Rolling hills that drift slowly.
                    let shift = (m.distance * 0.2).truncatingRemainder(dividingBy: 240)
                    for i in -1..<Int(size.width / 240) + 2 {
                        let x = CGFloat(i) * 240 - shift
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: m.ground - 70, width: 300, height: 160)), with: .color(Color(red: 0.55, green: 0.76, blue: 0.48)))
                    }
                    ctx.fill(Path(CGRect(x: 0, y: m.ground, width: size.width, height: size.height - m.ground)), with: .color(Color(red: 0.42, green: 0.62, blue: 0.3)))
                    for o in m.obstacles {
                        let r = CGRect(x: o.minX, y: m.ground - o.height, width: o.width, height: o.height)
                        ctx.fill(Path(roundedRect: r, cornerRadius: 10), with: .color(Color(red: 0.48, green: 0.36, blue: 0.26)))
                        ctx.fill(Path(roundedRect: r.insetBy(dx: 5, dy: 5), cornerRadius: 6), with: .color(Color(red: 0.6, green: 0.46, blue: 0.33)))
                    }
                    for c in m.crumbs {
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 9, y: m.ground - c.y - 9, width: 18, height: 18)), with: .color(.orange))
                    }
                    var c2 = ctx
                    sprite.draw(in: &c2, center: CGPoint(x: m.playerX, y: m.ground - m.radius - m.playerY), radius: m.radius)
                }
                .contentShape(Rectangle())
                .onTapGesture { m.jump() }
                GameHUD(primary: "\(min(m.score, WildGame.run.target)) / \(WildGame.run.target) m", secondary: "Crumbs \(m.crumbsEaten)",
                        progress: Double(m.score) / Double(WildGame.run.target))
            }
            .onAppear {
                m.size = geo.size
                loop.onTick = { dt in
                    m.step(dt)
                    if m.over { loop.stop(); onFinish(m.score) }
                }
                loop.start()
            }
            .onDisappear { loop.stop() }
        }
    }
}

// MARK: - Wildling Fishing

@MainActor
@Observable
final class FishingModel {
    enum Fish: String { case common = "Minnow", uncommon = "Perch", rare = "Golden carp"
        var points: Int { switch self { case .common: 50; case .uncommon: 90; case .rare: 150 } }
        var color: Color { switch self { case .common: .gray; case .uncommon: .green; case .rare: .orange } }
    }
    var tick = 0
    var marker = 0.0
    var direction = 1.0
    var zoneCenter = 0.5
    var zoneHalf = 0.08
    var cast = 1
    var caught: [Fish] = []
    var message: String?
    var over = false
    private var pause = 0.0
    private var rng = GameRandom(seed: UInt64(Date().timeIntervalSince1970))
    let bonus: Double
    static let casts = 6

    init(bonus: Double) {
        self.bonus = bonus
        newZone()
    }

    var score: Int { caught.reduce(0) { $0 + $1.points } }
    var speed: Double { 0.7 + Double(cast) * 0.18 }

    private func newZone() {
        zoneCenter = 0.2 + rng.unit() * 0.6
        zoneHalf = 0.075 * bonus
    }

    func tap() {
        guard !over, pause <= 0 else { return }
        let d = abs(marker - zoneCenter)
        if d <= zoneHalf {
            let fish: Fish = d < zoneHalf * 0.3 ? .rare : (d < zoneHalf * 0.65 ? .uncommon : .common)
            caught.append(fish)
            message = "\(fish.rawValue)! +\(fish.points)"
        } else {
            message = "Missed!"
        }
        pause = 0.9
    }

    func step(_ dt: Double) {
        guard !over else { return }
        if pause > 0 {
            pause -= dt
            if pause <= 0 {
                message = nil
                if cast >= Self.casts { over = true } else { cast += 1; newZone() }
            }
        } else {
            marker += direction * speed * dt
            if marker > 1 { marker = 1; direction = -1 }
            if marker < 0 { marker = 0; direction = 1 }
        }
        tick += 1
    }
}

struct FishingGameView: View {
    let sprite: GameSprite
    let bonus: (factor: Double, reason: String?)
    let onFinish: (Int) -> Void
    @State private var model: FishingModel?
    @State private var loop = GameLoop()

    var body: some View {
        let m = model ?? FishingModel(bonus: bonus.factor)
        let _ = m.tick
        ZStack(alignment: .top) {
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.78, green: 0.9, blue: 0.74)))
                let pond = CGRect(x: size.width * 0.12, y: size.height * 0.22, width: size.width * 0.76, height: size.height * 0.38)
                ctx.fill(Path(ellipseIn: pond), with: .linearGradient(Gradient(colors: [Color(red: 0.35, green: 0.65, blue: 0.9), Color(red: 0.12, green: 0.4, blue: 0.7)]),
                                                                       startPoint: CGPoint(x: 0, y: pond.minY), endPoint: CGPoint(x: 0, y: pond.maxY)))
                // Ripples and the bobber.
                let wobble = sin(Double(m.tick) / 9) * 3
                ctx.stroke(Path(ellipseIn: CGRect(x: pond.midX - 30, y: pond.midY - 8 + wobble, width: 60, height: 16)), with: .color(.white.opacity(0.5)), lineWidth: 2)
                ctx.fill(Path(ellipseIn: CGRect(x: pond.midX - 7, y: pond.midY - 7 + wobble, width: 14, height: 14)), with: .color(.red))
                var c2 = ctx
                sprite.draw(in: &c2, center: CGPoint(x: size.width * 0.18, y: pond.maxY + 40), radius: 34)
                ctx.stroke(Path { p in p.move(to: CGPoint(x: size.width * 0.18 + 20, y: pond.maxY + 15)); p.addLine(to: CGPoint(x: pond.midX, y: pond.midY + wobble)) },
                           with: .color(.black.opacity(0.4)), lineWidth: 1.5)
                // Timing bar.
                let bar = CGRect(x: 24, y: size.height * 0.8, width: size.width - 48, height: 26)
                ctx.fill(Path(roundedRect: bar, cornerRadius: 13), with: .color(.black.opacity(0.15)))
                let zone = CGRect(x: bar.minX + bar.width * (m.zoneCenter - m.zoneHalf), y: bar.minY, width: bar.width * m.zoneHalf * 2, height: bar.height)
                ctx.fill(Path(roundedRect: zone, cornerRadius: 8), with: .color(.green.opacity(0.75)))
                ctx.fill(Path(CGRect(x: zone.midX - 2, y: bar.minY, width: 4, height: bar.height)), with: .color(.yellow))
                let mx = bar.minX + bar.width * m.marker
                ctx.fill(Path(roundedRect: CGRect(x: mx - 4, y: bar.minY - 8, width: 8, height: bar.height + 16), cornerRadius: 4), with: .color(.white))
                // Caught fish row.
                for (i, f) in m.caught.enumerated() {
                    ctx.draw(Text(Image(systemName: "fish.fill")).font(.system(size: 22)).foregroundStyle(f.color),
                             at: CGPoint(x: 40 + CGFloat(i) * 36, y: size.height * 0.72))
                }
                if let msg = m.message {
                    ctx.draw(Text(msg).font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(.white), at: CGPoint(x: pond.midX, y: pond.minY + 30))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { m.tap() }
            GameHUD(primary: "\(m.score) / \(WildGame.fishing.target) pts", secondary: "Cast \(m.cast) of \(FishingModel.casts)" + (bonus.reason.map { " · \($0)" } ?? ""),
                    progress: Double(m.score) / Double(WildGame.fishing.target))
        }
        .onAppear {
            model = m
            loop.onTick = { dt in
                m.step(dt)
                if m.over { loop.stop(); onFinish(m.score) }
            }
            loop.start()
        }
        .onDisappear { loop.stop() }
    }
}

/// Score bar shown on top of every game.
struct GameHUD: View {
    let primary: String
    let secondary: String
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(primary).font(.system(size: 18, weight: .heavy, design: .rounded).monospacedDigit())
                Spacer()
                Text(secondary).font(.caption.weight(.semibold)).lineLimit(1)
            }
            ProgressView(value: min(1, max(0, progress))).tint(Theme.moss)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}
