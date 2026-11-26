import SwiftUI
import WidgetKit

extension WidgetLog {
    /// Notes the shared folder and which Starlite widgets the system says are
    /// on the home screen (if none, the app's refreshes can't reach them).
    nonisolated(unsafe) private static var notedFolder = false

    static func noteWidgets() {
        if !notedFolder {
            notedFolder = true
            write("Shared folder: \(AppGroup.id ?? "none found, the widget can't see the app's files") (tried \(AppGroup.candidates.joined(separator: ", ")))")
        }
        WidgetCenter.shared.getCurrentConfigurations { result in
            switch result {
            case .success(let list):
                write("The system knows \(list.count) Starlite widget\(list.count == 1 ? "" : "s")\(list.isEmpty ? "" : ": " + list.map { "\($0.kind) \($0.family)" }.joined(separator: ", ")).")
            case .failure(let e):
                write("Couldn't ask the system about the widgets: \(e.localizedDescription)")
            }
        }
    }
}

/// Settings → Widget → Widget Log.
struct WidgetLogView: View {
    @Environment(Look.self) private var look
    @State private var lines: [String] = []

    var body: some View {
        List {
            if lines.isEmpty {
                Text("Nothing yet. Play something and look at the widget, then come back.")
                    .foregroundStyle(look.palette.secondary)
            }
            ForEach(Array(lines.enumerated().reversed()), id: \.offset) { _, line in
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
                ShareLink(item: lines.joined(separator: "\n")) { Image(systemName: "square.and.arrow.up") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { UIPasteboard.general.string = lines.joined(separator: "\n") } label: { Image(systemName: "doc.on.doc") }
                    .accessibilityLabel("Copy")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    WidgetLog.clear()
                    lines = []
                } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Clear")
            }
        }
        .task {
            // The widget writes too: keep reading.
            while !Task.isCancelled {
                lines = WidgetLog.lines()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
