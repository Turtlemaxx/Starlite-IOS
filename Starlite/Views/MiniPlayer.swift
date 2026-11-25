import SwiftUI

/// The song on the tab bar's glass (Apple Music style); tap for the full player.
struct MiniPlayer: View {
    @Environment(Player.self) private var player
    @Environment(Look.self) private var look
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    var open: () -> Void

    var body: some View {
        let t = player.current
        HStack(spacing: 11) {
            ArtworkView(url: t?.artwork, seed: t?.title ?? "none", symbol: t == nil ? "music.note" : "music.note", corner: 6)
                .frame(width: 32, height: 32)
                .opacity(t == nil ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 0) {
                Text(t?.title ?? "Not Playing")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let t, placement != .inline {
                    Text(t.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                player.toggle()
            } label: {
                Image(systemName: player.playing ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 34, height: 34)
            }
            .disabled(t == nil)
            if placement != .inline {
                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .frame(width: 34, height: 34)
                }
                .disabled(player.upNext.isEmpty && player.repeatMode != .all)
            }
        }
        .fontWeight(look.prefs.iconWeight.weight)
        .foregroundStyle(look.palette.text)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            if t != nil { open() }
        }
        .tapFeedback(look, trigger: player.playing)
    }
}
