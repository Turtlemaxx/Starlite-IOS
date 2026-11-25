import AppIntents
import Foundation
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Shared between the app and its widget: the App Group they both see.
enum AppGroup {
    static let id = "group.io.github.turtlemaxx.starlite"

    /// The shared folder (the app's own folder if the group isn't there,
    /// e.g. in the simulator without signing).
    static var folder: URL {
        if let u = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) { return u }
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Shared", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func read<T: Codable>(_ type: T.Type, _ name: String, defaults: T) -> T {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return defaults }
        if let v = try? JSONDecoder().decode(T.self, from: data) { return v }
        // Saved by an older version: what's missing takes the default.
        guard let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let base = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(defaults))) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: base.merging(saved) { _, new in new }),
              let v = try? JSONDecoder().decode(T.self, from: merged) else { return defaults }
        return v
    }

    static func write<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: folder.appendingPathComponent(name), options: .atomic)
    }

    static var artworkURL: URL { folder.appendingPathComponent("widget-cover.jpg") }

    static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

/// What's playing, as the widget shows it.
struct WidgetSnapshot: Codable, Hashable {
    var title = "Not Playing"
    var artist = "Starlite"
    var album: String?
    var playing = false
    /// Where the song was when this was written, and when.
    var elapsed: Double = 0
    var at = Date()
    var duration: Double = 0
    var liked = false
    var hasTrack = false
    var upNext: String?
    /// The cover's colour, and the theme's.
    var coverColor: RGBA?
    var themeBackground = RGBA(0.07, 0.07, 0.07)
    var themeText = RGBA(1, 1, 1)
    var themeAccent = RGBA(0.96, 0.96, 0.96)
    /// The cover's key (the widget asks the app for /art/<key>).
    var art: String?
    /// The next songs, so the widget moves on by itself when one ends.
    var upcoming: [WidgetSong] = []

    static let empty = WidgetSnapshot()
    static let sample = WidgetSnapshot(title: "Golden Hour Drive", artist: "Nova Lane", album: "Coastline", playing: true, elapsed: 74, at: Date(), duration: 214, liked: true, hasTrack: true, upNext: "Tidal · Nova Lane", coverColor: RGBA(0.45, 0.3, 0.75))

    /// When the song started (for a progress bar that moves by itself).
    var startDate: Date { at.addingTimeInterval(-elapsed) }
    var endDate: Date { startDate.addingTimeInterval(max(duration, 1)) }

    /// What the widget should show once the songs before `i` have played
    /// (if nothing interrupts).
    func later(_ i: Int) -> WidgetSnapshot? {
        guard upcoming.indices.contains(i) else { return nil }
        var start = endDate
        for k in 0..<i { start = start.addingTimeInterval(max(upcoming[k].duration, 1)) }
        let song = upcoming[i]
        var s = self
        s.title = song.title
        s.artist = song.artist
        s.album = song.album
        s.duration = song.duration
        s.liked = song.liked
        s.art = song.art
        s.coverColor = song.color
        s.elapsed = 0
        s.at = start
        s.upcoming = Array(upcoming.dropFirst(i + 1))
        s.upNext = s.upcoming.first.map { "\($0.title) · \($0.artist)" }
        return s
    }
}

/// A song coming up, as the widget will show it.
struct WidgetSong: Codable, Hashable {
    var title: String
    var artist: String
    var album: String?
    var duration: Double
    var liked = false
    var art: String?
    var color: RGBA?
}

/// A short, file- and URL-safe key for a song's cover.
func widgetArtKey(_ id: String) -> String {
    var h: UInt64 = 0xcbf29ce484222325
    for b in id.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
    return String(h, radix: 16)
}

// MARK: - The widget's settings

enum WidgetLayout: String, Codable, CaseIterable, Identifiable {
    case classic, cover, bigArt, minimal, centered
    var id: String { rawValue }
    var label: String {
        switch self {
        case .classic: "Classic"
        case .cover: "Cover Behind"
        case .bigArt: "Big Cover"
        case .minimal: "Minimal"
        case .centered: "Centred"
        }
    }
}

