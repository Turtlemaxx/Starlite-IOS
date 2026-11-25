import Foundation

/// A small log file in the shared App Group folder: the app and the widget
/// each write a line at every step, and Settings → Widget → Widget Log shows
/// it. Lines are written straight away, so they survive a crash.
enum WidgetLog {
    static var url: URL { AppGroup.folder.appendingPathComponent("widget-log.txt") }

    private static var source: String {
        Bundle.main.bundleURL.pathExtension == "appex" ? "widget" : "app"
    }

    private static let lock = NSLock()

    static func write(_ message: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        let data = Data("\(f.string(from: Date())) [\(source)] \(message)\n".utf8)
        lock.lock()
        defer { lock.unlock() }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            if let size = try? handle.seekToEnd(), size > 60_000 {
                // Keep it small: drop the older half.
                try? handle.close()
                if let old = try? Data(contentsOf: url) {
                    try? (old.suffix(30_000) + data).write(to: url, options: .atomic)
                }
                return
            }
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func lines(limit: Int = 300) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Array(text.split(separator: "\n").suffix(limit).map(String.init))
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
