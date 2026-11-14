import QuartzCore
import SwiftUI
import UIKit

/// Drives a game at display rate (CADisplayLink), passing the time since the last frame.
@MainActor
final class GameLoop {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    var onTick: ((Double) -> Void)?

    func start() {
        stop()
        let proxy = Proxy { [weak self] t in self?.frame(t) }
        link = CADisplayLink(target: proxy, selector: #selector(Proxy.tick(_:)))
        link?.add(to: .main, forMode: .common)
        last = 0
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    private func frame(_ timestamp: CFTimeInterval) {
        defer { last = timestamp }
        guard last > 0 else { return }
        onTick?(min(1.0 / 20, timestamp - last))      // clamp after hiccups
    }

    private final class Proxy: NSObject {
        let handler: (CFTimeInterval) -> Void
        init(_ handler: @escaping (CFTimeInterval) -> Void) { self.handler = handler }
        @objc func tick(_ link: CADisplayLink) { MainActor.assumeIsolated { handler(link.timestamp) } }
    }
}

/// The Wildling as it appears in games: its 3D model render later; for now its real photo in a
/// round frame (the 3D models are coming soon).
struct GameSprite {
    let image: UIImage?
    let tint: Color
    let symbol: String

    func draw(in ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.fill(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(.white))
        var inner = ctx
        inner.clip(to: Path(ellipseIn: rect))
        if let image {
            inner.draw(Image(uiImage: image), in: rect)
        } else {
            inner.fill(Path(ellipseIn: rect), with: .color(tint))
            inner.draw(Text(Image(systemName: symbol)).font(.system(size: radius)).foregroundStyle(.white), at: center)
        }
    }
}

/// Picker → countdown → game → result, for one Wildling.
struct GameHostView: View {
    let entry: WildIndexEntry
    var preselected: WildGame? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionManager.self) private var collection

    enum Phase: Equatable { case pick, countdown(Int), playing, result(score: Int, food: Int) }
    @State private var game: WildGame?
    @State private var phase: Phase = .pick
    @State private var photo: UIImage?

    private var sprite: GameSprite { GameSprite(image: photo, tint: entry.group.tint, symbol: entry.group.symbol) }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .pick: picker
                case .countdown(let n): countdown(n)
                case .playing: playing
                case .result(let score, let food): result(score: score, food: food)
                }
            }
            .navigationTitle(game?.title ?? "Play with \(entry.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .playing ? "Give up" : "Close") {
                        if phase == .playing, let game { finish(score: game == .maze ? 0 : 0) } else { dismiss() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(phase == .playing)
        .task {
            if let url = entry.photoURL { photo = await ImagePipeline.shared.image(for: url, maxPixel: 300) }
            if let preselected, entry.canPlayToday { begin(preselected) }
        }
    }

    // MARK: Phases

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    SpeciesThumb(url: entry.photoURL, group: entry.group, size: 56, corner: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pick today's game").font(.system(size: 22, weight: .heavy, design: .rounded))
                        Text("One game a day for \(entry.displayName). Reach the goal to win food.")
                            .font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }
                }
                ForEach(WildGame.allCases) { g in
                    Button { begin(g) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: g.symbol).font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .background(LinearGradient(colors: [Theme.moss, Theme.mossDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(g.title).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.primary)
                                Text(g.howTo).font(.caption).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.leading)
                                Label(g.goal, systemImage: "flag.checkered").font(.caption.weight(.semibold)).foregroundStyle(Theme.moss)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(!entry.canPlayToday)
                }
                if !entry.canPlayToday, let last = entry.lastPlayedAt {
                    Label("Already played today. Next game \(PlayRules.nextPlay(after: last).formatted(.relative(presentation: .named)))",
                          systemImage: "moon.zzz.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(Theme.gutter)
        }
        .background(Theme.groupedBackground)
    }

    private func countdown(_ n: Int) -> some View {
        VStack(spacing: 16) {
            Spacer()
            if let game {
                Text(game.goal).font(.system(size: 20, weight: .bold, design: .rounded))
                Text(game.howTo).font(.subheadline).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center).padding(.horizontal, 30)
            }
            Text(n > 0 ? "\(n)" : "Go!").font(.system(size: 90, weight: .heavy, design: .rounded)).foregroundStyle(Theme.moss)
                .contentTransition(.numericText(value: Double(n)))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var playing: some View {
        switch game {
        case .run: RunGameView(sprite: sprite) { finish(score: $0) }
        case .fishing: FishingGameView(sprite: sprite, bonus: PlayRules.fishingBonus(for: entry.group)) { finish(score: $0) }
        case .dash: DashGameView(sprite: sprite) { finish(score: $0) }
        case .pop: PopGameView(sprite: sprite) { finish(score: $0) }
        case .maze: MazeGameView(sprite: sprite) { finish(score: $0) }
        case nil: EmptyView()
        }
    }

    private func result(score: Int, food: Int) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: food > 0 ? "takeoutbag.and.cup.and.straw.fill" : "moon.zzz.fill")
                .font(.system(size: 70, weight: .bold))
                .foregroundStyle(food > 0 ? Theme.moss : Theme.secondaryText)
                .symbolEffect(.bounce, value: food)
            Text(food > 0 ? "You won \(food) food!" : "Not this time").font(.system(size: 30, weight: .heavy, design: .rounded))
            if let game {
                Text("Score: \(score) \(game.unit) · goal: \(game.goal.lowercased())")
                    .font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
            Text(food > 0 ? "Feed it to \(entry.displayName) on its page for +\(PlayRules.feedXP) XP per meal."
                          : "\(entry.displayName) can play again tomorrow.")
                .font(.body).multilineTextAlignment(.center).padding(.horizontal, 30)
            Spacer()
            Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle()).padding(Theme.gutter)
        }
    }

    // MARK: Flow

    private func begin(_ g: WildGame) {
        guard collection.startGame(entry, game: g) else { return }
        game = g
        Task { @MainActor in
            for n in stride(from: 3, through: 0, by: -1) {
                withAnimation(.snappy) { phase = .countdown(n) }
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
            phase = .playing
        }
    }

    private func finish(score: Int) {
        guard let game, phase == .playing else { return }
        let food = collection.finishGame(entry, game: game, score: score)
        withAnimation(.spring(response: 0.45)) { phase = .result(score: score, food: food) }
    }
}
