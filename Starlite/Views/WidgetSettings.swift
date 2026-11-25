import SwiftUI

/// Settings → Widget: everything about the home-screen widget, with a live
/// preview of it at the top.
struct WidgetSettings: View {
    @Environment(Look.self) private var look
    @Environment(Player.self) private var player
    @Environment(Library.self) private var library
    @State private var prefs = AppGroup.read(WidgetPrefs.self, "widget-prefs.json", defaults: WidgetPrefs())

    /// The preview shows what's playing (or an example).
    private var snap: WidgetSnapshot {
        guard let t = player.current else { return .sample }
        var s = WidgetSnapshot()
        s.title = t.title
        s.artist = t.artist
        s.album = t.album
        s.hasTrack = true
        s.playing = player.playing
        s.elapsed = player.position
        s.at = Date()
        s.duration = player.duration > 0 ? player.duration : t.duration
        s.liked = library.isLiked(t)
        s.upNext = player.upNext.first.map { "\($0.title) · \($0.artist)" }
        let p = look.palette
        s.themeBackground = RGBA(p.background)
        s.themeText = RGBA(p.text)
        s.themeAccent = RGBA(p.accent)
        s.coverColor = look.coverColor.map { RGBA($0) }
        return s
    }

    var body: some View {
        Form {
            Section {
                WidgetContent(snap: snap, prefs: prefs, artwork: player.artworkImage)
                    .frame(width: 338, height: 158)
                    .background { WidgetBackdrop(snap: snap, prefs: prefs, artwork: player.artworkImage) }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
            } footer: {
                Text("To add it: touch and hold an empty spot on the home screen, tap Edit, Add Widget, and pick Starlite.")
            }

            Section("Layout") {
                chips(WidgetLayout.allCases, selected: prefs.layout, label: \.label) { prefs.layout = $0 }
            }
            .groupBackground(look)

            Section {
                if prefs.layout != .cover {
                    Picker("Background", selection: $prefs.background) {
                        ForEach(WidgetBackground.allCases) { Text($0.label).tag($0) }
                    }
                }
                if prefs.background == .color || prefs.background == .gradient, prefs.layout != .cover {
                    ColorPicker(prefs.background == .gradient ? "From" : "Colour", selection: colorBinding(\.color1), supportsOpacity: false)
                }
                if prefs.background == .gradient, prefs.layout != .cover {
                    ColorPicker("To", selection: colorBinding(\.color2), supportsOpacity: false)
                }
                if prefs.layout == .cover || prefs.background == .cover || prefs.background == .glass {
                    slider("Darken", value: $prefs.dim, range: 0...0.8, step: 0.05, text: "\(Int(prefs.dim * 100)) %")
                }
            } header: {
                Text("Background")
            }
            .groupBackground(look)

            Section("Colours") {
                Toggle("Text in the Theme's Colour", isOn: $prefs.themeText)
                if !prefs.themeText {
                    ColorPicker("Text", selection: colorBinding(\.textColor), supportsOpacity: false)
                }
                Picker("Accent", selection: $prefs.accentFrom) {
                    ForEach(WidgetAccent.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if prefs.accentFrom == .custom {
                    ColorPicker("Accent Colour", selection: colorBinding(\.accent), supportsOpacity: false)
                }
            }
            .groupBackground(look)

            Section {
                Toggle("Cover", isOn: $prefs.showArtwork)
                Toggle("Song Name", isOn: $prefs.showTitle)
                Toggle("Artist", isOn: $prefs.showArtist)
                Toggle("Album", isOn: $prefs.showAlbum)
                Toggle("Up Next", isOn: $prefs.showUpNext)
                Toggle("Progress Bar", isOn: $prefs.showProgress)
                if prefs.showProgress { Toggle("Times", isOn: $prefs.showTimes) }
                Toggle("Controls", isOn: $prefs.showControls)
                if prefs.showControls {
                    Toggle("Previous", isOn: $prefs.showPrevious)
                    Toggle("Next", isOn: $prefs.showNext)
                    Toggle("Like", isOn: $prefs.showLike)
                }
                Toggle("Starlite Logo", isOn: $prefs.showLogo)
                Toggle("Playing / Paused", isOn: $prefs.showStatus)
            } header: {
                Text("What's In It")
            }
            .groupBackground(look)

            Section("Text") {
                slider("Size", value: $prefs.titleSize, range: 12...26, step: 1, text: "\(Int(prefs.titleSize)) pt")
                Picker("Weight", selection: $prefs.titleWeight) {
                    ForEach(WidgetWeight.allCases) { Text($0.label).tag($0) }
                }
                Picker("Font", selection: $prefs.font) {
                    ForEach(WidgetFont.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Centred", isOn: $prefs.centeredText)
            }
            .groupBackground(look)

            if prefs.showArtwork {
                Section("Cover") {
                    slider("Size", value: $prefs.artworkSize, range: 0.6...1.3, step: 0.05, text: "\(Int(prefs.artworkSize * 100)) %")
                    slider("Corners", value: $prefs.artworkCorner, range: 0...40, step: 1, text: "\(Int(prefs.artworkCorner)) pt")
                    Toggle("Shadow", isOn: $prefs.artworkShadow)
                }
                .groupBackground(look)
            }

            if prefs.showControls {
                Section("Controls") {
                    Picker("Style", selection: $prefs.controls) {
                        ForEach(WidgetControls.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    slider("Size", value: $prefs.controlSize, range: 0.7...1.4, step: 0.05, text: "\(Int(prefs.controlSize * 100)) %")
                }
                .groupBackground(look)
            }

            Section("Spacing") {
                if prefs.showProgress {
                    slider("Progress Bar", value: $prefs.progressHeight, range: 2...10, step: 1, text: "\(Int(prefs.progressHeight)) pt")
                }
                slider("Edges", value: $prefs.padding, range: 6...24, step: 1, text: "\(Int(prefs.padding)) pt")
            }
            .groupBackground(look)

            Section {
                Button("Reset the Widget", role: .destructive) { withAnimation { prefs = WidgetPrefs() } }
                    .disabled(prefs == WidgetPrefs())
            }
            .groupBackground(look)
        }
        .themed(look)
        .tint(look.controlTint)
        .navigationTitle("Widget")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: prefs) { _, p in
            AppGroup.write(p, "widget-prefs.json")
            WidgetServer.shared.update(prefs: p)
            AppGroup.reloadWidgets()
        }
    }

    private func colorBinding(_ key: WritableKeyPath<WidgetPrefs, RGBA>) -> Binding<Color> {
        Binding(get: { prefs[keyPath: key].color }, set: { prefs[keyPath: key] = RGBA($0) })
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(text).monospacedDigit().foregroundStyle(look.palette.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private func chips<T: Hashable>(_ all: [T], selected: T, label: KeyPath<T, String>, pick: @escaping (T) -> Void) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(all, id: \.self) { v in
                    Button(v[keyPath: label]) { withAnimation(.snappy) { pick(v) } }
                        .buttonStyle(.bordered)
                        .tint(v == selected ? look.controlTint : look.palette.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }
}
