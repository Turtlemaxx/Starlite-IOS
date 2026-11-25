import SwiftUI

/// Something on the shelf: one of your playlists or one on a server.
struct ShelfItem: Identifiable, Hashable {
    var id: String
    var name: String
    var subtitle: String
    var artwork: URL?
    var symbol: String
    var kind: ListKind
    /// Your playlist's songs (server playlists load when opened).
    var tracks: [Track]?

    init(_ p: Playlist) {
        id = "p-" + p.id
        name = p.name
        subtitle = songCount(p.tracks)
        artwork = p.artwork
        symbol = p.symbol
        kind = .playlist(p.id)
        tracks = p.tracks
    }

    init(_ c: ServerCollection) {
        id = "s-" + c.server.rawValue + "-" + c.id
        name = c.name
        subtitle = c.subtitle
        artwork = c.artwork
        symbol = "music.note.list"
        kind = .server(c)
        tracks = nil
    }
}

/// Your music: Liked and Downloaded on top, then your playlists and your
/// servers' playlists, as CDs on shelves or as a list.
struct PlaylistsTab: View {
    @Environment(Look.self) private var look
    @Environment(Library.self) private var library
    @Environment(Services.self) private var services
    @Environment(Player.self) private var player
    @State private var path = NavigationPath()
    @State private var naming = false
    @State private var newName = ""
    @State private var renaming: Playlist?
    @State private var deleting: Playlist?
    @Namespace private var zoom

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(spacing: 14) {
                        PinnedTile(title: "Liked Music", count: library.liked.count, symbol: "heart") {
                            path.append(ListKind.liked)
                        }
                        .matchedTransitionSource(id: ListKind.liked.zoomId, in: zoom)
                        PinnedTile(title: "Downloaded", count: library.downloaded.count, symbol: "arrow.down.circle") {
                            path.append(ListKind.downloaded)
                        }
                        .matchedTransitionSource(id: ListKind.downloaded.zoomId, in: zoom)
                    }

                    section("Your Playlists", count: library.playlists.count, items: library.playlists.map(ShelfItem.init)) {
                        emptyShelf
                    }

                    // Each connected server's playlists, listed by themselves.
                    ForEach(services.connected) { s in
                        if let list = services.playlists[s], !list.isEmpty {
                            section(s.name, count: list.count, logo: s.logo, items: list.map(ShelfItem.init)) { EmptyView() }
                        } else if services.loading.contains(s) {
                            VStack(alignment: .leading, spacing: 12) {
                                header(s.name, count: nil, logo: s.logo)
                                ProgressView().frame(maxWidth: .infinity)
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
                    Button {
                        withAnimation(.snappy) { look.prefs.shelf.toggle() }
                    } label: {
                        Image(systemName: look.prefs.shelf ? "list.bullet" : "square.grid.2x2")
                    }
                    .accessibilityLabel(look.prefs.shelf ? "Show as a list" : "Show as CDs")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newName = ""; naming = true } label: { Image(systemName: "plus") }
                }
            }
            .navigationDestination(for: ListKind.self) { kind in
                // The page grows out of the CD (or tile) that was tapped.
                CollectionView(collection: kind)
                    .navigationTransition(.zoom(sourceID: kind.zoomId, in: zoom))
            }
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

