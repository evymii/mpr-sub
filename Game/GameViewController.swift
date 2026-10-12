//
//  GameViewController.swift
//  Game
//
//  Swift port of the Unity fan remake — presents the SpriteKit scenes and
//  forwards hardware keyboard events to the game scene (the Unity original
//  used Input.GetAxis / GetKeyDown).
//

import UIKit
import SpriteKit

class GameViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let skView = view as? SKView else { return }
        skView.isMultipleTouchEnabled = true
        skView.ignoresSiblingOrder = true
        skView.showsFPS = false
        skView.showsNodeCount = false

        // Debug hook: `simctl launch ... -startRole crew|impostor` skips the menu.
        let args = ProcessInfo.processInfo.arguments
        var scene: SKScene = MainMenuScene(size: skView.bounds.size)
        if let i = args.firstIndex(of: "-startRole"), i + 1 < args.count {
            scene = args[i + 1] == "impostor" ? GameScene(role: .impostor) : GameScene(role: .crew)
        }
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)
    }

    // MARK: - Keyboard forwarding (WASD / arrows / E / R / Q / M / Esc)

    private func handlePress(_ presses: Set<UIPress>, down: Bool) {
        guard let skView = view as? SKView,
              let scene = skView.scene as? GameScene else { return }
        for press in presses {
            guard let key = press.key?.keyCode else { continue }
            scene.keyPressed(key, isDown: down)
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let handled = (view as? SKView)?.scene is GameScene
        if handled { handlePress(presses, down: true); return }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let handled = (view as? SKView)?.scene is GameScene
        if handled { handlePress(presses, down: false); return }
        super.pressesEnded(presses, with: event)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .allButUpsideDown
    }

    override var prefersStatusBarHidden: Bool { true }

    override var prefersHomeIndicatorAutoHidden: Bool { true }
}
