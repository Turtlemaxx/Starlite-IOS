import Foundation

/// Where a song comes from.
enum TrackSource: Codable, Hashable {
    /// Navidrome (Subsonic API): the song's id and its file type.
    case navidrome(id: String, suffix: String?)
    /// Jellyfin: the item's id.
    case jellyfin(id: String)
    /// A file in the app's Documents folder (downloaded, or added in Files).
    case file(name: String)
}

struct Track: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var artist: String
    var album: String?
    /// Seconds (0: unknown).
    var duration: Double
    /// A cover picture (on the server, or a cached file for local songs).
    var artwork: URL?
    var source: TrackSource

    var isLocal: Bool {
        if case .file = source { return true }
        return false
    }

    /// The server song this is (for "is it downloaded?").
    var serverKey: String? {
        switch source {
        case .navidrome(let id, _): return "nd:\(id)"
        case .jellyfin(let id): return "jf:\(id)"
        case .file: return nil
        }
    }
}

/// A server playlist saved into your own playlists keeps where it came from.
enum PlaylistOrigin: Codable, Hashable {
    case navidrome(id: String)
    case jellyfin(id: String)
}

struct Playlist: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var tracks: [Track]
    /// An SF Symbol shown when there's no cover picture.
    var symbol: String = "music.note.list"
    var origin: PlaylistOrigin?
    var created: Date = .now

    /// The first song's cover stands for the playlist.
    var artwork: URL? { tracks.first(where: { $0.artwork != nil })?.artwork }
}

/// A playlist or album on a server (before its songs are loaded).
struct ServerCollection: Hashable, Identifiable {
    enum Kind: Hashable { case playlist, album }
    var id: String
    var name: String
    var subtitle: String
    var artwork: URL?
    var kind: Kind
    var server: ServerKind
}

enum ServerKind: String, Codable, Hashable, CaseIterable, Identifiable {
    case navidrome, jellyfin
    var id: String { rawValue }
    var name: String { self == .navidrome ? "Navidrome" : "Jellyfin" }
    var symbol: String { self == .navidrome ? "music.note.house" : "server.rack" }
    /// The service's own logo (an image in the asset catalog).
    var logo: String { self == .navidrome ? "LogoNavidrome" : "LogoJellyfin" }
}

/// "3:07"
func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let s = Int(seconds.rounded())
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}

/// "12 songs, 48 min"
func songCount(_ tracks: [Track]) -> String {
    let n = tracks.count
    let total = tracks.reduce(0) { $0 + $1.duration }
    var s = n == 1 ? "1 song" : "\(n) songs"
    if total >= 60 {
        let m = Int(total / 60)
        s += m >= 60 ? ", \(m / 60) h \(m % 60) min" : ", \(m) min"
    }
    return s
}
