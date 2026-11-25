import AppIntents
import SwiftUI
import UIKit

/// The Starlite widget (2×4, "medium"): what's playing, laid out and styled
/// the way Settings → Widget says. The app draws the same view as a preview.
struct WidgetContent: View {
    var snap: WidgetSnapshot
    var prefs: WidgetPrefs
    var artwork: UIImage?

    private var text: Color { prefs.themeText ? snap.themeText.color : prefs.textColor.color }
    private var secondary: Color { text.opacity(0.68) }
    private var accent: Color {
        switch prefs.accentFrom {
        case .theme: snap.themeAccent.color
        case .cover: (snap.coverColor ?? snap.themeAccent).color
        case .custom: prefs.accent.color
        }
    }
    private var align: HorizontalAlignment { prefs.centeredText ? .center : .leading }

    var body: some View {
        Group {
            switch prefs.layout {
            case .classic: classic
            case .cover: coverLayout
            case .bigArt: bigArt
            case .minimal: minimal
            case .centered: centered
            }
        }
        .foregroundStyle(text)
        .fontDesign(prefs.font.design)
    }

    // MARK: Layouts

    private var classic: some View {
        HStack(spacing: 14) {
            if prefs.showArtwork { cover(side: 118 * prefs.artworkSize) }
            VStack(alignment: align, spacing: 4) {
                topRow
                info
                Spacer(minLength: 2)
                if prefs.showProgress { progress }
                if prefs.showControls { controls }
            }
            .frame(maxWidth: .infinity, alignment: prefs.centeredText ? .center : .leading)
        }
        .padding(prefs.padding)
    }

    private var coverLayout: some View {
        VStack(alignment: align, spacing: 4) {
            topRow
            Spacer(minLength: 2)
            info
            if prefs.showProgress { progress.padding(.top, 4) }
            if prefs.showControls { controls }
        }
        .frame(maxWidth: .infinity, alignment: prefs.centeredText ? .center : .leading)
        .padding(prefs.padding)
    }

    private var bigArt: some View {
        HStack(spacing: 0) {
            if prefs.showArtwork {
                art
                    .scaledToFill()
                    .frame(width: 158 * prefs.artworkSize)
                    .frame(maxHeight: .infinity)
                    .clipped()
            }
            VStack(alignment: align, spacing: 4) {
                topRow
                info
                Spacer(minLength: 2)
                if prefs.showProgress { progress }
                if prefs.showControls { controls }
            }
            .frame(maxWidth: .infinity, alignment: prefs.centeredText ? .center : .leading)
            .padding(prefs.padding)
        }
    }

    private var minimal: some View {
        VStack(alignment: align, spacing: 6) {
            topRow
            Spacer(minLength: 0)
            info
            if prefs.showProgress { progress.padding(.top, 6) }
        }
        .frame(maxWidth: .infinity, alignment: prefs.centeredText ? .center : .leading)
        .padding(prefs.padding + 4)
    }

