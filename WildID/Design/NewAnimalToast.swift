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
