import CryptoKit
import Foundation

/// Navidrome through the Subsonic API. Only the salted token is kept
/// (in the Keychain), never the password.
struct SubsonicLogin: Codable, Hashable {
    var url: String
    var user: String
    var salt: String
    var token: String
}

enum ServerError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let m) = self { return m }
        return nil
    }
}

/// Cleans a typed address: adds http:// (https for internet names), drops a trailing slash.
func normalizedServerURL(_ raw: String) -> String {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while s.hasSuffix("/") { s.removeLast() }
    if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
        let host = s.split(separator: ":").first.map(String.init) ?? s
        let local = host.hasPrefix("192.168.") || host.hasPrefix("10.") || host.hasPrefix("172.") || host == "localhost" || host.hasSuffix(".local") || !host.contains(".")
        s = (local ? "http://" : "https://") + s
    }
    return s
}

struct Subsonic {
    var login: SubsonicLogin

    static func makeLogin(url: String, user: String, password: String) -> SubsonicLogin {
        let salt = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased()
        let digest = Insecure.MD5.hash(data: Data((password + salt).utf8))
        let token = digest.map { String(format: "%02x", $0) }.joined()
        return SubsonicLogin(url: normalizedServerURL(url), user: user, salt: salt, token: token)
    }

    private func url(_ method: String, _ extra: [URLQueryItem] = []) -> URL? {
        var c = URLComponents(string: "\(login.url)/rest/\(method).view")
        c?.queryItems = [
            URLQueryItem(name: "u", value: login.user),
            URLQueryItem(name: "t", value: login.token),
            URLQueryItem(name: "s", value: login.salt),
            URLQueryItem(name: "v", value: "1.16.1"),
            URLQueryItem(name: "c", value: "Starlite"),
            URLQueryItem(name: "f", value: "json"),
        ] + extra
        return c?.url
    }

    private func call(_ method: String, _ extra: [URLQueryItem] = []) async throws -> [String: Any] {
        guard let u = url(method, extra) else { throw ServerError.message("That server address doesn't look right") }
        var req = URLRequest(url: u)
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let h = resp as? HTTPURLResponse, h.statusCode != 200 {
            throw ServerError.message("The server answered with error \(h.statusCode)")
        }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let r = root["subsonic-response"] as? [String: Any] else {
            throw ServerError.message("That doesn't look like a Navidrome server")
        }
        if r["status"] as? String != "ok" {
            let msg = (r["error"] as? [String: Any])?["message"] as? String ?? "The server said no"
            throw ServerError.message(msg)
        }
        return r
    }

    func ping() async throws {
        _ = try await call("ping")
    }

    func coverURL(_ id: String?) -> URL? {
        guard let id, !id.isEmpty else { return nil }
        return url("getCoverArt", [URLQueryItem(name: "id", value: id), URLQueryItem(name: "size", value: "600")])
    }

    func streamURL(id: String, suffix: String?, quality: StreamQuality) -> URL? {
        var q = [URLQueryItem(name: "id", value: id)]
        // Formats iOS can't play arrive converted.
        let unplayable = ["opus", "ogg", "oga", "wma", "ape", "wv", "mpc"].contains((suffix ?? "").lowercased())
        if let t = quality.transcode {
            q += [URLQueryItem(name: "format", value: t.format), URLQueryItem(name: "maxBitRate", value: String(t.kbps))]
        } else if unplayable {
            q += [URLQueryItem(name: "format", value: "mp3"), URLQueryItem(name: "maxBitRate", value: "320")]
        } else {
            q += [URLQueryItem(name: "format", value: "raw")]
        }
        return url("stream", q)
    }

    private func track(_ s: [String: Any]) -> Track? {
        guard let id = s["id"] as? String else { return nil }
        return Track(
            id: "nd:\(id)",
            title: s["title"] as? String ?? "Unknown",
            artist: s["artist"] as? String ?? "Unknown artist",
            album: s["album"] as? String,
            duration: Double(s["duration"] as? Int ?? 0),
            artwork: coverURL(s["coverArt"] as? String),
            source: .navidrome(id: id, suffix: s["suffix"] as? String)
        )
    }

    func playlists() async throws -> [ServerCollection] {
        let r = try await call("getPlaylists")
        let list = (r["playlists"] as? [String: Any])?["playlist"] as? [[String: Any]] ?? []
        return list.compactMap { p in
            guard let id = p["id"] as? String else { return nil }
            let n = p["songCount"] as? Int ?? 0
            return ServerCollection(id: id, name: p["name"] as? String ?? "Playlist", subtitle: n == 1 ? "1 song" : "\(n) songs", artwork: coverURL(p["coverArt"] as? String), kind: .playlist, server: .navidrome)
        }
    }

    func recentAlbums() async throws -> [ServerCollection] {
        let r = try await call("getAlbumList2", [URLQueryItem(name: "type", value: "newest"), URLQueryItem(name: "size", value: "30")])
        let list = (r["albumList2"] as? [String: Any])?["album"] as? [[String: Any]] ?? []
        return list.compactMap { a in
            guard let id = a["id"] as? String else { return nil }
            return ServerCollection(id: id, name: a["name"] as? String ?? "Album", subtitle: a["artist"] as? String ?? "", artwork: coverURL(a["coverArt"] as? String), kind: .album, server: .navidrome)
        }
    }

    func tracks(of c: ServerCollection) async throws -> [Track] {
        if c.kind == .playlist {
            let r = try await call("getPlaylist", [URLQueryItem(name: "id", value: c.id)])
            let entries = (r["playlist"] as? [String: Any])?["entry"] as? [[String: Any]] ?? []
            return entries.compactMap(track)
        }
        let r = try await call("getAlbum", [URLQueryItem(name: "id", value: c.id)])
        let songs = (r["album"] as? [String: Any])?["song"] as? [[String: Any]] ?? []
        return songs.compactMap(track)
    }

    func search(_ text: String) async throws -> [Track] {
        let r = try await call("search3", [URLQueryItem(name: "query", value: text), URLQueryItem(name: "songCount", value: "40"), URLQueryItem(name: "albumCount", value: "0"), URLQueryItem(name: "artistCount", value: "0")])
        let songs = (r["searchResult3"] as? [String: Any])?["song"] as? [[String: Any]] ?? []
        return songs.compactMap(track)
    }
}
