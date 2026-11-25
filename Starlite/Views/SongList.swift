import SwiftUI

/// One song in a list: number, cover, title, artist (and album), length.
struct SongRow: View {
    @Environment(Look.self) private var look
    @Environment(Player.self) private var player
    @Environment(Library.self) private var library
    var track: Track
    var number: Int?

    var body: some View {
        let p = look.prefs
        let isCurrent = player.current?.id == track.id
        HStack(spacing: 12) {
            if p.showNumbers, let number {
                ZStack {
                    if isCurrent {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative, isActive: player.playing)
                            .foregroundStyle(look.palette.accent)
                    } else {
                        Text("\(number)").foregroundStyle(look.palette.secondary)
                    }
                }
                .font(.subheadline.monospacedDigit())
                .frame(width: 24)
            }
            if p.showArtwork {
                ArtworkView(url: track.artwork, seed: track.album ?? track.title, corner: max(4, CGFloat(p.corners) * 0.4))
                    .frame(width: p.rowSize.artwork, height: p.rowSize.artwork)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .foregroundStyle(isCurrent ? look.palette.accent : look.palette.text)
                    .lineLimit(1)
                Text(p.showAlbum && track.album != nil ? "\(track.artist) · \(track.album!)" : track.artist)
                    .font(.subheadline)
                    .foregroundStyle(look.palette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if let k = track.serverKey, let f = library.downloading[k] {
                ProgressView(value: f).progressViewStyle(.circular).controlSize(.small)
            } else if !track.isLocal && library.isDownloaded(track) {
                Image(systemName: "arrow.down.circle.fill").font(.footnote).foregroundStyle(look.palette.secondary)
            }
            if library.isLiked(track) {
                Image(systemName: "heart.fill").font(.footnote).foregroundStyle(look.palette.accent)
            }
            if track.duration > 0 {
                Text(formatTime(track.duration))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(look.palette.secondary)
            }
        }
        .padding(.vertical, p.rowSize.padding)
        .contentShape(Rectangle())
        .fontWeight(nil)
    }
}

/// What a long press on a song offers.
struct TrackMenu: View {
    @Environment(Player.self) private var player
    @Environment(Library.self) private var library
    @Environment(Services.self) private var services
    @Environment(Look.self) private var look
    var track: Track
    @Binding var addTo: Track?
    /// Your playlist the song is in (offers "Remove from Playlist").
    var playlistId: String?

