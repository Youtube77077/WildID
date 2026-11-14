import SwiftUI

// MARK: - Wildling Dash

@MainActor
@Observable
final class DashModel {
    struct Item { var p: CGPoint; let coin: Bool }
    var size: CGSize = .zero
    var tick = 0
    var playerX: CGFloat = 0
    var targetX: CGFloat = 0
    var items: [Item] = []
    var coins = 0
    var hits = 0
    var elapsed = 0.0
    var invulnerable = 0.0
    var over = false
    private var spawnIn = 0.4
    private var rng = GameRandom(seed: UInt64(Date().timeIntervalSince1970))
    let radius: CGFloat = 24
    var playerY: CGFloat { size.height * 0.82 }
    var speed: CGFloat { 280 + CGFloat(elapsed) * 8 }
    var scroll: CGFloat = 0

    func setup(_ s: CGSize) { size = s; playerX = s.width / 2; targetX = playerX }

    func step(_ dt: Double) {
        guard !over, size.width > 0 else { return }
        let dt = CGFloat(dt)
        elapsed += Double(dt)
        invulnerable = max(0, invulnerable - Double(dt))
        scroll += speed * dt
        playerX += (targetX - playerX) * min(1, 12 * dt)
        items = items.map { Item(p: CGPoint(x: $0.p.x, y: $0.p.y + speed * dt), coin: $0.coin) }.filter { $0.p.y < size.height + 30 }
        spawnIn -= Double(dt)
        if spawnIn <= 0 {
            let coin = rng.unit() < 0.55
            items.append(Item(p: CGPoint(x: 30 + CGFloat(rng.unit()) * (size.width - 60), y: -30), coin: coin))
            spawnIn = max(0.28, 0.65 - elapsed / 90) * (0.7 + rng.unit() * 0.6)
        }
        let me = CGPoint(x: playerX, y: playerY)
        items.removeAll { item in
            guard hypot(item.p.x - me.x, item.p.y - me.y) < radius + (item.coin ? 12 : 18) else { return false }
            if item.coin { coins += 1; return true }
            if invulnerable <= 0 { hits += 1; invulnerable = 0.9 }
            return true
        }
        if hits >= 3 || coins >= WildGame.dash.target { over = true }
        tick += 1
    }
}

struct DashGameView: View {
    let sprite: GameSprite
    let onFinish: (Int) -> Void
    @State private var model = DashModel()
    @State private var loop = GameLoop()

    var body: some View {
        let m = model
        let _ = m.tick
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Canvas { ctx, size in
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.86, green: 0.8, blue: 0.62)))
                    ctx.fill(Path(CGRect(x: 0, y: 0, width: 26, height: size.height)), with: .color(Color(red: 0.45, green: 0.66, blue: 0.35)))
                    ctx.fill(Path(CGRect(x: size.width - 26, y: 0, width: 26, height: size.height)), with: .color(Color(red: 0.45, green: 0.66, blue: 0.35)))
                    // Moving track marks.
                    let off = m.scroll.truncatingRemainder(dividingBy: 60)
                    for i in -1..<Int(size.height / 60) + 1 {
                        let y = CGFloat(i) * 60 + off
                        ctx.fill(Path(roundedRect: CGRect(x: size.width / 2 - 3, y: y, width: 6, height: 26), cornerRadius: 3), with: .color(.white.opacity(0.5)))
                    }
                    for it in m.items {
                        if it.coin {
                            ctx.fill(Path(ellipseIn: CGRect(x: it.p.x - 12, y: it.p.y - 12, width: 24, height: 24)), with: .color(Color(red: 1, green: 0.8, blue: 0.2)))
                            ctx.stroke(Path(ellipseIn: CGRect(x: it.p.x - 8, y: it.p.y - 8, width: 16, height: 16)), with: .color(.orange), lineWidth: 2)
                        } else {
                            ctx.fill(Path(roundedRect: CGRect(x: it.p.x - 20, y: it.p.y - 16, width: 40, height: 32), cornerRadius: 12), with: .color(.gray))
                        }
                    }
                    var c2 = ctx
                    if m.invulnerable > 0 { c2.opacity = (Int(m.invulnerable * 10) % 2 == 0) ? 0.4 : 1 }
                    sprite.draw(in: &c2, center: CGPoint(x: m.playerX, y: m.playerY), radius: m.radius)
                }
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in m.targetX = max(40, min(geo.size.width - 40, v.location.x)) })
                GameHUD(primary: "\(m.coins) / \(WildGame.dash.target) coins", secondary: String(repeating: "♥︎", count: max(0, 3 - m.hits)),
                        progress: Double(m.coins) / Double(WildGame.dash.target))
            }
            .onAppear {
                m.setup(geo.size)
                loop.onTick = { dt in
                    m.step(dt)
                    if m.over { loop.stop(); onFinish(m.coins) }
                }
                loop.start()
            }
            .onDisappear { loop.stop() }
        }
    }
}

