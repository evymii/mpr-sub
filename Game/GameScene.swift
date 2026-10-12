import UIKit
import SpriteKit

/// The main gameplay scene — Swift port of the Unity fan remake:
/// Player controller + follow camera (Player.cs), interactable stations with a
/// USE button (InteractableObject.cs), Card Swipe / Download tasks
/// (CardSwapTask.cs / DownloadMinigame.cs), CCTV system (CCTVSystem.cs) and the
/// shared task progress bar (ProgressTasks.cs) — plus the crewmate/impostor
/// game loop (TypePlayer) played with AI bots.
class GameScene: SKScene {
    enum Role { case crew, impostor }
    let role: Role

    // MARK: - World

    let world = SKNode()
    let map = SkeldMap()
    var stations: [TaskStation] = []
    let progress = ProgressTracker()
    private let stationNodes = SKNode()
    private var starsBack: SKSpriteNode!

    // MARK: - Participants

    var participants: [Participant] = []
    var playerParticipant: Participant?
    var bots: [Bot] = []
    var bodies: [Crewmate] = []
    private(set) var gameOver = false
    private var meetingActive = false
    private var witnessedKillBy: String?

    // Player tuning (Unity: Speed field on Player)
    let playerSpeed: CGFloat = 250
    var playerKillCooldown: TimeInterval = 10
    private var lastTime: TimeInterval = 0

    // MARK: - Input

    private var keyDirs: Set<UIKeyboardHIDUsage> = []
    private var joystickActive = false
    private var joystickVector = CGVector.zero
    private var joystickTouch: UITouch?
    private let joyBase = SKShapeNode(circleOfRadius: 62)
    private let joyKnob = SKShapeNode(circleOfRadius: 30)

    // MARK: - HUD

    let cam = SKCameraNode()
    private var progressCaption: SKLabelNode!
    private var progressBarBg: SKShapeNode!
    private var progressBarFill: SKShapeNode!
    private var progressPct: SKLabelNode!
    private var taskListLabels: [SKLabelNode] = []
    private var roomLabel: SKLabelNode!
    private var mapButton: SKNode!
    private var useButton: SKNode!
    private var reportButton: SKNode!
    private var killButton: SKNode?
    private var killCooldownLabel: SKLabelNode?
    private var toastLabel: SKLabelNode!
    private var hudBuilt = false

    // MARK: - Overlays

    var activeOverlay: MinigameOverlay?
    private var meeting: MeetingOverlay?
    private var minimap: SKNode?
    private var cctvActive = false
    private var cctvIndex = 0
    private var cctvUI: SKNode?
    private var cctvFeedLabel: SKLabelNode?
    private var cctvCamShapes: [SKShapeNode] = []
    private var cctvExitButton: SKNode?
    private var cctvScanlines: SKSpriteNode?
    private var endOverlay: SKNode?
    var camRooms: [Room] = []

    // Scan task state
    private var scanStation: TaskStation?
    private var scanProgress: CGFloat = 0
    private var scanBar: SKNode?

    // MARK: - Setup

    init(role: Role) {
        self.role = role
        super.init(size: CGSize(width: 1336, height: 700))
        scaleMode = .resizeFill
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(red: 0.05, green: 0.06, blue: 0.11, alpha: 1)
        lastTime = 0

        // --- world ---
        addChild(world)
        world.zPosition = 0

        starsBack = SKSpriteNode(texture: makeStarsTexture())
        starsBack.zPosition = -30
        starsBack.position = CGPoint(x: SkeldMap.worldSize.width / 2, y: SkeldMap.worldSize.height / 2)
        world.addChild(starsBack)

        let floor = SKSpriteNode(texture: map.makeFloorTexture())
        floor.size = SkeldMap.worldSize
        floor.position = starsBack.position
        floor.zPosition = -10
        world.addChild(floor)

        // Room name labels
        for room in map.rooms {
            let l = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            l.text = room.name.uppercased()
            l.fontSize = 30
            l.fontColor = UIColor(white: 1, alpha: 0.16)
            l.position = CGPoint(x: room.rect.midX, y: room.rect.midY + room.rect.height * 0.28)
            l.zPosition = -5
            world.addChild(l)
        }

        stations = TaskBoard.allStations()
        world.addChild(stationNodes)
        for st in stations {
            stationNodes.addChild(makeStationNode(for: st))
        }
        setupCCTVStation()

        // --- camera & HUD (before participants: the intro toast needs it) ---
        addChild(cam)
        camera = cam
        buildHUD()

        // --- participants ---
        setupParticipants()
        refreshTaskList()

        applyDebugStateIfNeeded()
    }

