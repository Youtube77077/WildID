import SwiftUI

/// WildID design tokens. Colors adapt to light and dark mode.
enum Theme {
    // Brand
    static let moss = Color("Moss")                  // primary brand green
    static let mossDeep = Color(red: 0.13, green: 0.36, blue: 0.24)
    static let fern = Color(red: 0.36, green: 0.62, blue: 0.40)
    static let lichen = Color(red: 0.92, green: 0.95, blue: 0.92)
    static let sunlight = Color(red: 1.00, green: 0.87, blue: 0.35) // "new detection" highlight
    static let sunlightSoft = Color(red: 1.00, green: 0.95, blue: 0.70)
    static let ember = Color(red: 0.66, green: 0.20, blue: 0.10)    // record/stop button

    // Surfaces
    static let background = Color(uiColor: .systemBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let softFill = Color(uiColor: .tertiarySystemFill)
    static let hairline = Color(uiColor: .separator)

    // Text
    static let secondaryText = Color(uiColor: .secondaryLabel)
    static let tertiaryText = Color(uiColor: .tertiaryLabel)

    static let cornerRadius: CGFloat = 16
    static let smallRadius: CGFloat = 10
    static let gutter: CGFloat = 16
}

extension Font {
    /// Large, heavy screen titles in the style of the reference screenshots.
    static let wildLargeTitle = Font.system(size: 34, weight: .heavy, design: .default)
    static let wildTitle = Font.system(size: 24, weight: .bold, design: .default)
    static let wildHeadline = Font.system(size: 17, weight: .semibold)
    static let wildCaps = Font.system(size: 12, weight: .bold).width(.standard)
}

extension View {
    func wildCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    func capsLabel() -> some View {
        self.font(.wildCaps)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(Theme.secondaryText)
    }
}

/// Formats scientific names in italics, as is convention.
struct ScientificName: View {
    let name: String
    var font: Font = .subheadline
    var body: some View {
        Text(name).font(font).italic().foregroundStyle(Theme.secondaryText)
    }
}
