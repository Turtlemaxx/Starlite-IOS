import PhotosUI
import SwiftUI

/// Settings: the same categories as Starlite on the computer, as grouped rows.
struct SettingsTab: View {
    @Environment(Look.self) private var look
    @Environment(Services.self) private var services
    @Environment(LastFM.self) private var lastfm
    @State private var path = NavigationPath()

    enum Page: Hashable { case appearance, layout, playback, sound, equalizer, lastfm, general }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image("Logo").resizable().scaledToFit().frame(width: 46, height: 46)
                            .colorMultiply(look.palette.text)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Starlite").font(.title3.weight(.bold))
                            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").font(.subheadline).foregroundStyle(look.palette.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .groupBackground(look)

                Section {
                    row(.appearance, "Appearance", symbol: "paintpalette")
                    row(.layout, "Layout", symbol: "rectangle.3.group")
                }
                .groupBackground(look)

                Section("Sound") {
                    row(.playback, "Playback", symbol: "play.circle")
                    row(.sound, "Sound", symbol: "slider.horizontal.3")
                }
                .groupBackground(look)

                Section("Services") {
                    ForEach(ServerKind.allCases) { s in
                        NavigationLink(value: s) {
                            HStack(spacing: 12) {
                                RowIcon(logo: s.logo)
                                Text(s.name)
                                Spacer()
                                Text(services.isConnected(s) ? "Connected" : "Not set up").foregroundStyle(look.palette.secondary)
                            }
                        }
                    }
                    NavigationLink(value: Page.lastfm) {
                        HStack(spacing: 12) {
                            RowIcon(logo: "LogoLastfm")
                            Text("Last.fm")
                            Spacer()
                            Text(lastfm.login != nil ? "Connected" : "Not set up").foregroundStyle(look.palette.secondary)
                        }
                    }
                }
                .groupBackground(look)

                Section {
                    row(.general, "General", symbol: "gearshape")
                }
                .groupBackground(look)
            }
            .themed(look)
            .tint(look.controlTint)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(look.prefs.bigTitles ? .large : .inline)
            .navigationDestination(for: Page.self) { p in
                switch p {
                case .appearance: AppearanceSettings()
                case .layout: LayoutSettings()
                case .playback: PlaybackSettings()
                case .sound: SoundSettings()
                case .equalizer: EqualizerSettings()
                case .lastfm: LastFMSettings()
                case .general: GeneralSettings()
                }
            }
            .navigationDestination(for: ServerKind.self) { ConnectView(server: $0) }
            .onAppear {
                if path.isEmpty {
                    if DemoScreen.current == .appearance { path.append(Page.appearance) }
                    if DemoScreen.current == .layout { path.append(Page.layout) }
                    if DemoScreen.current == .sound { path.append(Page.sound) }
                }
            }
        }
    }

    private func row(_ p: Page, _ title: String, symbol: String) -> some View {
        NavigationLink(value: p) {
            HStack(spacing: 12) {
                RowIcon(symbol: symbol)
                Text(title)
            }
        }
    }
}

/// What's behind each group of rows (solid, or a material for the glass looks).
private struct GroupBackground: ViewModifier {
    var look: Look
    func body(content: Content) -> some View {
        content.listRowBackground(look.rowFill)
    }
}

extension View {
    func groupBackground(_ look: Look) -> some View { modifier(GroupBackground(look: look)) }
}

// MARK: - Appearance

struct AppearanceSettings: View {
    @Environment(Look.self) private var look
    @State private var naming = false
    @State private var lookName = ""
    @State private var photo: PhotosPickerItem?

