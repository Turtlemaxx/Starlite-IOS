import Foundation

/// A word and when it's sung (seconds).
struct LyricWord: Hashable {
    var text: String
    var start: Double
    var end: Double
}

/// One line of lyrics. Timed lines know when each word is sung (from the
/// file when it says so, otherwise spread over the line by length). A line
/// with no words and `gap` is a pause in the singing (shown as three dots).
struct LyricLine: Identifiable, Hashable {
    var id: Int
    var time: Double?
    var end: Double?
    var text: String
    var words: [LyricWord] = []
    var gap = false
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
            lines = parse(o, length: t.duration)
        }
        if lines == nil, let arr = await get("https://lrclib.net/api/search", [URLQueryItem(name: "artist_name", value: t.artist), URLQueryItem(name: "track_name", value: t.title)]) as? [[String: Any]] {
            // The closest in length, if more than one was found.
            let best = arr.min { a, b in
                abs((a["duration"] as? Double ?? 0) - t.duration) < abs((b["duration"] as? Double ?? 0) - t.duration)
            }
            if let best { lines = parse(best, length: t.duration) }
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

    private static func parse(_ o: [String: Any], length: Double) -> [LyricLine]? {
        if let synced = o["syncedLyrics"] as? String, !synced.isEmpty {
            let lines = parseLRC(synced, length: length)
            if !lines.isEmpty { return lines }
        }
        if let plain = o["plainLyrics"] as? String, !plain.isEmpty {
            return plain.components(separatedBy: .newlines).enumerated().map { LyricLine(id: $0.offset, time: nil, text: $0.element) }
        }
        return nil
    }

    private static func stamp(_ tag: Substring) -> Double? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) else { return nil }
        return m * 60 + s
    }

    /// "[01:23.45] words" lines; word times from "<01:23.80>" tags when there are any.
    static func parseLRC(_ text: String, length: Double = 0) -> [LyricLine] {
        struct Raw { var time: Double; var text: String; var marks: [(Double, String)] }
        var raw: [Raw] = []
        for line in text.components(separatedBy: .newlines) {
            var rest = Substring(line)
            var times: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                if let t = stamp(rest[rest.index(after: rest.startIndex)..<close]) { times.append(t) }
                rest = rest[rest.index(after: close)...]
            }
            guard !times.isEmpty else { continue }
            // Word tags: "<00:12.30>Hello <00:12.80>there".
            var marks: [(Double, String)] = []
            var plain = ""
            var cur = rest
            while let open = cur.firstIndex(of: "<"), let close = cur[open...].firstIndex(of: ">"), let t = stamp(cur[cur.index(after: open)..<close]) {
                plain += cur[..<open]
                cur = cur[cur.index(after: close)...]
                let next = cur.firstIndex(of: "<") ?? cur.endIndex
                let word = String(cur[..<next])
                marks.append((t, word))
                plain += word
                cur = cur[next...]
            }
            plain += cur
            let words = (marks.isEmpty ? String(rest) : plain).trimmingCharacters(in: .whitespaces)
            for t in times { raw.append(Raw(time: t, text: words, marks: marks)) }
        }
        raw.sort { $0.time < $1.time }

        var out: [LyricLine] = []
        // A pause before the singing starts.
        if let first = raw.first, first.time >= 4 {
            out.append(LyricLine(id: 0, time: 0, end: first.time, text: "", gap: true))
        }
        for (k, r) in raw.enumerated() {
            let next = k + 1 < raw.count ? raw[k + 1].time : (length > r.time ? length : r.time + 6)
            if r.text.isEmpty {
                // An empty line in the file: a pause if it's long enough.
                if next - r.time >= 4 { out.append(LyricLine(id: 0, time: r.time, end: next, text: "", gap: true)) }
                continue
            }
            var line = LyricLine(id: 0, time: r.time, end: next, text: r.text)
            if !r.marks.isEmpty {
                var ws: [LyricWord] = []
                for (j, m) in r.marks.enumerated() {
                    let end = j + 1 < r.marks.count ? r.marks[j + 1].0 : min(next, m.0 + 1.2)
                    for piece in m.1.split(separator: " ", omittingEmptySubsequences: true) {
                        ws.append(LyricWord(text: String(piece), start: m.0, end: end))
                    }
                }
                line.words = ws
            } else {
                line.words = spread(r.text, from: r.time, to: next)
            }
            out.append(line)
            // A long instrumental stretch after this line.
            let sung = line.words.last?.end ?? r.time
            if next - sung >= 6 {
                out.append(LyricLine(id: 0, time: sung + 0.5, end: next, text: "", gap: true))
            }
        }
        return out.enumerated().map { var l = $0.element; l.id = $0.offset; return l }
    }

    /// Spreads a line's words over the time it's sung, by their length.
    /// A line is sung at most at about 13 characters a second, so a short
    /// line before a long pause doesn't crawl.
    static func spread(_ text: String, from start: Double, to next: Double) -> [LyricWord] {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !words.isEmpty else { return [] }
        let chars = Double(words.reduce(0) { $0 + $1.count + 1 })
        let span = max(0.35, min(next - start - 0.1, chars / 13 + 0.35))
        var t = start
        return words.map { w in
            let d = span * Double(w.count + 1) / chars
            defer { t += d }
            return LyricWord(text: w, start: t, end: t + d)
        }
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
    """, length: 214)
}
