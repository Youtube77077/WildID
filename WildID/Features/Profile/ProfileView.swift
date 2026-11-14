import Charts
import SwiftData
import SwiftUI

/// Your explorer profile: level, totals and highlights, all worked out on this iPhone from your
/// Wild Index (no account, nothing uploaded).
struct ProfileView: View {
    @Query(sort: \WildIndexEntry.firstCaughtAt) private var entries: [WildIndexEntry]
    @Query(sort: \SavedRecording.startedAt) private var recordings: [SavedRecording]
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router

    private var catches: [Catch] { entries.flatMap(\.catches) }
    private var totalXP: Int { entries.reduce(0) { $0 + $1.xp } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    totalsGrid
                    if !entries.isEmpty {
                        highlights
                        rarityBreakdown
                        groupBreakdown
                        methodBreakdown
                        activityChart
                    } else {
                        EmptyStateView(symbol: "chart.bar.xaxis", title: "No stats yet",
                                       message: "Catch your first animal with Sound ID, Photo ID or Step by Step and your stats appear here.")
                    }
                    Button { open { router.tab = .wildIndex; router.showAchievements = true } } label: {
                        Label("Achievements", systemImage: "trophy.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Text("Worked out on this iPhone from your Wild Index. Nothing is uploaded.")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 40)
            }
            .background(Theme.groupedBackground)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func open(_ action: @escaping @MainActor () -> Void) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            action()
        }
    }

    // MARK: Header

    private var header: some View {
        let lvl = XPRules.explorerLevel(totalXP: totalXP)
        return HStack(spacing: 16) {
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 9)
                Circle().trim(from: 0, to: lvl.fraction)
                    .stroke(Theme.sunlight, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: -2) {
                    Text("\(lvl.level)").font(.system(size: 34, weight: .heavy, design: .rounded))
                    Text("LEVEL").font(.system(size: 10, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(.white)
            }
            .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.rankTitle(level: lvl.level)).font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85)).textCase(.uppercase)
                Text("\(totalXP.formatted()) XP").font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("\(max(0, lvl.next - totalXP).formatted()) XP to level \(lvl.level + 1)")
                    .font(.footnote).foregroundStyle(.white.opacity(0.85))
                if let first = entries.first?.firstCaughtAt {
                    Text("Exploring since \(first.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.white.opacity(0.75))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(LinearGradient(colors: [Theme.mossDeep, Theme.moss], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.top, 8)
    }

    static func rankTitle(level: Int) -> String {
        switch level {
        case ..<3: "Newcomer"
        case 3..<6: "Explorer"
        case 6..<10: "Tracker"
        case 10..<15: "Naturalist"
        case 15..<25: "Field expert"
        default: "Wildlife legend"
        }
    }

    // MARK: Totals

    private var totalsGrid: some View {
        let days = Set(catches.map { Calendar.current.startOfDay(for: $0.date) })
        let countries = Set(catches.compactMap(\.countryCode)).count
        let places = Set(catches.compactMap(\.placeName)).count
        let hours = recordings.reduce(0) { $0 + $1.duration } / 3600
        let items: [StatItem] = [
            StatItem(value: "\(entries.count)", label: "species", symbol: "square.grid.2x2.fill"),
            StatItem(value: "\(catches.count)", label: "catches", symbol: "scope"),
            StatItem(value: "\(days.count)", label: "days out", symbol: "calendar"),
            StatItem(value: "\(Self.longestStreak(days))", label: "best streak (days)", symbol: "flame.fill"),
            StatItem(value: "\(countries)", label: countries == 1 ? "country" : "countries", symbol: "globe.europe.africa.fill"),
            StatItem(value: "\(places)", label: places == 1 ? "place" : "places", symbol: "mappin.and.ellipse"),
            StatItem(value: "\(Set(entries.compactMap(\.familyName)).count)", label: "families", symbol: "tree.fill"),
            StatItem(value: String(format: hours < 10 ? "%.1f" : "%.0f", hours), label: "hours listened (saved)", symbol: "waveform"),
            StatItem(value: "\(entries.filter { $0.level >= 5 }.count)", label: "Wildlings Lv 5+", symbol: "sparkles"),
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: item.symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.moss)
                    Text(item.value).font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
                    Text(item.label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryText).lineLimit(2)
                }
                .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    /// Longest run of consecutive days with at least one catch.
    static func longestStreak(_ days: Set<Date>) -> Int {
        let sorted = days.sorted()
        var best = sorted.isEmpty ? 0 : 1, run = 1
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            let gap = Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
            run = gap == 1 ? run + 1 : 1
            best = max(best, run)
        }
        return best
    }

