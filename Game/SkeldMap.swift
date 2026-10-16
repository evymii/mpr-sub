import UIKit
import SpriteKit

/// A room on The Skeld.
struct Room {
    let name: String
    let rect: CGRect        // world coordinates (points)
    let cameraPoint: CGPoint // where the CCTV camera looks at
}

/// Port of the Unity project's Skeld map: rooms + corridors, a walkability grid
/// for collision, a pre-rendered floor texture, and a navigation graph for bots.
final class SkeldMap {

    // World is ~2400 x 1500 points. y grows upward.
    static let worldSize = CGSize(width: 2400, height: 1500)

    let rooms: [Room] = [
        Room(name: "Upper Engine", rect: CGRect(x: 190, y: 1040, width: 300, height: 240), cameraPoint: CGPoint(x: 340, y: 1160)),
        Room(name: "Reactor",      rect: CGRect(x: 60,  y: 580,  width: 280, height: 360), cameraPoint: CGPoint(x: 200, y: 760)),
        Room(name: "Lower Engine", rect: CGRect(x: 190, y: 220,  width: 300, height: 240), cameraPoint: CGPoint(x: 340, y: 340)),
        Room(name: "Security",     rect: CGRect(x: 410, y: 660,  width: 200, height: 200), cameraPoint: CGPoint(x: 510, y: 760)),
        Room(name: "MedBay",       rect: CGRect(x: 680, y: 860,  width: 260, height: 240), cameraPoint: CGPoint(x: 810, y: 980)),
        Room(name: "Cafeteria",    rect: CGRect(x: 990, y: 940,  width: 500, height: 400), cameraPoint: CGPoint(x: 1240, y: 1140)),
        Room(name: "Weapons",      rect: CGRect(x: 1650, y: 1040, width: 280, height: 260), cameraPoint: CGPoint(x: 1790, y: 1170)),
        Room(name: "O2",           rect: CGRect(x: 1770, y: 800,  width: 200, height: 160), cameraPoint: CGPoint(x: 1870, y: 880)),
        Room(name: "Navigation",   rect: CGRect(x: 2060, y: 640,  width: 220, height: 240), cameraPoint: CGPoint(x: 2170, y: 760)),
        Room(name: "Shields",      rect: CGRect(x: 1640, y: 240,  width: 260, height: 240), cameraPoint: CGPoint(x: 1770, y: 360)),
        Room(name: "Communications", rect: CGRect(x: 1390, y: 90, width: 240, height: 180), cameraPoint: CGPoint(x: 1510, y: 180)),
        Room(name: "Storage",      rect: CGRect(x: 870, y: 90,  width: 320, height: 420), cameraPoint: CGPoint(x: 1030, y: 300)),
        Room(name: "Admin",        rect: CGRect(x: 1230, y: 520, width: 320, height: 240), cameraPoint: CGPoint(x: 1390, y: 640)),
        Room(name: "Electrical",   rect: CGRect(x: 520, y: 300,  width: 280, height: 240), cameraPoint: CGPoint(x: 660, y: 420)),
    ]

    // Corridors as rects (inclusive walkable area, overlapping the rooms they join).
    let corridors: [CGRect] = [
        // Upper Engine <-> Reactor (left vertical)
        CGRect(x: 200, y: 880, width: 110, height: 200),
        // Reactor <-> Lower Engine (left vertical)
        CGRect(x: 200, y: 420, width: 110, height: 200),
        // Security stub from the left vertical corridor
        CGRect(x: 290, y: 730, width: 140, height: 100),
        // Upper Engine <-> MedBay top corridor (west half)
        CGRect(x: 400, y: 1170, width: 420, height: 110),
        // MedBay stub (down from top corridor into MedBay)
        CGRect(x: 690, y: 950, width: 110, height: 260),
        // MedBay <-> Cafeteria top corridor (east half)
        CGRect(x: 830, y: 1170, width: 260, height: 110),
        // Cafeteria <-> Weapons
        CGRect(x: 1460, y: 1150, width: 220, height: 110),
        // Weapons <-> O2 corner corridor
        CGRect(x: 1810, y: 880, width: 110, height: 180),
        // O2 <-> Navigation
        CGRect(x: 1910, y: 800, width: 180, height: 100),
        // Cafeteria <-> Admin (vertical from cafeteria bottom right)
        CGRect(x: 1330, y: 640, width: 110, height: 340),
        // Admin <-> Storage
        CGRect(x: 1080, y: 430, width: 260, height: 110),
        // Storage <-> Electrical
        CGRect(x: 760, y: 380, width: 140, height: 100),
        // Electrical <-> Lower Engine (bottom corridor west)
        CGRect(x: 300, y: 380, width: 250, height: 100),
        // Storage <-> Shields bottom corridor
        CGRect(x: 1160, y: 190, width: 500, height: 110),
        // Shields <-> Navigation (right vertical)
        CGRect(x: 1940, y: 380, width: 110, height: 320),
        // Comms stub (up from bottom corridor)
        CGRect(x: 1470, y: 240, width: 100, height: 120),
        // Admin <-> bottom corridor / comms junction
        CGRect(x: 1430, y: 300, width: 100, height: 240),
    ]

