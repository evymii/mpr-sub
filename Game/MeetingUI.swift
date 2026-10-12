import UIKit
import SpriteKit

/// The emergency-meeting vote screen (ported from the Among Us flow; the Unity
/// project had roles but no meeting system). Tap a portrait to vote.
/// Lays itself out for the given viewport: wide grid in landscape, a tall
/// 2-column grid in portrait.
final class MeetingOverlay: SKNode {
    enum Phase { case voting, result }

    var onFinished: ((Participant?) -> Void)?  // ejected participant or nil

    private let participants: [Participant]     // alive at meeting start
    private let you: Participant?
    private let reporterName: String
    private let portraitLayout: Bool
    let contentSize: CGSize                     // unscaled bounds, for fit-scaling
    private var votes: [String: Int] = [:]      // voterName -> target index (-1 skip)
    private var phase: Phase = .voting
    private var timer: TimeInterval = 20
    private var timeLeft: TimeInterval = 20
    private let timerLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let statusLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private var resultLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private var selectedTarget: Int? = nil
    private var castYourVote = false
    private var botVoteBadges: [SKNode] = []

    init(participants: [Participant], you: Participant?, reporterName: String, viewport: CGSize) {
        self.participants = participants
        self.you = you
        self.reporterName = reporterName
        self.portraitLayout = viewport.height >= viewport.width
        // Content extent of the laid-out UI (for GameScene's fit-scale); the
        // dark backdrop is oversized and does not count.
        self.contentSize = portraitLayout ? CGSize(width: 360, height: 640) : CGSize(width: 870, height: 460)
        super.init()
        zPosition = 950
        isUserInteractionEnabled = true

        let dark = SKShapeNode(rectOf: CGSize(width: 6000, height: 4000))
        dark.fillColor = UIColor(white: 0, alpha: 0.75)
        dark.strokeColor = .clear
        addChild(dark)

        let panelRect = portraitLayout
            ? CGRect(x: -175, y: -320, width: 350, height: 640)
            : CGRect(x: -430, y: -260, width: 860, height: 520)
        let panel = SKShapeNode(path: CGPath(roundedRect: panelRect, cornerWidth: 24, cornerHeight: 24, transform: nil))
        panel.fillColor = UIColor(red: 0.13, green: 0.15, blue: 0.2, alpha: 1)
        panel.strokeColor = UIColor(red: 0.5, green: 0.53, blue: 0.62, alpha: 1)
        panel.lineWidth = 5
        addChild(panel)

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "EMERGENCY MEETING"
        title.fontSize = portraitLayout ? 20 : 34
        title.fontColor = UIColor(red: 0.98, green: 0.3, blue: 0.3, alpha: 1)
        title.position = portraitLayout ? CGPoint(x: 0, y: 284) : CGPoint(x: 0, y: 212)
        addChild(title)

        statusLabel.text = "\(reporterName) reported a body\nWho is the Impostor?"
        statusLabel.fontSize = portraitLayout ? 14 : 20
        statusLabel.fontColor = .white
        statusLabel.numberOfLines = 2
        statusLabel.position = portraitLayout ? CGPoint(x: 0, y: 252) : CGPoint(x: 0, y: 172)
        addChild(statusLabel)

        timerLabel.fontSize = portraitLayout ? 18 : 26
        timerLabel.fontColor = .white
        timerLabel.position = portraitLayout ? CGPoint(x: 140, y: 284) : CGPoint(x: 390, y: 212)
        addChild(timerLabel)

        buildPortraits()
        buildBottomButtons()

        resultLabel.fontSize = portraitLayout ? 15 : 30
        resultLabel.fontColor = .white
        resultLabel.numberOfLines = 3
        resultLabel.position = portraitLayout ? CGPoint(x: 0, y: -252) : CGPoint(x: 0, y: -120)
        resultLabel.isHidden = true
        addChild(resultLabel)

        // Bots vote after a short think
        for p in participants where !p.isPlayer {
            let delay = TimeInterval.random(in: 2.5...6.0)
            let target = botVoteTarget(p)
            run(.wait(forDuration: delay)) { [weak self] in
                self?.registerVote(voter: p, target: target, fromBot: true)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI construction

    private var portraitNodes: [SKNode] = []

    private func buildPortraits() {
        portraitNodes.forEach { $0.removeFromParent() }
        portraitNodes = []
        let cols = portraitLayout ? 2 : 4
        let cellW: CGFloat = portraitLayout ? 158 : 160
        let cellH: CGFloat = portraitLayout ? 128 : 130
        let stepX: CGFloat = portraitLayout ? 170 : 200
        let stepY: CGFloat = portraitLayout ? 145 : 150
        let gridTop: CGFloat = portraitLayout ? 130 : 120
        let faceSize = portraitLayout ? CGSize(width: 50, height: 64) : CGSize(width: 58, height: 74)
        let alive = participants
        for (i, p) in alive.enumerated() {
            let node = SKNode()
            let col = i % cols, row = i / cols
            node.position = CGPoint(x: -CGFloat(cols - 1) * stepX / 2 + CGFloat(col) * stepX,
                                    y: gridTop - CGFloat(row) * stepY)
            node.name = "vote_\(i)"

            let frame = SKShapeNode(rect: CGRect(x: -cellW / 2, y: -cellH / 2, width: cellW, height: cellH), cornerRadius: 14)
            frame.fillColor = UIColor(white: 0.1, alpha: 1)
            frame.strokeColor = p.isPlayer && you?.isImpostor == false ? UIColor(white: 0.9, alpha: 1) : UIColor(white: 0.35, alpha: 1)
            frame.lineWidth = 3
            node.addChild(frame)

            let face = SKSpriteNode(texture: CrewSheet.shared.texture(color: p.crewmate.color, frame: 0))
            face.size = faceSize
            face.position = CGPoint(x: 0, y: 8)
            node.addChild(face)

            let nameLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            nameLabel.text = p.isPlayer ? "YOU" : p.crewmate.crewName
            nameLabel.fontSize = portraitLayout ? 13 : 17
            nameLabel.fontColor = .white
            nameLabel.position = CGPoint(x: 0, y: -cellH / 2 + 16)
            node.addChild(nameLabel)

            if p.isPlayer && you?.isImpostor == true {
                let imp = SKLabelNode(fontNamed: "AvenirNext-Heavy")
                imp.text = "IMPOSTOR"
                imp.fontSize = portraitLayout ? 10 : 13
                imp.fontColor = UIColor(red: 0.98, green: 0.3, blue: 0.3, alpha: 1)
                imp.position = CGPoint(x: 0, y: 52)
                node.addChild(imp)
            }

            addChild(node)
            portraitNodes.append(node)
        }
    }

    private var confirmButton: SKShapeNode!
    private var skipButton: SKShapeNode!

    private func buildBottomButtons() {
        let bw: CGFloat = portraitLayout ? 144 : 220
        let bh: CGFloat = portraitLayout ? 54 : 64
        let y: CGFloat = portraitLayout ? -288 : -195

        confirmButton = SKShapeNode(rect: CGRect(x: -bw / 2, y: -bh / 2, width: bw, height: bh), cornerRadius: 16)
        confirmButton.fillColor = UIColor(red: 0.2, green: 0.7, blue: 0.35, alpha: 1)
        confirmButton.strokeColor = .clear
        let voteLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        voteLabel.text = "VOTE"
        voteLabel.fontSize = portraitLayout ? 16 : 22
        voteLabel.fontColor = .white
        voteLabel.position = CGPoint(x: 0, y: -8)
        confirmButton.addChild(voteLabel)
        confirmButton.position = CGPoint(x: portraitLayout ? 84 : 120, y: y)
        confirmButton.name = "confirm_vote"
        confirmButton.alpha = 0.35
        addChild(confirmButton)

        skipButton = SKShapeNode(rect: CGRect(x: -bw / 2, y: -bh / 2, width: bw, height: bh), cornerRadius: 16)
        skipButton.fillColor = UIColor(white: 0.35, alpha: 1)
        skipButton.strokeColor = .clear
        let skipLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        skipLabel.text = "SKIP VOTE"
        skipLabel.fontSize = portraitLayout ? 16 : 22
        skipLabel.fontColor = .white
        skipLabel.position = CGPoint(x: 0, y: -8)
        skipButton.addChild(skipLabel)
        skipButton.position = CGPoint(x: portraitLayout ? -84 : -140, y: y)
        skipButton.name = "skip_vote"
        addChild(skipButton)
    }

    // MARK: - Interaction

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard phase == .voting, !castYourVote, let t = touches.first else { return }
        let hit = atPoint(t.location(in: self))
        if let name = hit.name {
            if name == "confirm_vote", let sel = selectedTarget {
                registerVote(voter: you, target: sel, fromBot: false)
                return
            }
            if name == "skip_vote" {
                registerVote(voter: you, target: -1, fromBot: false)
                return
            }
            if name.hasPrefix("vote_"), let idx = Int(name.dropFirst(5)) {
                selectedTarget = idx
                highlightSelection(idx)
                confirmButton.alpha = 1
            }
        }
    }

    private func highlightSelection(_ idx: Int) {
        for (i, node) in portraitNodes.enumerated() {
            if let frame = node.children.first as? SKShapeNode {
                frame.strokeColor = i == idx ? UIColor(red: 1, green: 0.8, blue: 0.2, alpha: 1) : UIColor(white: 0.35, alpha: 1)
                frame.lineWidth = i == idx ? 6 : 3
            }
        }
    }

    // MARK: - Vote resolution

    /// How a bot votes. Witnesses of the actual kill vote the impostor;
    /// others pick randomly (biased slightly against quiet players = the human).
    private func botVoteTarget(_ bot: Participant) -> Int {
        if !bot.isImpostor, !bot.witnesses.isEmpty {
            for (idx, p) in participants.enumerated() where p.isImpostor { return idx }
        }
        if bot.isImpostor {
            // Frame someone alive that isn't the impostor; sometimes skip
            if Bool.random(probability: 0.8) {
                let innocents = participants.enumerated().filter { !$0.element.isImpostor }
                return innocents.randomElement()?.offset ?? -1
            }
            return -1
        }
        if Bool.random(probability: 0.35) { return -1 }
        // Innocent suspicion stays between the bots — the human is never a
        // random-vote target (witness votes above still target the impostor).
        let others = participants.enumerated().filter { !$0.element.isPlayer }
        return others.randomElement()?.offset ?? -1
    }

    private func registerVote(voter: Participant?, target: Int, fromBot: Bool) {
        if fromBot {
            guard let voter = voter, !votes.keys.contains(voter.crewmate.crewName) else { return }
            votes[voter.crewmate.crewName] = target
            addBadge(target: target, color: voter.crewmate.color.uiColor)
        } else {
            guard let voter = voter else { return }
            votes[voter.crewmate.crewName] = target
            castYourVote = true
            confirmButton.alpha = 0.35
            statusLabel.text = "Vote cast. Waiting for others…"
        }
        let allBotsVoted = participants.filter { !$0.isPlayer }.allSatisfy { votes[$0.crewmate.crewName] != nil }
        let humanVoted = you == nil || castYourVote
        if allBotsVoted && humanVoted {
            resolveVotes()
        }
    }

    private func addBadge(target: Int, color: UIColor) {
        guard target >= 0 && target < portraitNodes.count else { return }
        let badge = SKShapeNode(circleOfRadius: portraitLayout ? 7 : 8)
        badge.fillColor = color
        badge.strokeColor = UIColor(white: 0, alpha: 0.4)
        let count = portraitNodes[target].children.filter { $0.name == "badge" }.count
        let stepX: CGFloat = portraitLayout ? 22 : 26
        badge.position = CGPoint(x: -CGFloat(portraitLayout ? 4 : 5) * stepX / 2 + CGFloat(count % 5) * stepX + stepX / 2,
                                 y: 44 - CGFloat(count / 5) * 24)
        badge.name = "badge"
        portraitNodes[target].addChild(badge)
        botVoteBadges.append(badge)
    }

    private func resolveVotes() {
        guard phase == .voting else { return }
        phase = .result

        var tally = [Int](repeating: 0, count: participants.count)
        var skips = 0
        for (_, t) in votes { if t >= 0 && t < tally.count { tally[t] += 1 } else { skips += 1 } }
        let maxVotes = tally.max() ?? 0
        let top = tally.enumerated().filter { $0.element == maxVotes }
        let ejected: Participant?
        if maxVotes == 0 || skips >= maxVotes || top.count > 1 {
            ejected = nil
            resultLabel.text = "No one was ejected. (Skipped)"
        } else {
            let idx = top[0].offset
            let e = participants[idx]
            ejected = e
            let wasImpostor = e.isImpostor
            resultLabel.text = "\(e.isPlayer ? "You were" : "\(e.crewmate.crewName) was") ejected.\n\(wasImpostor ? "\(e.crewmate.crewName) was the Impostor." : "\(e.crewmate.crewName) was not the Impostor.")"
        }
        resultLabel.numberOfLines = 2
        resultLabel.isHidden = false
        statusLabel.isHidden = true
        confirmButton.isHidden = true
        skipButton.isHidden = true
        timerLabel.isHidden = true

        run(.wait(forDuration: 3.2)) { [weak self] in
            self?.onFinished?(ejected)
            self?.removeFromParent()
        }
    }

    func update(_ dt: TimeInterval) {
        guard phase == .voting else { return }
        timeLeft -= dt
        timerLabel.text = "\(Int(timeLeft))s"
        if timeLeft <= 0 { resolveVotes() }
    }
}
