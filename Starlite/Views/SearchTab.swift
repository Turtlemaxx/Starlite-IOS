import SwiftUI

/// Search everything at once: your playlists, liked and downloaded songs,
/// and the songs on each connected server.
struct SearchTab: View {
    @Environment(Look.self) private var look
    @Environment(Library.self) private var library
    @Environment(Services.self) private var services
    @Environment(Player.self) private var player
    @State private var text = ""
    @State private var server: [ServerKind: [Track]] = [:]
    @State private var searching: Set<ServerKind> = []
    @State private var addTo: Track?

    private var query: String { text.trimmingCharacters(in: .whitespaces) }

    private var myPlaylists: [Playlist] {
        library.playlists.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var serverPlaylists: [ServerCollection] {
        services.connected.flatMap { services.playlists[$0] ?? [] }.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var mySongs: [Track] {
        library.allTracks.filter { "\($0.title) \($0.artist) \($0.album ?? "")".localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.system(size: 40)).foregroundStyle(look.palette.secondary)
                        Text("Search your music").font(.headline)
                        Text(services.connected.isEmpty ? "Your playlists, liked and downloaded songs." : "Your playlists, liked and downloaded songs, and \(services.connected.map(\.name).joined(separator: " and ")).")
                            .font(.subheadline)
                            .foregroundStyle(look.palette.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    if !myPlaylists.isEmpty || !serverPlaylists.isEmpty {
                        Section("Playlists") {
                            ForEach(myPlaylists) { p in
                                NavigationLink(value: ListKind.playlist(p.id)) {
                                    playlistRow(name: p.name, sub: songCount(p.tracks), url: p.artwork, symbol: p.symbol)
                                }
                            }
                            ForEach(serverPlaylists) { c in
                                NavigationLink(value: ListKind.server(c)) {
                                    playlistRow(name: c.name, sub: "\(c.server.name) · \(c.subtitle)", url: c.artwork, symbol: "music.note.list")
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                    if !mySongs.isEmpty {
                        Section("Your Music") { songs(mySongs) }
                            .listRowBackground(Color.clear)
                    }
                    ForEach(services.connected) { s in
                        if searching.contains(s) {
                            Section(s.name) { ProgressView().frame(maxWidth: .infinity) }
                                .listRowBackground(Color.clear)
                        } else if let found = server[s], !found.isEmpty {
                            Section(s.name) { songs(found) }
                                .listRowBackground(Color.clear)
                        }
                    }
                    if mySongs.isEmpty && myPlaylists.isEmpty && serverPlaylists.isEmpty && searching.isEmpty && server.values.allSatisfy(\.isEmpty) {
                        Text("Nothing found for \u{201c}\(query)\u{201d}.")
                            .foregroundStyle(look.palette.secondary)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .themed(look)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(look.prefs.bigTitles ? .large : .inline)
            .searchable(text: $text, prompt: "Songs, artists, playlists")
            .navigationDestination(for: ListKind.self) { CollectionView(collection: $0) }
            .sheet(item: $addTo) { t in AddToPlaylistSheet(tracks: [t]) }
            // The servers are asked a moment after you stop typing.
            .task(id: query) {
                server = [:]
                guard query.count >= 2 else { return }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                for s in services.connected {
                    searching.insert(s)
                    let found = (try? await services.search(query, on: s)) ?? []
                    guard !Task.isCancelled else { searching.remove(s); return }
                    server[s] = found
                    searching.remove(s)
                }
            }
            .onAppear {
                if DemoScreen.current == .search, text.isEmpty { text = "night" }
            }
        }
    }

    private func playlistRow(name: String, sub: String, url: URL?, symbol: String) -> some View {
        HStack(spacing: 12) {
            ArtworkView(url: url, seed: name, symbol: symbol, corner: 6).frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).lineLimit(1)
                Text(sub).font(.subheadline).foregroundStyle(look.palette.secondary).lineLimit(1)
            }
        }
    }

    private func songs(_ list: [Track]) -> some View {
        ForEach(Array(list.prefix(50).enumerated()), id: \.element.id) { k, t in
            Button { player.play(Array(list.prefix(50)), at: k) } label: { SongRow(track: t, number: nil) }
                .buttonStyle(.plain)
                .contextMenu { TrackMenu(track: t, addTo: $addTo) }
        }
    }
}
