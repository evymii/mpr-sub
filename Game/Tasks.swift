import Foundation
import CoreGraphics

enum TaskKind: String, Codable, CaseIterable {
    case download     // port of DownloadMinigame.cs
    case cardSwipe    // port of CardSwapTask.cs
    case wiring       // extra: connect matching wires
    case scan         // extra: stand in the MedBay scanner

    var displayName: String {
        switch self {
        case .download:  return "Download Data"
        case .cardSwipe: return "Swipe Card"
        case .wiring:    return "Fix Wiring"
        case .scan:      return "Submit Scan"
        }
    }
}

/// A physical station in the world the player can interact with
/// (Unity: InteractableObject trigger area + action button).
struct TaskStation: Identifiable, Hashable {
    let id: Int
    let kind: TaskKind
    let roomName: String
    let position: CGPoint
    var completed: Bool = false

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: TaskStation, r: TaskStation) -> Bool { l.id == r.id }
}

/// Port of ProgressTasks.cs — shared task progress for the whole crew.
final class ProgressTracker {
    private(set) var totalTasks = 0
    private(set) var completedTasks = 0

    var fraction: CGFloat { totalTasks == 0 ? 0 : CGFloat(completedTasks) / CGFloat(totalTasks) }
    var isComplete: Bool { totalTasks > 0 && completedTasks >= totalTasks }

    func register(count: Int) { totalTasks += count }

    func completeOne() {
        completedTasks = min(totalTasks, completedTasks + 1)
    }

    func reset() { totalTasks = 0; completedTasks = 0 }
}

/// All stations on The Skeld. The player gets a personal subset as their tasks;
/// bots walk to stations too (their fake or real work).
enum TaskBoard {
    static func allStations() -> [TaskStation] {
        var id = 0
        func st(_ kind: TaskKind, _ room: String, _ x: CGFloat, _ y: CGFloat) -> TaskStation {
            id += 1
            return TaskStation(id: id, kind: kind, roomName: room, position: CGPoint(x: x, y: y))
        }
        return [
            // Downloads (DownloadMinigame consoles) spread across the ship
            st(.download, "Weapons",        1740, 1180),
            st(.download, "Navigation",     2180,  830),
            st(.download, "Electrical",      600,  480),
            st(.download, "Cafeteria",      1180, 1290),
            st(.download, "Communications", 1560,  150),
            st(.download, "Upper Engine",    430, 1200),
            // Card swipe (CardSwapTask) in Admin
            st(.cardSwipe, "Admin",         1330,  700),
            // Wiring panels
            st(.wiring, "Electrical",        760,  340),
            st(.wiring, "Admin",            1500,  700),
            st(.wiring, "Navigation",      2110,  690),
            // MedBay scanner
            st(.scan, "MedBay",              810,  950),
        ]
    }

    /// Random personal task list (Among Us gives each crewmate ~6).
    static func assignTasks(count: Int, from stations: [TaskStation]) -> [Int] {
        Array(stations.shuffled().prefix(count).map(\.id))
    }
}