    private var centered: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                if prefs.showArtwork { cover(side: 64 * prefs.artworkSize) }
                VStack(alignment: .leading, spacing: 2) { info }
                Spacer(minLength: 0)
                if prefs.showLogo { logo }
            }
            Spacer(minLength: 0)
            if prefs.showProgress { progress }
            if prefs.showControls { controls.frame(maxWidth: .infinity) }
        }
        .padding(prefs.padding)
    }

    // MARK: Pieces

    @ViewBuilder private var topRow: some View {
        if prefs.showLogo || prefs.showStatus {
            HStack(spacing: 6) {
                if prefs.showLogo { logo }
                if prefs.showStatus {
                    Text(snap.playing ? "Playing" : (snap.hasTrack ? "Paused" : "Starlite"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(secondary)
                }
                if !prefs.centeredText { Spacer(minLength: 0) }
            }
        }
    }

    private var logo: some View {
        Image("Logo")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: 16, height: 16)
            .foregroundStyle(accent)
    }

    @ViewBuilder private var info: some View {
        if prefs.showTitle {
            Text(snap.title)
                .font(.system(size: prefs.titleSize, weight: prefs.titleWeight.weight))
                .lineLimit(prefs.layout == .minimal ? 2 : 1)
                .multilineTextAlignment(prefs.centeredText ? .center : .leading)
        }
        if prefs.showArtist {
            Text(snap.artist).font(.system(size: prefs.titleSize * 0.8)).foregroundStyle(secondary).lineLimit(1)
        }
        if prefs.showAlbum, let a = snap.album {
            Text(a).font(.system(size: prefs.titleSize * 0.72)).foregroundStyle(secondary.opacity(0.85)).lineLimit(1)
        }
        if prefs.showUpNext, let n = snap.upNext {
            Text("Next: \(n)").font(.caption2).foregroundStyle(secondary).lineLimit(1).padding(.top, 2)
        }
    }

    private var art: Image {
        if let artwork { return Image(uiImage: artwork).resizable() }
        return Image(systemName: "music.note").resizable()
    }

    private func cover(side: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: prefs.artworkCorner, style: .continuous).fill(accent.opacity(0.18))
            if let artwork {
                Image(uiImage: artwork).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(.system(size: side * 0.34)).foregroundStyle(accent)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: prefs.artworkCorner, style: .continuous))
        .shadow(color: .black.opacity(prefs.artworkShadow ? 0.3 : 0), radius: 8, y: 4)
    }

    /// Moves by itself while playing (no updates needed).
    @ViewBuilder private var progress: some View {
        VStack(spacing: 3) {
            Group {
                if snap.playing && snap.duration > 0 {
                    ProgressView(timerInterval: snap.startDate...snap.endDate, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                } else {
                    ProgressView(value: snap.duration > 0 ? min(1, snap.elapsed / snap.duration) : 0)
                }
            }
            .progressViewStyle(.linear)
            .tint(accent)
            .scaleEffect(x: 1, y: max(0.5, prefs.progressHeight / 4), anchor: .center)
            if prefs.showTimes {
                HStack {
                    if snap.playing && snap.duration > 0 {
                        Text(timerInterval: snap.startDate...snap.endDate, countsDown: false)
                        Spacer()
                        Text(timerInterval: snap.startDate...snap.endDate, countsDown: true)
                    } else {
                        Text(clock(snap.elapsed))
                        Spacer()
                        Text(clock(max(0, snap.duration - snap.elapsed)))
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(secondary)
            }
        }
    }

    private func clock(_ s: Double) -> String {
        let t = Int(s.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    private var controls: some View {
        HStack(spacing: 18 * prefs.controlSize) {
            if prefs.showLike {
                control(LikeTrackIntent(), snap.liked ? "heart.fill" : "heart", 16)
            }
            if prefs.showPrevious {
                control(PreviousTrackIntent(), "backward.fill", 18)
            }
            control(TogglePlaybackIntent(), snap.playing ? "pause.fill" : "play.fill", 24, main: true)
            if prefs.showNext {
                control(NextTrackIntent(), "forward.fill", 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: prefs.centeredText || prefs.layout == .centered ? .center : .leading)
        .padding(.top, 2)
    }

    private func control<I: AppIntent>(_ intent: I, _ symbol: String, _ size: CGFloat, main: Bool = false) -> some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: size * prefs.controlSize))
                .foregroundStyle(prefs.controls == .filled && main ? Color.black.opacity(0.85) : (main ? text : text.opacity(0.85)))
                .frame(width: (main ? 40 : 32) * prefs.controlSize, height: (main ? 40 : 32) * prefs.controlSize)
                .background {
                    switch prefs.controls {
                    case .plain: Color.clear
                    case .circles: Circle().fill(text.opacity(0.14))
                    case .filled: Circle().fill(main ? accent : text.opacity(0.14))
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

/// What's behind the widget.
struct WidgetBackdrop: View {
    var snap: WidgetSnapshot
    var prefs: WidgetPrefs
    var artwork: UIImage?

    var body: some View {
        ZStack {
            switch effective {
            case .cover:
                if let artwork {
                    Image(uiImage: artwork).resizable().scaledToFill().blur(radius: 30).scaleEffect(1.3)
                } else {
                    snap.themeBackground.color
                }
            case .theme:
                snap.themeBackground.color
            case .color:
                prefs.color1.color
            case .gradient:
                LinearGradient(colors: [prefs.color1.color, prefs.color2.color], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .glass:
                let c = (snap.coverColor ?? snap.themeAccent).color
                LinearGradient(colors: [c.opacity(0.9), c.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .background(Color.black)
            }
            if prefs.layout == .cover || effective == .cover || effective == .glass {
                Color.black.opacity(prefs.dim)
            }
        }
    }

    /// "Cover Behind" always has the cover behind it.
    private var effective: WidgetBackground {
        prefs.layout == .cover ? .cover : prefs.background
    }
}
