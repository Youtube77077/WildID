import SwiftUI

/// Small, non-blocking "New Animal" card that slides up above the tab bar. It never takes
/// focus or interrupts recording; tapping it opens the species, swiping down dismisses it.
///
/// Animation: the card springs up, the animal's photo pops in with a little twist, sparks and
/// stars burst out in the colour of its rarity tier, a light sweep crosses the card, the XP
/// counts up, and Epic/Legendary catches keep a pulsing glow around the photo.
struct NewAnimalToast: View {
    let event: NewAnimalEvent
    var onTap: () -> Void
    var onDismiss: () -> Void

    @State private var shimmer = false
    @State private var burst = false
    @State private var popped = false
    @State private var glow = false
    @State private var shownXP = 0
    @State private var drag: CGFloat = 0

    private var tier: Rarity { event.tier }
    private var accent: Color { tier.color }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if tier >= .epic {
                    Circle()
                        .fill(tier.color.opacity(0.45))
                        .frame(width: 60, height: 60)
                        .blur(radius: 8)
                        .scaleEffect(glow ? 1.15 : 0.85)
                }
                // Burst: sparks and stars flying outward in the tier colour.
                ForEach(0..<12, id: \.self) { i in
                    Group {
                        if i.isMultiple(of: 3) {
                            Image(systemName: "star.fill").font(.system(size: 8, weight: .black))
                        } else {
                            Capsule().frame(width: 3, height: 9)
                        }
                    }
                    .foregroundStyle(i.isMultiple(of: 2) ? accent : accent.opacity(0.55))
                    .offset(y: burst ? -42 : -20)
                    .rotationEffect(.degrees(Double(i) * 30 + (burst ? 12 : 0)))
                    .opacity(burst ? 0 : 1)
                }
                SpeciesThumb(url: event.species.photoURL, group: event.species.group, size: 50, corner: 25)
                    .overlay(Circle().strokeBorder(accent, lineWidth: 3))
                    .scaleEffect(popped ? 1 : 0.3)
                    .rotationEffect(.degrees(popped ? 0 : -25))
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(event.kind == .levelUp ? "LEVEL UP!" : "NEW ANIMAL")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(tier.color)
                    TierBadge(tier: tier, compact: true)
                }
                Text(event.kind == .levelUp ? "\(event.displayName ?? event.species.commonName) reached Lv \(event.level)" : event.species.commonName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                Text("(\(event.species.scientificName))")
                    .font(.system(size: 13).italic())
                    .foregroundStyle(.black.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                Image(systemName: event.kind == .levelUp ? "arrow.up.circle.fill" : "sparkles")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(tier.color)
                    .symbolEffect(.bounce, value: shimmer)
                if event.xp > 0 {
                    Text("+\(shownXP) XP")
                        .font(.system(size: 12, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(.black.opacity(0.8))
                        .contentTransition(.numericText(value: Double(shownXP)))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // White card; the outline (and the sweep of light) takes the colour of the rarity tier.
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(colors: [tier.color.opacity(0), tier.color.opacity(0.18), tier.color.opacity(0)],
                                             startPoint: .leading, endPoint: .trailing))
                        .offset(x: shimmer ? 280 : -280)
                        .mask(RoundedRectangle(cornerRadius: 20, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(tier.gradient, lineWidth: 3)
                )
                .shadow(color: tier.color.opacity(tier >= .epic ? 0.45 : 0.25), radius: 16, y: 8)
        }
        // Confetti bursting up from the animal's photo. Drawn above the card but ignores touches,
        // so it never gets in the way (Sound ID keeps recording underneath).
        .overlay(alignment: .bottomLeading) {
            CatchConfetti(tier: tier, seed: event.id.hashValue)
                .frame(width: 420, height: 560, alignment: .bottomLeading)
                .offset(x: -16, y: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .offset(y: max(0, drag))
        .gesture(DragGesture().onChanged { drag = $0.translation.height }.onEnded { v in
            if v.translation.height > 40 { onDismiss() } else { withAnimation { drag = 0 } }
        })
        .onTapGesture(perform: onTap)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { popped = true }
            withAnimation(.easeOut(duration: 0.8).delay(0.1)) { burst = true }
            withAnimation(.easeInOut(duration: 1.1).delay(0.2)) { shimmer = true }
            if tier >= .epic { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { glow = true } }
            countUp()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.kind == .levelUp ? "Level up" : "New animal"): \(event.species.commonName), \(tier.title), plus \(event.xp) XP")
        .accessibilityAddTraits(.isButton)
    }

    /// Counts the XP up in a few steps (purely visual).
    private func countUp() {
        let target = event.xp
        guard target > 0 else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            for step in 1...8 {
                withAnimation(.snappy(duration: 0.12)) { shownXP = target * step / 8 }
                try? await Task.sleep(nanoseconds: 70_000_000)
            }
        }
    }
}

/// A one-shot confetti burst (about 2 seconds): pieces fly up and out from the photo, spin,
/// fall back under gravity and fade. Rarer animals get more pieces in their tier colours.
struct CatchConfetti: View {
    let tier: Rarity
    let seed: Int
    @State private var start = Date()

    private struct Piece {
        var vx, vy, spin, size: Double
        var color: Color
        var star: Bool
    }

    private var pieces: [Piece] {
        var rng = SplitMix(seed: UInt64(bitPattern: Int64(seed)))
        let count = [36, 46, 60, 78, 100][tier.rank]
        let palette: [Color] = [tier.color, tier.color.opacity(0.75), Theme.sunlight, .white, Theme.moss]
        return (0..<count).map { _ in
            let angle = Double.pi * (0.18 + 0.64 * rng.unit())          // mostly up, fanning right and left
            let speed = 260 + 380 * rng.unit()
            return Piece(vx: cos(angle) * speed * (rng.unit() < 0.5 ? 1 : 0.55), vy: -sin(angle) * speed,
                         spin: (rng.unit() - 0.5) * 14, size: 5 + 6 * rng.unit(),
                         color: palette[Int(rng.unit() * Double(palette.count)) % palette.count],
                         star: rng.unit() < 0.22)
        }
    }

    var body: some View {
        let pieces = self.pieces
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start)
            Canvas { ctx, size in
                guard t < 2.2 else { return }
                let origin = CGPoint(x: 56, y: size.height - 38)
                for p in pieces {
                    let x = origin.x + p.vx * t
                    let y = origin.y + p.vy * t + 0.5 * 900 * t * t       // gravity
                    let alpha = max(0, 1 - t / 2.2)
                    var piece = ctx
                    piece.opacity = alpha
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(p.spin * t))
                    if p.star {
                        var star = piece.resolve(Image(systemName: "star.fill"))
                        star.shading = .color(p.color)
                        piece.draw(star, in: CGRect(x: -p.size, y: -p.size, width: p.size * 2, height: p.size * 2))
                    } else {
                        piece.fill(Path(roundedRect: CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2), cornerRadius: 1.5),
                                   with: .color(p.color))
                    }
                }
            }
        }
        .onAppear { start = Date() }
    }
}

/// Small deterministic random generator (same confetti for the same pop-up).
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

/// Shows "New Animal" toasts inside any presentation (full-screen covers and sheets sit above
/// the root view, so each needs its own overlay).
struct NewAnimalToastOverlay: ViewModifier {
    @Environment(ToastCenter.self) private var toasts
    var bottomPadding: CGFloat
    var onOpen: (SpeciesRef) -> Void

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let event = toasts.current {
                NewAnimalToast(event: event, onTap: {
                    onOpen(event.species)
                    toasts.dismissCurrent()
                }, onDismiss: { toasts.dismissCurrent() })
                .padding(.bottom, bottomPadding)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: toasts.current?.id)
    }
}

extension View {
    func newAnimalToasts(bottomPadding: CGFloat = 24, onOpen: @escaping (SpeciesRef) -> Void) -> some View {
        modifier(NewAnimalToastOverlay(bottomPadding: bottomPadding, onOpen: onOpen))
    }
}
