import SwiftUI
import WidgetKit

/// What happened between the app and its widget, newest last (Settings →
/// Widget → Widget Log), to find out why the widget doesn't keep up.
@Observable
final class WidgetLog: @unchecked Sendable {
    static let shared = WidgetLog()

    private(set) var lines: [String] = []
    @ObservationIgnored private let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("widget-log.txt")

    private init() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let text = try? String(contentsOf: file, encoding: .utf8) {
            lines = text.split(separator: "\n").map(String.init).suffix(300)
        }
    }

    /// Adds a line (from any thread).
    func add(_ text: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        let line = "\(f.string(from: Date()))  \(text)"
        DispatchQueue.main.async {
            self.lines.append(line)
            if self.lines.count > 300 { self.lines.removeFirst(self.lines.count - 300) }
            try? self.lines.joined(separator: "\n").write(to: self.file, atomically: true, encoding: .utf8)
        }
    }

    func clear() {
        lines = []
        try? FileManager.default.removeItem(at: file)
    }

    /// Notes which Starlite widgets the system says are on the home screen
    /// (if none, the app's refreshes can't reach them).
    func noteWidgets() {
        WidgetCenter.shared.getCurrentConfigurations { result in
            switch result {
            case .success(let list):
                let kinds = list.map { "\($0.kind) (\(String(describing: $0.family)))" }.joined(separator: ", ")
                self.add("The system knows \(list.count) Starlite widget\(list.count == 1 ? "" : "s")\(list.isEmpty ? "" : ": \(kinds)").")
            case .failure(let e):
                self.add("Couldn't ask the system about the widgets: \(e.localizedDescription)")
            }
        }
    }
}

/// Settings → Widget → Widget Log.
struct WidgetLogView: View {
    @Environment(Look.self) private var look
    private var log = WidgetLog.shared

    var body: some View {
        List {
            if log.lines.isEmpty {
                Text("Nothing yet. Play something and look at the widget, then come back.")
                    .foregroundStyle(look.palette.secondary)
            }
            ForEach(Array(log.lines.enumerated().reversed()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .themed(look)
        .navigationTitle("Widget Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: log.lines.joined(separator: "\n")) { Image(systemName: "square.and.arrow.up") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { UIPasteboard.general.string = log.lines.joined(separator: "\n") } label: { Image(systemName: "doc.on.doc") }
                    .accessibilityLabel("Copy")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { log.clear() } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Clear")
            }
        }
    }
}
