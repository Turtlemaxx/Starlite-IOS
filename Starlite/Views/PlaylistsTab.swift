import SwiftUI

/// Your music: Liked and Downloaded on top, then your playlists as big CD
/// cases on shelves (or a list).
struct PlaylistsTab: View {
    @Environment(Look.self) private var look
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player
    @State private var path = NavigationPath()
    @State private var naming = false
    @State private var newName = ""
    @State private var renaming: Playlist?
    @State private var deleting: Playlist?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(spacing: 14) {
                        PinnedTile(title: "Liked Music", count: library.liked.count, symbol: "heart") {
                            path.append(ListKind.liked)
                        }
                        PinnedTile(title: "Downloaded", count: library.downloaded.count, symbol: "arrow.down.circle") {
                            path.append(ListKind.downloaded)
                        }
                    }

                    HStack(alignment: .firstTextBaseline) {
                        SectionTitle(title: "Your Playlists")
                        Text("\(library.playlists.count)").foregroundStyle(look.palette.secondary)
                    }

                    if library.playlists.isEmpty {
                        emptyShelf
                    } else if look.prefs.shelf {
                        Bookshelf(playlists: library.playlists, open: { path.append(ListKind.playlist($0.id)) }, rename: { renaming = $0; newName = $0.name }, delete: { deleting = $0 })
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(library.playlists) { p in
                                Button { path.append(ListKind.playlist(p.id)) } label: {
                                    HStack(spacing: 14) {
                                        ArtworkView(url: p.artwork, seed: p.name, symbol: p.symbol, corner: CGFloat(look.prefs.corners) * 0.5)
                                            .frame(width: 64, height: 64)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(p.name).font(.headline)
                                            Text(songCount(p.tracks)).font(.subheadline).foregroundStyle(look.palette.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(look.palette.secondary)
                                    }
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu { playlistMenu(p) }
                                Divider().opacity(0.4)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .themed(look)
            .navigationTitle("Playlists")
            .navigationBarTitleDisplayMode(look.prefs.bigTitles ? .large : .inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newName = ""; naming = true } label: { Image(systemName: "plus") }
                }
            }
            .navigationDestination(for: ListKind.self) { CollectionView(collection: $0) }
            .alert("New Playlist", isPresented: $naming) {
                TextField("Name", text: $newName)
                Button("Create") { library.create(newName) }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Rename Playlist", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Rename") { if let p = renaming { library.rename(p.id, to: newName) } }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete \(deleting?.name ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete Playlist", role: .destructive) { if let p = deleting { library.delete(p.id) } }
            } message: {
                Text("The songs stay where they are.")
            }
            .onAppear {
                if DemoScreen.current == .playlist, path.isEmpty, let p = library.playlists.first {
                    path.append(ListKind.playlist(p.id))
                }
            }
        }
    }

    private var emptyShelf: some View {
        VStack(spacing: 12) {
            Image(systemName: "opticaldisc").font(.system(size: 44)).foregroundStyle(look.palette.secondary)
            Text("No playlists yet").font(.headline)
            Text("Make one with +, or save a playlist from your music server.").font(.subheadline).foregroundStyle(look.palette.secondary).multilineTextAlignment(.center)
            Button("New Playlist") { newName = ""; naming = true }.buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .panel(look)
    }

    @ViewBuilder private func playlistMenu(_ p: Playlist) -> some View {
        Button { player.play(p.tracks) } label: { Label("Play", systemImage: "play.fill") }
        Button { player.play(p.tracks, shuffled: true) } label: { Label("Shuffle", systemImage: "shuffle") }
        Button { renaming = p; newName = p.name } label: { Label("Rename", systemImage: "pencil") }
        Button(role: .destructive) { deleting = p } label: { Label("Delete", systemImage: "trash") }
    }
}

/// Liked / Downloaded: a big tile at the top.
private struct PinnedTile: View {
    @Environment(Look.self) private var look
    var title: String
    var count: Int
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 26))
                    .fontWeight(look.prefs.iconWeight.weight)
                    .foregroundStyle(look.palette.accent)
                    .frame(height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline).foregroundStyle(look.palette.text)
                    Text(count == 1 ? "1 song" : "\(count) songs").font(.subheadline).foregroundStyle(look.palette.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .panel(look, interactive: true)
    }
}

