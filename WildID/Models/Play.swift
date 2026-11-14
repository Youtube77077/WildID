import Foundation

/// The five Wildling mini-games. Each Wildling can play one of them once per day; reaching the
/// goal earns food for that Wildling, missing it means waiting until tomorrow.
enum WildGame: String, CaseIterable, Identifiable, Codable {
    case run, fishing, dash, pop, maze
    var id: String { rawValue }

    var title: String {
        switch self {
        case .run: "Wildling Run"
        case .fishing: "Wildling Fishing"
        case .dash: "Wildling Dash"
        case .pop: "Wildling Pop"
        case .maze: "Wildling Maze"
        }
    }

    var symbol: String {
        switch self {
        case .run: "figure.run"
        case .fishing: "fish.fill"
        case .dash: "arrow.up.forward.circle.fill"
        case .pop: "circle.hexagongrid.fill"
        case .maze: "square.grid.3x3.middle.filled"
        }
    }

    var howTo: String {
        switch self {
        case .run: "Tap to jump over rocks and logs. Grab crumbs on the way."
        case .fishing: "Tap when the marker is in the green zone. The closer to the middle, the rarer the fish."
        case .dash: "Drag left and right to dodge rocks and collect coins. Three bumps and you're out."
        case .pop: "Aim and release to shoot. Match 3 or more of the same colour to pop them."
        case .maze: "Swipe to move. Collect treats and find the exit before time runs out."
        }
    }

    /// The score needed to win (for the maze: reach the exit within this many seconds).
    var target: Int {
        switch self {
        case .run: 400
        case .fishing: 300
        case .dash: 30
        case .pop: 35
        case .maze: 60
        }
    }

    var goal: String {
        switch self {
        case .run: "Run \(target) m"
        case .fishing: "Catch \(target) points of fish in 6 casts"
        case .dash: "Collect \(target) coins"
        case .pop: "Pop \(target) bubbles"
        case .maze: "Reach the exit within \(target) s"
        }
    }

    var unit: String {
        switch self {
        case .run: "m"
        case .fishing: "pts"
        case .dash: "coins"
        case .pop: "bubbles"
        case .maze: "s"
        }
    }
}

/// Daily play and feeding rules. Pure functions so they can be tested.
enum PlayRules {
    /// XP a Wildling gets from one meal.
    static let feedXP = 15

    /// One game per Wildling per calendar day. A clock set back before the last game locks play.
    static func canPlay(lastPlayedAt: Date?, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let last = lastPlayedAt else { return true }
        if now < last { return false }
        return !calendar.isDate(last, inSameDayAs: now)
    }

    /// When the next game unlocks (midnight after the last game).
    static func nextPlay(after last: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: last) ?? last)
    }

    /// Food earned: 0 when the goal is missed, 1 for reaching it, 2 for a great result
    /// (double the goal, or the maze in half the time).
    static func food(for game: WildGame, score: Int) -> Int {
        switch game {
        case .maze:
            guard score > 0, score <= game.target else { return 0 }
            return score <= game.target / 2 ? 2 : 1
        default:
            guard score >= game.target else { return 0 }
            return score >= game.target * 2 ? 2 : 1
        }
    }

    static func won(_ game: WildGame, score: Int) -> Bool { food(for: game, score: score) > 0 }

    /// Fishing bonus: animals at home near water get a wider catch zone.
    static func fishingBonus(for group: AnimalGroup) -> (factor: Double, reason: String?) {
        switch group {
        case .birds, .amphibians, .fish, .crustaceans: (1.4, "Water-lover bonus: wider catch zone")
        case .mammals, .reptiles: (1.15, "Small bonus: slightly wider zone")
        default: (1.0, nil)
        }
    }
}

/// Simple seeded random numbers so games (and tests) are reproducible.
struct GameRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func int(_ n: Int) -> Int { n <= 0 ? 0 : Int(next() % UInt64(n)) }
}

/// A perfect maze (exactly one path between any two cells) made with a depth-first search.
struct Maze {
    let cols: Int
    let rows: Int
    /// Open passages: for each cell index, the set of neighbour indices you can walk to.
    private(set) var open: [Set<Int>]

    init(cols: Int, rows: Int, seed: UInt64) {
        self.cols = cols
        self.rows = rows
        open = Array(repeating: [], count: cols * rows)
        var rng = GameRandom(seed: seed)
        var visited = Array(repeating: false, count: cols * rows)
        var stack = [0]
        visited[0] = true
        while let cell = stack.last {
            let options = neighbours(of: cell).filter { !visited[$0] }
            guard !options.isEmpty else { stack.removeLast(); continue }
            let next = options[rng.int(options.count)]
            open[cell].insert(next)
            open[next].insert(cell)
            visited[next] = true
            stack.append(next)
        }
    }

