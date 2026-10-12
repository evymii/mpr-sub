import UIKit
import SpriteKit

/// The 10 playable colors. Row order matches Art/characters_sheet.png.
enum CrewColor: Int, CaseIterable, Codable {
    case red = 0, blue, green, pink, orange, yellow, black, white, purple, cyan

    var displayName: String {
        ["Red", "Blue", "Green", "Pink", "Orange", "Yellow", "Black", "White", "Purple", "Cyan"][rawValue]
    }

    var uiColor: UIColor {
        switch self {
        case .red:    return UIColor(red: 193/255, green: 68/255, blue: 67/255, alpha: 1)
        case .blue:   return UIColor(red: 67/255, green: 94/255, blue: 193/255, alpha: 1)
        case .green:  return UIColor(red: 80/255, green: 168/255, blue: 84/255, alpha: 1)
        case .pink:   return UIColor(red: 222/255, green: 132/255, blue: 190/255, alpha: 1)
        case .orange: return UIColor(red: 240/255, green: 148/255, blue: 36/255, alpha: 1)
        case .yellow: return UIColor(red: 240/255, green: 222/255, blue: 60/255, alpha: 1)
        case .black:  return UIColor(red: 68/255, green: 72/255, blue: 84/255, alpha: 1)
        case .white:  return UIColor(red: 222/255, green: 230/255, blue: 228/255, alpha: 1)
        case .purple: return UIColor(red: 116/255, green: 60/255, blue: 168/255, alpha: 1)
        case .cyan:   return UIColor(red: 72/255, green: 208/255, blue: 208/255, alpha: 1)
        }
    }

    static func random(excluding: [CrewColor]) -> CrewColor {
        let pool = CrewColor.allCases.filter { !excluding.contains($0) }
        return pool.randomElement() ?? .red
    }
}

/// Loads and slices the recolored walk-cycle sheet that was generated from the
/// original Unity project's character sprites (idle + 12 walk frames per color).
final class CrewSheet {
    static let shared = CrewSheet()

    let sheetTexture: SKTexture
    static let frameCols = 13   // 0 = idle, 1...12 = walk
    static let colorRows = CrewColor.allCases.count

    private init() {
        sheetTexture = SKTexture(imageNamed: "characters_sheet")
    }

    func texture(color: CrewColor, frame: Int) -> SKTexture {
        let col = max(0, min(Self.frameCols - 1, frame))
        let w = 1.0 / CGFloat(Self.frameCols)
        let h = 1.0 / CGFloat(Self.colorRows)
        // PIL images are top-down; SKTexture rects are bottom-up.
        let row = Self.colorRows - 1 - color.rawValue
        let rect = CGRect(x: CGFloat(col) * w, y: CGFloat(row) * h, width: w, height: h)
        return SKTexture(rect: rect, in: sheetTexture)
    }

    /// Dead body sprite from the pre-rendered dead_body_sheet.png
    /// (bottom half of the crewmate with a bone sticking out).
    func deadBodyTexture(color: CrewColor) -> SKTexture {
        let full = SKTexture(imageNamed: "dead_body_sheet")
        let h = 1.0 / CGFloat(Self.colorRows)
        let row = CGFloat(Self.colorRows - 1 - color.rawValue)
        return SKTexture(rect: CGRect(x: 0, y: row * h, width: 1, height: h), in: full)
    }
}

/// A crewmate character in the world — port of Unity's Player prefab + Animator
/// (walk frames driven by speed, x-flip by horizontal direction).
final class Crewmate: SKNode {
    static let walkFPS = 11.0

    let color: CrewColor
    let crewName: String

    private let sprite = SKSpriteNode()
    private let nameLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private var walkTextures: [SKTexture] = []
    private var idleTexture: SKTexture
    private(set) var deadTexture: SKTexture

    /// Facing: +1 right, -1 left (Unity flips localScale.x).
    private(set) var facing: CGFloat = 1
    private var walkTime: TimeInterval = 0
    private(set) var isMoving = false

    /// Desired sprite height in points (texture scales to this).
    var bodyHeight: CGFloat = 74 {
        didSet { sprite.size.height = bodyHeight; sprite.size.width = bodyHeight * 0.72 }
    }

    init(color: CrewColor, name: String, showName: Bool = true) {
        self.color = color
        self.crewName = name
        self.idleTexture = CrewSheet.shared.texture(color: color, frame: 0)
        self.deadTexture = CrewSheet.shared.deadBodyTexture(color: color)
        walkTextures = (1...12).map { CrewSheet.shared.texture(color: color, frame: $0) }
        super.init()
        // Mirror onto SKNode.name (String?) so childNode(withName:) / debugging still work.
        self.name = name

        sprite.texture = idleTexture
        sprite.size = CGSize(width: bodyHeight * 0.72, height: bodyHeight)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.28) // feet anchor
        addChild(sprite)

        nameLabel.text = crewName
        nameLabel.fontSize = 17
        nameLabel.fontColor = .white
        nameLabel.verticalAlignmentMode = .bottom
        nameLabel.position = CGPoint(x: 0, y: bodyHeight * 0.92)
        nameLabel.zPosition = 10
        addChild(nameLabel)
        if !showName { nameLabel.isHidden = true }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    /// Call every frame with the movement vector (Unity: Player.Update).
    func update(dt: TimeInterval, moving: Bool, direction: CGPoint) {
        isMoving = moving
        if direction.x < -0.05 { facing = -1 }
        if direction.x > 0.05 { facing = 1 }
        sprite.xScale = facing

        if moving {
            walkTime += dt * Self.walkFPS
            let idx = Int(walkTime.truncatingRemainder(dividingBy: 12))
            sprite.texture = walkTextures[idx]
        } else {
            walkTime = 0
            sprite.texture = idleTexture
        }
    }

    func showDeadBody() {
        removeAllChildren()
        let body = SKSpriteNode(texture: deadTexture)
        body.size = CGSize(width: bodyHeight * 0.95, height: bodyHeight * 0.62)
        body.anchorPoint = CGPoint(x: 0.5, y: 0.1)
        body.zPosition = -1
        addChild(body)
    }
}