    var body: some View {
        @Bindable var look = look
        Form {
            Section("Theme") {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(ThemeKind.allCases) { t in
                            ThemeCard(theme: t, selected: look.prefs.theme == t) {
                                withAnimation(.easeInOut(duration: 0.25)) { look.prefs.theme = t }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.hidden)
                if look.prefs.theme == .custom {
                    ColorPicker("Background", selection: Binding(get: { look.prefs.customBackground.color }, set: { look.prefs.customBackground = RGBA($0) }), supportsOpacity: false)
                    ColorPicker("Accent", selection: Binding(get: { look.prefs.customAccent.color }, set: { look.prefs.customAccent = RGBA($0) }), supportsOpacity: false)
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label(look.prefs.customPicture == nil ? "Background Picture…" : "Change Picture…", systemImage: "photo")
                    }
                    if look.prefs.customPicture != nil {
                        Button("Remove Picture", role: .destructive) { look.prefs.customPicture = nil }
                    }
                }
            }
            .groupBackground(look)

            Section {
                ForEach(look.saved) { s in
                    Button {
                        withAnimation { look.prefs = look.prefs.lookOnly(from: s.look) }
                    } label: {
                        HStack {
                            Circle().fill(Look.palette(s.look, cover: nil).accent).frame(width: 14, height: 14)
                            Text(s.name).foregroundStyle(look.palette.text)
                            Spacer()
                            if sameLook(s.look) {
                                Text("In use").foregroundStyle(look.palette.secondary)
                            }
                        }
                    }
                }
                .onDelete { look.saved.remove(atOffsets: $0) }
                Button { lookName = ""; naming = true } label: { Label("Save the Current Look…", systemImage: "plus") }
            } header: {
                Text("Saved Looks")
            } footer: {
                Text("A look keeps the theme, colours, panels, text, icons and motion.")
            }
            .groupBackground(look)

            Section("Panels") {
                Picker("Style", selection: $look.prefs.style) {
                    ForEach(PanelStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading) {
                    HStack { Text("Corners"); Spacer(); Text("\(Int(look.prefs.corners)) pt").foregroundStyle(look.palette.secondary) }
                    Slider(value: $look.prefs.corners, in: 0...32, step: 1)
                }
            }
            .groupBackground(look)

            Section {
                Picker("Accent", selection: $look.prefs.accentFrom) {
                    ForEach(AccentFrom.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if look.prefs.accentFrom == .custom {
                    ColorPicker("Accent Colour", selection: Binding(get: { look.prefs.accent.color }, set: { look.prefs.accent = RGBA($0) }), supportsOpacity: false)
                }
                Toggle("Background From the Cover", isOn: $look.prefs.coverBackground)
            } header: {
                Text("Colour")
            } footer: {
                Text("Cover: the playing song's colours.")
            }
            .groupBackground(look)

            Section("Text and Icons") {
                Picker("Text Size", selection: $look.prefs.textSize) {
                    ForEach(TextSize.allCases) { Text($0.label).tag($0) }
                }
                Picker("Icon Weight", selection: $look.prefs.iconWeight) {
                    ForEach(IconWeight.allCases) { Text($0.label).tag($0) }
                }
            }
            .groupBackground(look)

            if look.prefs.theme.animated {
                Section("Motion") {
                    VStack(alignment: .leading) {
                        HStack { Text("Speed"); Spacer(); Text(look.prefs.motionSpeed < 0.01 ? "Still" : "\(Int(look.prefs.motionSpeed * 100)) %").foregroundStyle(look.palette.secondary) }
                        Slider(value: $look.prefs.motionSpeed, in: 0...3, step: 0.05)
                    }
                    VStack(alignment: .leading) {
                        HStack { Text("Amount"); Spacer(); Text("\(Int(look.prefs.motionAmount * 100)) %").foregroundStyle(look.palette.secondary) }
                        Slider(value: $look.prefs.motionAmount, in: 0.2...2, step: 0.05)
                    }
                }
                .groupBackground(look)
            }

            Section("Player") {
                Toggle("Cover Shrinks When Paused", isOn: $look.prefs.pausedArtworkShrinks)
            }
            .groupBackground(look)
        }
        .themed(look)
        .tint(look.controlTint)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset") {
                    withAnimation {
                        var d = LookPrefs()
                        d = look.prefs.lookOnly(from: d)
                        d.rowSize = look.prefs.rowSize
                        d.showNumbers = look.prefs.showNumbers
                        d.showAlbum = look.prefs.showAlbum
                        d.showArtwork = look.prefs.showArtwork
                        d.shelf = look.prefs.shelf
                        d.shelfSize = look.prefs.shelfSize
                        d.minimizeTabBar = look.prefs.minimizeTabBar
                        d.bigTitles = look.prefs.bigTitles
                        look.prefs = d
                    }
                }
            }
        }
        .alert("Save Look", isPresented: $naming) {
            TextField("Name", text: $lookName)
            Button("Save") {
                let name = lookName.isEmpty ? "My Look" : lookName
                look.saved.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                look.saved.append(SavedLook(name: name, look: look.prefs))
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: photo) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self), UIImage(data: data) != nil else { return }
                let name = "background-\(Int(Date().timeIntervalSince1970)).jpg"
                try? data.write(to: Storage.support.appendingPathComponent(name))
                look.prefs.customPicture = name
            }
        }
    }

    /// The saved look is what's on screen (playback settings don't count).
    private func sameLook(_ l: LookPrefs) -> Bool {
        let a = look.prefs, b = l
        return a.theme == b.theme && a.style == b.style && a.accentFrom == b.accentFrom && a.accent == b.accent && a.coverBackground == b.coverBackground && a.corners == b.corners && a.textSize == b.textSize && a.iconWeight == b.iconWeight && a.motionSpeed == b.motionSpeed && a.motionAmount == b.motionAmount && a.customBackground == b.customBackground && a.customAccent == b.customAccent
    }
}

