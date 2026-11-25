import Foundation
import Network

/// Hands the widget what's playing, its settings and the covers, on
/// 127.0.0.1 only (nothing outside the phone can reach it), and takes its
/// button presses. This is what makes the widget work without an App Group.
final class WidgetServer: @unchecked Sendable {
    static let shared = WidgetServer()

    private let queue = DispatchQueue(label: "starlite.widget-server")
    private var listener: NWListener?
    private var snap = WidgetSnapshot.empty
    private var prefs = AppGroup.read(WidgetPrefs.self, "widget-prefs.json", defaults: WidgetPrefs())
    /// Covers by key: this song's and the next ones'.
    private var arts: [String: Data] = [:]

    /// What the widget last picked up, and what it said it showed (for the
    /// line under the preview in Settings → Widget).
    private var served: (at: Date, title: String, covers: Int, next: Int)?
    private var shown: (at: Date, report: String)?
    private var reloadAsked: Date?

    private init() {}

    func update(now s: WidgetSnapshot, arts covers: [String: Data]) {
        queue.async {
            self.snap = s
            self.arts = covers
        }
    }

    func update(prefs p: WidgetPrefs) {
        queue.async { self.prefs = p }
    }

    func askedReload() {
        queue.async { self.reloadAsked = Date() }
    }

    /// A line about how the widget is doing.
    func status() -> String {
        queue.sync {
            let f = DateFormatter()
            f.timeStyle = .medium
            guard let s = served else {
                return "The widget hasn't picked up anything from Starlite yet."
            }
            var line = "Widget picked up “\(s.title)” at \(f.string(from: s.at)): \(s.covers) cover\(s.covers == 1 ? "" : "s"), \(s.next) next song\(s.next == 1 ? "" : "s")."
            if let r = shown { line += " It showed: \(r.report) (\(f.string(from: r.at)))." }
            if let a = reloadAsked { line += " Last asked to refresh at \(f.string(from: a))." }
            return line
        }
    }

    /// Starts listening (again, if the system stopped it while away).
    func start() {
        queue.async {
            if let l = self.listener {
                switch l.state {
                case .failed, .cancelled: l.cancel()
                default: return
                }
            }
            let params = NWParameters.tcp
            params.requiredInterfaceType = .loopback
            params.allowLocalEndpointReuse = true
            guard let port = NWEndpoint.Port(rawValue: WidgetLink.port),
                  let l = try? NWListener(using: params, on: port) else {
                WidgetLog.shared.add("Couldn't listen for the widget on port \(WidgetLink.port).")
                return
            }
            l.newConnectionHandler = { [weak self] c in self?.serve(c) }
            l.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: WidgetLog.shared.add("Listening for the widget.")
                case .failed(let e): WidgetLog.shared.add("Listening for the widget failed: \(e). Trying again.")
                default: break
                }
                if case .failed = state {
                    self?.queue.asyncAfter(deadline: .now() + 2) { self?.listener = nil; self?.start() }
                }
            }
            l.start(queue: self.queue)
            self.listener = l
        }
    }

    private func serve(_ c: NWConnection) {
        c.stateUpdateHandler = { state in
            if case .failed = state { c.cancel() }
        }
        c.start(queue: queue)
        c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8),
                  let line = request.split(separator: "\r\n").first else { c.cancel(); return }
            let parts = line.split(separator: " ")
            let path = parts.count > 1 ? String(parts[1]) : "/"
            if path == "/widget" {
                // Everything at once: the song, the settings and the covers.
                let payload = WidgetPayload(snap: self.snap, prefs: self.prefs, covers: self.arts)
                self.served = (Date(), self.snap.hasTrack ? self.snap.title : "Not Playing", self.arts.count, self.snap.upcoming.count)
                let s = self.snap
                WidgetLog.shared.add("Widget picked up “\(s.hasTrack ? s.title : "Not Playing")” (\(s.playing ? "playing" : "paused") at \(Int(s.elapsed + (s.playing ? Date().timeIntervalSince(s.at) : 0)))s), \(self.arts.count) cover(s) for \(s.upcoming.count) next song(s), this song's cover: \(s.art.map { self.arts[$0] != nil ? "sent" : "missing" } ?? "none").")
                self.reply(c, try? JSONEncoder().encode(payload), type: "application/json")
            } else if path.hasPrefix("/shown/") {
                self.shown = (Date(), String(path.dropFirst(7)).removingPercentEncoding ?? "")
                WidgetLog.shared.add("Widget shows \(self.shown?.report ?? "").")
                self.reply(c, Data("ok".utf8))
            } else if path.hasPrefix("/cmd/"), let cmd = PlayerCommand(rawValue: String(path.dropFirst(5))) {
                // Answers once the player has done it and has the new song's
                // cover (the widget redraws right after).
                WidgetLog.shared.add("Widget button: \(cmd.rawValue).")
                Task { @MainActor in
                    CommandBridge.handler?(cmd)
                    await CommandBridge.settle()
                    Player.shared.syncWidget(reload: false)
                    self.queue.async { self.reply(c, Data("ok".utf8)) }
                }
            } else {
                self.reply(c, nil)
            }
        }
    }

    private func reply(_ c: NWConnection, _ body: Data?, type: String = "text/plain") {
        let status = body == nil ? "404 Not Found" : "200 OK"
        let b = body ?? Data()
        var out = Data("HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(b.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
        out.append(b)
        // Send it all and end the stream properly; the widget closes its
        // side once it has read everything (closing here right away could
        // cut a big reply short).
        c.send(content: out, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
            self?.queue.asyncAfter(deadline: .now() + 10) { c.cancel() }
        })
    }
}
