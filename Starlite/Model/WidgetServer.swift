import Foundation
import Network

/// Hands the widget what's playing, its settings and the cover, on
/// 127.0.0.1 only (nothing outside the phone can reach it), and takes its
/// button presses. This is what makes the widget work without an App Group.
final class WidgetServer: @unchecked Sendable {
    static let shared = WidgetServer()

    private let queue = DispatchQueue(label: "starlite.widget-server")
    private var listener: NWListener?
    private var now = Data()
    private var prefs = Data()
    private var art: Data?

    private init() {
        prefs = (try? JSONEncoder().encode(AppGroup.read(WidgetPrefs.self, "widget-prefs.json", defaults: WidgetPrefs()))) ?? Data()
        now = (try? JSONEncoder().encode(WidgetSnapshot.empty)) ?? Data()
    }

    func update(now snap: WidgetSnapshot, art data: Data?) {
        guard let n = try? JSONEncoder().encode(snap) else { return }
        queue.async {
            self.now = n
            self.art = data
        }
    }

    func update(prefs p: WidgetPrefs) {
        guard let d = try? JSONEncoder().encode(p) else { return }
        queue.async { self.prefs = d }
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
                  let l = try? NWListener(using: params, on: port) else { return }
            l.newConnectionHandler = { [weak self] c in self?.serve(c) }
            l.stateUpdateHandler = { [weak self] state in
                if case .failed = state {
                    self?.queue.asyncAfter(deadline: .now() + 2) { self?.listener = nil; self?.start() }
                }
            }
            l.start(queue: self.queue)
            self.listener = l
        }
    }

    private func serve(_ c: NWConnection) {
        c.start(queue: queue)
        c.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8),
                  let line = request.split(separator: "\r\n").first else { c.cancel(); return }
            let parts = line.split(separator: " ")
            let path = parts.count > 1 ? String(parts[1]) : "/"
            switch path {
            case "/now": self.reply(c, self.now, type: "application/json")
            case "/prefs": self.reply(c, self.prefs, type: "application/json")
            case "/art":
                if let a = self.art { self.reply(c, a, type: "image/jpeg") } else { self.reply(c, nil) }
            default:
                if path.hasPrefix("/cmd/"), let cmd = PlayerCommand(rawValue: String(path.dropFirst(5))) {
                    // Answers once the player has done it (and told us the new state).
                    DispatchQueue.main.async {
                        CommandBridge.handler?(cmd)
                        self.queue.async { self.reply(c, Data("ok".utf8), type: "text/plain") }
                    }
                } else {
                    self.reply(c, nil)
                }
            }
        }
    }

    private func reply(_ c: NWConnection, _ body: Data?, type: String = "text/plain") {
        let status = body == nil ? "404 Not Found" : "200 OK"
        let b = body ?? Data()
        var out = Data("HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(b.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
        out.append(b)
        c.send(content: out, completion: .contentProcessed { _ in c.cancel() })
    }
}