enum WidgetBackground: String, Codable, CaseIterable, Identifiable {
    case cover, theme, color, gradient, glass
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cover: "Blurred Cover"
        case .theme: "Theme"
        case .color: "Colour"
        case .gradient: "Gradient"
        case .glass: "Cover Colour"
        }
    }
}

enum WidgetFont: String, Codable, CaseIterable, Identifiable {
    case standard, rounded, serif, mono
    var id: String { rawValue }
    var label: String { self == .mono ? "Mono" : rawValue.capitalized }
    var design: Font.Design {
        switch self {
        case .standard: .default
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        }
    }
}

enum WidgetWeight: String, Codable, CaseIterable, Identifiable {
    case regular, medium, semibold, bold, heavy
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var weight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        }
    }
}

enum WidgetControls: String, Codable, CaseIterable, Identifiable {
    case plain, circles, filled
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum WidgetAccent: String, Codable, CaseIterable, Identifiable {
    case theme, cover, custom
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Everything about the widget that can be changed.
struct WidgetPrefs: Codable, Hashable {
    var layout: WidgetLayout = .classic
    var background: WidgetBackground = .cover
    var color1 = RGBA(0.12, 0.10, 0.20)
    var color2 = RGBA(0.35, 0.18, 0.45)
    var dim: Double = 0.35
    var accentFrom: WidgetAccent = .theme
    var accent = RGBA(1, 1, 1)
    var textColor = RGBA(1, 1, 1)
    var themeText = false
    // What's in it
    var showArtwork = true
    var showTitle = true
    var showArtist = true
    var showAlbum = false
    var showProgress = true
    var showTimes = true
    var showControls = true
    var showPrevious = true
    var showNext = true
    var showLike = false
    var showLogo = true
    var showUpNext = false
    var showStatus = false
    // How it looks
    var artworkSize: Double = 1
    var artworkCorner: Double = 12
    var artworkShadow = true
    var titleSize: Double = 17
    var titleWeight: WidgetWeight = .semibold
    var font: WidgetFont = .standard
    var centeredText = false
    var controlSize: Double = 1
    var controls: WidgetControls = .plain
    var progressHeight: Double = 4
    var padding: Double = 14
}

// MARK: - Buttons in the widget (they run inside the app)

enum PlayerCommand: String {
    case toggle, next, previous, like
}

/// The app hands the widget's buttons to its player through this.
enum CommandBridge {
    nonisolated(unsafe) static var handler: ((PlayerCommand) -> Void)?
    /// Whether the app has the new song's cover yet (the widget redraws
    /// right after a button, so it waits for it a little).
    nonisolated(unsafe) static var ready: (() -> Bool)?

    /// Waits (up to 1.5 s) until the app has the cover.
    static func settle() async {
        for _ in 0..<15 {
            if await MainActor.run(body: { ready?() ?? true }) { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    static func send(_ c: PlayerCommand) async {
        // Running inside the app: straight to the player.
        if handler != nil {
            await MainActor.run { handler?(c) }
            await settle()
            return
        }
        // Running in the widget: ask the app, or signal it and give it a moment.
        if await WidgetLink.command(c) { return }
        WidgetLink.post(c)
        try? await Task.sleep(for: .milliseconds(900))
    }
}

struct TogglePlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play or Pause"
    func perform() async throws -> some IntentResult {
        await CommandBridge.send(.toggle)
        return .result()
    }
}

struct NextTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Next Song"
    func perform() async throws -> some IntentResult {
        await CommandBridge.send(.next)
        return .result()
    }
}

struct PreviousTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Previous Song"
    func perform() async throws -> some IntentResult {
        await CommandBridge.send(.previous)
        return .result()
    }
}

struct LikeTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Like the Song"
    func perform() async throws -> some IntentResult {
        await CommandBridge.send(.like)
        return .result()
    }
}
