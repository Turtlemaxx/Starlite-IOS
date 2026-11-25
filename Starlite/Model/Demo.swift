import Foundation

/// Made-up songs and playlists for screenshots (launch with -StarliteDemo YES).
/// Nothing is saved and nothing goes over the network.
enum Demo {
    private static let songs: [(String, String, String, Double)] = [
        ("Golden Hour Drive", "Nova Lane", "Coastline", 214),
        ("Paper Planets", "The Lumen", "Orbits", 189),
        ("Slow Motion City", "Mira Vale", "Afterglow", 243),
        ("Neon Rain", "Kites at Night", "Static Bloom", 201),
        ("Tidal", "Nova Lane", "Coastline", 236),
        ("Fever Dream", "Saint Ivory", "Velvet Hours", 178),
        ("Late Bloomer", "The Lumen", "Orbits", 222),
        ("Satellite Hearts", "Echo Park Kids", "Lightyears", 197),
        ("Sunday Static", "Mira Vale", "Afterglow", 254),
        ("Glass Garden", "Kites at Night", "Static Bloom", 211),
        ("Northbound", "Saint Ivory", "Velvet Hours", 230),
        ("Overthinker", "Echo Park Kids", "Lightyears", 185),
    ]

    static func tracks(for seed: String) -> [Track] {
        let start = abs(seed.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % songs.count
        return (0..<songs.count).map { k in
            let (t, a, al, d) = songs[(start + k) % songs.count]
            return Track(id: "nd:demo\((start + k) % songs.count)", title: t, artist: a, album: al, duration: d, artwork: nil, source: .navidrome(id: "demo\(k)", suffix: "mp3"))
        }
    }

    static func fill(library: Library, services: Services, player: Player) {
        let all = tracks(for: "a")
        library.liked = Array(all.prefix(7))
        library.downloaded = Array(all.suffix(5)).map { var t = $0; t.id = "file:\(t.title)"; t.source = .file(name: t.title + ".mp3"); return t }
        library.playlists = [
            Playlist(id: "p1", name: "Late Night Drive", tracks: tracks(for: "drive"), symbol: "moon.stars"),
            Playlist(id: "p2", name: "Focus", tracks: Array(tracks(for: "focus").prefix(8)), symbol: "headphones"),
            Playlist(id: "p3", name: "Summer 2026", tracks: Array(tracks(for: "summer").prefix(10)), symbol: "sun.max"),
            Playlist(id: "p4", name: "Gym", tracks: Array(tracks(for: "gym").prefix(9)), symbol: "flame"),
            Playlist(id: "p5", name: "Acoustic", tracks: Array(tracks(for: "acoustic").prefix(6)), symbol: "guitars"),
            Playlist(id: "p6", name: "Rainy Days", tracks: Array(tracks(for: "rain").prefix(11)), symbol: "cloud.rain"),
        ]
        services.navidrome = SubsonicLogin(url: "http://192.168.1.10:4533", user: "demo", salt: "", token: "")
        services.shown = .navidrome
        services.playlists[.navidrome] = ["Good Mix", "Throwbacks", "Chill", "Road Trip", "Party"].enumerated().map {
            ServerCollection(id: "s\($0.offset)", name: $0.element, subtitle: "\(12 + $0.offset * 7) songs", artwork: nil, kind: .playlist, server: .navidrome)
        }
        services.albums[.navidrome] = [("Coastline", "Nova Lane"), ("Orbits", "The Lumen"), ("Afterglow", "Mira Vale"), ("Static Bloom", "Kites at Night"), ("Velvet Hours", "Saint Ivory"), ("Lightyears", "Echo Park Kids")].enumerated().map {
            ServerCollection(id: "a\($0.offset)", name: $0.element.0, subtitle: $0.element.1, artwork: nil, kind: .album, server: .navidrome)
        }
        player.show(library.playlists[0].tracks, at: 2, position: 74)
    }
}
