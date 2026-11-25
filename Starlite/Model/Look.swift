import SwiftUI

/// A colour that can be saved.
struct RGBA: Codable, Hashable {
    var r: Double, g: Double, b: Double, a: Double = 1

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(_ c: Color) {
        let u = UIColor(c)
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 1)
        u.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(Double(r), Double(g), Double(b), Double(a))
    }

    var color: Color { Color(red: r, green: g, blue: b, opacity: a) }
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
}

enum ThemeKind: String, Codable, CaseIterable, Identifiable {
    case dark, light, cherry, stars, bubbles, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .cherry: "Cherry Blossom"
        case .stars: "Stars"
        case .bubbles: "Bubbles"
        case .custom: "Custom"
        }
    }
    var animated: Bool { self == .cherry || self == .stars || self == .bubbles }
}

/// How panels look (the tab bar is always Apple's Liquid Glass).
enum PanelStyle: String, Codable, CaseIterable, Identifiable {
    case liquid, frosted, solid
    var id: String { rawValue }
    var label: String {
        switch self {
        case .liquid: "Liquid Glass"
        case .frosted: "Frosted"
        case .solid: "Solid"
        }
    }
}

enum AccentFrom: String, Codable, CaseIterable, Identifiable {
    case theme, cover, custom
    var id: String { rawValue }
    var label: String { self == .theme ? "Theme" : self == .cover ? "Cover" : "Custom" }
}

enum RowSize: String, Codable, CaseIterable, Identifiable {
    case compact, normal, large
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var artwork: CGFloat { self == .compact ? 40 : self == .normal ? 50 : 62 }
    var padding: CGFloat { self == .compact ? 5 : self == .normal ? 8 : 11 }
}

enum ShelfSize: String, Codable, CaseIterable, Identifiable {
    case large, extraLarge
    var id: String { rawValue }
    var label: String { self == .large ? "Two per shelf" : "One per shelf" }
    var columns: Int { self == .large ? 2 : 1 }
}

enum TextSize: String, Codable, CaseIterable, Identifiable {
    case small, standard, large, extraLarge
    var id: String { rawValue }
    var label: String { self == .extraLarge ? "Extra large" : rawValue.capitalized }
    var dynamic: DynamicTypeSize {
        switch self {
        case .small: .small
        case .standard: .large
        case .large: .xLarge
        case .extraLarge: .xxLarge
        }
    }
}

