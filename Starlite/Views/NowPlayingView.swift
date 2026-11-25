import AVKit
import MediaPlayer
import SwiftUI

/// The full-screen player: the cover (or the lyrics, or what's next) over
/// the cover's own colours, then the song, the seek bar, the controls,
/// the volume, and lyrics / AirPlay / queue.
struct NowPlayingView: View {
    @Environment(Player.self) private var player
    @Environment(Look.self) private var look
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    enum Pane { case cover, lyrics, queue }
    @State private var pane: Pane = .cover
    @State private var scrubbing: Double?
    @State private var addTo: Track?
    @State private var artist: String?
    /// How far the player has been pulled down (it follows your finger).
    @State private var drag: CGFloat = 0

    var body: some View {
        let t = player.current
        GeometryReader { g in
            VStack(spacing: 0) {
                Capsule()
                    .fill(.white.opacity(0.4))
                    .frame(width: 38, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    .contentShape(Rectangle().inset(by: -14))
                    .onTapGesture { dismiss() }

                Group {
                    switch pane {
                    case .cover:
                        VStack {
                            Spacer(minLength: 0)
                            ArtworkView(url: t?.artwork, seed: t?.album ?? t?.title ?? "", corner: 12)
                                .frame(width: g.size.width - 56)
                                .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
                                .scaleEffect(player.playing || !look.prefs.pausedArtworkShrinks ? 1 : 0.86)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: player.playing)
                            Spacer(minLength: 0)
                        }
                    case .lyrics:
                        LyricsPane()
                    case .queue:
                        QueuePane()
                    }
                }
                .frame(maxHeight: .infinity)
                .transition(.opacity)

                // The song: title, artist (tap for more of theirs), like, more.
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t?.title ?? "Not Playing")
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                        Button {
                            if let t { artist = t.artist }
                        } label: {
                            Text(t?.artist ?? "")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                    if let t {
                        Button { library.toggleLike(t) } label: {
                            Image(systemName: library.isLiked(t) ? "heart.fill" : "heart")
                                .font(.title2)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.plain)
                        Menu {
                            TrackMenu(track: t, addTo: $addTo)
                            Button { artist = t.artist } label: { Label("More by \(t.artist)", systemImage: "music.mic") }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.title2)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 22)

                Scrubber(scrubbing: $scrubbing)
                    .padding(.top, 20)

                if let e = player.error {
                    Text(e).font(.footnote).foregroundStyle(.white.opacity(0.7)).padding(.top, 2)
                }

                // Back, play / pause, forward.
                HStack(spacing: 0) {
                    control("backward.fill", size: 28) { player.previous() }
                    control(player.playing ? "pause.fill" : "play.fill", size: 44) { player.toggle() }
                    control("forward.fill", size: 28) { player.next() }
                }
                .padding(.vertical, 18)

                // Volume, with a speaker on each side.
                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill").font(.footnote)
                    VolumeSlider().frame(height: 30)
                    Image(systemName: "speaker.wave.3.fill").font(.footnote)
                }
                .foregroundStyle(.white.opacity(0.6))

                // Lyrics, AirPlay, what's next.
                HStack {
                    paneButton(.lyrics, "quote.bubble")
                    Spacer()
                    RoutePicker().frame(width: 30, height: 30)
                    Spacer()
                    paneButton(.queue, "list.bullet")
                }
                .padding(.horizontal, 36)
                .padding(.top, 14)
                .padding(.bottom, 10)
            }
            .padding(.horizontal, 28)
            .foregroundStyle(.white)
            .fontWeight(look.prefs.iconWeight.weight)
        }
        .background { CoverBackdrop(image: player.artworkImage).ignoresSafeArea() }
        // Rounded only while pulled down; the mask reaches past the screen's
        // edges, so the background still fills the very top.
        .mask { RoundedRectangle(cornerRadius: drag > 0 ? 36 : 0, style: .continuous).ignoresSafeArea() }
        .offset(y: drag)
        .gesture(DragGesture(minimumDistance: 12)
            .onChanged { v in drag = max(0, v.translation.height) }
            .onEnded { v in
                if v.translation.height > 150 || v.predictedEndTranslation.height > 420 {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { drag = 0 }
                }
            })
        .presentationBackground(.clear)
        .preferredColorScheme(.dark)
        .tint(look.palette.accent)
        .sheet(item: $addTo) { t in AddToPlaylistSheet(tracks: [t]) }
        .sheet(item: Binding(get: { artist.map { ArtistName(name: $0) } }, set: { artist = $0?.name })) { a in
            ArtistSheet(artist: a.name)
        }
        .tapFeedback(look, trigger: player.playing)
        .onAppear {
            if DemoScreen.current == .lyrics { pane = .lyrics }
        }
    }

    private func control(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .contentTransition(.symbolEffect(.replace))
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
    }

    private func paneButton(_ p: Pane, _ symbol: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { pane = pane == p ? .cover : p }
        } label: {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(pane == p ? .white : .white.opacity(0.55))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
    }
}

private struct ArtistName: Identifiable {
    var name: String
    var id: String { name }
}

/// The cover, blurred, behind the player. Clipped to the screen, so none of
/// its colour is left glowing when the player slides away.
private struct CoverBackdrop: View {
    @Environment(Look.self) private var look
    var image: UIImage?
    var body: some View {
        GeometryReader { g in
            ZStack {
                Color.black
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: g.size.width, height: g.size.height)
                        .blur(radius: 60, opaque: true)
                        .opacity(0.9)
                } else {
                    LinearGradient(colors: [look.palette.accent.opacity(0.35), look.palette.background], startPoint: .top, endPoint: .bottom)
                }
                Color.black.opacity(0.28)
            }
            .frame(width: g.size.width, height: g.size.height)
            .clipped()
        }
    }
}