    // MARK: - Walkability grid

    static let cell = 20.0
    let cols: Int
    let rows: Int
    private var blocked: [Bool]

    /// Graph nodes for bot navigation (index -> position).
    private(set) var navNodes: [CGPoint] = []
    private(set) var navEdges: [[Int]] = []

    init() {
        cols = Int(Self.worldSize.width / Self.cell)
        rows = Int(Self.worldSize.height / Self.cell)
        blocked = [Bool](repeating: true, count: cols * rows)

        for r in rooms + corridors.map({ Room(name: "", rect: $0, cameraPoint: .zero) }) {
            markWalkable(r.rect)
        }
        buildNavGraph()
    }

    private func markWalkable(_ rect: CGRect) {
        let x0 = max(0, Int(rect.minX / Self.cell))
        let x1 = min(cols - 1, Int(rect.maxX / Self.cell))
        let y0 = max(0, Int(rect.minY / Self.cell))
        let y1 = min(rows - 1, Int(rect.maxY / Self.cell))
        for gx in x0...x1 where gx >= 0 && gx < cols {
            for gy in y0...y1 where gy >= 0 && gy < rows {
                blocked[gy * cols + gx] = false
            }
        }
    }

    func isWalkable(_ point: CGPoint) -> Bool {
        let gx = Int(point.x / Self.cell), gy = Int(point.y / Self.cell)
        guard gx >= 0, gx < cols, gy >= 0, gy < rows else { return false }
        return !blocked[gy * cols + gx]
    }

