import Foundation

/// One line of lyrics; `time` (seconds) when they're timed.
struct LyricLine: Identifiable, Hashable {
    var id: Int
    var time: Double?
    var text: String
}

/// Lyrics from lrclib.net, the same place Starlite on the computer asks.
enum Lyrics {
    private static var cache: [String: [LyricLine]] = [:]

    static func fetch(_ t: Track) async -> [LyricLine]? {
        if let c = cache[t.id] { return c }
        if Storage.demo { return demo }
        var lines: [LyricLine]?
        var q = [URLQueryItem(name: "artist_name", value: t.artist), URLQueryItem(name: "track_name", value: t.title)]
        if let a = t.album { q.append(URLQueryItem(name: "album_name", value: a)) }
        if t.duration > 0 { q.append(URLQueryItem(name: "duration", value: String(Int(t.duration.rounded())))) }
        if let o = await get("https://lrclib.net/api/get", q) as? [String: Any] {
            lines = parse(o)
        }
        if lines == nil, let arr = await get("https://lrclib.net/api/search", [URLQueryItem(name: "artist_name", value: t.artist), URLQueryItem(name: "track_name", value: t.title)]) as? [[String: Any]], let first = arr.first {
            lines = parse(first)
        }
        if let lines { cache[t.id] = lines }
        return lines
    }

    private static func get(_ base: String, _ q: [URLQueryItem]) async -> Any? {
        var c = URLComponents(string: base)
        c?.queryItems = q
        guard let u = c?.url else { return nil }
        var req = URLRequest(url: u)
        req.timeoutInterval = 12
        req.setValue("Starlite for iPhone (https://github.com/Turtlemaxx/Starlite-IOS)", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func parse(_ o: [String: Any]) -> [LyricLine]? {
        if let synced = o["syncedLyrics"] as? String, !synced.isEmpty {
            let lines = parseLRC(synced)
            if !lines.isEmpty { return lines }
        }
        if let plain = o["plainLyrics"] as? String, !plain.isEmpty {
            return plain.components(separatedBy: .newlines).enumerated().map { LyricLine(id: $0.offset, time: nil, text: $0.element) }
        }
        return nil
    }

    /// "[01:23.45] words" lines.
    static func parseLRC(_ text: String) -> [LyricLine] {
        var out: [LyricLine] = []
        for raw in text.components(separatedBy: .newlines) {
            var rest = Substring(raw)
            var times: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                let parts = tag.split(separator: ":")
                if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
                    times.append(m * 60 + s)
                }
                rest = rest[rest.index(after: close)...]
            }
            let words = rest.trimmingCharacters(in: .whitespaces)
            for t in times { out.append(LyricLine(id: 0, time: t, text: words)) }
        }
        return out.sorted { ($0.time ?? 0) < ($1.time ?? 0) }.enumerated().map { LyricLine(id: $0.offset, time: $0.element.time, text: $0.element.text) }
    }

    private static let demo: [LyricLine] = parseLRC("""
    [00:58.00] Streetlights painting gold on the dashboard
    [01:04.00] Windows down, the city's asleep
    [01:10.00] Every song we know on the radio
    [01:16.00] Every promise ours to keep
    [01:22.00] Golden hour, golden hour
    [01:28.00] Drive until the morning comes
    [01:34.00] Golden hour, golden hour
    [01:40.00] We were never on the run
    """)
}