/// The seek bar with the time on each side.
private struct Scrubber: View {
    @Environment(Player.self) private var player
    @Binding var scrubbing: Double?

    var body: some View {
        let d = max(player.duration, 1)
        let pos = scrubbing ?? player.position
        VStack(spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule().fill(.white.opacity(scrubbing == nil ? 0.8 : 1))
                        .frame(width: max(0, min(1, pos / d)) * g.size.width)
                }
                .frame(height: scrubbing == nil ? 7 : 11)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in scrubbing = max(0, min(1, v.location.x / g.size.width)) * d }
                    .onEnded { _ in
                        if let s = scrubbing { player.seek(to: s) }
                        scrubbing = nil
                    })
                .animation(.snappy(duration: 0.2), value: scrubbing == nil)
            }
            .frame(height: 22)
            HStack {
                Text(formatTime(pos))
                Spacer()
                Text("-" + formatTime(max(0, player.duration - pos)))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.55))
        }
    }
}

/// The system volume slider (it also moves with the buttons on the side).
private struct VolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView(frame: .zero)
        v.tintColor = .white
        return v
    }
    func updateUIView(_ v: MPVolumeView, context: Context) {}
}

/// AirPlay and Bluetooth outputs.
private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = UIColor.white.withAlphaComponent(0.55)
        v.activeTintColor = .white
        return v
    }
    func updateUIView(_ v: AVRoutePickerView, context: Context) {}
}

/// The lyrics, the current line bright; tap a line to go there.
private struct LyricsPane: View {
    @Environment(Player.self) private var player
    @Environment(Look.self) private var look
    @State private var lines: [LyricLine]?
    @State private var loading = false

    var body: some View {
        let t = player.current
        Group {
            if loading {
                ProgressView().tint(.white)
            } else if let lines, !lines.isEmpty {
                let timed = lines.first?.time != nil
                let now = timed ? (lines.lastIndex { ($0.time ?? 0) <= player.position + 0.25 } ?? -1) : -1
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(lines) { l in
                                Text(l.text.isEmpty ? "♪" : l.text)
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(.white.opacity(!timed || l.id == now ? 1 : 0.35))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(l.id)
                                    .onTapGesture { if let s = l.time { player.seek(to: s) } }
                                    .animation(.easeOut(duration: 0.25), value: now)
                            }
                        }
                        .padding(.vertical, 40)
                    }
                    .scrollIndicators(.hidden)
                    .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom))
                    .onChange(of: now) { _, n in
                        if n >= 0 { withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(n, anchor: .center) } }
                    }
                    .onAppear { if now >= 0 { proxy.scrollTo(now, anchor: .center) } }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "quote.bubble").font(.largeTitle).foregroundStyle(.white.opacity(0.5))
                    Text(look.prefs.lyricsOnline ? "No lyrics found for this song" : "Finding lyrics online is off (Settings, Playback)")
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: t?.id) {
            guard let t, look.prefs.lyricsOnline else { lines = nil; return }
            loading = true
            lines = await Lyrics.fetch(t)
            loading = false
        }
    }
}

/// What plays next (tap one to play it now), with shuffle and repeat.
private struct QueuePane: View {
    @Environment(Player.self) private var player
    @Environment(Look.self) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Playing Next").font(.headline)
                Spacer()
                Button { player.setShuffle(!player.shuffle) } label: {
                    Image(systemName: "shuffle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(player.shuffle ? Color.black : .white)
                        .frame(width: 36, height: 30)
                        .background(player.shuffle ? Color.white : Color.white.opacity(0.15), in: Capsule())
                }
                Button { player.cycleRepeat() } label: {
                    Image(systemName: player.repeatMode.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(player.repeatMode != .off ? Color.black : .white)
                        .frame(width: 36, height: 30)
                        .background(player.repeatMode != .off ? Color.white : Color.white.opacity(0.15), in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            if player.upNext.isEmpty {
                Text("Nothing else is lined up.").foregroundStyle(.white.opacity(0.55))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(player.upNext.enumerated()), id: \.offset) { k, t in
                            Button {
                                player.jump(to: player.index + 1 + k)
                            } label: {
                                HStack(spacing: 12) {
                                    ArtworkView(url: t.artwork, seed: t.album ?? t.title, corner: 6).frame(width: 44, height: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t.title).lineLimit(1)
                                        Text(t.artist).font(.subheadline).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

/// More songs by an artist, from your playlists, liked and downloaded songs.
struct ArtistSheet: View {
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player
    @Environment(Look.self) private var look
    @Environment(\.dismiss) private var dismiss
    var artist: String
    @State private var addTo: Track?

    var body: some View {
        let songs = library.songs(by: artist)
        NavigationStack {
            List {
                if songs.isEmpty {
                    Text("Nothing else by \(artist) in your music yet.").foregroundStyle(look.palette.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(Array(songs.enumerated()), id: \.element.id) { k, t in
                    Button {
                        player.play(songs, at: k)
                        dismiss()
                    } label: {
                        SongRow(track: t, number: nil)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .contextMenu { TrackMenu(track: t, addTo: $addTo) }
                }
            }
            .listStyle(.plain)
            .themed(look)
            .navigationTitle(artist)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { player.play(songs, shuffled: true); dismiss() } label: { Image(systemName: "shuffle") }
                        .disabled(songs.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(item: $addTo) { t in AddToPlaylistSheet(tracks: [t]) }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(look.palette.dark ? .dark : .light)
    }
}