// MARK: - Wildling Pop

@MainActor
@Observable
final class PopModel {
    static let palette: [Color] = [Color(red: 0.93, green: 0.33, blue: 0.3), Color(red: 0.25, green: 0.6, blue: 0.95),
                                   Color(red: 0.3, green: 0.75, blue: 0.4), Color(red: 1, green: 0.78, blue: 0.2)]
    var size: CGSize = .zero
    var tick = 0
    var board = PopBoard(cols: 8, rows: 7, colors: 4, seed: UInt64(Date().timeIntervalSince1970))
    var current = 0
    var next = 1
    var aim: CGFloat = -.pi / 2
    var shot: (p: CGPoint, v: CGVector, color: Int)?
    var cleared = 0
    var shots = 0
    var drops = 0
    var over = false
    private var rng = GameRandom(seed: UInt64(Date().timeIntervalSince1970) &+ 7)

    var d: CGFloat { size.width / 8 }
    var rowH: CGFloat { d * 0.866 }
    var top: CGFloat { 86 + CGFloat(drops) * rowH }
    var shooter: CGPoint { CGPoint(x: size.width / 2, y: size.height - 70) }
    var dangerY: CGFloat { shooter.y - d * 1.4 }

    func setup(_ s: CGSize) { size = s; current = randomColor(); next = randomColor() }

    func center(_ r: Int, _ c: Int) -> CGPoint {
        CGPoint(x: CGFloat(c) * d + d / 2 + (r % 2 == 0 ? 0 : d / 2), y: top + CGFloat(r) * rowH + d / 2)
    }

    private func randomColor() -> Int {
        let present = Set(board.cells.flatMap { $0.compactMap { $0 } })
        let choices = present.isEmpty ? Array(0..<4) : Array(present)
        return choices[rng.int(choices.count)]
    }

    func setAim(to point: CGPoint) {
        let a = atan2(point.y - shooter.y, point.x - shooter.x)
        aim = max(-.pi + 0.2, min(-0.2, a))
    }

    func fire() {
        guard shot == nil, !over else { return }
        shot = (shooter, CGVector(dx: cos(aim) * 950, dy: sin(aim) * 950), current)
        current = next
        next = randomColor()
    }

    func step(_ dt: Double) {
        guard !over, size.width > 0, var s = shot else { tick += 1; return }
        let r = d / 2
        // Sub-steps so fast shots don't skip past bubbles.
        for _ in 0..<4 {
            s.p.x += s.v.dx * CGFloat(dt) / 4
            s.p.y += s.v.dy * CGFloat(dt) / 4
            if s.p.x < r { s.p.x = r; s.v.dx = abs(s.v.dx) }
            if s.p.x > size.width - r { s.p.x = size.width - r; s.v.dx = -abs(s.v.dx) }
            if s.p.y - r <= top || touchesBubble(s.p) { land(s); shot = nil; tick += 1; return }
        }
        shot = s
        tick += 1
    }

    private func touchesBubble(_ p: CGPoint) -> Bool {
        for (ri, row) in board.cells.enumerated() { for (ci, cell) in row.enumerated() where cell != nil {
            if hypot(center(ri, ci).x - p.x, center(ri, ci).y - p.y) < d * 0.85 { return true }
        } }
        return false
    }

    private func land(_ s: (p: CGPoint, v: CGVector, color: Int)) {
        // Nearest empty cell to where the shot stopped.
        var best: (Int, Int)? = nil
        var bestDist = CGFloat.infinity
        let rows = board.cells.count + 1
        for ri in 0..<rows {
            let width = ri % 2 == 0 ? board.cols : board.cols - 1
            for ci in 0..<width {
                if ri < board.cells.count, board.cells[ri][ci] != nil { continue }
                let dist = hypot(center(ri, ci).x - s.p.x, center(ri, ci).y - s.p.y)
                if dist < bestDist { bestDist = dist; best = (ri, ci) }
            }
        }
        if let (ri, ci) = best { cleared += board.place(color: s.color, row: ri, col: ci) }
        shots += 1
        if shots % 7 == 0 { drops += 1 }
        let lowest = board.lowestRow
        if cleared >= WildGame.pop.target || board.remaining == 0 { over = true }
        else if lowest >= 0, center(lowest, 0).y + d / 2 >= dangerY { over = true }
    }
}

struct PopGameView: View {
    let sprite: GameSprite
    let onFinish: (Int) -> Void
    @State private var model = PopModel()
    @State private var loop = GameLoop()