enum IconWeight: String, Codable, CaseIterable, Identifiable {
    case light, regular, semibold, bold
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var weight: Font.Weight {
        switch self {
        case .light: .light
        case .regular: .regular
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

enum StreamQuality: String, Codable, CaseIterable, Identifiable {
    case original, aac256, mp3_320, mp3_192, mp3_128
    var id: String { rawValue }
    var label: String {
        switch self {
        case .original: "Original"
        case .aac256: "AAC 256 kbit/s"
        case .mp3_320: "MP3 320 kbit/s"
        case .mp3_192: "MP3 192 kbit/s"
        case .mp3_128: "MP3 128 kbit/s"
        }
    }
    /// Format and bitrate to ask the server for (nil: as stored).
    var transcode: (format: String, kbps: Int)? {
        switch self {
        case .original: nil
        case .aac256: ("aac", 256)
        case .mp3_320: ("mp3", 320)
        case .mp3_192: ("mp3", 192)
        case .mp3_128: ("mp3", 128)
        }
    }
}

/// Everything you can change about how Starlite looks and behaves.
struct LookPrefs: Codable, Hashable {
    var theme: ThemeKind = .dark
    var style: PanelStyle = .solid
    var accentFrom: AccentFrom = .theme
    var accent = RGBA(0.588, 0.510, 1.0)
    var coverBackground = false
    var corners: Double = 14
    var textSize: TextSize = .standard
    var iconWeight: IconWeight = .regular
    var motionSpeed: Double = 1
    var motionAmount: Double = 1
    // Custom theme
    var customBackground = RGBA(0.08, 0.07, 0.12)
    var customAccent = RGBA(1.0, 0.45, 0.6)
    var customPicture: String?
    // Layout
    var rowSize: RowSize = .normal
    var showNumbers = true
    var showAlbum = false
    var showArtwork = true
    var shelf = true
    var shelfSize: ShelfSize = .large
    var minimizeTabBar = true
    var bigTitles = true
    // Playback and the rest
    var stream: StreamQuality = .original
    var download: StreamQuality = .original
    var haptics = true
    var pausedArtworkShrinks = true
    var lyricsOnline = true

    /// Saved looks keep the look, not playback settings.
    func lookOnly(from other: LookPrefs) -> LookPrefs {
        var l = other
        l.stream = stream
        l.download = download
        l.haptics = haptics
        return l
    }
}

struct SavedLook: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var look: LookPrefs
}

/// The colours a theme draws with.
struct Palette {
    var background: Color
    var panel: Color
    var text: Color
    var secondary: Color
    var accent: Color
    var dark: Bool
}

@Observable
final class Look {
    var prefs: LookPrefs { didSet { Storage.save(prefs, "look.json") } }
    var saved: [SavedLook] { didSet { Storage.save(saved, "looks.json") } }
    /// The playing song's main colour (for "accent from the cover").
    var coverColor: Color?

    init() {
        prefs = Storage.load(LookPrefs.self, "look.json") ?? LookPrefs()
        saved = Storage.load([SavedLook].self, "looks.json") ?? []
    }

    var palette: Palette { Look.palette(prefs, cover: coverColor) }

    /// How another theme would look (the theme cards in Settings).
    func preview(_ t: ThemeKind) -> Palette {
        var p = prefs
        p.theme = t
        p.accentFrom = .theme
        return Look.palette(p, cover: nil)
    }

    static func palette(_ p: LookPrefs, cover coverColor: Color?) -> Palette {
        var pal: Palette
        switch p.theme {
        case .dark:
            pal = Palette(background: Color(white: 0.07), panel: Color(white: 0.13), text: .white, secondary: Color(white: 0.62), accent: Color(white: 0.96), dark: true)
        case .light:
            pal = Palette(background: Color(white: 0.965), panel: .white, text: Color(white: 0.1), secondary: Color(white: 0.45), accent: Color(white: 0.1), dark: false)
        case .cherry:
            pal = Palette(background: Color(red: 0.06, green: 0.045, blue: 0.055), panel: Color(red: 0.14, green: 0.1, blue: 0.12), text: .white, secondary: Color(red: 0.72, green: 0.62, blue: 0.66), accent: Color(red: 1, green: 0.72, blue: 0.78), dark: true)
        case .stars:
            pal = Palette(background: Color(red: 0.02, green: 0.025, blue: 0.05), panel: Color(red: 0.09, green: 0.1, blue: 0.15), text: .white, secondary: Color(red: 0.6, green: 0.63, blue: 0.72), accent: Color(red: 0.86, green: 0.9, blue: 1), dark: true)
        case .bubbles:
            pal = Palette(background: Color(red: 0.03, green: 0.05, blue: 0.08), panel: Color(red: 0.08, green: 0.12, blue: 0.17), text: .white, secondary: Color(red: 0.57, green: 0.63, blue: 0.7), accent: Color(red: 0.66, green: 0.87, blue: 1), dark: true)
        case .custom:
            let bg = p.customBackground
            let dark = bg.luminance < 0.55
            pal = Palette(background: bg.color, panel: dark ? Color.white.opacity(0.08) : Color.white.opacity(0.7), text: dark ? .white : Color(white: 0.08), secondary: dark ? Color.white.opacity(0.62) : Color.black.opacity(0.5), accent: p.customAccent.color, dark: dark)
        }
        switch p.accentFrom {
        case .theme: break
        case .cover: if let c = coverColor { pal.accent = c }
        case .custom: pal.accent = p.accent.color
        }
        return pal
    }

    /// Switches and sliders: the accent, unless it's nearly white or black
    /// (a white switch can't be told apart from an off one): then green.
    var controlTint: Color {
        let a = RGBA(palette.accent)
        return a.luminance > 0.82 || a.luminance < 0.15 ? Color(red: 0.2, green: 0.78, blue: 0.35) : palette.accent
    }

    /// Text and icons on top of the accent (a filled Play button).
    var onAccent: Color {
        let a = RGBA(palette.accent)
        return a.luminance > 0.6 ? Color(white: 0.08) : .white
    }
}