    // MARK: Highlights

    private var highlights: some View {
        let rarest = entries.max { ($0.tier.rank, $1.firstCaughtAt) < ($1.tier.rank, $0.firstCaughtAt) }
        let most = entries.max { $0.catches.count < $1.catches.count }
        let top = entries.max { $0.xp < $1.xp }
        let latest = entries.max { $0.lastCaughtAt < $1.lastCaughtAt }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Highlights").font(.system(size: 20, weight: .heavy, design: .rounded))
            if let rarest { highlightRow("Rarest catch", rarest, detail: rarest.tier.title, tier: rarest.tier) }
            if let top { highlightRow("Top Wildling", top, detail: "Lv \(top.level) · \(top.xp) XP") }
            if let most { highlightRow("Most caught", most, detail: "\(most.catches.count)×") }
            if let first = entries.first { highlightRow("First catch", first, detail: first.firstCaughtAt.wildShort) }
            if let latest { highlightRow("Latest catch", latest, detail: latest.lastCaughtAt.wildShort) }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func highlightRow(_ title: String, _ e: WildIndexEntry, detail: String, tier: Rarity? = nil) -> some View {
        HStack(spacing: 12) {
            SpeciesThumb(url: e.photoURL, group: e.group, size: 44, corner: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased()).font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(Theme.secondaryText)
                Text(e.displayName).font(.system(size: 16, weight: .bold, design: .rounded)).lineLimit(1)
            }
            Spacer()
            if let tier { TierBadge(tier: tier, compact: true) } else {
                Text(detail).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    // MARK: Breakdowns

    private func bars(_ title: String, _ rows: [BarRow]) -> some View {
        let maxValue = max(1, rows.map { $0.value }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 20, weight: .heavy, design: .rounded))
            ForEach(rows) { row in
                let label = row.label
                let value = row.value
                let color = row.color
                let symbol = row.symbol
                HStack(spacing: 10) {
                    Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(color).frame(width: 18)
                    Text(label).font(.system(size: 14, weight: .semibold)).frame(width: 96, alignment: .leading).lineLimit(1)
                    GeometryReader { g in
                        Capsule().fill(Theme.softFill)
                            .overlay(alignment: .leading) {
                                Capsule().fill(color.gradient).frame(width: max(value > 0 ? 8 : 0, g.size.width * CGFloat(value) / CGFloat(maxValue)))
                            }
                    }
                    .frame(height: 12)
                    Text("\(value)").font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit()).frame(width: 34, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var rarityBreakdown: some View {
        bars("By rarity (best catch)", Rarity.allCases.reversed().map { t in
            BarRow(label: t.title, value: entries.filter { $0.tier == t }.count, color: t.color, symbol: t.symbol)
        })
    }

    private var groupBreakdown: some View {
        bars("By animal group", AnimalGroup.allCases.compactMap { g in
            let n = entries.filter { $0.group == g }.count
            return (n > 0 || g != .other) ? BarRow(label: g.title, value: n, color: g.tint, symbol: g.symbol) : nil
        })
    }

    private var methodBreakdown: some View {
        bars("How you caught them", CatchMethod.allCases.map { m in
            BarRow(label: m.title, value: catches.filter { $0.method == m }.count, color: Theme.moss, symbol: m.symbol)
        })
    }

    private var activityChart: some View {
        let cal = Calendar.current
        let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        let months = (0..<12).reversed().compactMap { cal.date(byAdding: .month, value: -$0, to: thisMonth) }
        let counts = months.map { m in MonthCount(month: m, count: catches.filter { cal.isDate($0.date, equalTo: m, toGranularity: .month) }.count) }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Catches per month").font(.system(size: 20, weight: .heavy, design: .rounded))
            Chart(counts) { item in
                BarMark(x: .value("Month", item.month, unit: .month), y: .value("Catches", item.count))
                    .foregroundStyle(Theme.moss.gradient)
                    .cornerRadius(4)
            }
            .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
            .frame(height: 150)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct StatItem: Identifiable {
    let value: String
    let label: String
    let symbol: String
    var id: String { label }
}

private struct BarRow: Identifiable {
    let label: String
    let value: Int
    let color: Color
    let symbol: String
    var id: String { label }
}

private struct MonthCount: Identifiable {
    let month: Date
    let count: Int
    var id: Date { month }
}
