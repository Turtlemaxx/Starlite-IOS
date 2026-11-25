import PhotosUI
import SwiftUI

/// Settings: the same categories as Starlite on the computer, as grouped rows.
struct SettingsTab: View {
    @Environment(Look.self) private var look
    @Environment(Services.self) private var services
    @State private var path = NavigationPath()

    enum Page: Hashable { case appearance, layout, playback, general }

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
                .listRowBackground(rowBackground)

                Section {
                    row(.appearance, "Appearance", "paintpalette.fill", .purple)
                    row(.layout, "Layout", "rectangle.3.group.fill", .blue)
                }
                .listRowBackground(rowBackground)

                Section("Sound") {
                    row(.playback, "Playback", "headphones", .orange)
                }
                .listRowBackground(rowBackground)

                Section("Services") {
                    ForEach(ServerKind.allCases) { s in
                        NavigationLink(value: s) {
                            HStack(spacing: 12) {
                                SymbolBadge(symbol: s.symbol, color: s == .navidrome ? .blue : .indigo)
                                Text(s.name)
                                Spacer()
                                Text(services.isConnected(s) ? "Connected" : "Not set up").foregroundStyle(look.palette.secondary)
                            }
                        }
                    }
                }
                .listRowBackground(rowBackground)

                Section {
                    row(.general, "General", "gearshape.fill", .gray)
                }
                .listRowBackground(rowBackground)
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
                case .general: GeneralSettings()
                }
            }
            .navigationDestination(for: ServerKind.self) { ConnectView(server: $0) }
            .onAppear {
                if path.isEmpty {
                    if DemoScreen.current == .appearance { path.append(Page.appearance) }
                    if DemoScreen.current == .layout { path.append(Page.layout) }
                }
            }
        }
    }

    private var rowBackground: some View {
        Rectangle().fill(.clear).panel(look, radius: 0)
    }

    private func row(_ p: Page, _ title: String, _ symbol: String, _ color: Color) -> some View {
        NavigationLink(value: p) {
            HStack(spacing: 12) {
                SymbolBadge(symbol: symbol, color: color)
                Text(title)
            }
        }
    }
}

/// The glass (or frosted, or solid) behind each group of rows.
private struct GroupBackground: ViewModifier {
    var look: Look
    func body(content: Content) -> some View {
        content.listRowBackground(Rectangle().fill(.clear).panel(look, radius: 0))
    }
}

private extension View {
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
