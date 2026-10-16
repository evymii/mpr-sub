import UIKit
import SpriteKit

/// Port of the Unity minigame canvases (CardUI / DownloadUI): a modal panel
/// that opens on USE, freezes the player, and reports completion.
class MinigameOverlay: SKNode {
    var onComplete: (() -> Void)?
    var onClose: (() -> Void)?

    let panel = SKShapeNode()
    let titleLabel = SKLabelNode(fontNamed: ThemeFonts.heavy)
    let closeButton = SKNode()

    /// Natural (unscaled) panel bounds — GameScene fit-scales the overlay to
    /// the viewport (portrait phones) using this.
    let contentSize: CGSize

    init(title: String, size: CGSize = CGSize(width: 620, height: 420)) {
        contentSize = size
        let panelSize = size
        super.init()
        zPosition = 900
        isUserInteractionEnabled = true

        let dark = SKShapeNode(rectOf: CGSize(width: 6000, height: 4000))
        dark.fillColor = ThemeColors.overlayDark.withAlphaComponent(0.55)
        dark.strokeColor = .clear
        addChild(dark)

        panel.path = CGPath(roundedRect: CGRect(origin: .zero, size: panelSize), cornerWidth: 26, cornerHeight: 26, transform: nil)
        panel.fillColor = ThemeColors.surface
        panel.strokeColor = ThemeColors.line
        panel.lineWidth = 5
        panel.position = CGPoint(x: -panelSize.width / 2, y: -panelSize.height / 2)
        addChild(panel)

        titleLabel.text = title
        titleLabel.fontSize = 30
        titleLabel.fontColor = ThemeColors.text
        titleLabel.position = CGPoint(x: 0, y: panelSize.height / 2 - 52)
        addChild(titleLabel)

        // Close button (Unity: Escape -> ExitAction)
        let btn = SKShapeNode(circleOfRadius: 24)
        btn.fillColor = ThemeColors.danger
        btn.strokeColor = .clear
        let x1 = SKLabelNode(fontNamed: ThemeFonts.heavy)
        x1.text = "X"
        x1.fontSize = 24
        x1.fontColor = ThemeColors.text
        x1.position = CGPoint(x: 0, y: -8)
        btn.addChild(x1)
        closeButton.addChild(btn)
        closeButton.position = CGPoint(x: panelSize.width / 2 - 42, y: panelSize.height / 2 - 48)
        closeButton.name = "mg_close"
        addChild(closeButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    func close() {
        onClose?()
        removeFromParent()
    }

    func finish() {
        onComplete?()
        removeFromParent()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        if atPoint(p).name == "mg_close" || closeButton.contains(p) { close() }
    }
}

/// Port of DownloadMinigame.cs: progress fills over time, then completes.
final class DownloadOverlay: MinigameOverlay {
    private let fill = SKShapeNode()
    private let pctLabel = SKLabelNode(fontNamed: ThemeFonts.demi)
    private let statusLabel = SKLabelNode(fontNamed: ThemeFonts.med)
    private var progress: CGFloat = 0
    private var elapsed: TimeInterval = 0
    private let duration: TimeInterval = 5.0

    init() {
        super.init(title: "Download Data")

        let barW: CGFloat = 460, barH: CGFloat = 34
        let bg = SKShapeNode(rectOf: CGSize(width: barW, height: barH), cornerRadius: barH / 2)
        bg.fillColor = ThemeColors.surface2
        bg.strokeColor = ThemeColors.line.withAlphaComponent(0.6)
        bg.lineWidth = 2
        bg.position = CGPoint(x: 0, y: 20)
        addChild(bg)

        fill.path = CGPath(rect: CGRect(x: -barW / 2 + 4, y: -barH / 2 + 4, width: 0, height: barH - 8), transform: nil)
        fill.fillColor = ThemeColors.success
        fill.strokeColor = .clear
        fill.position = bg.position
        addChild(fill)

        pctLabel.text = "0%"
        pctLabel.fontSize = 40
        pctLabel.fontColor = ThemeColors.text
        pctLabel.position = CGPoint(x: 0, y: 70)
        addChild(pctLabel)

        statusLabel.text = "Connecting to relay…"
        statusLabel.fontSize = 19
        statusLabel.fontColor = ThemeColors.textSecondary
        statusLabel.position = CGPoint(x: 0, y: -55)
        addChild(statusLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ dt: TimeInterval) {
        guard progress < 1 else { return }
        elapsed += dt
        progress = min(1, CGFloat(elapsed / duration))

        let barW: CGFloat = 460, barH: CGFloat = 34
        let w = (barW - 8) * progress
        fill.path = CGPath(rect: CGRect(x: -barW / 2 + 4, y: -barH / 2 + 4, width: w, height: barH - 8), transform: nil)

        pctLabel.text = "\(Int(progress * 100))%"
        switch progress {
        case ..<0.15: statusLabel.text = "Connecting to relay…"
        case ..<0.55: statusLabel.text = "Downloading star maps…"
        case ..<0.9:  statusLabel.text = "Downloading crew logs…"
        default:      statusLabel.text = "Complete!"
        }

        if progress >= 1 {
            run(.wait(forDuration: 0.35)) { [weak self] in self?.finish() }
        }
    }
}

/// Port of CardSwapTask.cs: drag the card through the reader.
/// Reaching the end completes; releasing early snaps back ("Bad read").
final class CardSwipeOverlay: MinigameOverlay {
    private let card = SKNode()
    private let cardBody = SKShapeNode()
    private let track = SKShapeNode()
    private let hint = SKLabelNode(fontNamed: ThemeFonts.demi)
    private var dragging = false
    private var cardX: CGFloat = -190
    private let minX: CGFloat = -190, maxX: CGFloat = 190

    init() {
        super.init(title: "Swipe Card", size: CGSize(width: 620, height: 380))

        let trackW: CGFloat = 520
        track.path = CGPath(roundedRect: CGRect(x: -trackW / 2, y: -34, width: trackW, height: 68), cornerWidth: 12, cornerHeight: 12, transform: nil)
        track.fillColor = ThemeColors.surface2
        track.strokeColor = ThemeColors.line.withAlphaComponent(0.5)
        track.lineWidth = 2
        track.position = CGPoint(x: 0, y: -10)
        addChild(track)

        let slot = SKShapeNode(rectOf: CGSize(width: 8, height: 90))
        slot.fillColor = ThemeColors.divider
        slot.strokeColor = .clear
        slot.position = CGPoint(x: minX - 26, y: -10)
        addChild(slot)

        cardBody.path = CGPath(roundedRect: CGRect(x: -70, y: -46, width: 140, height: 92), cornerWidth: 10, cornerHeight: 10, transform: nil)
        cardBody.fillColor = ThemeColors.butter
        cardBody.strokeColor = ThemeColors.text.withAlphaComponent(0.8)
        cardBody.lineWidth = 3
        let stripe = SKShapeNode(rectOf: CGSize(width: 120, height: 14))
        stripe.fillColor = ThemeColors.text.withAlphaComponent(0.85)
        stripe.strokeColor = .clear
        stripe.position = CGPoint(x: 0, y: -14)
        cardBody.addChild(stripe)
        card.addChild(cardBody)
        card.position = CGPoint(x: cardX, y: -10)
        addChild(card)

        hint.text = "Drag the card through the reader →"
        hint.fontSize = 21
        hint.fontColor = ThemeColors.textSecondary
        hint.position = CGPoint(x: 0, y: -120)
        addChild(hint)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        if card.contains(p) { dragging = true }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard dragging, let t = touches.first else { return }
        let p = t.location(in: self)
        cardX = max(minX, min(maxX, p.x))
        card.position.x = cardX
        hint.text = ""
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard dragging else { return }
        dragging = false
        if cardX >= maxX - 4 {
            hint.text = "Accepted. Thank you!"
            hint.fontColor = ThemeColors.sageDeep
            run(.wait(forDuration: 0.4)) { [weak self] in self?.finish() }
        } else {
            hint.text = "Bad read. Try again."
            hint.fontColor = ThemeColors.coralDeep
            card.run(.moveTo(x: minX, duration: 0.25))
            cardX = minX
        }
    }
}

/// Extra task: connect the three colored wires.
final class WiringOverlay: MinigameOverlay {
    private let wireColors: [UIColor] = [
        ThemeColors.danger,
        ThemeColors.primary,
        ThemeColors.butter,
    ]
    private var leftOrder: [Int] = []
    private var rightOrder: [Int] = []
    private var connected: Set<Int> = []
    private var selectedLeft: Int? = nil
    private var lineNodes: [SKShapeNode] = []

    init() {
        super.init(title: "Fix Wiring", size: CGSize(width: 620, height: 420))
        resetBoard()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func resetBoard() {
        leftOrder = wireColors.indices.shuffled()
        rightOrder = wireColors.indices.shuffled()
        connected = []
        selectedLeft = nil
        lineNodes.forEach { $0.removeFromParent() }
        lineNodes = []
        buildSides()
    }

    private func buildSides() {
        // remove previous port nodes
        children.filter { $0.name == "port" }.forEach { $0.removeFromParent() }
        for slot in 0..<3 {
            // left port
            let li = leftOrder[slot]
            let lp = makePort(colorIndex: li, side: .left, slot: slot)
            addChild(lp)
            // right port
            let ri = rightOrder[slot]
            let rp = makePort(colorIndex: ri, side: .right, slot: slot)
            addChild(rp)
        }
    }

    private enum Side { case left, right }

    private func makePort(colorIndex: Int, side: Side, slot: Int) -> SKNode {
        let node = SKNode()
        node.name = "port"
        let y = CGFloat(70 - slot * 70)
        let x: CGFloat = side == .left ? -220 : 220
        node.position = CGPoint(x: x, y: y)
        let circle = SKShapeNode(circleOfRadius: 22)
        circle.fillColor = wireColors[colorIndex]
        circle.strokeColor = ThemeColors.text.withAlphaComponent(0.5)
        circle.lineWidth = 3
        node.addChild(circle)
        let meta = SKNode()
        meta.name = side == .left ? "L\(colorIndex)" : "R\(colorIndex)"
        circle.name = meta.name
        node.userData = ["idx": colorIndex, "side": side == .left ? 0 : 1]
        let num = SKLabelNode(fontNamed: ThemeFonts.demi)
        num.text = "\(colorIndex + 1)"
        num.fontSize = 15
        num.fontColor = ThemeColors.text
        num.position = CGPoint(x: 0, y: -36)
        node.addChild(num)
        return node
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let t = touches.first else { return }
        let hit = atPoint(t.location(in: self))
        guard let name = hit.name, name.count == 2, name.first == "L" || name.first == "R",
              let idx = name.last?.wholeNumberValue else { return }

        if name.first == "L" {
            if connected.contains(idx) { return }
            selectedLeft = idx
        } else if let sel = selectedLeft, sel == idx, !connected.contains(idx) {
            // connect!
            connected.insert(idx)
            selectedLeft = nil
            drawLine(colorIndex: idx)
            if connected.count == 3 {
                run(.wait(forDuration: 0.45)) { [weak self] in self?.finish() }
            }
        } else {
            selectedLeft = nil
        }
    }

    private func drawLine(colorIndex: Int) {
        let lSlot = leftOrder.firstIndex(of: colorIndex) ?? 0
        let rSlot = rightOrder.firstIndex(of: colorIndex) ?? 0
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -220 + 22, y: CGFloat(70 - lSlot * 70)))
        path.addLine(to: CGPoint(x: 220 - 22, y: CGFloat(70 - rSlot * 70)))
        let line = SKShapeNode(path: path)
        line.strokeColor = wireColors[colorIndex]
        line.lineWidth = 10
        line.zPosition = -1
        addChild(line)
        lineNodes.append(line)
    }
}
