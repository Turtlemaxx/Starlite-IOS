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
    static var hasGroup: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id) != nil
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 1.5
        c.timeoutIntervalForResource = 3
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    private static func get(_ path: String) async -> Data? {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)"),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    /// What's playing, the widget's settings and the cover, from the app
    /// (nil when the app isn't running).
    static func fetch() async -> (WidgetSnapshot, WidgetPrefs, UIImage?)? {
        async let now = get("/now")
        async let prefs = get("/prefs")
        async let art = get("/art")
        guard let n = await now, let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: n) else { return nil }
        let p = await prefs.flatMap { try? JSONDecoder().decode(WidgetPrefs.self, from: $0) } ?? WidgetPrefs()
        let image = await art.flatMap { UIImage(data: $0) }
        return (snap, p, image)
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