/// A small picture of a theme.
private struct ThemeCard: View {
    @Environment(Look.self) private var look
    var theme: ThemeKind
    var selected: Bool
    var action: () -> Void

    var body: some View {
        let p = look.preview(theme)
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.background)
                    decoration
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().fill(p.text.opacity(0.85)).frame(width: 38, height: 5)
                        Capsule().fill(p.text.opacity(0.3)).frame(width: 50, height: 4)
                        Capsule().fill(p.text.opacity(0.3)).frame(width: 30, height: 4)
                        Spacer()
                        HStack(spacing: 4) {
                            Circle().fill(p.accent).frame(width: 9, height: 9)
                            Capsule().fill(p.text.opacity(0.3)).frame(width: 26, height: 4)
                        }
                    }
                    .padding(10)
                }
                .frame(width: 84, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? look.palette.accent : look.palette.secondary.opacity(0.3), lineWidth: selected ? 2.5 : 1))
                Text(theme.label).font(.caption.weight(selected ? .semibold : .regular)).foregroundStyle(look.palette.text).lineLimit(1)
            }
            .frame(width: 88)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var decoration: some View {
        switch theme {
        case .stars:
            Canvas { ctx, size in
                for i in 0..<14 {
                    let x = Double((i * 37) % 80) + 2, y = Double((i * 53) % 108) + 2
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)), with: .color(.white.opacity(0.8)))
                }
            }
        case .cherry:
            Canvas { ctx, _ in
                for (x, y) in [(52.0, 30.0), (66.0, 62.0), (40.0, 80.0), (70.0, 20.0)] {
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 7, height: 4.5)), with: .color(Color(red: 1, green: 0.72, blue: 0.78).opacity(0.85)))
                }
            }
        case .bubbles:
            Canvas { ctx, _ in
                for (x, y, r) in [(54.0, 70.0, 11.0), (66.0, 34.0, 7.0), (40.0, 30.0, 5.0)] {
                    ctx.stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(Color(red: 0.66, green: 0.87, blue: 1).opacity(0.75)), lineWidth: 1)
                }
            }
        default:
            EmptyView()
        }
    }
}

