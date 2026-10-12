import UIKit
import SpriteKit

/// Minimal start screen: white paper, black ink, a welcome message and the
/// game title, then role select. Works in portrait and landscape.
final class MainMenuScene: SKScene {

    static let gameTitle = "Life at Our University"

    private var helpOverlay: SKNode?

    override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        build()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        removeAllChildren()
        helpOverlay = nil
        build()
    }

    private func build() {
        backgroundColor = .white

        let w = size.width, h = size.height
        let margin: CGFloat = 32
        let maxTextW = w - margin * 2

        // --- measure the centered column -----------------------------------
        // Widest text is the title's second line, "Our University" (~8 em).
        let titleF = min(50, max(28, maxTextW / 8.0))
        let btnW = min(320, maxTextW)
        let btnH: CGFloat = 52
        let footerH: CGFloat = 20

        // Fixed element heights + base gaps between them.
        let fixedHeights: CGFloat = 17 /* eyebrow */ + 2 /* divider */ + btnH + btnH + 18 /* how-to */
        let baseGaps: CGFloat = 20 + 8 + 26 + 34 + 14 + 30
        let avail = h - 48 - footerH

        var gapsScale = (avail - fixedHeights - 2 * titleF) / baseGaps
        gapsScale = min(1.25, max(0.6, gapsScale))
        let gaps = baseGaps * gapsScale
        let total = fixedHeights + 2 * titleF + gaps
        let top = total / 2          // cursor starts at the top of the column

        // --- column ----------------------------------------------------------
        let column = SKNode()
        column.position = CGPoint(x: w / 2, y: h / 2)
        column.alpha = 0
        column.run(.fadeAlpha(to: 1, duration: 0.45))
        addChild(column)

        var y = top
        func place(_ height: CGFloat, _ gap: CGFloat, _ add: (CGFloat) -> Void) {
            y -= height / 2
            add(y)
            y -= height / 2 + gap * gapsScale
        }

        // WELCOME TO
        place(17, 20) { cy in
            let l = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            l.text = "W E L C O M E   T O"
            l.fontSize = 13
            l.fontColor = UIColor(white: 0.55, alpha: 1)
            l.position = CGPoint(x: 0, y: cy - 5)
            column.addChild(l)
        }

        // Title, two lines
        place(titleF, 8) { cy in
            let l = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            l.text = "Life at"
            l.fontSize = titleF
            l.fontColor = .black
            l.position = CGPoint(x: 0, y: cy - titleF * 0.35)
            column.addChild(l)
        }
        place(titleF, 26) { cy in
            let l = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            l.text = "Our University"
            l.fontSize = titleF
            l.fontColor = .black
            l.position = CGPoint(x: 0, y: cy - titleF * 0.35)
            column.addChild(l)
        }

        // Divider
        place(2, 34) { cy in
            let line = SKShapeNode(rectOf: CGSize(width: 36, height: 2), cornerRadius: 1)
            line.fillColor = .black
            line.strokeColor = .clear
            line.position = CGPoint(x: 0, y: cy)
            column.addChild(line)
        }

        // Buttons
        place(btnH, 14) { cy in
            column.addChild(self.makeButton(text: "Play as Crewmate", name: "btn_crew",
                                            width: btnW, height: btnH, primary: true,
                                            at: CGPoint(x: 0, y: cy)))
        }
        place(btnH, 30) { cy in
            column.addChild(self.makeButton(text: "Play as Impostor", name: "btn_impostor",
                                            width: btnW, height: btnH, primary: false,
                                            at: CGPoint(x: 0, y: cy)))
        }
        place(18, 0) { cy in
            let l = SKLabelNode(fontNamed: "AvenirNext-Medium")
            l.text = "How to play"
            l.fontSize = 15
            l.fontColor = UIColor(white: 0.45, alpha: 1)
            l.position = CGPoint(x: 0, y: cy - 5)
            l.name = "btn_help"
            column.addChild(l)
            let underline = SKShapeNode(rectOf: CGSize(width: 70, height: 1), cornerRadius: 0.5)
            underline.fillColor = UIColor(white: 0.45, alpha: 1)
            underline.strokeColor = .clear
            underline.position = CGPoint(x: 0, y: cy - 15)
            underline.name = "btn_help"
            column.addChild(underline)
        }

        // Footer
        let footer = SKLabelNode(fontNamed: "AvenirNext-Medium")
        footer.text = "a tiny game about campus life"
        footer.fontSize = 11
        footer.fontColor = UIColor(white: 0.72, alpha: 1)
        footer.position = CGPoint(x: w / 2, y: 18)
        addChild(footer)
    }

    private func makeButton(text: String, name: String, width: CGFloat, height: CGFloat,
                            primary: Bool, at p: CGPoint) -> SKNode {
        let b = SKShapeNode(rect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
                            cornerRadius: height / 2)
        b.fillColor = primary ? .black : .white
        b.strokeColor = primary ? .clear : .black
        b.lineWidth = 1.5
        b.name = name
        b.position = p
        let l = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        l.text = text
        l.fontSize = 16
        l.fontColor = primary ? .white : .black
        l.name = name
        l.position = CGPoint(x: 0, y: -5.5)
        b.addChild(l)
        return b
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let hit = atPoint(t.location(in: self))

        if helpOverlay != nil {
            helpOverlay?.removeFromParent()
            helpOverlay = nil
            return
        }

        var node: SKNode? = hit
        var name: String? = nil
        while let n = node {
            if n.name?.hasPrefix("btn_") == true { name = n.name; break }
            node = n.parent
        }

        switch name {
        case "btn_crew": startGame(.crew)
        case "btn_impostor": startGame(.impostor)
        case "btn_help": showHelp()
        default: break
        }
    }

    private func startGame(_ role: GameScene.Role) {
        let scene = GameScene(role: role)
        scene.scaleMode = .resizeFill
        view?.presentScene(scene, transition: .fade(withDuration: 0.5))
    }

    private func showHelp() {
        let overlay = SKNode()
        overlay.zPosition = 100

        let paper = SKShapeNode(rectOf: CGSize(width: 6000, height: 4000))
        paper.fillColor = UIColor(white: 1, alpha: 0.97)
        paper.strokeColor = .clear
        overlay.addChild(paper)

        let portrait = size.height >= size.width
        let bodyF: CGFloat = portrait ? 13 : 15

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "HOW TO PLAY"
        title.fontSize = 24
        title.fontColor = .black
        title.position = CGPoint(x: 0, y: 150)
        overlay.addChild(title)

        let lines = [
            "MOVE — joystick (left of screen) or WASD / arrows",
            "USE / E — use a station, open CCTV in Security",
            "REPORT / R — report a body, start a meeting",
            "KILL / Q — impostor only · 25 s cooldown",
            "MAP / M — minimap with your tasks",
            "",
            "Crewmate: finish tasks, spot the killer, vote them out.",
            "Impostor: eliminate the crew before tasks are done.",
            "Security cameras can witness kills.",
        ]
        for (i, line) in lines.enumerated() {
            let l = SKLabelNode(fontNamed: "AvenirNext-Medium")
            l.text = line
            l.fontSize = line.isEmpty ? 8 : bodyF
            l.fontColor = i >= 6 ? UIColor(white: 0.15, alpha: 1) : UIColor(white: 0.35, alpha: 1)
            l.position = CGPoint(x: 0, y: 112 - CGFloat(i + 1) * (bodyF + 9))
            overlay.addChild(l)
        }

        let tap = SKLabelNode(fontNamed: "AvenirNext-Medium")
        tap.text = "tap anywhere to close"
        tap.fontSize = 12
        tap.fontColor = UIColor(white: 0.55, alpha: 1)
        tap.position = CGPoint(x: 0, y: -size.height / 2 + 40)
        overlay.addChild(tap)

        addChild(overlay)
        helpOverlay = overlay
    }
}
