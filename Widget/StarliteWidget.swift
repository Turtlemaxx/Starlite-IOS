import SwiftUI
import WidgetKit

/// What's playing in Starlite, on the home screen (2×4). The app asks for a
/// refresh when something changes and the widget gets the song from the app
/// (or the shared App Group folder); the progress bar and the times run by
/// themselves in between.
struct NowPlayingEntry: TimelineEntry {
    var date: Date
    var snap: WidgetSnapshot
    var prefs: WidgetPrefs
    var artwork: UIImage?
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: .now, snap: .sample, prefs: WidgetPrefs(), artwork: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        Task { completion(await current()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        Task {
            let e = await current()
            // When the song should be over, look again (the app usually asks sooner).
            let next = e.snap.playing && e.snap.duration > 0 ? e.snap.endDate.addingTimeInterval(2) : Date.now.addingTimeInterval(1800)
            completion(Timeline(entries: [e], policy: .after(next)))
        }
    }

    /// From the app itself (works when sideloaded, without an App Group),
    /// else the App Group's files, else what the widget saw last.
    private func current() async -> NowPlayingEntry {
        if let live = await WidgetLink.fetch() {
            let (snap, prefs, art) = live
            Cache.save(snap, prefs, art)
            return NowPlayingEntry(date: .now, snap: snap, prefs: prefs, artwork: snap.hasTrack ? art : nil)
        }
        if WidgetLink.hasGroup {
            let snap = AppGroup.read(WidgetSnapshot.self, "widget-now.json", defaults: .empty)
            let prefs = AppGroup.read(WidgetPrefs.self, "widget-prefs.json", defaults: WidgetPrefs())
            let art = snap.hasTrack ? UIImage(contentsOfFile: AppGroup.artworkURL.path) : nil
            return NowPlayingEntry(date: .now, snap: snap, prefs: prefs, artwork: art)
        }
        // The app isn't running, so nothing is playing: show where it stopped.
        let (saved, prefs, art) = Cache.load()
        var snap = saved
        if snap.playing {
            snap.elapsed = min(snap.elapsed + Date.now.timeIntervalSince(snap.at), max(snap.duration, 0))
            snap.at = .now
            snap.playing = false
        }
        return NowPlayingEntry(date: .now, snap: snap, prefs: prefs, artwork: snap.hasTrack ? art : nil)
    }
}

/// The widget's own copy of what it last got from the app.
private enum Cache {
    static var folder: URL {
        let u = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Widget", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func save(_ snap: WidgetSnapshot, _ prefs: WidgetPrefs, _ art: UIImage?) {
        let f = folder
        if let d = try? JSONEncoder().encode(snap) { try? d.write(to: f.appendingPathComponent("now.json"), options: .atomic) }
        if let d = try? JSONEncoder().encode(prefs) { try? d.write(to: f.appendingPathComponent("prefs.json"), options: .atomic) }
        let cover = f.appendingPathComponent("cover.jpg")
        if let d = art?.jpegData(compressionQuality: 0.85) {
            try? d.write(to: cover, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: cover)
        }
    }

    static func load() -> (WidgetSnapshot, WidgetPrefs, UIImage?) {
        let f = folder
        let snap = (try? Data(contentsOf: f.appendingPathComponent("now.json"))).flatMap { try? JSONDecoder().decode(WidgetSnapshot.self, from: $0) } ?? .empty
        let prefs = (try? Data(contentsOf: f.appendingPathComponent("prefs.json"))).flatMap { try? JSONDecoder().decode(WidgetPrefs.self, from: $0) } ?? WidgetPrefs()
        return (snap, prefs, UIImage(contentsOfFile: f.appendingPathComponent("cover.jpg").path))
    }
}

struct StarliteWidgetView: View {
    var entry: NowPlayingEntry
    var body: some View {
        WidgetContent(snap: entry.snap, prefs: entry.prefs, artwork: entry.artwork)
            .containerBackground(for: .widget) {
                WidgetBackdrop(snap: entry.snap, prefs: entry.prefs, artwork: entry.artwork)
            }
            .widgetURL(URL(string: "starlite://nowplaying"))
    }
}

struct StarliteNowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StarliteNowPlaying", provider: NowPlayingProvider()) { entry in
            StarliteWidgetView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("What's playing in Starlite, with controls. Change everything about it in Starlite's Settings, Widget.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct StarliteWidgets: WidgetBundle {
    var body: some Widget {
        StarliteNowPlayingWidget()
    }
}