    var body: some View {
        Button { player.playNext(track) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
        Button { player.addToQueue(track) } label: { Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") }
        Divider()
        Button { addTo = track } label: { Label("Add to a Playlist…", systemImage: "text.badge.plus") }
        Button { library.toggleLike(track) } label: {
            library.isLiked(track) ? Label("Unlike", systemImage: "heart.slash") : Label("Like", systemImage: "heart")
        }
        if !track.isLocal {
            if library.isDownloaded(track) {
                Button(role: .destructive) { library.removeDownload(of: track) } label: { Label("Remove Download", systemImage: "trash") }
            } else {
                Button { library.download(track, services: services, quality: look.prefs.download) } label: { Label("Download", systemImage: "arrow.down.circle") }
            }
        } else {
            Button(role: .destructive) { library.deleteFile(track) } label: { Label("Delete from iPhone", systemImage: "trash") }
        }
        if let playlistId {
            Button(role: .destructive) { library.remove(track.id, from: playlistId) } label: { Label("Remove from Playlist", systemImage: "minus.circle") }
        }
    }
}

/// Pick one of your playlists (or make a new one) for some songs.
struct AddToPlaylistSheet: View {
    @Environment(Library.self) private var library
    @Environment(Look.self) private var look
    @Environment(\.dismiss) private var dismiss
    var tracks: [Track]
    @State private var newName = ""
    @State private var naming = false

    var body: some View {
        NavigationStack {
            List {
                Button {
                    naming = true
                } label: {
                    Label("New Playlist…", systemImage: "plus").foregroundStyle(look.palette.accent)
                }
                ForEach(library.playlists) { p in
                    Button {
                        library.add(tracks, to: p.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            ArtworkView(url: p.artwork, seed: p.name, symbol: p.symbol, corner: 6).frame(width: 44, height: 44)
                            VStack(alignment: .leading) {
                                Text(p.name).foregroundStyle(look.palette.text)
                                Text(songCount(p.tracks)).font(.caption).foregroundStyle(look.palette.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert("New Playlist", isPresented: $naming) {
                TextField("Name", text: $newName)
                Button("Create") {
                    library.create(newName, tracks: tracks)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Which songs a playlist page shows.
enum ListKind: Hashable {
    case playlist(String)
    case liked
    case downloaded
    case server(ServerCollection)

    /// Ties the page to what it grows out of when it opens.
    var zoomId: String {
        switch self {
        case .playlist(let id): "playlist-" + id
        case .liked: "liked"
        case .downloaded: "downloaded"
        case .server(let c): "server-" + c.id
        }
    }
}

/// A playlist, album, Liked or Downloaded: big cover, name, Play and
/// Shuffle, then the songs as a plain list.
struct CollectionView: View {
    @Environment(Look.self) private var look
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player
    @Environment(Services.self) private var services
    var collection: ListKind

    @State private var serverTracks: [Track]?
    @State private var loadError: String?
    @State private var addTo: Track?
    @State private var addAll = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var importing = false
    @State private var search = ""

    private var info: (title: String, subtitle: String, url: URL?, seed: String, symbol: String) {
        switch collection {
        case .playlist(let id):
            let p = library.playlist(id)
            return (p?.name ?? "Playlist", songCount(p?.tracks ?? []), p?.artwork, p?.name ?? "", p?.symbol ?? "music.note.list")
        case .liked:
            return ("Liked Music", songCount(library.liked), nil, "liked", "heart.fill")
        case .downloaded:
            return ("Downloaded Music", songCount(library.downloaded), nil, "downloaded", "arrow.down")
        case .server(let c):
            return (c.name, serverTracks.map(songCount) ?? c.subtitle, c.artwork, c.name, c.kind == .album ? "opticaldisc" : "music.note.list")
        }
    }

    private var tracks: [Track] {
        let all: [Track]
        switch collection {
        case .playlist(let id): all = library.playlist(id)?.tracks ?? []
        case .liked: all = library.liked
        case .downloaded: all = library.downloaded
        case .server: all = serverTracks ?? []
        }
        guard !search.isEmpty else { return all }
        return all.filter { "\($0.title) \($0.artist) \($0.album ?? "")".localizedCaseInsensitiveContains(search) }
    }

    private var playlistId: String? {
        if case .playlist(let id) = collection { return id }
        return nil
    }

    var body: some View {
        let i = info
        let list = tracks
        List {
            VStack(spacing: 14) {
                ArtworkView(url: i.url, seed: i.seed, symbol: i.symbol, corner: CGFloat(look.prefs.corners))
                    .frame(width: 250, height: 250)
                    .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
                    .overlay(alignment: .center) {
                        if case .liked = collection { LikedCover(corner: CGFloat(look.prefs.corners)) }
                        if case .downloaded = collection { DownloadedCover(corner: CGFloat(look.prefs.corners)) }
                    }
                VStack(spacing: 3) {
                    Text(i.title).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                    Text(i.subtitle).font(.subheadline).foregroundStyle(look.palette.secondary)
                }
                PlayShuffleButtons(play: { player.play(list) }, shuffle: { player.play(list, shuffled: true) })
                    .disabled(list.isEmpty)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 10)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            if serverTracks == nil, case .server = collection, loadError == nil {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            if let e = loadError {
                Text(e).foregroundStyle(look.palette.secondary).listRowBackground(Color.clear)
            }
            if list.isEmpty && serverTracks != nil || list.isEmpty && !isServer {
                emptyNote.listRowBackground(Color.clear).listRowSeparator(.hidden)
            }

            ForEach(Array(list.enumerated()), id: \.element.id) { k, t in
                Button {
                    player.play(list, at: k)
                } label: {
                    SongRow(track: t, number: k + 1)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(look.palette.secondary.opacity(0.25))
                .contextMenu { TrackMenu(track: t, addTo: $addTo, playlistId: playlistId) }
                .swipeActions(edge: .trailing) {
                    if let id = playlistId {
                        Button(role: .destructive) { library.remove(t.id, from: id) } label: { Label("Remove", systemImage: "minus.circle") }
                    } else if case .liked = collection {
                        Button(role: .destructive) { library.toggleLike(t) } label: { Label("Unlike", systemImage: "heart.slash") }
                    } else if case .downloaded = collection {
                        Button(role: .destructive) { library.deleteFile(t) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                .swipeActions(edge: .leading) {
                    Button { player.playNext(t) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }.tint(.indigo)
                    Button { library.toggleLike(t) } label: { Label("Like", systemImage: library.isLiked(t) ? "heart.slash" : "heart") }.tint(.pink)
                }
            }
            .onMove(perform: playlistId == nil || !search.isEmpty ? nil : { from, to in library.move(in: playlistId!, from: from, to: to) })
        }
        .listStyle(.plain)
        .searchable(text: $search, prompt: "Find in \(i.title)")
        .themed(look)
        .navigationTitle(i.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(item: $addTo) { t in AddToPlaylistSheet(tracks: [t]) }
        .sheet(isPresented: $addAll) { AddToPlaylistSheet(tracks: tracks) }
        .alert("Rename Playlist", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Rename") { if let id = playlistId { library.rename(id, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { r in
            if case .success(let urls) = r { Task { await library.importFiles(urls) } }
        }
        .task { await loadServer() }
        .refreshable {
            if case .downloaded = collection { await library.scan() } else { await loadServer() }
        }
    }

    private var isServer: Bool {
        if case .server = collection { return true }
        return false
    }

    @ViewBuilder private var emptyNote: some View {
        switch collection {
        case .liked: Text("Songs you like show up here. Tap the heart in the player.").foregroundStyle(look.palette.secondary)
        case .downloaded: Text("Download songs from your server, or add music files in the Files app (On My iPhone → Starlite).").foregroundStyle(look.palette.secondary)
        case .playlist: Text("Add songs with a long press on any song.").foregroundStyle(look.palette.secondary)
        case .server: Text("This is empty.").foregroundStyle(look.palette.secondary)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                switch collection {
                case .playlist:
                    Button { newName = info.title; renaming = true } label: { Label("Rename", systemImage: "pencil") }
                    Button { tracks.forEach { library.download($0, services: services, quality: look.prefs.download) } } label: { Label("Download All", systemImage: "arrow.down.circle") }
                    EditButton()
                case .server(let c):
                    Button {
                        library.create(c.name, tracks: tracks, origin: c.server == .navidrome ? .navidrome(id: c.id) : .jellyfin(id: c.id))
                    } label: { Label("Add to My Playlists", systemImage: "plus.square.on.square") }
                    .disabled(serverTracks == nil)
                    Button { addAll = true } label: { Label("Add Songs to a Playlist…", systemImage: "text.badge.plus") }
                    Button { tracks.forEach { library.download($0, services: services, quality: look.prefs.download) } } label: { Label("Download All", systemImage: "arrow.down.circle") }
                case .liked:
                    Button { addAll = true } label: { Label("Add All to a Playlist…", systemImage: "text.badge.plus") }
                    Button { tracks.forEach { library.download($0, services: services, quality: look.prefs.download) } } label: { Label("Download All", systemImage: "arrow.down.circle") }
                case .downloaded:
                    Button { importing = true } label: { Label("Add from Files…", systemImage: "folder.badge.plus") }
                    Button { addAll = true } label: { Label("Add All to a Playlist…", systemImage: "text.badge.plus") }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
        }
    }

    private func loadServer() async {
        guard case .server(let c) = collection else { return }
        do {
            serverTracks = try await services.tracks(of: c)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// Liked Music's cover: the heart, in the theme's colours.
struct LikedCover: View {
    @Environment(Look.self) private var look
    var corner: CGFloat
    var body: some View {
        PlainCover(symbol: "heart", corner: corner)
    }
}

/// Downloaded Music's cover: the arrow, in the theme's colours.
struct DownloadedCover: View {
    var corner: CGFloat
    var body: some View {
        PlainCover(symbol: "arrow.down.circle", corner: corner)
    }
}

/// A cover that's just an icon on the theme's panel colour.
private struct PlainCover: View {
    @Environment(Look.self) private var look
    var symbol: String
    var corner: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(look.palette.panel)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 72))
                    .fontWeight(look.prefs.iconWeight.weight)
                    .foregroundStyle(look.palette.accent)
            )
    }
}
