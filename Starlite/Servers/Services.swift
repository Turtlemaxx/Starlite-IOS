import Foundation

/// The connected servers and what's been loaded from them.
@Observable
final class Services {
    var navidrome: SubsonicLogin? { didSet { Keychain.set(navidrome, for: "navidrome") } }
    var jellyfin: JellyfinLogin? { didSet { Keychain.set(jellyfin, for: "jellyfin") } }
    /// The server the Music Server tab shows.
    var shown: ServerKind = .navidrome

    var playlists: [ServerKind: [ServerCollection]] = [:]
    var albums: [ServerKind: [ServerCollection]] = [:]
    var loading: Set<ServerKind> = []
    var errors: [ServerKind: String] = [:]

    init() {
        navidrome = Keychain.get(SubsonicLogin.self, for: "navidrome")
        jellyfin = Keychain.get(JellyfinLogin.self, for: "jellyfin")
        if navidrome == nil && jellyfin != nil { shown = .jellyfin }
    }

    var connected: [ServerKind] {
        ServerKind.allCases.filter { isConnected($0) }
    }

    func isConnected(_ s: ServerKind) -> Bool {
        s == .navidrome ? navidrome != nil : jellyfin != nil
    }

    /// "user at 192.168.1.10:4533"
    func describe(_ s: ServerKind) -> String? {
        switch s {
        case .navidrome:
            guard let l = navidrome else { return nil }
            return "\(l.user) · \(URL(string: l.url)?.host() ?? l.url)"
        case .jellyfin:
            guard let l = jellyfin else { return nil }
            return "\(l.userName) · \(URL(string: l.url)?.host() ?? l.url)"
        }
    }

    func connect(_ s: ServerKind, url: String, user: String, password: String) async throws {
        switch s {
        case .navidrome:
            let login = Subsonic.makeLogin(url: url, user: user, password: password)
            do {
                try await Subsonic(login: login).ping()
            } catch let e as ServerError {
                throw e
            } catch {
                throw ServerError.message("Couldn't reach the server: \(error.localizedDescription)")
            }
            navidrome = login
        case .jellyfin:
            jellyfin = try await Jellyfin.signIn(url: url, user: user, password: password)
        }
        shown = s
        await refresh(s)
    }

    func disconnect(_ s: ServerKind) {
        if s == .navidrome { navidrome = nil } else { jellyfin = nil }
        playlists[s] = nil
        albums[s] = nil
        errors[s] = nil
        if let other = connected.first { shown = other }
    }

    func refresh(_ s: ServerKind) async {
        guard isConnected(s), !Storage.demo else { return }
        loading.insert(s)
        defer { loading.remove(s) }
        do {
            switch s {
            case .navidrome:
                let api = Subsonic(login: navidrome!)
                async let p = api.playlists()
                async let a = api.recentAlbums()
                playlists[s] = try await p
                albums[s] = try await a
            case .jellyfin:
                let api = Jellyfin(login: jellyfin!)
                async let p = api.playlists()
                async let a = api.recentAlbums()
                playlists[s] = try await p
                albums[s] = try await a
            }
            errors[s] = nil
        } catch {
            errors[s] = error.localizedDescription
        }
    }

    func tracks(of c: ServerCollection) async throws -> [Track] {
        if Storage.demo { return Demo.tracks(for: c.name) }
        switch c.server {
        case .navidrome:
            guard let l = navidrome else { throw ServerError.message("Navidrome isn't connected") }
            return try await Subsonic(login: l).tracks(of: c)
        case .jellyfin:
            guard let l = jellyfin else { throw ServerError.message("Jellyfin isn't connected") }
            return try await Jellyfin(login: l).tracks(of: c)
        }
    }

    func search(_ text: String, on s: ServerKind) async throws -> [Track] {
        if Storage.demo { return Demo.tracks(for: text).prefix(6).map { $0 } }
        switch s {
        case .navidrome:
            guard let l = navidrome else { return [] }
            return try await Subsonic(login: l).search(text)
        case .jellyfin:
            guard let l = jellyfin else { return [] }
            return try await Jellyfin(login: l).search(text)
        }
    }

    /// Where a song plays from (nil: its server isn't connected).
    func url(for t: Track, quality: StreamQuality) -> URL? {
        switch t.source {
        case .file(let name):
            return Storage.documents.appendingPathComponent(name)
        case .navidrome(let id, let suffix):
            guard let l = navidrome else { return nil }
            return Subsonic(login: l).streamURL(id: id, suffix: suffix, quality: quality)
        case .jellyfin(let id):
            guard let l = jellyfin else { return nil }
            return Jellyfin(login: l).streamURL(id: id, quality: quality)
        }
    }

    /// A downloadable file for a server song (never HLS).
    func downloadURL(for t: Track, quality: StreamQuality) -> (URL, String)? {
        switch t.source {
        case .file: return nil
        case .navidrome(let id, let suffix):
            guard let l = navidrome, let u = Subsonic(login: l).streamURL(id: id, suffix: suffix, quality: quality) else { return nil }
            let unplayable = ["opus", "ogg", "oga", "wma", "ape", "wv", "mpc"].contains((suffix ?? "").lowercased())
            let ext = quality.transcode.map { $0.format == "aac" ? "m4a" : $0.format } ?? (unplayable ? "mp3" : (suffix ?? "mp3"))
            return (u, ext)
        case .jellyfin(let id):
            guard let l = jellyfin else { return nil }
            var c = URLComponents(string: "\(l.url)/Audio/\(id)/universal")
            c?.queryItems = [
                URLQueryItem(name: "UserId", value: l.userId),
                URLQueryItem(name: "DeviceId", value: Jellyfin.deviceId),
                URLQueryItem(name: "api_key", value: l.token),
                URLQueryItem(name: "Container", value: "mp3,m4a,flac,wav"),
                URLQueryItem(name: "TranscodingContainer", value: "mp3"),
                URLQueryItem(name: "TranscodingProtocol", value: "http"),
                URLQueryItem(name: "AudioCodec", value: "mp3"),
                URLQueryItem(name: "MaxStreamingBitrate", value: String((quality.transcode?.kbps ?? 320) * 1000)),
            ]
            guard let u = c?.url else { return nil }
            return (u, "mp3")
        }
    }
}