    func index(_ col: Int, _ row: Int) -> Int { row * cols + col }
    func position(_ i: Int) -> (col: Int, row: Int) { (i % cols, i / cols) }

    func neighbours(of i: Int) -> [Int] {
        let (c, r) = position(i)
        var out: [Int] = []
        if c > 0 { out.append(i - 1) }
        if c < cols - 1 { out.append(i + 1) }
        if r > 0 { out.append(i - cols) }
        if r < rows - 1 { out.append(i + cols) }
        return out
    }

    func canMove(from i: Int, to j: Int) -> Bool { open[i].contains(j) }

    /// Length of the shortest path between two cells (nil if unreachable — never, in a perfect maze).
    func pathLength(from a: Int, to b: Int) -> Int? {
        var dist = [a: 0]
        var queue = [a]
        while !queue.isEmpty {
            let cur = queue.removeFirst()
            if cur == b { return dist[cur] }
            for n in open[cur] where dist[n] == nil {
                dist[n] = dist[cur]! + 1
                queue.append(n)
            }
        }
        return nil
    }
}

/// Bubble board for Wildling Pop: offset hex rows, colours as small integers (nil = empty).
struct PopBoard {
    let cols: Int
    var cells: [[Int?]]

    init(cols: Int, rows: Int, colors: Int, seed: UInt64) {
        self.cols = cols
        var rng = GameRandom(seed: seed)
        cells = (0..<rows).map { r in (0..<(r % 2 == 0 ? cols : cols - 1)).map { _ in rng.int(colors) } }
    }

    func width(ofRow r: Int) -> Int { r % 2 == 0 ? cols : cols - 1 }

    func neighbours(_ r: Int, _ c: Int) -> [(Int, Int)] {
        let even = r % 2 == 0
        let candidates = even
            ? [(r - 1, c - 1), (r - 1, c), (r, c - 1), (r, c + 1), (r + 1, c - 1), (r + 1, c)]
            : [(r - 1, c), (r - 1, c + 1), (r, c - 1), (r, c + 1), (r + 1, c), (r + 1, c + 1)]
        return candidates.filter { $0.0 >= 0 && $0.0 < cells.count && $0.1 >= 0 && $0.1 < width(ofRow: $0.0) }
    }

    mutating func ensureRows(_ n: Int) {
        while cells.count < n { cells.append(Array(repeating: nil, count: width(ofRow: cells.count))) }
    }

    /// Places a bubble and resolves matches. Returns how many bubbles were removed (popped +
    /// dropped because they no longer hang from the top).
    mutating func place(color: Int, row r: Int, col c: Int) -> Int {
        ensureRows(r + 1)
        cells[r][c] = color
        // Same-colour group connected to the new bubble.
        var group: Set<[Int]> = [[r, c]]
        var stack = [(r, c)]
        while let (cr, cc) = stack.popLast() {
            for (nr, nc) in neighbours(cr, cc) where cells[nr][nc] == color && !group.contains([nr, nc]) {
                group.insert([nr, nc]); stack.append((nr, nc))
            }
        }
        guard group.count >= 3 else { return 0 }
        for g in group { cells[g[0]][g[1]] = nil }
        // Drop everything no longer connected to the top row.
        var anchored: Set<[Int]> = []
        stack = (0..<width(ofRow: 0)).compactMap { cells[0][$0] != nil ? (0, $0) : nil }
        stack.forEach { anchored.insert([$0.0, $0.1]) }
        while let (cr, cc) = stack.popLast() {
            for (nr, nc) in neighbours(cr, cc) where cells[nr][nc] != nil && !anchored.contains([nr, nc]) {
                anchored.insert([nr, nc]); stack.append((nr, nc))
            }
        }
        var dropped = 0
        for rr in cells.indices { for cc in cells[rr].indices where cells[rr][cc] != nil && !anchored.contains([rr, cc]) {
            cells[rr][cc] = nil; dropped += 1
        } }
        return group.count + dropped
    }

    var remaining: Int { cells.reduce(0) { $0 + $1.compactMap { $0 }.count } }
    var lowestRow: Int { cells.lastIndex { $0.contains { $0 != nil } } ?? -1 }
}
