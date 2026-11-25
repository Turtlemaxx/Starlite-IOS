import SwiftUI

/// Your Navidrome or Jellyfin server: its playlists, newest albums and a search.
struct ServerTab: View {
    @Environment(Look.self) private var look
    @Environment(Services.self) private var services
    @Environment(Player.self) private var player
    @Environment(Library.self) private var library
    @State private var path = NavigationPath()
    @State private var search = ""
    @State private var results: [Track] = []
    @State private var searching = false
    @State private var addTo: Track?

    var body: some View {
        @Bindable var services = services
        NavigationStack(path: $path) {
            Group {
                if services.connected.isEmpty {
                    ConnectChoice()
                } else {
                    content
                }
            }
            .themed(look)
            .navigationTitle(services.connected.isEmpty ? "Music Server" : services.shown.name)
            .navigationBarTitleDisplayMode(look.prefs.bigTitles ? .large : .inline)
            .navigationDestination(for: ListKind.self) { CollectionView(collection: $0) }
            .navigationDestination(for: ServerKind.self) { ConnectView(server: $0) }
            .toolbar {
                if services.connected.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Picker("Server", selection: $services.shown) {
                            ForEach(services.connected) { Text($0.name).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .sheet(item: $addTo) { t in AddToPlaylistSheet(tracks: [t]) }
        }
    }

    private var content: some View {
        let s = services.shown
        return ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !search.isEmpty {
                    searchResults
                } else {
                    if !library.recent.isEmpty {
                        RecentlyPlayed()
                    }
                    if let e = services.errors[s] {
                        Label(e, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(look.palette.secondary)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .panel(look)
                    }
                    if services.loading.contains(s) && services.playlists[s] == nil {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }
                    if let pl = services.playlists[s], !pl.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle(title: "Playlists")
                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 16) {
                                    ForEach(pl) { c in card(c, size: 170) }
                                }
                                .scrollTargetLayout()
                            }
                            .scrollTargetBehavior(.viewAligned)
                            .scrollIndicators(.hidden)
                            .scrollClipDisabled()
                        }
                    }
                    if let al = services.albums[s], !al.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle(title: "Recently Added")
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 20) {
                                ForEach(al) { c in card(c, size: nil) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .searchable(text: $search, prompt: "Songs on \(s.name)")
        .onSubmit(of: .search) { Task { await runSearch() } }
        .onChange(of: search) { _, v in
            if v.isEmpty { results = [] }
        }
        .refreshable { await services.refresh(s) }
        .task(id: s) {
            if services.playlists[s] == nil { await services.refresh(s) }
        }
    }

    private func card(_ c: ServerCollection, size: CGFloat?) -> some View {
        Button { path.append(ListKind.server(c)) } label: {
            VStack(alignment: .leading, spacing: 6) {
                ArtworkView(url: c.artwork, seed: c.name, symbol: c.kind == .album ? "opticaldisc" : "music.note.list", corner: CGFloat(look.prefs.corners) * 0.7)
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(c.subtitle).font(.caption).foregroundStyle(look.palette.secondary).lineLimit(1)
                }
                .frame(width: size, alignment: .leading)
            }
        }
        .buttonStyle(PressScale())
        .contextMenu {
            if c.kind == .playlist {
                Button {
                    Task {
                        if let t = try? await services.tracks(of: c) {
                            library.create(c.name, tracks: t, origin: c.server == .navidrome ? .navidrome(id: c.id) : .jellyfin(id: c.id))
                        }
                    }
                } label: { Label("Add to My Playlists", systemImage: "plus.square.on.square") }
            }
            Button {
                Task { if let t = try? await services.tracks(of: c) { player.play(t) } }
            } label: { Label("Play", systemImage: "play.fill") }
            Button {
                Task { if let t = try? await services.tracks(of: c) { player.play(t, shuffled: true) } }
            } label: { Label("Shuffle", systemImage: "shuffle") }
        }
    }

    @ViewBuilder private var searchResults: some View {
        if searching {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
        } else if results.isEmpty {
            Text("Press Search to look for \u{201c}\(search)\u{201d}.").foregroundStyle(look.palette.secondary)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { k, t in
                    Button { player.play(results, at: k) } label: { SongRow(track: t, number: nil) }
                        .buttonStyle(.plain)
                        .contextMenu { TrackMenu(track: t, addTo: $addTo) }
                    Divider().opacity(0.35)
                }
            }
        }
    }

