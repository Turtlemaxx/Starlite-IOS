import SwiftUI

/// A number from a string that's the same every launch.
func stableSeed(_ s: String) -> Int {
    s.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) } & 0x7fff_ffff
}

/// A cover: the picture, or (without one) a symbol on the theme's colours.
struct ArtworkView: View {
    @Environment(Look.self) private var look
    var url: URL?
    var seed: String
    var symbol: String = "music.note"
    var corner: CGFloat = 10

    var body: some View {
        GeometryReader { g in
            ZStack {
                placeholder(g.size)
                if let url {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                        }
                    }
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func placeholder(_ size: CGSize) -> some View {
        let p = look.palette
        return ZStack {
            p.panel
            p.accent.opacity(p.dark ? 0.10 : 0.08)
            Image(systemName: symbol)
                .font(.system(size: max(10, size.width * 0.32)))
                .fontWeight(look.prefs.iconWeight.weight)
                .foregroundStyle(p.accent.opacity(0.85))
        }
    }
}

extension View {
    /// A panel in the chosen style: Liquid Glass, frosted or solid.
    @ViewBuilder
    func panel(_ look: Look, radius: CGFloat? = nil, interactive: Bool = false) -> some View {
        let r = radius ?? CGFloat(look.prefs.corners) + 6
        switch look.prefs.style {
        case .liquid:
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: .rect(cornerRadius: r))
        case .frosted:
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: r, style: .continuous))
        case .solid:
            self.background(look.palette.panel, in: RoundedRectangle(cornerRadius: r, style: .continuous))
        }
    }

    /// The theme behind a screen, with its colours.
    func themed(_ look: Look) -> some View {
        modifier(Themed(look: look))
    }

    /// A light tap, when haptics are on.
    func tapFeedback<T: Equatable>(_ look: Look, trigger: T) -> some View {
        sensoryFeedback(.selection, trigger: trigger) { _, _ in look.prefs.haptics }
    }
}

private struct Themed: ViewModifier {
    var look: Look
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background { ThemeBackground(look: look).ignoresSafeArea() }
            .foregroundStyle(look.palette.text)
    }
}

/// The icon at the start of a Settings row: a plain symbol (or a logo).
struct RowIcon: View {
    @Environment(Look.self) private var look
    var symbol: String? = nil
    var logo: String? = nil
    var body: some View {
        Group {
            if let logo {
                Image(logo).renderingMode(.template).resizable().scaledToFit().frame(width: 20, height: 20)
            } else if let symbol {
                Image(systemName: symbol).font(.system(size: 18)).fontWeight(look.prefs.iconWeight.weight)
            }
        }
        .foregroundStyle(look.palette.accent)
        .frame(width: 28)
    }
}

extension Look {
    /// Behind a row of a grouped list: solid, or a material for the glass
    /// styles (glass on single rows lost its edge at the group's corners).
    @ViewBuilder var rowFill: some View {
        switch prefs.style {
        case .solid: palette.panel
        case .frosted: Rectangle().fill(.ultraThinMaterial)
        case .liquid: Rectangle().fill(.regularMaterial).opacity(0.85)
        }
    }
}

/// A heading over a section of a page, with "See all"-style action.
struct SectionTitle: View {
    var title: String
    var body: some View {
        Text(title)
            .font(.title2.weight(.bold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Play and Shuffle side by side, like Apple Music.
struct PlayShuffleButtons: View {
    @Environment(Look.self) private var look
    var play: () -> Void
    var shuffle: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            Button(action: play) {
                Label("Play", systemImage: "play.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(look.palette.accent)
            .foregroundStyle(look.onAccent)
            Button(action: shuffle) {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)
            .foregroundStyle(look.palette.accent)
        }
        .fontWeight(look.prefs.iconWeight.weight)
    }
}