    var body: some View {
        let m = model
        let _ = m.tick
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Canvas { ctx, size in
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [Color(red: 0.16, green: 0.32, blue: 0.4), Color(red: 0.08, green: 0.18, blue: 0.24)]),
                                                                                          startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                    ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: m.top)), with: .color(.black.opacity(0.25)))
                    ctx.stroke(Path { p in p.move(to: CGPoint(x: 0, y: m.dangerY)); p.addLine(to: CGPoint(x: size.width, y: m.dangerY)) },
                               with: .color(.red.opacity(0.5)), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    let r = m.d / 2 - 1.5
                    for (ri, row) in m.board.cells.enumerated() { for (ci, cell) in row.enumerated() {
                        guard let cell else { continue }
                        let c = m.center(ri, ci)
                        bubble(&ctx, at: c, radius: r, color: PopModel.palette[cell])
                    } }
                    // Aim guide.
                    let s = m.shooter
                    ctx.stroke(Path { p in p.move(to: s); p.addLine(to: CGPoint(x: s.x + cos(m.aim) * 140, y: s.y + sin(m.aim) * 140)) },
                               with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 2, dash: [4, 6]))
                    if let shot = m.shot { bubble(&ctx, at: shot.p, radius: r, color: PopModel.palette[shot.color]) }
                    else { bubble(&ctx, at: s, radius: r, color: PopModel.palette[m.current]) }
                    bubble(&ctx, at: CGPoint(x: s.x + 70, y: s.y + 20), radius: r * 0.6, color: PopModel.palette[m.next])
                    var c2 = ctx
                    sprite.draw(in: &c2, center: CGPoint(x: s.x - 80, y: s.y + 12), radius: 26)
                }
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in m.setAim(to: v.location) }
                    .onEnded { v in m.setAim(to: v.location); m.fire() })
                GameHUD(primary: "\(min(m.cleared, WildGame.pop.target)) / \(WildGame.pop.target) popped", secondary: "Ceiling drops every 7 shots",
                        progress: Double(m.cleared) / Double(WildGame.pop.target))
            }
            .onAppear {
                m.setup(geo.size)
                loop.onTick = { dt in
                    m.step(dt)
                    if m.over { loop.stop(); onFinish(m.cleared) }
                }
                loop.start()
            }
            .onDisappear { loop.stop() }
        }
    }

    private func bubble(_ ctx: inout GraphicsContext, at c: CGPoint, radius r: CGFloat, color: Color) {
        let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: rect), with: .color(color))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.5, y: c.y - r * 0.6, width: r * 0.6, height: r * 0.45)), with: .color(.white.opacity(0.45)))
    }
}

// MARK: - Wildling Maze

@MainActor
@Observable
final class MazeModel {
    let maze: Maze
    var tick = 0
    var cell = 0
    var drawPos: CGPoint = .zero          // in cell units (col, row), animated
    var path: [Int] = []                  // queued cells to slide through
    var treats: Set<Int>
    var treatsEaten = 0
    var elapsed = 0.0
    var over = false
    var reachedExit = false
    let exit: Int

    init(seed: UInt64 = UInt64(Date().timeIntervalSince1970)) {
        maze = Maze(cols: 9, rows: 13, seed: seed)
        exit = maze.cols * maze.rows - 1
        var rng = GameRandom(seed: seed &+ 99)
        var t = Set<Int>()
        while t.count < 5 { let i = 1 + rng.int(maze.cols * maze.rows - 2); t.insert(i) }
        treats = t
    }

    /// Seconds left (each treat adds 5 s).
    var timeLeft: Double { Double(WildGame.maze.target) + Double(treatsEaten) * 5 - elapsed }
    /// Score: seconds taken (lower is better); 0 when time ran out.
    var score: Int { reachedExit ? max(1, Int(ceil(elapsed - Double(treatsEaten) * 5))) : 0 }

    /// Slides in a direction until a junction, a turn or a wall (fewer swipes needed).
    func move(dc: Int, dr: Int) {
        guard !over, path.isEmpty else { return }
        var cur = cell
        var route: [Int] = []
        while true {
            let (c, r) = maze.position(cur)
            let nc = c + dc, nr = r + dr
            guard nc >= 0, nc < maze.cols, nr >= 0, nr < maze.rows else { break }
            let next = maze.index(nc, nr)
            guard maze.canMove(from: cur, to: next) else { break }
            route.append(next)
            cur = next
            // Stop at junctions, dead ends, treats and the exit; corners stop on the next check.
            if maze.open[cur].count != 2 || treats.contains(cur) || cur == exit { break }
        }
        path = route
    }

