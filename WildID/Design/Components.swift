import SwiftUI

// MARK: - Species visuals

struct SpeciesThumb: View {
    let url: URL?
    var group: AnimalGroup = .other
    var size: CGFloat = 64
    var corner: CGFloat = 10

    var body: some View {
        RemoteImage(url: url, maxPixel: size * 3, placeholderSymbol: group.symbol, tint: group.tint)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

/// Row used in lists (Explore, search, results), modelled on the reference app's species rows.
struct SpeciesRow: View {
    let commonName: String
    let scientificName: String
    let photoURL: URL?
    let group: AnimalGroup
    var inIndex: Bool = false
    var detail: String? = nil
    var trailing: AnyView? = nil
    var showScientific = true

    var body: some View {
        HStack(spacing: 14) {
            SpeciesThumb(url: photoURL, group: group, size: 76, corner: 8)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(commonName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if inIndex {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.moss)
                            .accessibilityLabel("In your Wild Index")
                    }
                }
                if showScientific {
                    ScientificName(name: scientificName, font: .subheadline)
                }
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 0)
            if let trailing { trailing }
        }
        .contentShape(Rectangle())
    }
}

/// Large circular action buttons (Step by Step / Sound / Photo).
struct CircleActionButton: View {
    let title: String
    let symbol: String
    var prominent = false
    var size: CGFloat = 104
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Circle()
                    .fill(prominent ? AnyShapeStyle(Theme.moss.gradient) : AnyShapeStyle(Theme.softFill))
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: size * 0.36, weight: .semibold))
                            .foregroundStyle(prominent ? .white : Color.primary.opacity(0.65))
                    }
                    .shadow(color: prominent ? Theme.moss.opacity(0.35) : .clear, radius: 12, y: 6)
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(prominent ? Theme.moss : .primary.opacity(0.8))
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.moss
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(tint.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.wildTitle)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Theme.secondaryText) }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action).font(.subheadline.weight(.semibold)).tint(Theme.moss)
            }
        }
    }
}

// MARK: - Badges

struct Pill: View {
    let text: String
    var symbol: String? = nil
    var tint: Color = Theme.moss
    var filled = false

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(filled ? .white : tint)
        .background(filled ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.14)), in: Capsule())
    }
}

struct RarityBadge: View {
    let rarity: Rarity
    var body: some View { TierBadge(tier: rarity, compact: true) }
}

/// IUCN Red List category badge.
struct ConservationBadge: View {
    let code: String
    var body: some View {
        Pill(text: "\(code) · \(Self.name(code))", tint: Self.color(code), filled: ["EN", "CR", "EW", "EX"].contains(code))
    }
    static func name(_ code: String) -> String {
        switch code {
        case "LC": "Least Concern"
        case "NT": "Near Threatened"
        case "VU": "Vulnerable"
        case "EN": "Endangered"
        case "CR": "Critically Endangered"
        case "EW": "Extinct in the Wild"
        case "EX": "Extinct"
        case "DD": "Data Deficient"
        default: code
        }
    }
    static func color(_ code: String) -> Color {
        switch code {
        case "LC": Theme.fern
        case "NT": Color(red: 0.55, green: 0.7, blue: 0.2)
        case "VU": Color(red: 0.9, green: 0.65, blue: 0.1)
        case "EN": Color(red: 0.9, green: 0.4, blue: 0.1)
        case "CR": Color(red: 0.8, green: 0.15, blue: 0.15)
        default: Color.gray
        }
    }
}

struct ConfidenceMeter: View {
    let value: Double
    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.softFill)
                    Capsule().fill(color).frame(width: geo.size.width * value)
                }
            }
            .frame(width: 44, height: 6)
            Text("\(Int((value * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
        }
    }
    var color: Color { value >= 0.8 ? Theme.moss : value >= 0.5 ? Theme.fern : Color.orange }
}

// MARK: - Empty / offline states

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.fern)
            Text(title).font(.title3.weight(.bold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.moss)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("Offline — showing saved data. Identification lists and maps need a connection.")
                .font(.footnote)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.gradient)
    }
}

struct ErrorRetryView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.orange)
            Text(message).font(.subheadline).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
            Button("Try again", action: retry).buttonStyle(.bordered).tint(Theme.moss)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Formatting helpers

extension TimeInterval {
    /// 00:08 or 1:02:03
    var clockString: String {
        let total = Int(self.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

extension Date {
    var wildDay: String { formatted(.dateTime.month(.wide).day().year()) }
    var wildShort: String { formatted(.dateTime.month(.abbreviated).day()) }
}