// MARK: - Layout

struct LayoutSettings: View {
    @Environment(Look.self) private var look

    var body: some View {
        @Bindable var look = look
        Form {
            Section("Song Lists") {
                Picker("Row Size", selection: $look.prefs.rowSize) {
                    ForEach(RowSize.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Song Numbers", isOn: $look.prefs.showNumbers)
                Toggle("Covers", isOn: $look.prefs.showArtwork)
                Toggle("Album Names", isOn: $look.prefs.showAlbum)
            }
            .groupBackground(look)

            Section {
                Toggle("CD Shelf", isOn: $look.prefs.shelf)
                if look.prefs.shelf {
                    Picker("Size", selection: $look.prefs.shelfSize) {
                        ForEach(ShelfSize.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Playlists")
            } footer: {
                Text("Off: your playlists as a list.")
            }
            .groupBackground(look)

            Section("Navigation") {
                Toggle("Large Titles", isOn: $look.prefs.bigTitles)
                Toggle("Shrink Tab Bar While Scrolling", isOn: $look.prefs.minimizeTabBar)
            }
            .groupBackground(look)
        }
        .themed(look)
        .tint(look.controlTint)
        .navigationTitle("Layout")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Playback

struct PlaybackSettings: View {
    @Environment(Look.self) private var look

    var body: some View {
        @Bindable var look = look
        Form {
            Section {
                Picker("Streaming", selection: $look.prefs.stream) {
                    ForEach(StreamQuality.allCases) { Text($0.label).tag($0) }
                }
                Picker("Downloads", selection: $look.prefs.download) {
                    ForEach(StreamQuality.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Quality")
            } footer: {
                Text("Original plays songs as they're stored on your server. The others ask the server to convert them, which saves data on mobile networks (Navidrome needs that format set up under Settings, Transcoding). Formats iPhone can't play are always converted.")
            }
            .groupBackground(look)

            Section {
                Toggle("Find Lyrics Online", isOn: $look.prefs.lyricsOnline)
            } header: {
                Text("Lyrics")
            } footer: {
                Text("Timed lyrics for the song you're playing, from lrclib.net (the same as Starlite on the computer).")
            }
            .groupBackground(look)
        }
        .themed(look)
        .tint(look.controlTint)
        .navigationTitle("Playback")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - General

struct GeneralSettings: View {
    @Environment(Look.self) private var look
    @Environment(Library.self) private var library
    @State private var used: Int64 = 0
    @State private var confirmDelete = false

    var body: some View {
        @Bindable var look = look
        Form {
            Section("Feel") {
                Toggle("Haptics", isOn: $look.prefs.haptics)
            }
            .groupBackground(look)

            Section {
                LabeledContent("Songs on This iPhone", value: ByteCountFormatter.string(fromByteCount: used, countStyle: .file))
                Button("Delete Downloaded Songs", role: .destructive) { confirmDelete = true }
                    .disabled(library.downloadInfo.isEmpty)
            } header: {
                Text("Storage")
            } footer: {
                Text("Music you add in the Files app (On My iPhone, Starlite) isn't deleted here.")
            }
            .groupBackground(look)

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                Link(destination: URL(string: "https://github.com/Turtlemaxx/Starlite-IOS")!) {
                    Label("Starlite on GitHub", systemImage: "arrow.up.right.square")
                }
            }
            .groupBackground(look)
        }
        .themed(look)
        .tint(look.controlTint)
        .navigationTitle("General")
        .navigationBarTitleDisplayMode(.inline)
        .task { used = library.usedBytes() }
        .confirmationDialog("Delete all downloaded songs?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                library.deleteAllDownloads()
                used = library.usedBytes()
            }
        } message: {
            Text("You can download them again from your server.")
        }
    }
}

// MARK: - Sound

/// Speed, bass, clarity, balance, mono, and the way to the equalizer.
struct SoundSettings: View {
    @Environment(Look.self) private var look
    @Environment(Sound.self) private var sound

    var body: some View {
        @Bindable var sound = sound
        Form {
            Section {
                sliderRow("Speed", value: $sound.prefs.speed, range: 0.5...2, step: 0.05, text: String(format: "%.2f×", sound.prefs.speed))
                Toggle("Keep the Pitch", isOn: $sound.prefs.keepPitch)
            } header: {
                Text("Speed")
            } footer: {
                Text("Off: faster songs sound higher, like a record spun faster.")
            }
            .groupBackground(look)

            Section("Tone") {
                sliderRow("Bass", value: $sound.prefs.bass, range: -12...12, step: 0.5, text: db(sound.prefs.bass))
                sliderRow("Clarity", value: $sound.prefs.clarity, range: -12...12, step: 0.5, text: db(sound.prefs.clarity))
                NavigationLink(value: SettingsTab.Page.equalizer) {
                    HStack {
                        Text("Equalizer")
                        Spacer()
                        Text(sound.prefs.eqOn ? "On" : "Off").foregroundStyle(look.palette.secondary)
                    }
                }
            }
            .groupBackground(look)

            Section {
                sliderRow("Balance", value: $sound.prefs.balance, range: -1...1, step: 0.05, text: balance(sound.prefs.balance))
                Toggle("Mono", isOn: $sound.prefs.mono)
            } header: {
                Text("Output")
            } footer: {
                Text("For your own files and server songs. Everything here is off by default: then songs play exactly as they are.")
            }
            .groupBackground(look)

            Section {
                Button("Reset Sound", role: .destructive) { withAnimation { sound.prefs = SoundPrefs() } }
                    .disabled(sound.prefs == SoundPrefs())
            }
            .groupBackground(look)
        }
        .themed(look)
        .tint(look.controlTint)
        .navigationTitle("Sound")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func db(_ v: Double) -> String {
        v == 0 ? "0 dB" : String(format: "%+.1f dB", v)
    }

    private func balance(_ v: Double) -> String {
        abs(v) < 0.025 ? "Centre" : (v < 0 ? "L \(Int(-v * 100)) %" : "R \(Int(v * 100)) %")
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(text).monospacedDigit().foregroundStyle(look.palette.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }
}

/// Ten bands and a preamp, with presets.
struct EqualizerSettings: View {
    @Environment(Look.self) private var look
    @Environment(Sound.self) private var sound

    var body: some View {
        @Bindable var sound = sound
        Form {
            Section {
                Toggle("Equalizer", isOn: $sound.prefs.eqOn)
            }
            .groupBackground(look)

            Section("Presets") {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(SoundPrefs.presets, id: \.0) { name, gains in
                            let on = sound.prefs.eq == gains
                            Button(name) {
                                withAnimation(.snappy) {
                                    sound.prefs.eq = gains
                                    sound.prefs.eqOn = true
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(on ? look.controlTint : look.palette.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }
            .groupBackground(look)

            Section {
                HStack(alignment: .bottom, spacing: 0) {
                    band("Pre", value: $sound.prefs.preamp)
                    Divider().frame(height: 170).padding(.horizontal, 2)
                    ForEach(0..<10, id: \.self) { k in
                        band(label(SoundPrefs.bands[k]), value: $sound.prefs.eq[k])
                    }
                }
                .padding(.vertical, 8)
                .opacity(sound.prefs.eqOn ? 1 : 0.45)
                .disabled(!sound.prefs.eqOn)
            } header: {
                Text("Bands")
            } footer: {
                Text("Drag up to boost, down to cut (±12 dB).")
            }
            .groupBackground(look)
        }
        .themed(look)
        .tint(look.controlTint)
        .navigationTitle("Equalizer")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func label(_ f: Double) -> String {
        f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))"
    }

    /// One band: a vertical slider with its value over it and the frequency under it.
    private func band(_ name: String, value: Binding<Double>) -> some View {
        VStack(spacing: 6) {
            Text(value.wrappedValue == 0 ? "0" : String(format: "%+.0f", value.wrappedValue))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(look.palette.secondary)
            VerticalSlider(value: value, range: -12...12)
                .frame(width: 26, height: 150)
            Text(name).font(.caption2).foregroundStyle(look.palette.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A thin vertical slider (drag up and down; double tap: back to 0).
private struct VerticalSlider: View {
    @Environment(Look.self) private var look
    @Binding var value: Double
    var range: ClosedRange<Double>

    var body: some View {
        GeometryReader { g in
            let h = g.size.height
            let f = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let zero = (0 - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack {
                Capsule().fill(look.palette.secondary.opacity(0.25)).frame(width: 4)
                // The part between 0 and the value.
                let top = h * (1 - max(f, zero)), bottom = h * (1 - min(f, zero))
                Capsule().fill(look.controlTint)
                    .frame(width: 4, height: max(0, bottom - top))
                    .position(x: g.size.width / 2, y: (top + bottom) / 2)
                Circle().fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .frame(width: 20, height: 20)
                    .position(x: g.size.width / 2, y: h * (1 - f))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let t = 1 - max(0, min(1, v.location.y / h))
                let raw = range.lowerBound + t * (range.upperBound - range.lowerBound)
                value = (raw * 2).rounded() / 2
            })
            .onTapGesture(count: 2) { value = 0 }
        }
    }
}

// MARK: - Last.fm

/// Your own Last.fm API account, then allow Starlite in the browser.
struct LastFMSettings: View {
    @Environment(Look.self) private var look
    @Environment(LastFM.self) private var lastfm
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase
    @State private var busy = false

    var body: some View {
        @Bindable var lastfm = lastfm
        Form {
            if let l = lastfm.login {
                Section {
                    LabeledContent("Connected as", value: l.user)
                    if let s = lastfm.lastScrobble {
                        LabeledContent("Last scrobble", value: s)
                    }
                    Button("Disconnect", role: .destructive) { lastfm.disconnect() }
                } footer: {
                    Text("Starlite shows what you play on Last.fm and scrobbles a song once you've heard half of it (or 4 minutes).")
                }
                .groupBackground(look)
            } else {
                Section {
                    TextField("API key", text: $lastfm.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Shared secret", text: $lastfm.secret)
                } header: {
                    Text("Your Last.fm API account")
                } footer: {
                    Text("Make one at last.fm/api/account/create (any name works), then paste its API key and shared secret here.")
                }
                .groupBackground(look)

                Section {
                    if lastfm.pendingToken == nil {
                        Button {
                            Task {
                                busy = true
                                if let u = await lastfm.start() { openURL(u) }
                                busy = false
                            }
                        } label: {
                            HStack { Text("Connect").fontWeight(.semibold); Spacer(); if busy { ProgressView() } }
                        }
                        .disabled(busy)
                    } else {
                        Button {
                            Task { busy = true; await lastfm.finish(); busy = false }
                        } label: {
                            HStack { Text("I've Allowed Starlite").fontWeight(.semibold); Spacer(); if busy { ProgressView() } }
                        }
                        Button("Start Over") { lastfm.pendingToken = nil }
                    }
                } footer: {
                    if let s = lastfm.status {
                        Text(s).foregroundStyle(.red)
                    } else if lastfm.pendingToken != nil {
                        Text("Allow Starlite on the page that opened, then come back.")
                    }
                }
                .groupBackground(look)
            }
        }
        .themed(look)
        .tint(look.controlTint)
        .navigationTitle("Last.fm")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: phase) { _, p in
            // Back from the browser: finish signing in by itself.
            if p == .active, lastfm.pendingToken != nil, lastfm.login == nil {
                Task { await lastfm.finish() }
            }
        }
    }
}