    /// True if the straight segment between the points is walkable (sampled).
    func lineWalkable(from a: CGPoint, to b: CGPoint, step: CGFloat = 10) -> Bool {
        let d = hypot(b.x - a.x, b.y - a.y)
        let n = max(1, Int(d / step))
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n)
            if !isWalkable(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)) {
                return false
            }
        }
        return true
    }

    func room(at point: CGPoint) -> Room? {
        rooms.first { $0.rect.insetBy(dx: -8, dy: -8).contains(point) }
    }

    func room(named name: String) -> Room? {
        rooms.first { $0.name == name }
    }

    // MARK: - Collision (circle vs blocked cells), axis-separated like Unity's Rigidbody

    /// Move a circle by delta, sliding along walls. Returns corrected position.
    func move(_ pos: CGPoint, by delta: CGVector, radius: CGFloat) -> CGPoint {
        var p = pos
        // Try X
        var t = CGPoint(x: p.x + delta.dx, y: p.y)
        if circleFits(t, radius: radius) { p = t }
        // Try Y
        t = CGPoint(x: p.x, y: p.y + delta.dy)
        if circleFits(t, radius: radius) { p = t }
        return p
    }

    func circleFits(_ center: CGPoint, radius: CGFloat) -> Bool {
        let probes: [CGPoint] = [
            CGPoint(x: center.x - radius, y: center.y), CGPoint(x: center.x + radius, y: center.y),
            CGPoint(x: center.x, y: center.y - radius), CGPoint(x: center.x, y: center.y + radius),
            CGPoint(x: center.x - radius * 0.7, y: center.y - radius * 0.7),
            CGPoint(x: center.x + radius * 0.7, y: center.y - radius * 0.7),
            CGPoint(x: center.x - radius * 0.7, y: center.y + radius * 0.7),
            CGPoint(x: center.x + radius * 0.7, y: center.y + radius * 0.7),
        ]
        return probes.allSatisfy { isWalkable($0) }
    }

    // MARK: - Navigation graph

    private func buildNavGraph() {
        navNodes = []
        // One node per room center + a few per corridor (ends & middle).
        for r in rooms { navNodes.append(CGPoint(x: r.rect.midX, y: r.rect.midY)) }
        for c in corridors {
            let horizontal = c.width >= c.height
            let mid = CGPoint(x: c.midX, y: c.midY)
            navNodes.append(mid)
            if horizontal {
                navNodes.append(CGPoint(x: c.minX + 15, y: c.midY))
                navNodes.append(CGPoint(x: c.maxX - 15, y: c.midY))
            } else {
                navNodes.append(CGPoint(x: c.midX, y: c.minY + 15))
                navNodes.append(CGPoint(x: c.midX, y: c.maxY - 15))
            }
        }
        // Edge between nodes with a clear straight path.
        navEdges = Array(repeating: [], count: navNodes.count)
        for i in 0..<navNodes.count {
            for j in (i + 1)..<navNodes.count {
                let a = navNodes[i], b = navNodes[j]
                let d = hypot(b.x - a.x, b.y - a.y)
                if d < 720 && lineWalkable(from: a, to: b, step: 24) {
                    navEdges[i].append(j)
                    navEdges[j].append(i)
                }
            }
        }
    }

    /// BFS shortest path (node list) between the nodes nearest to start/goal.
    func path(from start: CGPoint, to goal: CGPoint) -> [CGPoint] {
        guard let s = nearestNode(to: start), let g = nearestNode(to: goal) else { return [] }
        var prev = [Int](repeating: -1, count: navNodes.count)
        var queue = [s]
        var seen = [Bool](repeating: false, count: navNodes.count)
        seen[s] = true
        var head = 0
        while head < queue.count {
            let cur = queue[head]; head += 1
            if cur == g { break }
            for n in navEdges[cur] where !seen[n] {
                seen[n] = true
                prev[n] = cur
                queue.append(n)
            }
        }
        guard seen[g] else { return [] }
        var pathIdx: [Int] = [g]
        var cur = g
        while prev[cur] != -1 { cur = prev[cur]; pathIdx.append(cur) }
        pathIdx.reverse()
        // Drop the first node if we can walk straight to the second one.
        var pts = pathIdx.map { navNodes[$0] }
        if pts.count >= 2 && lineWalkable(from: start, to: pts[1], step: 20) { pts.removeFirst() }
        pts.append(goal)
        return pts
    }

    private func nearestNode(to p: CGPoint) -> Int? {
        var best = -1, bestD = CGFloat.greatestFiniteMagnitude
        for (i, n) in navNodes.enumerated() where isWalkable(n) {
            let d = hypot(n.x - p.x, n.y - p.y)
            if d < bestD { bestD = d; best = i }
        }
        return best >= 0 ? best : nil
    }

    /// Random walkable point near the center of a random room.
    func randomRoomPoint(excluding: String? = nil) -> CGPoint {
        let candidates = rooms.filter { $0.name != excluding }
        let r = candidates.randomElement() ?? rooms[0]
        for _ in 0..<12 {
            let p = CGPoint(x: r.rect.midX + CGFloat.random(in: -r.rect.width * 0.3...r.rect.width * 0.3),
                            y: r.rect.midY + CGFloat.random(in: -r.rect.height * 0.3...r.rect.height * 0.3))
            if circleFits(p, radius: 18) { return p }
        }
        return CGPoint(x: r.rect.midX, y: r.rect.midY)
    }

    // MARK: - Rendering

    private static var cachedFloor: SKTexture?

    /// Renders floors + walls once into a texture (space background is separate).
    func makeFloorTexture(scale: CGFloat = 1.5) -> SKTexture {
        if let cached = Self.cachedFloor { return cached }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: Self.worldSize, format: format)
        let img = renderer.image { ctx in
            let c = ctx.cgContext
            // UIKit renderer is top-down; world space is bottom-up — flip.
            c.translateBy(x: 0, y: Self.worldSize.height)
            c.scaleBy(x: 1, y: -1)

            let floorColor = UIColor(hex: 0xFFFEFB)
            let floorEdge = UIColor(hex: 0xDED6CA)
            let wallColor = UIColor(hex: 0xE9E4DC)
            let wallTop = UIColor(hex: 0xD8D1C6)

            // Pass 1: walls = union of rects inflated by wall thickness.
            let wallThickness: CGFloat = 5
            let wallPath = CGMutablePath()
            for r in rooms.map(\.rect) + corridors {
                wallPath.addRect(r.insetBy(dx: -wallThickness, dy: -wallThickness))
            }
            c.addPath(wallPath)
            c.setFillColor(wallColor.cgColor)
            c.fillPath()

            // Wall top highlight: stroke around inflated union.
            c.addPath(wallPath)
            c.setStrokeColor(wallTop.cgColor)
            c.setLineWidth(3)
            c.strokePath()

            // Pass 2: floors on top.
            let floorPath = CGMutablePath()
            for r in rooms.map(\.rect) + corridors { floorPath.addRect(r) }
            c.addPath(floorPath)
            c.setFillColor(floorColor.cgColor)
            c.fillPath()

            // Floor inner outline + panel grid for detail.
            c.addPath(floorPath)
            c.setStrokeColor(floorEdge.cgColor)
            c.setLineWidth(4)
            c.strokePath()

            c.setLineWidth(2)
            c.setStrokeColor(ThemeColors.text.withAlphaComponent(0.045).cgColor)
            for x in stride(from: 0, through: Self.worldSize.width, by: 80) {
                for y in stride(from: 0, through: Self.worldSize.height, by: 80) {
                    let cellRect = CGRect(x: x, y: y, width: 80, height: 80)
                    if rooms.contains(where: { $0.rect.intersects(cellRect) }) || corridors.contains(where: { $0.intersects(cellRect) }) {
                        c.stroke(cellRect)
                    }
                }
            }

            // Room accents: cafeteria center table ring, reactor glow pads.
            if let cafe = room(named: "Cafeteria")?.rect {
                c.setFillColor(UIColor(hex: 0xEFEBE4).cgColor)
                c.fillEllipse(in: CGRect(x: cafe.midX - 70, y: cafe.midY - 6, width: 140, height: 120))
                c.setFillColor(UIColor(hex: 0xE4DED4).cgColor)
                c.fillEllipse(in: CGRect(x: cafe.midX - 46, y: cafe.midY + 18, width: 92, height: 80))
            }
        }
        let tex = SKTexture(image: img)
        Self.cachedFloor = tex
        return tex
    }
}
