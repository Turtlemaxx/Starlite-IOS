import Foundation
import UIKit

/// How the widget reaches the app when they don't share an App Group
/// (sideloading tools such as Feather drop it): the app answers on a port
/// that only this phone can reach (127.0.0.1), and the widget's buttons also
/// send a system-wide signal the app listens for.
enum WidgetLink {
    static let port: UInt16 = 47811
    static let prefix = "io.github.turtlemaxx.starlite.cmd."

    /// Whether the App Group is really there (signed with it).
    static var hasGroup: Bool { AppGroup.isShared }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 3
        c.timeoutIntervalForResource = 5
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    private static func get(_ path: String) async -> Data? {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)"),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    /// What's playing, the widget's settings and the covers (this song's and
    /// the next ones', by key), from the app in one go; nil when the app
    /// isn't running.
    static func fetch() async -> (WidgetSnapshot, WidgetPrefs, [String: UIImage])? {
        guard let d = await get("/widget"), let p = try? JSONDecoder().decode(WidgetPayload.self, from: d) else { return nil }
        var covers: [String: UIImage] = [:]
        for (k, data) in p.covers {
            if let img = UIImage(data: data) { covers[k] = img }
        }
        return (p.snap, p.prefs, covers)
    }

    /// Tells the app what the widget ended up showing (shown under the
    /// preview in Settings → Widget).
    static func report(_ text: String) async {
        let t = text.addingPercentEncoding(withAllowedCharacters: .alphanumerics)?.prefix(1500) ?? ""
        _ = await get("/shown/\(t)")
    }

    /// Asks the app to do a button's job; true once it has.
    static func command(_ c: PlayerCommand) async -> Bool {
        await get("/cmd/\(c.rawValue)") != nil
    }

    // MARK: The system-wide signal

    static func post(_ c: PlayerCommand) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName((prefix + c.rawValue) as CFString), nil, nil, true)
    }

    private final class Token {}
    private static let token = Token()

    /// The app listens for the widget's buttons.
    static func listen() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = UnsafeRawPointer(Unmanaged.passUnretained(token).toOpaque())
        for c in [PlayerCommand.toggle, .next, .previous, .like] {
            CFNotificationCenterAddObserver(center, observer, { _, _, name, _, _ in
                guard let cf = name?.rawValue else { return }
                let raw = cf as String
                guard let c = PlayerCommand(rawValue: String(raw.dropFirst(WidgetLink.prefix.count))) else { return }
                DispatchQueue.main.async { CommandBridge.handler?(c) }
            }, (prefix + c.rawValue) as CFString, nil, .deliverImmediately)
        }
    }
}
