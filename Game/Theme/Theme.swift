import UIKit

// MARK: - Hex convenience

extension UIColor {
    /// `UIColor(hex: 0xFAF8F5)` — sRGB, opaque.
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Color tokens (light "Academic Campus Pastel")

/// Single source of truth for every color in the game. Screens must reference
/// these tokens — never inline UIColor literals. Deeper "ink" variants exist
/// so accent-colored text and fills still meet WCAG AA on light surfaces.
enum ThemeColors {
    // Surfaces
    static let bg            = UIColor(hex: 0xFAF8F5) // warm off-white paper
    static let surface       = UIColor(hex: 0xFFFFFF)
    static let surface2      = UIColor(hex: 0xF3F0EB)
    static let divider       = UIColor(hex: 0xE8E4DE)

    // Accents
    static let primary       = UIColor(hex: 0xA8D0E6) // pastel blue
    static let mint          = UIColor(hex: 0xB8E0D2)
    static let peach         = UIColor(hex: 0xF9C9B6)
    static let lavender      = UIColor(hex: 0xD6C9E8)
    static let butter        = UIColor(hex: 0xFCEBB0)

    // Semantic
    static let danger        = UIColor(hex: 0xF4A6A6) // soft coral
    static let success       = UIColor(hex: 0xA8D5BA) // sage

    // Deep ("ink") variants — for text on light fills and for fills that
    // must carry white/light text. All pair with `text` at ≥ 4.5:1.
    static let coralDeep     = UIColor(hex: 0xC75B5B)
    static let sageDeep      = UIColor(hex: 0x4E8A6A)
    static let primaryDeep   = UIColor(hex: 0x4C7A99)
    static let mintDeep      = UIColor(hex: 0x3F8A73)
    static let butterInk     = UIColor(hex: 0x8A6A1E) // amber text on light bg

    // Text
    static let text          = UIColor(hex: 0x3A3A4A) // soft charcoal, never black
    static let textSecondary = UIColor(hex: 0x8A8A99)
    static let textOnDark    = UIColor.white          // over `overlayDark` only

    // Lines & overlays
    static let line          = UIColor(hex: 0xC9C2B8) // soft warm stroke
    static let lineStrong    = UIColor(hex: 0xAFA89B)
    static let overlayDark   = UIColor(hex: 0x2E2E3A) // modal scrims (soft, warm)

    /// Player roster pastels — index order MUST match `CrewColor` and the
    /// character sheet row order (see Art/generate_characters.py).
    static let playerPastels: [UInt32] = [
        0xE8A0A4, // rose
        0xA3C7E8, // sky
        0xA8D5BA, // mint
        0xF5C6A5, // peach
        0xF2B880, // apricot
        0xF2DE8A, // lemon
        0x9BA8D9, // periwinkle
        0xF3D9D9, // blush
        0xC6AFE3, // lilac
        0xA3DED8, // aqua
    ]
}

// MARK: - Typography

/// SF Pro Rounded resolved through a font descriptor so SKLabelNode (which
/// takes a font *name*) gets the rounded design too. Falls back to the plain
/// system face if `.rounded` is unavailable on the running OS.
enum ThemeFonts {
    static let heavy: String = roundedName(.semibold) // was AvenirNext-Heavy
    static let demi:  String = roundedName(.medium)   // was AvenirNext-DemiBold
    static let med:   String = roundedName(.regular)  // was AvenirNext-Medium

    private static func roundedName(_ weight: UIFont.Weight) -> String {
        let base = UIFont.systemFont(ofSize: 16, weight: weight)
        let desc = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        return UIFont(descriptor: desc, size: 16).fontName
    }
}

// MARK: - Metrics

/// 8-pt grid.
enum ThemeSpacing {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24
    static let s6: CGFloat = 32
}

enum ThemeRadius {
    static let card: CGFloat = 16
    static let button: CGFloat = 12
    static let modal: CGFloat = 24
    static let capsule: CGFloat = 999
}

// MARK: - Theme entry point

enum Theme {
    /// Gated flag for the (optional, future) menu ambient layer — drifting
    /// clouds / paper planes. The layer does not exist yet; when added it
    /// must also honor UIAccessibility.isReduceMotionEnabled.
    static var enableAmbientMotion: Bool = true

    static var colors: ThemeColors.Type { ThemeColors.self }
}
