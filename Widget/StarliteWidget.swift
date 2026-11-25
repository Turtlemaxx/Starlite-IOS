import SwiftUI
import WidgetKit

/// What's playing in Starlite, on the home screen (2×4). The app writes the
/// song and the widget's settings into the shared App Group folder and asks
/// for a refresh when something changes; the progress bar and the times run
/// by themselves in between.
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
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let e = current()
        // When the song should be over, look again (the app usually asks sooner).
        let next = e.snap.playing && e.snap.duration > 0 ? e.snap.endDate.addingTimeInterval(2) : Date.now.addingTimeInterval(3600)
        completion(Timeline(entries: [e], policy: .after(next)))
    }

    private func current() -> NowPlayingEntry {
        let snap = AppGroup.read(WidgetSnapshot.self, "widget-now.json", defaults: .empty)
        let prefs = AppGroup.read(WidgetPrefs.self, "widget-prefs.json", defaults: WidgetPrefs())
        let art = snap.hasTrack ? UIImage(contentsOfFile: AppGroup.artworkURL.path) : nil
        return NowPlayingEntry(date: .now, snap: snap, prefs: prefs, artwork: art)
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