    private func runSearch() async {
        guard !search.isEmpty else { return }
        searching = true
        results = (try? await services.search(search, on: services.shown)) ?? []
        searching = false
    }
}

/// No server yet: pick one to connect.
private struct ConnectChoice: View {
    @Environment(Look.self) private var look
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image("Logo").resizable().scaledToFit().frame(width: 96, height: 96)
                    .colorMultiply(look.palette.text)
                    .padding(.top, 30)
                Text("Your music, from your server").font(.title2.weight(.bold)).multilineTextAlignment(.center)
                Text("Connect Navidrome or Jellyfin to play your playlists and albums. You can connect both.")
                    .font(.subheadline)
                    .foregroundStyle(look.palette.secondary)
                    .multilineTextAlignment(.center)
                VStack(spacing: 12) {
                    ForEach(ServerKind.allCases) { s in
                        NavigationLink(value: s) {
                            HStack(spacing: 14) {
                                RowIcon(logo: s.logo)
                                Text(s.name).font(.headline)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(look.palette.secondary)
                            }
                            .padding(16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .panel(look, interactive: true)
                    }
                }
                .padding(.top, 8)
            }
            .padding(24)
        }
    }
}

/// Sign in to Navidrome or Jellyfin (or see the connection and sign out).
struct ConnectView: View {
    @Environment(Look.self) private var look
    @Environment(Services.self) private var services
    @Environment(\.dismiss) private var dismiss
    var server: ServerKind
    @State private var url = ""
    @State private var user = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            if let d = services.describe(server) {
                Section {
                    LabeledContent("Connected", value: d)
                    Button("Disconnect", role: .destructive) { services.disconnect(server) }
                } footer: {
                    Text("Starlite keeps a sign-in token in the Keychain, not your password.")
                }
                .groupBackground(look)
            } else {
                Section {
                    TextField(server == .navidrome ? "Address, e.g. 192.168.1.10:4533" : "Address, e.g. 192.168.1.10:8096", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Username", text: $user)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                } header: {
                    Text(server.name)
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text("Your password is only used to sign in; Starlite keeps a token in the Keychain.")
                    }
                }
                Section {
                    Button {
                        Task { await connect() }
                    } label: {
                        HStack {
                            Text("Connect").fontWeight(.semibold)
                            Spacer()
                            if busy { ProgressView() }
                        }
                    }
                    .disabled(busy || url.isEmpty || user.isEmpty)
                }
            }
        }
        .themed(look)
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func connect() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await services.connect(server, url: url, user: user, password: password)
            password = ""
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// What you played last: small tiles in two rows, the cover on the left.
private struct RecentlyPlayed: View {
    @Environment(Look.self) private var look
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player

    var body: some View {
        let recent = library.recent
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Recently Played")
            ScrollView(.horizontal) {
                LazyHGrid(rows: [GridItem(.fixed(60), spacing: 10), GridItem(.fixed(60), spacing: 10)], spacing: 10) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { k, t in
                        Button { player.play(recent, at: k) } label: {
                            HStack(spacing: 10) {
                                ArtworkView(url: t.artwork, seed: t.album ?? t.title, corner: 6)
                                    .frame(width: 44, height: 44)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(t.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(t.artist).font(.caption).foregroundStyle(look.palette.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .frame(width: 236, height: 60)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressScale())
                        .panel(look, radius: CGFloat(look.prefs.corners) * 0.6 + 4)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }
}