    /// Rotation / resize: re-lay everything out for the new aspect.
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard hudBuilt else { return }
        layoutHUD()
        refreshTaskList()
        if cctvActive { layoutCCTVUI() }
        if minimap != nil { toggleMinimap() }   // close; it re-opens in the new aspect
        if let overlay = activeOverlay {
            overlay.setScale(fitScale(for: overlay.contentSize))
        }
        if let meeting {
            meeting.setScale(fitScale(for: meeting.contentSize))
        }
        if let endOverlay {
            endOverlay.setScale(fitScale(for: CGSize(width: 460, height: 400)))
        }
    }

    private var isPortrait: Bool { size.height >= size.width }

    /// Scale that shrinks a centered overlay (a camera child) to fit the view.
    private func fitScale(for content: CGSize, padding: CGFloat = 28) -> CGFloat {
        min(1, (size.width - padding * 2) / content.width,
            (size.height - padding * 2) / content.height)
    }

    /// Debug hook for screenshot testing: `-debugState minimap|cctv|task|download|wiring|meeting`.
    private func applyDebugStateIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-debugState"), i + 1 < args.count else { return }
        let you = playerParticipant
        switch args[i + 1] {
        case "minimap":
            run(.wait(forDuration: 0.6)) { [weak self] in self?.toggleMinimap() }
        case "cctv":
            you?.crewmate.position = cctvStationPosition
            run(.wait(forDuration: 0.6)) { [weak self] in self?.openCCTV() }
        case "task":
            if let st = stations.first(where: { $0.kind == .cardSwipe }) {
                you?.crewmate.position = st.position
                run(.wait(forDuration: 0.6)) { [weak self] in self?.useAction() }
            }
        case "download":
            if let st = stations.first(where: { $0.kind == .download }) {
                you?.crewmate.position = st.position
                run(.wait(forDuration: 0.6)) { [weak self] in self?.useAction() }
            }
        case "wiring":
            if let st = stations.first(where: { $0.kind == .wiring }) {
                you?.crewmate.position = st.position
                run(.wait(forDuration: 0.6)) { [weak self] in self?.useAction() }
            }
        case "meeting":
            if let you {
                let botsSorted = bots.sorted { $0.participant.crewmate.position.x < $1.participant.crewmate.position.x }
                if botsSorted.count >= 2 {
                    let killer = botsSorted[0].participant
                    let victim = botsSorted[1].participant
                    run(.wait(forDuration: 0.8)) { [weak self] in
                        self?.performKill(killer: killer, victim: victim)
                        self?.beginMeeting(reporter: you, bodyPosition: victim.crewmate.position)
                    }
                }
            }
        case "victory":
            run(.wait(forDuration: 0.8)) { [weak self] in
                self?.gameOver = true
                self?.showEndScreen(victory: true, message: "All tasks complete. The ship is safe!")
            }
        case "defeat":
            run(.wait(forDuration: 0.8)) { [weak self] in
                self?.gameOver = true
                self?.showEndScreen(victory: false, message: "The Impostor took over the ship.")
            }
        default:
            break
        }
    }

    private func setupParticipants() {
        let spawnCenter = map.room(named: "Cafeteria")!.rect
        let allColors = CrewColor.allCases.shuffled()
        let playerColor = allColors[0]
        let botColors = Array(allColors.prefix(6).dropFirst())

        // Player
        let pCrew = Crewmate(color: playerColor, name: "YOU")
        pCrew.position = CGPoint(x: spawnCenter.midX, y: spawnCenter.midY - 40)
        world.addChild(pCrew)
        let you = Participant(crewmate: pCrew, isImpostor: role == .impostor,
                              tasks: TaskBoard.assignTasks(count: 6, from: stations))
        participants.append(you)
        playerParticipant = you

        // Bots: 5 total. Crew mode -> one of them is the impostor.
        let impostorBotIndex = role == .crew ? Int.random(in: 0..<5) : -1
        for i in 0..<5 {
            let botCrew = Crewmate(color: botColors[i], name: botColors[i].displayName)
            let a = CGFloat(i) / 5 * 2 * .pi
            botCrew.position = CGPoint(x: spawnCenter.midX + cos(a) * 130, y: spawnCenter.midY + sin(a) * 90)
            world.addChild(botCrew)
            let botTasks = TaskBoard.assignTasks(count: 4, from: stations)
            let p = Participant(crewmate: botCrew, isImpostor: i == impostorBotIndex, tasks: botTasks)
            participants.append(p)
            bots.append(Bot(participant: p, game: self))
        }

        // Total progress pool: my tasks (if crew) + crew-bots' tasks
        let myTasks = role == .crew ? 6 : 0
        let crewBotCount = role == .crew ? 4 : 5
        progress.register(count: myTasks + crewBotCount * 4)

        if role == .impostor {
            showToast("You are the IMPOSTOR. Eliminate the crew before tasks finish.")
        } else {
            showToast("You are a CREWMATE. Finish tasks and find the Impostor.")
        }
    }

    private func makeStationNode(for st: TaskStation) -> SKNode {
        let node = SKNode()
        node.position = st.position
        node.name = "station_\(st.id)"
        if st.kind == .scan {
            let pad = SKShapeNode(circleOfRadius: 42)
            pad.fillColor = UIColor(white: 1, alpha: 0.08)
            pad.strokeColor = UIColor(red: 0.3, green: 0.9, blue: 0.7, alpha: 0.7)
            pad.lineWidth = 4
            pad.zPosition = -2
            node.addChild(pad)
        } else {
            let body = SKShapeNode(rectOf: CGSize(width: 44, height: 34), cornerRadius: 6)
            body.fillColor = UIColor(white: 0.22, alpha: 1)
            body.strokeColor = UIColor(white: 0.75, alpha: 1)
            body.lineWidth = 3
            let screen = SKShapeNode(rectOf: CGSize(width: 28, height: 18), cornerRadius: 3)
            screen.fillColor = UIColor(red: 0.35, green: 0.9, blue: 0.75, alpha: 0.9)
            screen.strokeColor = .clear
            node.addChild(body)
            node.addChild(screen)
        }
        return node
    }

    private func markStationComplete(_ st: TaskStation) {
        if let node = stationNodes.childNode(withName: "station_\(st.id)") {
            for child in node.children {
                if let shape = child as? SKShapeNode {
                    shape.strokeColor = UIColor(white: 0.4, alpha: 0.4)
                    shape.fillColor = UIColor(white: 0.15, alpha: 0.6)
                }
            }
            node.alpha = 0.5
        }
        if let idx = stations.firstIndex(where: { $0.id == st.id }) {
            stations[idx].completed = true
        }
    }

    // MARK: - Frame update

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : min(0.05, currentTime - lastTime)
        lastTime = currentTime
        guard dt > 0 else { return }

        if !gameOver && !meetingActive {
            updatePlayer(dt)
            for bot in bots { bot.update(currentTime, dt) }
            updateScanTask(dt)
        }
        updateCamera(dt)
        updateHUD(dt)
        if let meeting { meeting.update(dt) }
        if let overlay = activeOverlay {
            (overlay as? DownloadOverlay)?.update(dt)
        }
    }

    private var movementLocked: Bool {
        gameOver || activeOverlay != nil || meetingActive || cctvActive
    }

    private func updatePlayer(_ dt: TimeInterval) {
        guard let you = playerParticipant else { return }
        let crew = you.crewmate

        var dir = CGVector.zero
        if !movementLocked {
            if joystickActive { dir = joystickVector }
            let k = keyboardVector()
            if k.dx != 0 || k.dy != 0 { dir = k }
        }
        let len = hypot(dir.dx, dir.dy)
        let moving = len > 0.08
        if moving {
            let nx = dir.dx / max(len, 1), ny = dir.dy / max(len, 1)
            let speed = playerSpeed * min(1, len)
            crew.position = map.move(crew.position, by: CGVector(dx: nx * speed * CGFloat(dt), dy: ny * speed * CGFloat(dt)), radius: 15)
        }
        crew.update(dt: dt, moving: moving, direction: CGPoint(x: dir.dx, y: dir.dy))
        crew.zPosition = crew.position.y
        if !you.isAlive { crew.alpha = 0.45 } // ghost

        playerKillCooldown = max(0, playerKillCooldown - dt)
    }

    private func keyboardVector() -> CGVector {
        var v = CGVector.zero
        for k in keyDirs {
            switch k {
            case .keyboardLeftArrow, .keyboardA: v.dx -= 1
            case .keyboardRightArrow, .keyboardD: v.dx += 1
            case .keyboardUpArrow, .keyboardW: v.dy += 1
            case .keyboardDownArrow, .keyboardS: v.dy -= 1
            default: break
            }
        }
        return v
    }

    private func updateCamera(_ dt: TimeInterval) {
        var target: CGPoint
        if cctvActive {
            target = camRooms[cctvIndex].cameraPoint
        } else if let you = playerParticipant {
            target = you.crewmate.position
        } else {
            target = cam.position
        }
        let t: CGFloat = 0.12
        cam.position.x += (target.x - cam.position.x) * t
        cam.position.y += (target.y - cam.position.y) * t

        // Clamp to world
        let hw = sceneSize.width / 2, hh = sceneSize.height / 2
        cam.position.x = max(hw, min(SkeldMap.worldSize.width - hw, cam.position.x))
        cam.position.y = max(hh, min(SkeldMap.worldSize.height - hh, cam.position.y))

        // Star parallax
        starsBack.position = CGPoint(x: SkeldMap.worldSize.width / 2 - (cam.position.x - SkeldMap.worldSize.width / 2) * 0.12,
                                     y: SkeldMap.worldSize.height / 2 - (cam.position.y - SkeldMap.worldSize.height / 2) * 0.12)
    }

    // MARK: - Kills & bodies

    func performKill(killer: Participant, victim: Participant) {
        guard victim.isAlive, victim !== killer else { return }
        victim.isAlive = false
        let crew = victim.crewmate
        crew.showDeadBody()
        crew.zPosition = crew.position.y - 1
        bodies.append(crew)

        // Nearby alive bots become witnesses
        for p in participants where p.isAlive && !p.isPlayer {
            let d = hypot(p.crewmate.position.x - crew.position.x, p.crewmate.position.y - crew.position.y)
            if d < 320 { killer.witnesses.append(p.crewmate.crewName) }
        }
        // The player might witness it directly or on CCTV
        if let you = playerParticipant, killer !== you, you.isAlive {
            let d = hypot(you.crewmate.position.x - crew.position.x, you.crewmate.position.y - crew.position.y)
            let onCam = cctvActive && hypot(cam.position.x - crew.position.x, cam.position.y - crew.position.y) < 430
            if d < 330 || onCam {
                witnessedKillBy = killer.crewmate.crewName
                showToast("You saw \(killer.crewmate.crewName) kill!")
                flashRed()
            }
        }

        if victim.isPlayer {
            showToast("You were killed. Finish your tasks as a ghost!")
        } else if hypot((playerParticipant?.crewmate.position.x ?? -9999) - crew.position.x,
                        (playerParticipant?.crewmate.position.y ?? -9999) - crew.position.y) < 420 {
            flashRed()
        }
        checkWin()
    }

    private var redFlash: SKShapeNode?
    private func flashRed() {
        let f = SKShapeNode(rectOf: CGSize(width: 6000, height: 4000))
        f.fillColor = UIColor(red: 0.8, green: 0, blue: 0, alpha: 0.35)
        f.strokeColor = .clear
        f.zPosition = 800
        cam.addChild(f)
        f.run(.sequence([.wait(forDuration: 0.15), .fadeOut(withDuration: 0.3)])) { f.removeFromParent() }
    }

    // MARK: - Tasks

    func botCompletedTask() {
        guard !progress.isComplete else { return }
        progress.completeOne()
        checkWin()
    }

    private func completeMyTask(_ st: TaskStation) {
        markStationComplete(st)
        if let you = playerParticipant {
            you.remainingTaskIds.removeAll { $0 == st.id }
            if !you.isImpostor {
                progress.completeOne()
            }
        }
        checkWin()
    }

    private func updateScanTask(_ dt: TimeInterval) {
        guard let st = scanStation, let you = playerParticipant else { return }
        let d = hypot(you.crewmate.position.x - st.position.x, you.crewmate.position.y - st.position.y)
        if d > 55 || !you.isAlive {
            cancelScan()
            return
        }
        scanProgress += CGFloat(dt) / 6.0
        if let bar = scanBar, let fill = bar.childNode(withName: "fill") as? SKShapeNode {
            fill.path = CGPath(rect: CGRect(x: -44, y: -5, width: 88 * min(1, scanProgress), height: 10), transform: nil)
        }
        if scanProgress >= 1 {
            scanBar?.removeFromParent(); scanBar = nil
            scanStation = nil
            completeMyTask(st)
            showToast("Scan submitted!")
        }
    }

    private func cancelScan() {
        scanBar?.removeFromParent()
        scanBar = nil
        scanStation = nil
        scanProgress = 0
    }

    // MARK: - Meetings

    func beginMeeting(reporter: Participant, bodyPosition: CGPoint) {
        guard !meetingActive, !gameOver else { return }
        meetingActive = true
        cancelScan()
        closeCCTV()

        let alive = participants.filter { $0.isAlive }
        let you = playerParticipant?.isAlive == true ? playerParticipant : nil
        let overlay = MeetingOverlay(participants: alive, you: you,
                                     reporterName: reporter.isPlayer ? "YOU" : reporter.crewmate.crewName,
                                     viewport: sceneSize)
        overlay.zPosition = 950
        overlay.setScale(fitScale(for: overlay.contentSize))
        cam.addChild(overlay)   // camera child → always screen-centered
        overlay.onFinished = { [weak self] ejected in
            self?.endMeeting(ejected: ejected)
        }
        meeting = overlay
    }

    private func endMeeting(ejected: Participant?) {
        meeting?.removeFromParent()
        meeting = nil

        if let ejected {
            ejected.isAlive = false
            ejected.crewmate.removeFromParent()
        }
        // Clear all bodies
        for b in bodies { b.removeFromParent() }
        bodies = []

        // Reset witnesses & cooldowns, gather survivors in Cafeteria
        let cafe = map.room(named: "Cafeteria")!.rect
        let aliveList = participants.filter { $0.isAlive }
        for (i, p) in aliveList.enumerated() {
            let a = CGFloat(i) / CGFloat(max(1, aliveList.count)) * 2 * .pi
            p.crewmate.position = CGPoint(x: cafe.midX + cos(a) * 140, y: cafe.midY + sin(a) * 95)
            if let bot = bots.first(where: { $0.participant === p }) {
                bot.killCooldown = TimeInterval.random(in: 18...26)
                bot.state = .idle
            }
        }
        for p in participants { p.witnesses = [] }
        playerKillCooldown = 12
        witnessedKillBy = nil

        meetingActive = false
        checkWin()
    }

    // MARK: - Win / lose

    private func checkWin() {
        guard !gameOver else { return }
        let aliveCrewBots = participants.filter { !$0.isImpostor && !$0.isPlayer && $0.isAlive }
        let impostorsAlive = participants.filter { $0.isImpostor && $0.isAlive }
        let playerAlive = playerParticipant?.isAlive ?? false

        var won: Bool? = nil
        var text = ""

        if role == .impostor {
            if !playerAlive {
                won = false; text = "You were ejected into space."
            } else if progress.isComplete {
                won = false; text = "The crew completed all tasks."
            } else if aliveCrewBots.isEmpty {
                won = true; text = "You eliminated the entire crew."
            }
        } else {
            if progress.isComplete {
                won = true; text = "All tasks complete. The ship is safe!"
            } else if impostorsAlive.isEmpty {
                won = true; text = "The Impostor was ejected. Crew wins!"
            } else if aliveCrewBots.isEmpty {
                won = false; text = "The Impostor took over the ship."
            }
        }

        if let won {
            gameOver = true
            closeCCTV()
            minimap?.removeFromParent(); minimap = nil
            showEndScreen(victory: won, message: text)
        }
    }

    private func showEndScreen(victory: Bool, message: String) {
        let overlay = SKNode()
        overlay.zPosition = 1000

        let dark = SKShapeNode(rectOf: CGSize(width: 6000, height: 4000))
        dark.fillColor = UIColor(white: 0, alpha: 0.78)
        dark.strokeColor = .clear
        overlay.addChild(dark)

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = victory ? "VICTORY" : "DEFEAT"
        title.fontSize = 84
        title.fontColor = victory ? UIColor(red: 0.35, green: 0.9, blue: 0.45, alpha: 1) : UIColor(red: 0.95, green: 0.25, blue: 0.25, alpha: 1)
        title.position = CGPoint(x: 0, y: 130)
        overlay.addChild(title)

        let face = SKSpriteNode(texture: CrewSheet.shared.texture(color: playerParticipant?.crewmate.color ?? .red, frame: 0))
        face.size = CGSize(width: 100, height: 130)
        face.position = CGPoint(x: 0, y: 20)
        overlay.addChild(face)

        let msg = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        msg.text = message
        msg.fontSize = isPortrait ? 18 : 24
        msg.fontColor = .white
        msg.position = CGPoint(x: 0, y: -80)
        overlay.addChild(msg)

        let buttonOffset: CGFloat = isPortrait ? 85 : 150
        func makeButton(_ text: String, _ name: String, _ color: UIColor, _ x: CGFloat) -> SKShapeNode {
            let bw: CGFloat = isPortrait ? 130 : 260
            let b = SKShapeNode(rect: CGRect(x: -bw / 2, y: -30, width: bw, height: 60), cornerRadius: 15)
            b.fillColor = color
            b.strokeColor = .clear
            b.name = name
            b.position = CGPoint(x: x, y: -170)
            let l = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            l.text = text
            l.fontSize = isPortrait ? 16 : 22
            l.fontColor = .white
            l.position = CGPoint(x: 0, y: -8)
            b.addChild(l)
            return b
        }
        overlay.addChild(makeButton("PLAY AGAIN", "end_again", UIColor(red: 0.2, green: 0.65, blue: 0.35, alpha: 1), -buttonOffset))
        overlay.addChild(makeButton("MAIN MENU", "end_menu", UIColor(white: 0.35, alpha: 1), buttonOffset))
        overlay.setScale(fitScale(for: CGSize(width: 460, height: 400)))
        cam.addChild(overlay)
        endOverlay = overlay
    }

    // MARK: - CCTV (CCTVSystem.cs)

    private func setupCCTVStation() {
        camRooms = ["Cafeteria", "Upper Engine", "Storage", "Navigation"].compactMap { map.room(named: $0) }
        guard let sec = map.room(named: "Security") else { return }
        let node = SKNode()
        node.position = CGPoint(x: sec.rect.midX + 40, y: sec.rect.midY - 20)
        node.name = "cctv_station"
        let desk = SKShapeNode(rectOf: CGSize(width: 66, height: 46), cornerRadius: 8)
        desk.fillColor = UIColor(white: 0.2, alpha: 1)
        desk.strokeColor = UIColor(white: 0.8, alpha: 1)
        desk.lineWidth = 3
        let scr = SKShapeNode(rectOf: CGSize(width: 44, height: 26), cornerRadius: 4)
        scr.fillColor = UIColor(red: 0.9, green: 0.3, blue: 0.25, alpha: 0.85)
        scr.strokeColor = .clear
        node.addChild(desk)
        node.addChild(scr)
        world.addChild(node)
    }

    var cctvStationPosition: CGPoint {
        guard let sec = map.room(named: "Security") else { return .zero }
        return CGPoint(x: sec.rect.midX + 40, y: sec.rect.midY - 20)
    }

    private func openCCTV() {
        cctvActive = true
        cancelScan()
        let ui = SKNode()
        ui.zPosition = 500

        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = "● CAMERA FEED"
        label.fontSize = 24
        label.fontColor = UIColor(red: 0.95, green: 0.3, blue: 0.3, alpha: 1)
        ui.addChild(label)
        cctvFeedLabel = label

        cctvCamShapes = []
        for i in 0..<camRooms.count {
            let b = SKShapeNode()
            b.fillColor = UIColor(white: 0.15, alpha: 1)
            b.strokeColor = UIColor(white: 0.7, alpha: 1)
            b.lineWidth = 2
            b.name = "cam_\(i)"
            let l = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            l.text = "CAM \(i + 1)"
            l.fontSize = 16
            l.fontColor = .white
            l.position = CGPoint(x: 0, y: -6)
            b.addChild(l)
            ui.addChild(b)
            cctvCamShapes.append(b)
        }

        let close = SKShapeNode(rect: CGRect(x: -60, y: -22, width: 120, height: 44), cornerRadius: 12)
        close.fillColor = UIColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1)
        close.strokeColor = .clear
        close.name = "cctv_close"
        let cl = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        cl.text = "EXIT"
        cl.fontSize = 19
        cl.fontColor = .white
        cl.position = CGPoint(x: 0, y: -7)
        close.addChild(cl)
        ui.addChild(close)
        cctvExitButton = close

        // Scanlines
        let stripes = SKSpriteNode(texture: makeScanlinesTexture())
        stripes.alpha = 0.5
        stripes.zPosition = -1
        ui.addChild(stripes)
        cctvScanlines = stripes

        cam.addChild(ui)
        cctvUI = ui
        layoutCCTVUI()
        cctvIndex = 0
    }

    /// Positions the CCTV chrome for the current aspect (rotation-safe).
    private func layoutCCTVUI() {
        let w = sceneSize.width, h = sceneSize.height
        let portrait = isPortrait

        cctvFeedLabel?.fontSize = portrait ? 18 : 24
        cctvFeedLabel?.position = portrait
            ? CGPoint(x: -w / 2 + 96, y: h / 2 - 56)
            : CGPoint(x: -w / 2 + 150, y: h / 2 - 50)

        let bw: CGFloat = portrait ? 80 : 140
        for (i, b) in cctvCamShapes.enumerated() {
            b.path = CGPath(roundedRect: CGRect(x: -bw / 2, y: -20, width: bw, height: 40),
                            cornerWidth: 10, cornerHeight: 10, transform: nil)
            b.position = portrait
                ? CGPoint(x: -135 + CGFloat(i) * 90, y: -h / 2 + 64)
                : CGPoint(x: -270 + CGFloat(i) * 180, y: -h / 2 + 60)
        }

        cctvExitButton?.position = portrait
            ? CGPoint(x: w / 2 - 70, y: h / 2 - 56)
            : CGPoint(x: w / 2 - 90, y: -h / 2 + 62)

        cctvScanlines?.size = CGSize(width: w * 1.2, height: h * 1.2)
    }

    private func closeCCTV() {
        cctvActive = false
        cctvUI?.removeFromParent()
        cctvUI = nil
    }

    // MARK: - HUD

    private var sceneSize: CGSize { size }

    private func buildHUD() {
        guard !hudBuilt else { return }
        hudBuilt = true

        progressCaption = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        progressCaption.text = role == .impostor ? "CREW TASK PROGRESS" : "TASK PROGRESS"
        progressCaption.fontSize = 14
        progressCaption.fontColor = UIColor(white: 0.8, alpha: 1)
        progressCaption.horizontalAlignmentMode = .left
        cam.addChild(progressCaption)

        progressBarBg = SKShapeNode()
        progressBarBg.name = "progressBarBg"
        progressBarBg.fillColor = UIColor(white: 0.12, alpha: 1)
        progressBarBg.strokeColor = UIColor(white: 0.9, alpha: 0.6)
        progressBarBg.lineWidth = 2
        cam.addChild(progressBarBg)

        progressBarFill = SKShapeNode()
        progressBarFill.fillColor = UIColor(red: 0.25, green: 0.85, blue: 0.4, alpha: 1)
        progressBarFill.strokeColor = .clear
        progressBarFill.xScale = 0.0001
        cam.addChild(progressBarFill)

        progressPct = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        progressPct.fontSize = 15
        progressPct.fontColor = .white
        cam.addChild(progressPct)

        roomLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        roomLabel.fontSize = 24
        roomLabel.fontColor = UIColor(white: 1, alpha: 0.85)
        cam.addChild(roomLabel)

        useButton = makeRoundButton(radius: 44, label: "USE", color: UIColor(red: 0.95, green: 0.85, blue: 0.2, alpha: 1), name: "btn_use")
        cam.addChild(useButton)

        reportButton = makeRoundButton(radius: 40, label: "REPORT", color: UIColor(red: 0.9, green: 0.25, blue: 0.2, alpha: 1), name: "btn_report", fontSize: 15)
        cam.addChild(reportButton)

        if role == .impostor {
            let kb = makeRoundButton(radius: 40, label: "KILL", color: UIColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1), name: "btn_kill")
            let cd = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            cd.fontSize = 22
            cd.fontColor = .white
            cd.position = CGPoint(x: 0, y: -7)
            cd.zPosition = 5
            kb.addChild(cd)
            killCooldownLabel = cd
            killButton = kb
            cam.addChild(kb)
        }

        mapButton = makeRoundButton(radius: 30, label: "MAP", color: UIColor(white: 0.25, alpha: 1), name: "btn_map", fontSize: 15)
        cam.addChild(mapButton)

        joyBase.fillColor = UIColor(white: 1, alpha: 0.06)
        joyBase.strokeColor = UIColor(white: 1, alpha: 0.35)
        joyBase.lineWidth = 3
        joyBase.zPosition = 50
        joyBase.isHidden = true
        cam.addChild(joyBase)
        joyKnob.fillColor = UIColor(white: 1, alpha: 0.3)
        joyKnob.strokeColor = .clear
        joyKnob.zPosition = 51
        joyKnob.isHidden = true
        cam.addChild(joyKnob)

        toastLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        toastLabel.fontSize = 22
        toastLabel.fontColor = UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)
        toastLabel.zPosition = 60
        toastLabel.numberOfLines = 3
        toastLabel.lineBreakMode = .byWordWrapping
        toastLabel.alpha = 0
        cam.addChild(toastLabel)

        setButton(useButton, enabled: false)
        setButton(reportButton, enabled: false)
        if let kb = killButton { setButton(kb, enabled: false) }

        layoutHUD()
    }

    /// Positions the HUD for the current aspect (landscape classic, portrait
    /// stacked below the notch with a right-edge action column).
    private func layoutHUD() {
        let w = sceneSize.width, h = sceneSize.height

        if isPortrait {
            // Clear the notch / Dynamic Island and the home indicator.
            roomLabel.fontSize = 20
            roomLabel.position = CGPoint(x: 0, y: h / 2 - 76)

            let barW: CGFloat = 190
            progressBarBg.path = CGPath(roundedRect: CGRect(x: -barW / 2, y: -10, width: barW, height: 20), cornerWidth: 10, cornerHeight: 10, transform: nil)
            progressBarBg.position = CGPoint(x: 0, y: h / 2 - 104)
            progressBarFill.path = CGPath(roundedRect: CGRect(x: -barW / 2 + 4, y: -7, width: barW - 8, height: 14), cornerWidth: 7, cornerHeight: 7, transform: nil)
            progressBarFill.position = progressBarBg.position
            progressPct.fontSize = 13
            progressPct.position = CGPoint(x: -barW / 2 - 30, y: h / 2 - 109)
            progressCaption.isHidden = true

            mapButton.position = CGPoint(x: w / 2 - 56, y: h / 2 - 150)

            useButton.position = CGPoint(x: w / 2 - 72, y: -h / 2 + 108)
            if role == .impostor {
                killButton?.position = CGPoint(x: w / 2 - 72, y: -h / 2 + 216)
                reportButton.position = CGPoint(x: -w / 2 + 72, y: -h / 2 + 108)
            } else {
                reportButton.position = CGPoint(x: w / 2 - 72, y: -h / 2 + 216)
            }

            toastLabel.fontSize = 15
            toastLabel.position = CGPoint(x: 0, y: h * 0.20)
        } else {
            roomLabel.fontSize = 24
            roomLabel.position = CGPoint(x: 0, y: h / 2 - 44)

            let barX = -w / 2 + 190, barY = h / 2 - 40
            let barW: CGFloat = 300
            progressBarBg.path = CGPath(roundedRect: CGRect(x: -barW / 2, y: -10, width: barW, height: 20), cornerWidth: 10, cornerHeight: 10, transform: nil)
            progressBarBg.position = CGPoint(x: barX, y: barY)
            progressBarFill.path = CGPath(roundedRect: CGRect(x: -barW / 2 + 4, y: -7, width: barW - 8, height: 14), cornerWidth: 7, cornerHeight: 7, transform: nil)
            progressBarFill.position = progressBarBg.position
            progressPct.fontSize = 15
            progressPct.position = CGPoint(x: barX + 175, y: barY - 5)
            progressCaption.isHidden = false
            progressCaption.position = CGPoint(x: barX - 150, y: barY + 16)

            mapButton.position = CGPoint(x: w / 2 - 60, y: h / 2 - 50)

            useButton.position = CGPoint(x: w / 2 - 90, y: -h / 2 + 100)
            if role == .impostor {
                killButton?.position = CGPoint(x: w / 2 - 200, y: -h / 2 + 150)
                reportButton.position = CGPoint(x: w / 2 - 200, y: -h / 2 + 60)
            } else {
                reportButton.position = CGPoint(x: w / 2 - 200, y: -h / 2 + 150)
            }

            toastLabel.fontSize = 20
            toastLabel.position = CGPoint(x: 0, y: h * 0.28)
        }
    }

    private func makeRoundButton(radius: CGFloat, label: String, color: UIColor, name: String, fontSize: CGFloat = 18) -> SKNode {
        let node = SKNode()
        node.name = name
        let circle = SKShapeNode(circleOfRadius: radius)
        circle.fillColor = color
        circle.strokeColor = UIColor(white: 0, alpha: 0.35)
        circle.lineWidth = 4
        circle.name = name
        node.addChild(circle)
        let l = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        l.text = label
        l.fontSize = fontSize
        l.fontColor = UIColor(white: 0.1, alpha: 1)
        l.position = CGPoint(x: 0, y: -fontSize / 2.6)
        l.name = name
        node.addChild(l)
        return node
    }

    private func setButton(_ node: SKNode?, enabled: Bool) {
        node?.alpha = enabled ? 1 : 0.25
    }

    private func refreshTaskList() {
        taskListLabels.forEach { $0.removeFromParent() }
        taskListLabels = []
        guard let you = playerParticipant else { return }
        let baseX = -sceneSize.width / 2 + (isPortrait ? 16 : 20)
        let baseY = sceneSize.height / 2 - (isPortrait ? 150 : 90)
        let header = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        header.text = you.isImpostor ? "FAKE TASKS:" : "YOUR TASKS:"
        header.fontSize = isPortrait ? 12 : 14
        header.fontColor = you.isImpostor ? UIColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 1) : UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
        header.horizontalAlignmentMode = .left
        header.position = CGPoint(x: baseX, y: baseY)
        cam.addChild(header)
        taskListLabels.append(header)

        let step: CGFloat = isPortrait ? 17 : 18
        for (i, tid) in you.remainingTaskIds.prefix(6).enumerated() {
            if let st = stations.first(where: { $0.id == tid }) {
                let l = SKLabelNode(fontNamed: "AvenirNext-Medium")
                l.text = "• \(st.kind.displayName) — \(st.roomName)"
                l.fontSize = isPortrait ? 12 : 13
                l.fontColor = UIColor(white: 0.85, alpha: 1)
                l.horizontalAlignmentMode = .left
                l.position = CGPoint(x: baseX, y: baseY - 20 - CGFloat(i) * step)
                cam.addChild(l)
                taskListLabels.append(l)
            }
        }
    }

    private func updateHUD(_ dt: TimeInterval) {
        guard let you = playerParticipant else { return }

        let f = progress.fraction
        progressBarFill.xScale = max(0.0001, f)
        progressPct.text = "\(Int(f * 100))%"

        if cctvActive {
            roomLabel.text = "CAM \(cctvIndex + 1): \(camRooms.isEmpty ? "" : camRooms[cctvIndex].name)"
        } else {
            roomLabel.text = map.room(at: you.crewmate.position)?.name ?? ""
        }

        if gameOver || meetingActive { return }

        // USE button: nearest usable station or the CCTV desk
        var usable = false
        if !cctvActive {
            var best = CGFloat(95)
            for st in stations where !st.completed {
                let d = hypot(st.position.x - you.crewmate.position.x, st.position.y - you.crewmate.position.y)
                if d < best { best = d; usable = true }
            }
            let cctvD = hypot(cctvStationPosition.x - you.crewmate.position.x, cctvStationPosition.y - you.crewmate.position.y)
            if cctvD < 90 { usable = true }
        }
        setButton(useButton, enabled: usable)

        // REPORT button
        let nearBody = bodies.contains { hypot($0.position.x - you.crewmate.position.x, $0.position.y - you.crewmate.position.y) < 150 }
        setButton(reportButton, enabled: nearBody && you.isAlive)

        // KILL button
        if role == .impostor, let kb = killButton {
            var target: Participant?
            if you.isAlive && playerKillCooldown <= 0 {
                target = participants.first {
                    $0.isAlive && !$0.isPlayer && !$0.isImpostor &&
                    hypot($0.crewmate.position.x - you.crewmate.position.x, $0.crewmate.position.y - you.crewmate.position.y) < 115
                }
            }
            setButton(kb, enabled: target != nil)
            if playerKillCooldown > 0 {
                killCooldownLabel?.text = "\(Int(ceil(playerKillCooldown)))"
                killCooldownLabel?.isHidden = false
            } else {
                killCooldownLabel?.isHidden = true
            }
        }
    }

    private func showToast(_ text: String) {
        guard let toast = toastLabel else { return }
        let fontSize: CGFloat = isPortrait ? 15 : 20
        let maxWidth = sceneSize.width - (isPortrait ? 56 : 120)
        let font = UIFont(name: "AvenirNext-DemiBold", size: fontSize) ?? .systemFont(ofSize: fontSize)
        let lines = wrap(text: text, font: font, maxWidth: maxWidth)
        toast.text = lines.joined(separator: "\n")
        toast.fontSize = fontSize
        toast.numberOfLines = max(1, lines.count)
        toast.removeAllActions()
        toast.alpha = 1
        toast.run(.sequence([.wait(forDuration: 3.2), .fadeOut(withDuration: 0.8)]))
    }

    /// Greedy word wrap so toasts stay inside the viewport in portrait.
    private func wrap(text: String, font: UIFont, maxWidth: CGFloat) -> [String] {
        guard (text as NSString).size(withAttributes: [.font: font]).width > maxWidth else { return [text] }
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ") {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if (candidate as NSString).size(withAttributes: [.font: font]).width <= maxWidth || current.isEmpty {
                current = candidate
            } else {
                lines.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    // MARK: - Minimap

    private func toggleMinimap() {
        if minimap != nil {
            minimap?.removeFromParent()
            minimap = nil
            return
        }
        let panel = SKNode()
        panel.zPosition = 700

        let portrait = isPortrait
        let panelW: CGFloat = portrait ? min(sceneSize.width - 28, 350) : 620
        let mapW: CGFloat = portrait ? panelW - 44 : 560
        let mapH = SkeldMap.worldSize.height * (mapW / SkeldMap.worldSize.width)
        let panelH: CGFloat = portrait ? mapH + 96 : 420

        let bgPanel = SKShapeNode(rectOf: CGSize(width: panelW, height: panelH), cornerRadius: 20)
        bgPanel.fillColor = UIColor(white: 0.08, alpha: 0.96)
        bgPanel.strokeColor = UIColor(white: 0.8, alpha: 0.6)
        bgPanel.lineWidth = 4
        panel.addChild(bgPanel)

        let mapSprite = SKSpriteNode(texture: map.makeFloorTexture())
        let scale = mapW / SkeldMap.worldSize.width
        mapSprite.size = CGSize(width: SkeldMap.worldSize.width * scale, height: SkeldMap.worldSize.height * scale)
        let mapY: CGFloat = portrait ? 16 : 8
        mapSprite.position = CGPoint(x: 0, y: mapY)
        panel.addChild(mapSprite)

        func toMap(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - SkeldMap.worldSize.width / 2) * scale,
                    y: (p.y - SkeldMap.worldSize.height / 2) * scale + mapY)
        }

        let dotR: CGFloat = portrait ? 7 : 8
        if let you = playerParticipant, !you.isImpostor {
            for tid in you.remainingTaskIds {
                if let st = stations.first(where: { $0.id == tid }) {
                    let dot = SKShapeNode(circleOfRadius: dotR)
                    dot.fillColor = UIColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
                    dot.strokeColor = .clear
                    dot.position = toMap(st.position)
                    panel.addChild(dot)
                }
            }
        }

        if let you = playerParticipant {
            let dot = SKShapeNode(circleOfRadius: dotR + 2)
            dot.fillColor = you.crewmate.color.uiColor
            dot.strokeColor = .white
            dot.lineWidth = 3
            dot.position = toMap(you.crewmate.position)
            panel.addChild(dot)
        }

        let hint = SKLabelNode(fontNamed: "AvenirNext-Medium")
        hint.text = "Tap anywhere to close · yellow = your tasks"
        hint.fontSize = portrait ? 12 : 14
        hint.fontColor = UIColor(white: 0.7, alpha: 1)
        hint.position = CGPoint(x: 0, y: -panelH / 2 + 22)
        panel.addChild(hint)

        cam.addChild(panel)
        minimap = panel
    }

    // MARK: - Interactions

    private func useAction() {
        guard let you = playerParticipant else { return } // ghosts keep doing tasks
        if cctvActive { return }

        // CCTV desk?
        if hypot(cctvStationPosition.x - you.crewmate.position.x, cctvStationPosition.y - you.crewmate.position.y) < 90 {
            openCCTV()
            return
        }

        var best = CGFloat(95); var target: TaskStation?
        for st in stations where !st.completed {
            let d = hypot(st.position.x - you.crewmate.position.x, st.position.y - you.crewmate.position.y)
            if d < best { best = d; target = st }
        }
        guard let st = target else { return }

        switch st.kind {
        case .download:
            openOverlay(DownloadOverlay(), station: st)
        case .cardSwipe:
            openOverlay(CardSwipeOverlay(), station: st)
        case .wiring:
            openOverlay(WiringOverlay(), station: st)
        case .scan:
            beginScan(station: st)
        }
    }

    private func openOverlay(_ overlay: MinigameOverlay, station: TaskStation) {
        cancelScan()
        activeOverlay = overlay
        overlay.onComplete = { [weak self] in
            self?.activeOverlay = nil
            self?.completeMyTask(station)
            self?.refreshTaskList()
        }
        overlay.onClose = { [weak self] in
            self?.activeOverlay = nil
        }
        overlay.position = .zero
        overlay.setScale(fitScale(for: overlay.contentSize))
        cam.addChild(overlay)   // camera child → always screen-centered
    }

    private func beginScan(station: TaskStation) {
        scanStation = station
        scanProgress = 0
        let bar = SKNode()
        let bg = SKShapeNode(rectOf: CGSize(width: 96, height: 18), cornerRadius: 9)
        bg.fillColor = UIColor(white: 0.1, alpha: 0.8)
        bg.strokeColor = .white
        bg.lineWidth = 2
        bar.addChild(bg)
        let fill = SKShapeNode(rect: CGRect(x: -44, y: -5, width: 1, height: 10), cornerRadius: 0)
        fill.fillColor = UIColor(red: 0.3, green: 0.95, blue: 0.7, alpha: 1)
        fill.strokeColor = .clear
        fill.name = "fill"
        bar.addChild(fill)
        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.text = "SCANNING…"
        label.fontSize = 13
        label.fontColor = .white
        label.position = CGPoint(x: 0, y: 22)
        bar.addChild(label)
        bar.zPosition = 40
        bar.position = CGPoint(x: 0, y: 60)
        playerParticipant?.crewmate.addChild(bar)
        scanBar = bar
    }

    private func reportAction() {
        guard let you = playerParticipant, you.isAlive else { return }
        guard let body = bodies.first(where: { hypot($0.position.x - you.crewmate.position.x, $0.position.y - you.crewmate.position.y) < 150 }) else { return }
        beginMeeting(reporter: you, bodyPosition: body.position)
    }

    private func killAction() {
        guard let you = playerParticipant, you.isImpostor, you.isAlive, playerKillCooldown <= 0 else { return }
        guard let victim = participants.first(where: {
            $0.isAlive && !$0.isPlayer && !$0.isImpostor &&
            hypot($0.crewmate.position.x - you.crewmate.position.x, $0.crewmate.position.y - you.crewmate.position.y) < 115
        }) else { return }

        let victimPos = victim.crewmate.position
        performKill(killer: you, victim: victim)
        you.crewmate.position = victimPos
        playerKillCooldown = 25
    }

    // MARK: - Touch input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let camLocation = touch.location(in: cam)

        if minimap != nil {
            toggleMinimap()
            return
        }

        if let name = nodeAt(location, names: ["btn_use", "btn_report", "btn_kill", "btn_map", "end_again", "end_menu",
                                               "cam_0", "cam_1", "cam_2", "cam_3", "cctv_close"]) {
            handleButton(name)
            return
        }

        if cctvActive { return }

        if camLocation.x < -sceneSize.width * 0.12 && !movementLocked {
            joystickActive = true
            joystickTouch = touch
            joyBase.position = camLocation
            joyBase.isHidden = false
            joyKnob.position = camLocation
            joyKnob.isHidden = false
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch == joystickTouch, joystickActive else { return }
        let camLocation = touch.location(in: cam)
        var v = CGVector(dx: camLocation.x - joyBase.position.x, dy: camLocation.y - joyBase.position.y)
        let len = hypot(v.dx, v.dy)
        let maxR: CGFloat = 58
        if len > maxR { v = CGVector(dx: v.dx / len * maxR, dy: v.dy / len * maxR) }
        joyKnob.position = CGPoint(x: joyBase.position.x + v.dx, y: joyBase.position.y + v.dy)
        joystickVector = CGVector(dx: v.dx / maxR, dy: v.dy / maxR)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first, touch == joystickTouch {
            joystickActive = false
            joystickTouch = nil
            joystickVector = .zero
            joyBase.isHidden = true
            joyKnob.isHidden = true
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    /// Find a named button among the hit subtree (buttons are camera children).
    private func nodeAt(_ location: CGPoint, names: [String]) -> String? {
        var node: SKNode? = atPoint(location)
        while let n = node {
            if let name = n.name, names.contains(name) { return name }
            node = n.parent
        }
        for n in nodes(at: location).reversed() {
            if let name = n.name, names.contains(name) { return name }
        }
        return nil
    }

    private func handleButton(_ name: String) {
        switch name {
        case "btn_use": useAction()
        case "btn_report": reportAction()
        case "btn_kill": killAction()
        case "btn_map": toggleMinimap()
        case "cctv_close": closeCCTV()
        case "cam_0": cctvIndex = 0
        case "cam_1": cctvIndex = 1
        case "cam_2": cctvIndex = 2
        case "cam_3": cctvIndex = 3
        case "end_again":
            let scene = GameScene(role: role)
            scene.scaleMode = .resizeFill
            view?.presentScene(scene, transition: .fade(withDuration: 0.4))
        case "end_menu":
            let scene = MainMenuScene(size: sceneSize)
            scene.scaleMode = .resizeFill
            view?.presentScene(scene, transition: .fade(withDuration: 0.4))
        default: break
        }
    }

    // MARK: - Keyboard (forwarded by GameViewController)

    func keyPressed(_ key: UIKeyboardHIDUsage, isDown: Bool) {
        if isDown {
            keyDirs.insert(key)
            switch key {
            case .keyboardE: if !movementLocked { useAction() }
            case .keyboardR: if !movementLocked { reportAction() }
            case .keyboardQ: if !movementLocked { killAction() }
            case .keyboardM: toggleMinimap()
            case .keyboardEscape:
                if cctvActive { closeCCTV() }
                else if activeOverlay != nil { activeOverlay?.close() }
                else if minimap != nil { toggleMinimap() }
            default: break
            }
        } else {
            keyDirs.remove(key)
        }
    }

    // MARK: - Textures

    private func makeStarsTexture() -> SKTexture {
        let size = CGSize(width: 3000, height: 2100)
        // Explicit scale 1 — at the device's 3x scale the bitmap would be
        // 9000x6300, over the simulator GPU's max texture size (8192).
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let img = renderer.image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(red: 0.045, green: 0.05, blue: 0.09, alpha: 1).cgColor)
            c.fill(CGRect(origin: .zero, size: size))
            for _ in 0..<420 {
                let x = CGFloat.random(in: 0...size.width)
                let y = CGFloat.random(in: 0...size.height)
                let r = CGFloat.random(in: 0.7...2.4)
                let a = CGFloat.random(in: 0.25...0.95)
                c.setFillColor(UIColor(white: 1, alpha: a).cgColor)
                c.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
        }
        return SKTexture(image: img)
    }

    private func makeScanlinesTexture() -> SKTexture {
        let size = CGSize(width: 64, height: 64)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let img = renderer.image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(white: 0, alpha: 0.22).cgColor)
            for y in stride(from: CGFloat(0), to: size.height, by: 4) {
                c.fill(CGRect(x: 0, y: y, width: size.width, height: 2))
            }
        }
        return SKTexture(image: img)
    }
}
