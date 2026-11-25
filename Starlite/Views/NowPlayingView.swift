import AVKit
import MediaPlayer
import SwiftUI

/// The full-screen player: big cover over its own colours, the bar to seek,
/// the controls, volume, AirPlay and what's up next.
struct NowPlayingView: View {
    @Environment(Player.self) private var player
    @Environment(Look.self) private var look
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var showQueue = false
    @State private var scrubbing: Double?
    @State private var addTo: Track?

    var body: some View {
        let t = player.current
        GeometryReader { g in
            VStack(spacing: 0) {
                Capsule()
                    .fill(.white.opacity(0.35))
                    .frame(width: 40, height: 5)
                    .padding(.top, 8)
                    .onTapGesture { dismiss() }

                if showQueue {
                    QueueList()
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    Spacer(minLength: 12)
                    ArtworkView(url: t?.artwork, seed: t?.title ?? "none", corner: 14)
                        .frame(width: g.size.width - 48)
                        .shadow(color: .black.opacity(0.35), radius: 26, y: 14)
                        .scaleEffect(player.playing || !look.prefs.pausedArtworkShrinks ? 1 : 0.84)
                        .animation(.spring(response: 0.45, dampingFraction: 0.72), value: player.playing)
                    Spacer(minLength: 12)
                }

                // Title, artist, like.
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t?.title ?? "Not Playing").font(.title3.weight(.bold)).lineLimit(1)
                        Text(t?.artist ?? "").font(.title3).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                    }
                    Spacer()
                    if let t {
                        Button {
                            library.toggleLike(t)
                        } label: {
                            Image(systemName: library.isLiked(t) ? "heart.fill" : "heart")
                                .font(.title3)
                                .contentTransition(.symbolEffect(.replace))
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        Menu {
                            TrackMenu(track: t, addTo: $addTo)
                        } label: {
                            Image(systemName: "ellipsis").font(.title3).frame(width: 40, height: 40)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                    }
                }
                .padding(.top, 8)

                Scrubber(scrubbing: $scrubbing)
                    .padding(.top, 18)

                if let e = player.error {
                    Text(e).font(.footnote).foregroundStyle(.white.opacity(0.75)).padding(.top, 4)
                }

                // Controls.
                HStack {
                    Spacer()
                    Button { player.previous() } label: { Image(systemName: "backward.fill").font(.system(size: 30)) }
                    Spacer()
                    Button { player.toggle() } label: {
                        Image(systemName: player.playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 46))
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 70, height: 70)
                    }
                    Spacer()
                    Button { player.next() } label: { Image(systemName: "forward.fill").font(.system(size: 30)) }
                    Spacer()
                }
                .padding(.vertical, 14)

                VolumeSlider()
                    .frame(height: 34)

                // Shuffle, AirPlay, repeat, queue.
                HStack {
                    Button { player.setShuffle(!player.shuffle) } label: {
                        Image(systemName: "shuffle").font(.title3).foregroundStyle(player.shuffle ? look.palette.accent : .white.opacity(0.7))
                    }
                    Spacer()
                    RoutePicker().frame(width: 34, height: 34)
                    Spacer()
                    Button { player.cycleRepeat() } label: {
                        Image(systemName: player.repeatMode.symbol).font(.title3).foregroundStyle(player.repeatMode == .off ? .white.opacity(0.7) : look.palette.accent)
                    }
                    Spacer()
                    Button { withAnimation(.snappy) { showQueue.toggle() } } label: {
                        Image(systemName: "list.bullet").font(.title3).foregroundStyle(showQueue ? look.palette.accent : .white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 10)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
            .foregroundStyle(.white)
            .fontWeight(look.prefs.iconWeight.weight)
        }
        .background { CoverBackdrop(image: player.artworkImage, seed: t?.title ?? "none").ignoresSafeArea() }
        .preferredColorScheme(.dark)
        .tint(look.palette.accent)
        .sheet(item: $addTo) { t in AddToPlaylistSheet(tracks: [t]) }
        .tapFeedback(look, trigger: player.playing)
        .gesture(DragGesture().onEnded { v in if v.translation.height > 120 { dismiss() } })
    }
}

/// The cover, blurred and darkened, behind the full-screen player.
private struct CoverBackdrop: View {
    var image: UIImage?
    var seed: String
    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill().blur(radius: 70).scaleEffect(1.4)
            } else {
                let h = Double(stableSeed(seed) % 360) / 360
                LinearGradient(colors: [Color(hue: h, saturation: 0.6, brightness: 0.55), Color(hue: h + 0.1 > 1 ? h - 0.9 : h + 0.1, saturation: 0.7, brightness: 0.2)], startPoint: .top, endPoint: .bottom)
            }
            Color.black.opacity(0.32)
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
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white.opacity(scrubbing == nil ? 0.85 : 1))
                        .frame(width: max(0, min(1, pos / d)) * g.size.width)
                }
                .frame(height: scrubbing == nil ? 6 : 10)
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
            .foregroundStyle(.white.opacity(0.6))
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
        v.tintColor = UIColor.white.withAlphaComponent(0.7)
        v.activeTintColor = .white
        return v
    }
    func updateUIView(_ v: AVRoutePickerView, context: Context) {}
}

/// What plays next; tap one to play it now.
private struct QueueList: View {
    @Environment(Player.self) private var player
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Playing Next").font(.headline).padding(.top, 16)
            if player.upNext.isEmpty {
                Text("Nothing else is lined up.").foregroundStyle(.white.opacity(0.6))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(player.upNext.enumerated()), id: \.offset) { k, t in
                            Button {
                                player.jump(to: player.index + 1 + k)
                            } label: {
                                HStack(spacing: 12) {
                                    ArtworkView(url: t.artwork, seed: t.title, corner: 6).frame(width: 44, height: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t.title).lineLimit(1)
                                        Text(t.artist).font(.subheadline).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxHeight: .infinity)
    }
}
