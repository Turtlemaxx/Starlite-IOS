import CryptoKit
import Foundation

/// Last.fm, the same way as Starlite on the computer: your own API key and
/// shared secret, you allow Starlite on last.fm in the browser, and from
/// then on it shows what you play ("now playing") and scrobbles it.
struct LastFMLogin: Codable, Hashable {
    var apiKey: String
    var secret: String
    var sessionKey: String
    var user: String
}

@Observable
final class LastFM {
    var login: LastFMLogin? { didSet { Keychain.set(login, for: "lastfm") } }
    var apiKey: String = UserDefaults.standard.string(forKey: "lastfmKey") ?? "" { didSet { UserDefaults.standard.set(apiKey, forKey: "lastfmKey") } }
    var secret: String = UserDefaults.standard.string(forKey: "lastfmSecret") ?? "" { didSet { UserDefaults.standard.set(secret, forKey: "lastfmSecret") } }
    /// Waiting for you to allow Starlite on last.fm.
    var pendingToken: String?
    var status: String?
    var lastScrobble: String?

    init() {
        login = Keychain.get(LastFMLogin.self, for: "lastfm")
    }

    private static let api = "https://ws.audioscrobbler.com/2.0/"

    private static func sign(_ params: [String: String], secret: String) -> String {
        let base = params.keys.sorted().map { $0 + params[$0]! }.joined() + secret
        return Insecure.MD5.hash(data: Data(base.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func call(_ params: [String: String], secret: String, post: Bool) async throws -> [String: Any] {
        var p = params
        p["api_sig"] = sign(params, secret: secret)
        p["format"] = "json"
        var req: URLRequest
        if post {
            req = URLRequest(url: URL(string: api)!)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var c = URLComponents()
            c.queryItems = p.map { URLQueryItem(name: $0.key, value: $0.value) }
            req.httpBody = (c.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        } else {
            var c = URLComponents(string: api)!
            c.queryItems = p.map { URLQueryItem(name: $0.key, value: $0.value) }
            req = URLRequest(url: c.url!)
        }
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let msg = o["message"] as? String, o["error"] != nil { throw ServerError.message(msg) }
        return o
    }

    /// Step 1: a token, and the page where you allow Starlite.
    func start() async -> URL? {
        status = nil
        let key = apiKey.trimmingCharacters(in: .whitespaces), sec = secret.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !sec.isEmpty else {
            status = "Fill in the API key and the shared secret first"
            return nil
        }
        do {
            let o = try await LastFM.call(["method": "auth.getToken", "api_key": key], secret: sec, post: false)
            guard let token = o["token"] as? String else { throw ServerError.message("Last.fm didn't answer as expected") }
            pendingToken = token
            return URL(string: "https://www.last.fm/api/auth/?api_key=\(key)&token=\(token)")
        } catch {
            status = error.localizedDescription
            return nil
        }
    }

    /// Step 2 (after you've allowed it): the session that stays.
    func finish() async {
        guard let token = pendingToken else { return }
        let key = apiKey.trimmingCharacters(in: .whitespaces), sec = secret.trimmingCharacters(in: .whitespaces)
        do {
            let o = try await LastFM.call(["method": "auth.getSession", "api_key": key, "token": token], secret: sec, post: false)
            guard let s = o["session"] as? [String: Any], let sk = s["key"] as? String else { throw ServerError.message("Allow Starlite on last.fm first") }
            login = LastFMLogin(apiKey: key, secret: sec, sessionKey: sk, user: s["name"] as? String ?? "")
            pendingToken = nil
            status = nil
        } catch {
            status = error.localizedDescription
        }
    }

    func disconnect() {
        login = nil
        pendingToken = nil
        lastScrobble = nil
    }

    private func params(_ method: String, _ t: Track, _ l: LastFMLogin) -> [String: String] {
        var p = ["method": method, "api_key": l.apiKey, "sk": l.sessionKey, "artist": t.artist, "track": t.title]
        if let a = t.album, !a.isEmpty { p["album"] = a }
        if t.duration > 0 { p["duration"] = String(Int(t.duration)) }
        return p
    }

    func nowPlaying(_ t: Track) {
        guard let l = login, !Storage.demo else { return }
        let p = params("track.updateNowPlaying", t, l)
        Task { _ = try? await LastFM.call(p, secret: l.secret, post: true) }
    }

    func scrobble(_ t: Track, startedAt: Date) {
        guard let l = login, !Storage.demo else { return }
        var p = params("track.scrobble", t, l)
        p["timestamp"] = String(Int(startedAt.timeIntervalSince1970))
        Task {
            if (try? await LastFM.call(p, secret: l.secret, post: true)) != nil {
                await MainActor.run { self.lastScrobble = "\(t.artist) – \(t.title)" }
            }
        }
    }
}
