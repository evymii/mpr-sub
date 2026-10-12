import Foundation
import CoreGraphics
import SpriteKit

/// A player-colored participant (the human or a bot).
final class Participant {
    let crewmate: Crewmate
    let isImpostor: Bool
    var isAlive: Bool = true
    var isPlayer: Bool { crewmate.crewName == "YOU" }

    /// Task ids this participant still has to visit (bots use them as waypoints).
    var remainingTaskIds: [Int] = []

    /// Bots that saw this participant kill (impostors only).
    var witnesses: [String] = []

    init(crewmate: Crewmate, isImpostor: Bool, tasks: [Int]) {
        self.crewmate = crewmate
        self.isImpostor = isImpostor
        self.remainingTaskIds = tasks
    }
}

/// Bot AI. Crew bots walk between their task stations and work there;
/// the impostor bot wanders and kills when its cooldown is up.
final class Bot {
    enum State {
        case idle
        case walking(path: [CGPoint], index: Int)
        case working(until: TimeInterval)
    }

    let participant: Participant
    var state: State = .idle
    private var stateDeadline: TimeInterval = 0
    var killCooldown: TimeInterval = 20
    private var reportDelay: TimeInterval = -1   // >0 when heading toward a body to report
    var reportBodyAt: CGPoint?

    weak var game: GameScene?
    let speed: CGFloat = 165

    init(participant: Participant, game: GameScene) {
        self.participant = participant
        self.game = game
    }

    var position: CGPoint {
        get { participant.crewmate.position }
        set { participant.crewmate.position = newValue }
    }

    func update(_ now: TimeInterval, _ dt: TimeInterval) {
        guard participant.isAlive, let game = game else { return }

        // Heading to a body to report it
        if reportDelay > 0 {
            reportDelay -= dt
            if reportDelay <= 0, let body = reportBodyAt {
                game.beginMeeting(reporter: participant, bodyPosition: body)
                reportBodyAt = nil
                return
            }
        }

        killCooldown = max(0, killCooldown - dt)

        switch state {
        case .idle:
            pickNewGoal(now: now)

        case .walking(var path, var idx):
            let target = path[idx]
            let d = hypot(target.x - position.x, target.y - position.y)
            if d < 14 {
                idx += 1
                if idx >= path.count {
                    state = .working(until: now + TimeInterval.random(in: 3.5...6.5))
                    participant.crewmate.update(dt: dt, moving: false, direction: .zero)
                } else {
                    state = .walking(path: path, index: idx)
                    stepToward(path[idx], dt: dt, game: game)
                }
            } else {
                stepToward(target, dt: dt, game: game)
            }

        case .working(let until):
            participant.crewmate.update(dt: dt, moving: false, direction: .zero)
            if now >= until {
                // Complete a task if this crew bot still has any
                if !participant.isImpostor, !participant.remainingTaskIds.isEmpty {
                    participant.remainingTaskIds.removeFirst()
                    game.botCompletedTask()
                }
                pickNewGoal(now: now)
            }
        }

        // Impostor bot kill logic
        if participant.isImpostor && killCooldown <= 0 {
            tryKill(game: game)
        }

        // Crew bots notice nearby bodies
        if !participant.isImpostor, reportDelay < 0,
           game.bodies.contains(where: { hypot($0.position.x - position.x, $0.position.y - position.y) < 170 }) {
            let body = game.bodies.first { hypot($0.position.x - position.x, $0.position.y - position.y) < 170 }!
            reportBodyAt = body.position
            reportDelay = TimeInterval.random(in: 0.8...2.2)
            state = .idle
        }
    }

    private func stepToward(_ target: CGPoint, dt: TimeInterval, game: GameScene) {
        let dx = target.x - position.x, dy = target.y - position.y
        let d = max(1, hypot(dx, dy))
        let vx = dx / d * speed, vy = dy / d * speed
        let newPos = game.map.move(position, by: CGVector(dx: vx * CGFloat(dt), dy: vy * CGFloat(dt)), radius: 16)
        position = newPos
        participant.crewmate.update(dt: dt, moving: true, direction: CGPoint(x: vx, y: vy))
    }

    private func pickNewGoal(now: TimeInterval) {
        guard let game = game else { return }
        var goal: CGPoint? = nil

        // Prefer walking to one of this bot's remaining task stations
        if !participant.remainingTaskIds.isEmpty, Bool.random() {
            let nextId = participant.remainingTaskIds.first!
            if let st = game.stations.first(where: { $0.id == nextId }) {
                goal = st.position
            }
        }
        if goal == nil { goal = game.map.randomRoomPoint() }
        guard let g = goal else { return }

        let start = position
        if game.map.lineWalkable(from: start, to: g, step: 16) {
            state = .walking(path: [g], index: 0)
        } else if let near = nearestWalkable(from: start) {
            let path = game.map.path(from: near, to: g)
            if path.isEmpty {
                state = .working(until: now + 1.5) // stuck; retry shortly
            } else {
                state = .walking(path: path, index: 0)
            }
        } else {
            state = .working(until: now + 1.5)
        }
    }

    private func nearestWalkable(from p: CGPoint) -> CGPoint? {
        let game_ = game
        for radius in [CGFloat(30), 60, 100, 160] {
            for _ in 0..<8 {
                let a = CGFloat.random(in: 0...(2 * .pi))
                let q = CGPoint(x: p.x + cos(a) * radius, y: p.y + sin(a) * radius)
                if game_?.map.isWalkable(q) == true { return q }
            }
        }
        return nil
    }

    private func tryKill(game: GameScene) {
        // Only kill when the human player isn't standing right there most of
        // the time — leaves a chance to witness the kill from mid range.
        let playerCrew = game.playerParticipant?.crewmate
        for victim in game.participants where !victim.isPlayer && victim.isAlive && !victim.isImpostor {
            let d = hypot(victim.crewmate.position.x - position.x,
                          victim.crewmate.position.y - position.y)
            guard d < 70 else { continue }
            var playerDist = CGFloat.greatestFiniteMagnitude
            if let pc = playerCrew, game.playerParticipant?.isAlive == true {
                playerDist = hypot(pc.position.x - position.x, pc.position.y - position.y)
            }
            if playerDist < 320 && Bool.random(probability: 0.75) { continue } // usually waits

            game.performKill(killer: participant, victim: victim)
            killCooldown = TimeInterval.random(in: 22...34)
            // Flee the scene
            let far = game.map.randomRoomPoint()
            let path = game.map.path(from: position, to: far)
            if !path.isEmpty { state = .walking(path: path, index: 0) }
            return
        }
    }
}

extension Bool {
    static func random(probability: Double) -> Bool {
        Double.random(in: 0...1) < probability
    }
}