    func step(_ dt: Double) {
        guard !over else { return }
        elapsed += dt
        if let target = path.first {
            let (tc, tr) = maze.position(target)
            let goal = CGPoint(x: CGFloat(tc), y: CGFloat(tr))
            let dx = goal.x - drawPos.x, dy = goal.y - drawPos.y
            let dist = hypot(dx, dy)
            let stepLen = CGFloat(dt) * 11
            if dist <= stepLen {
                drawPos = goal
                cell = target
                path.removeFirst()
                if treats.remove(cell) != nil { treatsEaten += 1 }
                if cell == exit { reachedExit = true; over = true }
            } else {
                drawPos.x += dx / dist * stepLen
                drawPos.y += dy / dist * stepLen
            }
        }
        if timeLeft <= 0 { over = true }
        tick += 1
    }
}

struct MazeGameView: View {
    let sprite: GameSprite
    let onFinish: (Int) -> Void
    @State private var model = MazeModel()
    @State private var loop = GameLoop()

    var body: some View {
        let m = model
        let _ = m.tick
        VStack(spacing: 0) {
            GameHUD(primary: "\(max(0, Int(ceil(m.timeLeft)))) s left", secondary: "Treats \(m.treatsEaten)/5 · +5 s each",
                    progress: 1 - max(0, m.timeLeft) / Double(WildGame.maze.target + 25))
            GeometryReader { geo in
                let cs = min(geo.size.width / CGFloat(m.maze.cols), geo.size.height / CGFloat(m.maze.rows))
                let origin = CGPoint(x: (geo.size.width - cs * CGFloat(m.maze.cols)) / 2, y: (geo.size.height - cs * CGFloat(m.maze.rows)) / 2)
                Canvas { ctx, _ in
                    let mz = m.maze
                    ctx.fill(Path(CGRect(x: origin.x, y: origin.y, width: cs * CGFloat(mz.cols), height: cs * CGFloat(mz.rows))), with: .color(Color(red: 0.93, green: 0.96, blue: 0.88)))
                    let (ec, er) = mz.position(m.exit)
                    ctx.fill(Path(roundedRect: CGRect(x: origin.x + CGFloat(ec) * cs + 3, y: origin.y + CGFloat(er) * cs + 3, width: cs - 6, height: cs - 6), cornerRadius: 6),
                             with: .color(Theme.moss.opacity(0.6)))
                    for t in m.treats {
                        let (c, r) = mz.position(t)
                        ctx.fill(Path(ellipseIn: CGRect(x: origin.x + (CGFloat(c) + 0.3) * cs, y: origin.y + (CGFloat(r) + 0.3) * cs, width: cs * 0.4, height: cs * 0.4)), with: .color(.orange))
                    }
                    var walls = Path()
                    for i in 0..<(mz.cols * mz.rows) {
                        let (c, r) = mz.position(i)
                        let x = origin.x + CGFloat(c) * cs, y = origin.y + CGFloat(r) * cs
                        if r == 0 || !mz.canMove(from: i, to: i - mz.cols) { walls.move(to: CGPoint(x: x, y: y)); walls.addLine(to: CGPoint(x: x + cs, y: y)) }
                        if c == 0 || !mz.canMove(from: i, to: i - 1) { walls.move(to: CGPoint(x: x, y: y)); walls.addLine(to: CGPoint(x: x, y: y + cs)) }
                        if c == mz.cols - 1 { walls.move(to: CGPoint(x: x + cs, y: y)); walls.addLine(to: CGPoint(x: x + cs, y: y + cs)) }
                        if r == mz.rows - 1 { walls.move(to: CGPoint(x: x, y: y + cs)); walls.addLine(to: CGPoint(x: x + cs, y: y + cs)) }
                    }
                    ctx.stroke(walls, with: .color(Color(red: 0.25, green: 0.4, blue: 0.3)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    var c2 = ctx
                    sprite.draw(in: &c2, center: CGPoint(x: origin.x + (m.drawPos.x + 0.5) * cs, y: origin.y + (m.drawPos.y + 0.5) * cs), radius: cs * 0.36)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 14).onEnded { v in
                    let dx = v.translation.width, dy = v.translation.height
                    if abs(dx) > abs(dy) { m.move(dc: dx > 0 ? 1 : -1, dr: 0) } else { m.move(dc: 0, dr: dy > 0 ? 1 : -1) }
                })
            }
            HStack(spacing: 18) {
                padButton("arrow.left") { m.move(dc: -1, dr: 0) }
                padButton("arrow.up") { m.move(dc: 0, dr: -1) }
                padButton("arrow.down") { m.move(dc: 0, dr: 1) }
                padButton("arrow.right") { m.move(dc: 1, dr: 0) }
            }
            .padding(.vertical, 10)
        }
        .onAppear {
            loop.onTick = { dt in
                m.step(dt)
                if m.over { loop.stop(); onFinish(m.score) }
            }
            loop.start()
        }
        .onDisappear { loop.stop() }
    }

    private func padButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 20, weight: .bold)).frame(width: 54, height: 44)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        }
        .tint(.primary)
    }
}
