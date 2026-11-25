import Foundation
import UIKit

/// Jellyfin: signed in once, then only the access token is kept (Keychain).
struct JellyfinLogin: Codable, Hashable {
    var url: String
    var userId: String
    var token: String
    var userName: String
}

struct Jellyfin {
    var login: JellyfinLogin

    static var deviceId: String {
        if let id = UserDefaults.standard.string(forKey: "jfDeviceId") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "jfDeviceId")
        return id
    }

    static func authHeader(token: String? = nil) -> String {
        var h = "MediaBrowser Client=\"Starlite\", Device=\"iPhone\", DeviceId=\"\(deviceId)\", Version=\"0.1.0\""
        if let token { h += ", Token=\"\(token)\"" }
        return h
    }

    static func signIn(url raw: String, user: String, password: String) async throws -> JellyfinLogin {
        let base = normalizedServerURL(raw)
        guard let u = URL(string: "\(base)/Users/AuthenticateByName") else { throw ServerError.message("That server address doesn't look right") }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(authHeader(), forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["Username": user, "Pw": password])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw ServerError.message("Wrong username or password") }
        guard code == 200, let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let token = o["AccessToken"] as? String, let userObj = o["User"] as? [String: Any], let uid = userObj["Id"] as? String else {
            throw ServerError.message(code == 0 ? "Couldn't reach the server" : "That doesn't look like a Jellyfin server (error \(code))")
        }
        return JellyfinLogin(url: base, userId: uid, token: token, userName: userObj["Name"] as? String ?? user)
    }

    private func get(_ path: String, _ q: [URLQueryItem] = []) async throws -> [String: Any] {
        var c = URLComponents(string: "\(login.url)\(path)")
        c?.queryItems = q.isEmpty ? nil : q
        guard let u = c?.url else { throw ServerError.message("That server address doesn't look right") }
        var req = URLRequest(url: u)
        req.timeoutInterval = 15
        req.setValue(Jellyfin.authHeader(token: login.token), forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw ServerError.message("Signed out: connect Jellyfin again in Settings") }
        guard code == 200 else { throw ServerError.message("The server answered with error \(code)") }
        if let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] { return ["Items": arr] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    func imageURL(_ id: String?) -> URL? {
        guard let id else { return nil }
        return URL(string: "\(login.url)/Items/\(id)/Images/Primary?maxHeight=600&quality=90&api_key=\(login.token)")
    }

    func streamURL(id: String, quality: StreamQuality) -> URL? {
        var c = URLComponents(string: "\(login.url)/Audio/\(id)/universal")
        var q = [
            URLQueryItem(name: "UserId", value: login.userId),
            URLQueryItem(name: "DeviceId", value: Jellyfin.deviceId),
            URLQueryItem(name: "api_key", value: login.token),
            // What iOS plays as it is; anything else becomes AAC.
            URLQueryItem(name: "Container", value: "mp3,aac,m4a|aac,m4a|alac,m4b|aac,flac,alac,wav"),
            // A plain stream (not HLS), so the equalizer works on it too.
            URLQueryItem(name: "TranscodingContainer", value: "mp3"),
            URLQueryItem(name: "TranscodingProtocol", value: "http"),
            URLQueryItem(name: "AudioCodec", value: "mp3"),
        ]
        if let t = quality.transcode {
            q.append(URLQueryItem(name: "MaxStreamingBitrate", value: String(t.kbps * 1000)))
        } else {
            q.append(URLQueryItem(name: "MaxStreamingBitrate", value: "140000000"))
        }
        c?.queryItems = q
        return c?.url
    }

    private func track(_ i: [String: Any]) -> Track? {
        guard let id = i["Id"] as? String else { return nil }
        let artists = (i["Artists"] as? [String])?.joined(separator: ", ")
        let ticks = (i["RunTimeTicks"] as? Double) ?? Double(i["RunTimeTicks"] as? Int ?? 0)
        let hasOwn = (i["ImageTags"] as? [String: Any])?["Primary"] != nil
        let albumId = i["AlbumId"] as? String
        return Track(
            id: "jf:\(id)",
            title: i["Name"] as? String ?? "Unknown",
            artist: artists ?? (i["AlbumArtist"] as? String ?? "Unknown artist"),
            album: i["Album"] as? String,
            duration: ticks / 10_000_000,
            artwork: imageURL(hasOwn ? id : albumId),
            source: .jellyfin(id: id)
        )
    }

    private func collection(_ i: [String: Any], kind: ServerCollection.Kind) -> ServerCollection? {
        guard let id = i["Id"] as? String else { return nil }
        let sub: String
        if kind == .playlist {
            let n = i["ChildCount"] as? Int ?? 0
            sub = n == 1 ? "1 song" : "\(n) songs"
        } else {
            sub = (i["AlbumArtist"] as? String) ?? ((i["Artists"] as? [String])?.first ?? "")
        }
        return ServerCollection(id: id, name: i["Name"] as? String ?? "", subtitle: sub, artwork: imageURL(id), kind: kind, server: .jellyfin)
    }

    func playlists() async throws -> [ServerCollection] {
        let r = try await get("/Users/\(login.userId)/Items", [URLQueryItem(name: "IncludeItemTypes", value: "Playlist"), URLQueryItem(name: "Recursive", value: "true"), URLQueryItem(name: "Fields", value: "ChildCount")])
        return (r["Items"] as? [[String: Any]] ?? []).compactMap { collection($0, kind: .playlist) }
    }

    func recentAlbums() async throws -> [ServerCollection] {
        let r = try await get("/Users/\(login.userId)/Items/Latest", [URLQueryItem(name: "IncludeItemTypes", value: "MusicAlbum"), URLQueryItem(name: "Limit", value: "30")])
        return (r["Items"] as? [[String: Any]] ?? []).compactMap { collection($0, kind: .album) }
    }

    func tracks(of c: ServerCollection) async throws -> [Track] {
        let r: [String: Any]
        if c.kind == .playlist {
            r = try await get("/Playlists/\(c.id)/Items", [URLQueryItem(name: "UserId", value: login.userId)])
        } else {
            r = try await get("/Users/\(login.userId)/Items", [URLQueryItem(name: "ParentId", value: c.id), URLQueryItem(name: "IncludeItemTypes", value: "Audio"), URLQueryItem(name: "SortBy", value: "ParentIndexNumber,IndexNumber")])
        }
        return (r["Items"] as? [[String: Any]] ?? []).compactMap(track)
    }

    func search(_ text: String) async throws -> [Track] {
        let r = try await get("/Users/\(login.userId)/Items", [URLQueryItem(name: "SearchTerm", value: text), URLQueryItem(name: "IncludeItemTypes", value: "Audio"), URLQueryItem(name: "Recursive", value: "true"), URLQueryItem(name: "Limit", value: "40")])
        return (r["Items"] as? [[String: Any]] ?? []).compactMap(track)
    }
}
