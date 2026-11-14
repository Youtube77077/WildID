import SwiftData
import SwiftUI

/// The Pet Index: the same animals as the Wild Index, shown as companions you level up.
struct PetsView: View {
    @Query(sort: \WildIndexEntry.lastCaughtAt, order: .reverse) private var entries: [WildIndexEntry]
    @Environment(Router.self) private var router

    enum Sort: String, CaseIterable, Identifiable {
        case level = "Highest level", recent = "Recently caught", tier = "Rarity", name = "Name"
        var id: String { rawValue }
    }

    @State private var sort: Sort = .level
    @State private var tierFilter: Rarity? = nil
    @State private var showRules = false

    private var totalXP: Int { entries.reduce(0) { $0 + $1.xp } }

    private var visible: [WildIndexEntry] {
        var list = entries.filter { tierFilter == nil || $0.tier == tierFilter }
        switch sort {
        case .level: list.sort { ($0.xp, $0.lastCaughtAt) > ($1.xp, $1.lastCaughtAt) }
        case .recent: list.sort { $0.lastCaughtAt > $1.lastCaughtAt }
        case .tier: list.sort { ($0.tier.rank, $0.xp) > ($1.tier.rank, $1.xp) }
        case .name: list.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    explorerCard
                    tierStrip
                    if entries.isEmpty {
                        VStack(spacing: 14) {
                            ModelPlaceholder(group: .birds, size: 160)
                            Text("No companions yet").font(.system(size: 22, weight: .heavy, design: .rounded))
                            Text("Every animal you catch with Sound ID, Photo ID or Step by Step joins your Pet Index. Catch it again later to earn XP and level it up.")
                                .font(.subheadline).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
                            Button { router.showSoundID = true } label: { Label("Start Sound ID", systemImage: "waveform") }
                                .buttonStyle(PrimaryButtonStyle())
                        }
                        .padding(.top, 20)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 16) {
                            ForEach(visible) { e in
                                NavigationLink(value: PetRoute(key: e.key)) { PetCard(entry: e) }
                                    .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 40)
            }
            .background(Theme.groupedBackground)
            .navigationTitle("Pet Index")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showRules = true } label: { Image(systemName: "questionmark.circle") }
                        .accessibilityLabel("How XP works")
                    Menu {
                        Picker("Sort", selection: $sort) { ForEach(Sort.allCases) { Text($0.rawValue).tag($0) } }
                    } label: { Image(systemName: "arrow.up.arrow.down") }
                }
            }
            .wildDestinations()
            .sheet(isPresented: $showRules) { XPRulesView() }
        }
    }

    private var explorerCard: some View {
        let lvl = XPRules.explorerLevel(totalXP: totalXP)
        return HStack(spacing: 16) {
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 8)
                Circle().trim(from: 0, to: lvl.fraction)
                    .stroke(Theme.sunlight, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: -2) {
                    Text("\(lvl.level)").font(.system(size: 28, weight: .heavy, design: .rounded))
                    Text("LEVEL").font(.system(size: 9, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(.white)
            }
            .frame(width: 78, height: 78)
            VStack(alignment: .leading, spacing: 4) {
                Text("Explorer").font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(.white.opacity(0.8)).textCase(.uppercase)
                Text("\(totalXP.formatted()) XP").font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("\(entries.count) companions · \(max(0, lvl.next - totalXP).formatted()) XP to level \(lvl.level + 1)")
                    .font(.footnote).foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(LinearGradient(colors: [Theme.mossDeep, Theme.moss], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var tierStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { tierFilter = nil } label: {
                    Text("All \(entries.count)").font(.system(size: 13, weight: .bold, design: .rounded))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .foregroundStyle(tierFilter == nil ? .white : .primary)
                        .background(tierFilter == nil ? AnyShapeStyle(Theme.moss) : AnyShapeStyle(Theme.card), in: Capsule())
                }
                ForEach(Rarity.allCases, id: \.self) { t in
                    let n = entries.filter { $0.tier == t }.count
                    Button { tierFilter = (tierFilter == t ? nil : t) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: t.symbol).font(.system(size: 10, weight: .heavy))
                            Text("\(t.title) \(n)").font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .foregroundStyle(tierFilter == t ? .white : t.color)
                        .background(tierFilter == t ? AnyShapeStyle(t.gradient) : AnyShapeStyle(Theme.card), in: Capsule())
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct PetRoute: Hashable, Identifiable {
    let key: String
    var id: String { key }
}

struct PetDetailView: View {
    let entryKey: String
    @Query private var results: [WildIndexEntry]
    @Environment(CollectionManager.self) private var collection
    @State private var renaming = false
    @State private var newName = ""
    @State private var facts: SpeciesFacts?
    @State private var appeared = false

    init(entryKey: String) {
        self.entryKey = entryKey
        _results = Query(filter: #Predicate<WildIndexEntry> { $0.key == entryKey })
    }

    var body: some View {
        if let e = results.first { content(e) } else {
            EmptyStateView(symbol: "pawprint", title: "Not in your Pet Index", message: "This animal was removed.")
        }
    }

    private func content(_ e: WildIndexEntry) -> some View {
        let p = XPRules.progress(forXP: e.xp)
        return ScrollView {
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    e.group.habitat.frame(height: 400)
                    LevelArc(fraction: p.fraction)
                        .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 300, height: 300)
                        .padding(.top, 96)
                    VStack(spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("LV").font(.system(size: 18, weight: .heavy, design: .rounded))
                            Text("\(p.level)").font(.system(size: 44, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 4)
                        .padding(.top, 52)
                        PetModelView(scientificName: e.scientificName, group: e.group, size: 230)
                            .scaleEffect(appeared ? 1 : 0.7)
                            .opacity(appeared ? 1 : 0)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Button {
                        e.isFavorite.toggle()
                        try? collection.context.save()
                        BackupStore.shared.scheduleBackup(context: collection.context)
                    } label: {
                        Image(systemName: e.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(e.isFavorite ? .yellow : .white)
                            .shadow(radius: 3)
                    }
                    .padding(.top, 60).padding(.trailing, 20)
                    .accessibilityLabel(e.isFavorite ? "Remove favourite" : "Mark favourite")
                }

                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        Button { newName = e.nickname ?? ""; renaming = true } label: {
                            HStack(spacing: 8) {
                                Text(e.displayName).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(.primary)
                                Image(systemName: "pencil").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.tertiaryText)
                            }
                        }
                        .accessibilityLabel("Rename \(e.displayName)")
                        if e.nickname != nil {
                            Text(e.commonName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                        }
                        Text(e.scientificName).font(.subheadline).italic().foregroundStyle(Theme.secondaryText)
                        XPBar(xp: e.xp, height: 10).padding(.horizontal, 30).padding(.top, 6)
                        Text(p.level >= XPRules.maxLevel ? "Max level reached" : "\(p.into) / \(p.needed) XP to level \(p.level + 1)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Theme.secondaryText)
                    }

                    HStack {
                        statColumn(value: weightText, label: "WEIGHT")
                        Divider().frame(height: 44)
                        VStack(spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: e.group.symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 34, height: 34).background(e.group.tint, in: Circle())
                                Image(systemName: e.tier.symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 34, height: 34).background(e.tier.gradient, in: Circle())
                            }
                            Text("\(e.group.singular.uppercased()) / \(e.tier.title.uppercased())").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Theme.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        Divider().frame(height: 44)
                        statColumn(value: sizeText, label: "SIZE")
                    }

                    Divider()

                    HStack {
                        statColumn(value: "\(e.catches.count)", label: "CATCHES")
                        Divider().frame(height: 44)
                        statColumn(value: "\(e.xp.formatted())", label: "TOTAL XP")
                        Divider().frame(height: 44)
                        statColumn(value: e.firstCaughtAt.wildShort, label: "MET ON")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("XP history").font(.system(size: 18, weight: .heavy, design: .rounded))
                        ForEach(e.sortedCatches.prefix(12)) { c in
                            HStack {
                                Image(systemName: c.method.symbol).frame(width: 26).foregroundStyle(Theme.moss)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(c.isFirstCatch ? "First catch" : c.method.title).font(.subheadline.weight(.semibold))
                                    Text("\(c.date.formatted(date: .abbreviated, time: .shortened)) · \(c.placeName ?? "Unknown place")")
                                        .font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                                }
                                Spacer()
                                Text(c.xpAwarded > 0 ? "+\(c.xpAwarded) XP" : "cooldown")
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundStyle(c.xpAwarded > 0 ? Theme.moss : Theme.tertiaryText)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .wildCard(padding: 14)

                    HStack(spacing: 12) {
                        NavigationLink(value: WildIndexEntryRoute(key: e.key)) {
                            Label("Wild Index", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        NavigationLink(value: SpeciesRef(scientificName: e.scientificName, commonName: e.commonName, taxonID: e.taxonID, photoURL: e.photoURL, group: e.group)) {
                            Label("Species facts", systemImage: "book").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    Text("Catch \(e.commonName) again (at least an hour apart, up to 3 times a day) to earn more XP. There are no battles — your companions only grow by exploring.")
                        .font(.caption).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
                }
                .padding(20)
                .background(Theme.background, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
                .offset(y: -28)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appeared = true } }
        .task { facts = try? await WikidataAPI().facts(scientificName: e.scientificName) }
        .alert("Nickname", isPresented: $renaming) {
            TextField(e.commonName, text: $newName)
            Button("Save") { collection.rename(e, to: newName) }
            Button("Reset", role: .destructive) { collection.rename(e, to: nil) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Give your \(e.commonName) a name. Its real species name stays in the Wild Index.") }
    }

    private var weightText: String { facts?.measures.first { $0.label == "Mass" }?.value.components(separatedBy: " – ").last ?? "—" }
    private var sizeText: String {
        (facts?.measures.first { $0.label == "Length" } ?? facts?.measures.first { $0.label == "Height" })?.value.components(separatedBy: " – ").last ?? "—"
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 20, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Semicircular level-progress arc with a marker (drawn above the companion).
struct LevelArc: Shape {
    var fraction: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r = rect.width / 2
        p.addArc(center: center, radius: r, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        let angle = Angle.degrees(180 + 180 * min(1, max(0, fraction)))
        let dot = CGPoint(x: center.x + r * CGFloat(Foundation.cos(angle.radians)), y: center.y + r * CGFloat(Foundation.sin(angle.radians)))
        p.addEllipse(in: CGRect(x: dot.x - 6, y: dot.y - 6, width: 12, height: 12))
        return p
    }
}

struct XPRulesView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Earning XP") {
                    ForEach(Rarity.allCases, id: \.self) { t in
                        HStack {
                            TierBadge(tier: t)
                            Spacer()
                            Text("first catch +\(XPRules.firstCatchXP(t)) · again +\(XPRules.repeatXP(t))").font(.footnote.monospacedDigit())
                        }
                    }
                }
                Section("Fair play") {
                    Label("Repeat catches earn XP at most once per hour per animal, and 3 times a day.", systemImage: "clock")
                    Label("Sound ID and Photo ID earn full XP. Step by Step earns half, manual sightings a quarter.", systemImage: "checkmark.seal")
                    Label("Each animal is added at most once per Sound ID session.", systemImage: "waveform")
                    Label("No battles and nothing to buy — companions grow only by exploring.", systemImage: "leaf")
                }
                Section("Rarity") { Text(Rarity.explanation).font(.footnote) }
                Section("Levels") {
                    Text("Level 2 at 75 XP, level 5 at 750 XP, level 10 at 3,375 XP, up to level \(XPRules.maxLevel). Your Explorer level adds up the XP of all your companions.")
                        .font(.footnote)
                }
            }
            .navigationTitle("How XP works")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