    private func header(_ title: String, count: Int?, logo: String? = nil) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if let logo {
                Image(logo).renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(look.palette.accent)
            }
            Text(title).font(.title2.weight(.bold))
            Spacer()
            if let count { Text("\(count)").foregroundStyle(look.palette.secondary) }
        }
    }

    @ViewBuilder
    private func section<E: View>(_ title: String, count: Int, logo: String? = nil, items: [ShelfItem], @ViewBuilder empty: () -> E) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header(title, count: count, logo: logo)
            if items.isEmpty {
                empty()
            } else if look.prefs.shelf {
                Bookshelf(items: items, zoom: zoom, open: { path.append($0.kind) }, menu: { menu($0) })
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        Button { path.append(item.kind) } label: {
                            HStack(spacing: 14) {
                                ArtworkView(url: item.artwork, seed: item.name, symbol: item.symbol, corner: CGFloat(look.prefs.corners) * 0.5)
                                    .frame(width: 60, height: 60)
                                    .matchedTransitionSource(id: item.kind.zoomId, in: zoom)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.headline).lineLimit(1)
                                    Text(item.subtitle).font(.subheadline).foregroundStyle(look.palette.secondary).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(look.palette.secondary)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu { menu(item) }
                        Divider().opacity(0.4)
                    }
                }
            }
        }
    }

    private var emptyShelf: some View {
        VStack(spacing: 12) {
            Image(systemName: "opticaldisc").font(.system(size: 40)).foregroundStyle(look.palette.secondary)
            Text("No playlists yet").font(.headline)
            Text("Make one with +, or add one from your music server.").font(.subheadline).foregroundStyle(look.palette.secondary).multilineTextAlignment(.center)
            Button("New Playlist") { newName = ""; naming = true }.buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .panel(look)
    }

    @ViewBuilder private func menu(_ item: ShelfItem) -> some View {
        switch item.kind {
        case .playlist(let id):
            if let p = library.playlist(id) {
                Button { player.play(p.tracks) } label: { Label("Play", systemImage: "play.fill") }
                Button { player.play(p.tracks, shuffled: true) } label: { Label("Shuffle", systemImage: "shuffle") }
                Button { renaming = p; newName = p.name } label: { Label("Rename", systemImage: "pencil") }
                Button(role: .destructive) { deleting = p } label: { Label("Delete", systemImage: "trash") }
            }
        case .server(let c):
            Button { Task { if let t = try? await services.tracks(of: c) { player.play(t) } } } label: { Label("Play", systemImage: "play.fill") }
            Button { Task { if let t = try? await services.tracks(of: c) { player.play(t, shuffled: true) } } } label: { Label("Shuffle", systemImage: "shuffle") }
            Button {
                Task {
                    if let t = try? await services.tracks(of: c) {
                        library.create(c.name, tracks: t, origin: c.server == .navidrome ? .navidrome(id: c.id) : .jellyfin(id: c.id))
                    }
                }
            } label: { Label("Add to My Playlists", systemImage: "plus.square.on.square") }
        default:
            EmptyView()
        }
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
        .panel(look)
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

/// CDs standing on shelves, big enough to hit easily.
private struct Bookshelf<M: View>: View {
    @Environment(Look.self) private var look
    @Environment(Player.self) private var player
    var items: [ShelfItem]
    var zoom: Namespace.ID
    var open: (ShelfItem) -> Void
    @ViewBuilder var menu: (ShelfItem) -> M
    /// The CD being opened: its disc glides out, then the page opens.
    @State private var opening: String?

    private func tap(_ item: ShelfItem) {
        guard opening == nil else { return }
        withAnimation(.easeOut(duration: 0.22)) { opening = item.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { open(item) }
        // Back in place (unseen, behind the page) for when you come back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { opening = nil }
    }

    /// The playlist that's playing (its disc stays out, turning).
    private func isPlaying(_ item: ShelfItem) -> Bool {
        guard player.playing, let c = player.current, let t = item.tracks else { return false }
        return t.contains { $0.id == c.id }
    }

    var body: some View {
        let cols = look.prefs.shelfSize.columns
        let rows = stride(from: 0, to: items.count, by: cols).map { Array(items[$0..<min($0 + cols, items.count)]) }
        VStack(spacing: 30) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(spacing: 0) {
                    HStack(alignment: .bottom, spacing: 22) {
                        ForEach(row) { item in
                            Button { tap(item) } label: {
                                CDCase(item: item, pulled: opening == item.id, spinning: isPlaying(item), zoom: zoom)
                            }
                            .buttonStyle(PressScale())
                            .contextMenu { menu(item) }
                            .tapFeedback(look, trigger: opening == item.id)
                        }
                        if row.count < cols {
                            ForEach(0..<(cols - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                        }
                    }
                    .padding(.horizontal, 10)
                    ShelfBoard()
                    HStack(alignment: .top, spacing: 22) {
                        ForEach(row) { item in
                            VStack(spacing: 2) {
                                Text(item.name).font(.headline).lineLimit(1)
                                Text(item.subtitle).font(.caption).foregroundStyle(look.palette.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture { tap(item) }
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

/// A playlist as a CD: its cover, with the disc peeking out behind it.
/// Opening it glides the disc out; the playing one's disc stays a little
/// out, turning.
struct CDCase: View {
    @Environment(Look.self) private var look
    var item: ShelfItem
    var pulled = false
    var spinning = false
    var zoom: Namespace.ID? = nil

    var body: some View {
        GeometryReader { g in
            let side = g.size.height
            let disc = side * 0.92
            let rest = g.size.width - disc
            let out = pulled ? side * 0.3 : (spinning ? side * 0.12 : 0)
            ZStack(alignment: .leading) {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !spinning)) { tl in
                    let turn = spinning ? tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8) / 8 * 360 : 0
                    Disc(item: item)
                        .rotationEffect(.degrees(turn + (pulled ? 70 : 0)))
                }
                .frame(width: disc, height: disc)
                .offset(x: rest + out)
                .shadow(color: .black.opacity(0.22), radius: 4, x: 2, y: 2)
                cover(side)
            }
        }
        .aspectRatio(1.22, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func cover(_ side: CGFloat) -> some View {
        let art = ArtworkView(url: item.artwork, seed: item.name, symbol: item.symbol, corner: max(3, CGFloat(look.prefs.corners) * 0.35))
            .frame(width: side, height: side)
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 6)
        if let zoom {
            art.matchedTransitionSource(id: item.kind.zoomId, in: zoom)
        } else {
            art
        }
    }
}

/// A CD: brushed silver, the cover printed on its label, a hole.
private struct Disc: View {
    @Environment(Look.self) private var look
    var item: ShelfItem

    var body: some View {
        GeometryReader { g in
            let d = g.size.width
            ZStack {
                Circle().fill(AngularGradient(colors: [
                    Color(white: 0.80), Color(white: 0.94), Color(white: 0.78), Color(white: 0.90),
                    Color(white: 0.76), Color(white: 0.95), Color(white: 0.80),
                ], center: .center))
                ForEach(1..<6) { k in
                    Circle().strokeBorder(.black.opacity(0.045), lineWidth: 0.5)
                        .frame(width: d * (0.66 + 0.06 * CGFloat(k)), height: d * (0.66 + 0.06 * CGFloat(k)))
                }
                ArtworkView(url: item.artwork, seed: item.name, symbol: item.symbol, corner: 0)
                    .frame(width: d * 0.6, height: d * 0.6)
                    .clipShape(Circle())
                Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1).frame(width: d * 0.6, height: d * 0.6)
                Circle().fill(Color(white: 0.88, opacity: 0.9)).frame(width: d * 0.2, height: d * 0.2)
                Circle().fill(look.palette.background).frame(width: d * 0.09, height: d * 0.09)
                Circle().strokeBorder(.black.opacity(0.14), lineWidth: 0.5)
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