/// Shrinks a little while pressed.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Playlists as CD cases standing on shelves, big enough to hit easily.
private struct Bookshelf: View {
    @Environment(Look.self) private var look
    var playlists: [Playlist]
    var open: (Playlist) -> Void
    var rename: (Playlist) -> Void
    var delete: (Playlist) -> Void
    @Environment(Player.self) private var player

    var body: some View {
        let cols = look.prefs.shelfSize.columns
        let rows = stride(from: 0, to: playlists.count, by: cols).map { Array(playlists[$0..<min($0 + cols, playlists.count)]) }
        VStack(spacing: 30) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(spacing: 0) {
                    HStack(alignment: .bottom, spacing: 22) {
                        ForEach(row) { p in
                            Button { open(p) } label: { CDCase(playlist: p) }
                                .buttonStyle(PressScale())
                                .contextMenu {
                                    Button { player.play(p.tracks) } label: { Label("Play", systemImage: "play.fill") }
                                    Button { player.play(p.tracks, shuffled: true) } label: { Label("Shuffle", systemImage: "shuffle") }
                                    Button { rename(p) } label: { Label("Rename", systemImage: "pencil") }
                                    Button(role: .destructive) { delete(p) } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                        if row.count < cols {
                            ForEach(0..<(cols - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                        }
                    }
                    .padding(.horizontal, 10)
                    // The shelf board they stand on.
                    ShelfBoard()
                    HStack(alignment: .top, spacing: 22) {
                        ForEach(row) { p in
                            VStack(spacing: 2) {
                                Text(p.name).font(.headline).lineLimit(1)
                                Text(songCount(p.tracks)).font(.caption).foregroundStyle(look.palette.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .onTapGesture { open(p) }
                        }
                        if row.count < cols {
                            ForEach(0..<(cols - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                        }
                    }
                    .padding(.top, 10)
                    .padding(.horizontal, 10)
                }
            }
        }
    }
}

/// A playlist as a CD: its cover, with the disc sliding out behind it.
struct CDCase: View {
    @Environment(Look.self) private var look
    var playlist: Playlist

    var body: some View {
        GeometryReader { g in
            let side = g.size.height
            let disc = side * 0.92
            ZStack(alignment: .leading) {
                Disc(playlist: playlist)
                    .frame(width: disc, height: disc)
                    .offset(x: g.size.width - disc)
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 2, y: 2)
                ArtworkView(url: playlist.artwork, seed: playlist.name, symbol: playlist.symbol, corner: max(3, CGFloat(look.prefs.corners) * 0.35))
                    .frame(width: side, height: side)
                    .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 6)
            }
        }
        .aspectRatio(1.22, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }
}

/// A CD: silver with a faint rainbow, the cover printed on its label, a hole.
private struct Disc: View {
    @Environment(Look.self) private var look
    var playlist: Playlist

    var body: some View {
        GeometryReader { g in
            let d = g.size.width
            ZStack {
                Circle().fill(AngularGradient(colors: [
                    Color(white: 0.86), Color(red: 0.80, green: 0.86, blue: 0.95), Color(white: 0.97),
                    Color(red: 0.95, green: 0.86, blue: 0.92), Color(white: 0.82), Color(red: 0.86, green: 0.95, blue: 0.88),
                    Color(white: 0.96), Color(white: 0.86),
                ], center: .center))
                // The label: the playlist's cover, printed on the disc.
                ArtworkView(url: playlist.artwork, seed: playlist.name, symbol: playlist.symbol, corner: 0)
                    .frame(width: d * 0.62, height: d * 0.62)
                    .clipShape(Circle())
                    .opacity(0.9)
                Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1).frame(width: d * 0.62, height: d * 0.62)
                // The clear ring and the hole.
                Circle().fill(Color(white: 0.9, opacity: 0.85)).frame(width: d * 0.2, height: d * 0.2)
                Circle().fill(look.palette.background).frame(width: d * 0.09, height: d * 0.09)
                Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The board under a row of CDs.
private struct ShelfBoard: View {
    @Environment(Look.self) private var look
    var body: some View {
        Color.clear
            .frame(height: 16)
            .panel(look, radius: 8)
            .shadow(color: .black.opacity(look.palette.dark ? 0.5 : 0.15), radius: 8, y: 6)
    }
}
