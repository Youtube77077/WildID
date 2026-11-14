import SwiftUI

/// Small, non-blocking "New Animal" card that slides up above the tab bar. It never takes
/// focus or interrupts recording; tapping it opens the species, swiping down dismisses it.
struct NewAnimalToast: View {
    let event: NewAnimalEvent
    var onTap: () -> Void
    var onDismiss: () -> Void

    @State private var shimmer = false
    @State private var burst = false
    @State private var drag: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                ForEach(0..<8, id: \.self) { i in
                    Capsule()
                        .fill(Theme.sunlight)
                        .frame(width: 3, height: 9)
                        .offset(y: burst ? -34 : -22)
                        .rotationEffect(.degrees(Double(i) * 45))
                        .opacity(burst ? 0 : 1)
                }
                SpeciesThumb(url: event.species.photoURL, group: event.species.group, size: 48, corner: 24)
                    .overlay(Circle().strokeBorder(Theme.sunlight, lineWidth: 2.5))
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(event.kind == .levelUp ? "LEVEL UP!" : "NEW ANIMAL")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(Theme.mossDeep)
                    if event.kind == .newAnimal {
                        TierBadge(tier: event.tier, compact: true)
                    }
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
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.mossDeep)
                    .symbolEffect(.bounce, value: shimmer)
                if event.xp > 0 {
                    Text("+\(event.xp) XP")
                        .font(.system(size: 11, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.mossDeep)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Theme.sunlightSoft, Theme.sunlight], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0)],
                                             startPoint: .leading, endPoint: .trailing))
                        .offset(x: shimmer ? 260 : -260)
                        .mask(RoundedRectangle(cornerRadius: 20, style: .continuous))
                )
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        }
        .padding(.horizontal, 16)
        .offset(y: max(0, drag))
        .gesture(DragGesture().onChanged { drag = $0.translation.height }.onEnded { v in
            if v.translation.height > 40 { onDismiss() } else { withAnimation { drag = 0 } }
        })
        .onTapGesture(perform: onTap)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { burst = true }
            withAnimation(.easeInOut(duration: 1.1).delay(0.15)) { shimmer = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("New animal: \(event.species.commonName), \(event.species.scientificName)")
        .accessibilityAddTraits(.isButton)
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
