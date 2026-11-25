import SwiftUI

@main
struct StarliteApp: App {
    @State private var look = Look()
    @State private var library = Library()
    @State private var services = Services()
    @State private var player = Player.shared
    @State private var sound = Sound()
    @State private var lastfm = LastFM()

    init() {
        // Covers come over the network a lot: keep plenty of them.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
        // The widget's buttons.
        CommandBridge.handler = { Player.shared.handle($0) }
        // The widget reaches the app this way when there's no App Group.
        WidgetLink.listen()
        WidgetServer.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(look)
                .environment(library)
                .environment(services)
                .environment(player)
                .environment(sound)
                .environment(lastfm)
                .onAppear {
                    player.configure(services: services, library: library, look: look, sound: sound, lastfm: lastfm)
                    if Storage.demo {
                        Demo.fill(library: library, services: services, player: player)
                    }
                    player.syncWidget()
                }
                .task {
                    await library.scan()
                    for s in services.connected { await services.refresh(s) }
                }
        }
    }
}

enum AppTab: Hashable {
    case server, playlists, settings, search
}

/// The screens the screenshot run opens (launch argument -StarliteScreen).
enum DemoScreen: String {
    case playlists, playlist, nowplaying, lyrics, server, settings, appearance, layout, sound, search, light, bubbles, list, widget, empty
    static var current: DemoScreen? {
        guard Storage.demo, let s = UserDefaults.standard.string(forKey: "StarliteScreen") else { return nil }
        return DemoScreen(rawValue: s)
    }
}

struct RootView: View {
    @Environment(Look.self) private var look
    @Environment(Player.self) private var player
    @Environment(\.scenePhase) private var phase
    @Environment(Library.self) private var library
    @State private var tab: AppTab = .playlists
    @State private var nowPlaying = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("Music Server", systemImage: "server.rack", value: AppTab.server) {
                ServerTab()
            }
            Tab("Playlists", systemImage: "music.note.list", value: AppTab.playlists) {
                PlaylistsTab()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsTab()
            }
            // The search bubble, apart at the right of the tab bar.
            Tab(value: AppTab.search, role: .search) {
                SearchTab()
            }
        }
        .tabBarMinimizeBehavior(look.prefs.minimizeTabBar ? .onScrollDown : .never)
        .tabViewBottomAccessory {
            MiniPlayer(open: { nowPlaying = true })
        }
        .fullScreenCover(isPresented: $nowPlaying) {
            NowPlayingView()
        }
        .tint(look.palette.accent)
        .preferredColorScheme(look.palette.dark ? .dark : .light)
        .dynamicTypeSize(look.prefs.textSize.dynamic)
        .fontWeight(nil)
        .tapFeedback(look, trigger: tab)
        // Tapping the widget opens the player.
        .onOpenURL { url in
            if url.scheme == "starlite", url.host() == "nowplaying" { nowPlaying = true }
        }
        .onChange(of: phase) { _, p in
            // Songs put in through the Files app show up when you come back.
            if p == .active {
                Task { await library.scan() }
                WidgetServer.shared.start()
            }
        }
        .onAppear {
            switch DemoScreen.current {
            case .server: tab = .server
            case .settings, .appearance, .layout, .sound, .widget: tab = .settings
            case .nowplaying, .lyrics: nowPlaying = true
            case .search: tab = .search
            case .list: look.prefs.shelf = false
            case .light: look.prefs.theme = .light
            case .bubbles: look.prefs.theme = .bubbles
            default: break
            }
        }
    }
}
