//
//  LayoutTests.swift
//  GameTests
//
//  Regression tests for portrait/landscape layout: build the scenes at phone
//  sizes in both orientations and assert the viewport-anchored HUD controls
//  stay inside the screen, including across a mid-game rotation.
//

import Testing
import SpriteKit
@testable import Game

@MainActor
struct LayoutTests {

    private let portrait = CGSize(width: 402, height: 874)   // iPhone 17 Pro
    private let landscape = CGSize(width: 874, height: 402)

    private func assertControlsFit(_ scene: GameScene, _ label: String) {
        let w = scene.size.width, h = scene.size.height
        let radii = ["btn_use": CGFloat(44), "btn_report": 40, "btn_kill": 40, "btn_map": 30]
        for (name, r) in radii {
            guard let node = scene.childNode(withName: "//\(name)") else {
                if name == "btn_kill", scene.role == .crew { continue }
                Issue.record("\(label): missing HUD node \(name)")
                continue
            }
            #expect(abs(node.position.x) + r <= w / 2 + 0.5,
                    "\(label): \(name) x=\(node.position.x) overflows width \(w)")
            #expect(abs(node.position.y) + r <= h / 2 + 0.5,
                    "\(label): \(name) y=\(node.position.y) overflows height \(h)")
        }
        // Progress bar (camera child, viewport-anchored) must be on-screen.
        if let bar = scene.childNode(withName: "//progressBarBg") as? SKShapeNode {
            #expect(abs(bar.position.x) + 100 <= w / 2 + 0.5, "\(label): progress bar x overflow")
            #expect(abs(bar.position.y) + 12 <= h / 2 + 0.5, "\(label): progress bar y overflow")
        } else {
            Issue.record("\(label): missing progress bar")
        }
    }

    @Test func crewHUDFitsPortrait() {
        let scene = GameScene(role: .crew)
        scene.size = portrait
        scene.didMove(to: SKView())
        assertControlsFit(scene, "crew portrait")
    }

    @Test func crewHUDFitsLandscape() {
        let scene = GameScene(role: .crew)
        scene.size = landscape
        scene.didMove(to: SKView())
        assertControlsFit(scene, "crew landscape")
    }

    @Test func impostorHUDFitsPortrait() {
        let scene = GameScene(role: .impostor)
        scene.size = portrait
        scene.didMove(to: SKView())
        assertControlsFit(scene, "impostor portrait")
    }

    @Test func impostorHUDFitsLandscape() {
        let scene = GameScene(role: .impostor)
        scene.size = landscape
        scene.didMove(to: SKView())
        assertControlsFit(scene, "impostor landscape")
    }

    @Test func relayoutsWhenRotatingMidGame() {
        let scene = GameScene(role: .impostor)
        scene.size = portrait
        scene.didMove(to: SKView())
        scene.size = landscape          // rotate the phone
        scene.didChangeSize(portrait)
        assertControlsFit(scene, "after rotation to landscape")
        scene.size = portrait           // and back
        scene.didChangeSize(landscape)
        assertControlsFit(scene, "after rotation back to portrait")
    }

    @Test func menuFitsBothOrientations() {
        for (sz, label) in [(portrait, "menu portrait"), (landscape, "menu landscape")] {
            let menu = MainMenuScene(size: sz)
            menu.didMove(to: SKView())
            for name in ["btn_crew", "btn_impostor", "btn_help"] {
                guard let node = menu.childNode(withName: "//\(name)") else {
                    Issue.record("\(label): missing \(name)")
                    continue
                }
                let p = menu.convert(node.position, from: node.parent!)
                #expect(abs(p.x) <= sz.width / 2 + 0.5, "\(label): \(name) x overflow (\(p.x))")
                #expect(abs(p.y) <= sz.height / 2 + 0.5, "\(label): \(name) y overflow (\(p.y))")
            }
        }
    }
}
