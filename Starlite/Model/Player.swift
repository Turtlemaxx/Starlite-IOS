import AVFoundation
import MediaPlayer
import SwiftUI

enum RepeatMode: String, Codable {
    case off, all, one
    var symbol: String { self == .one ? "repeat.1" : "repeat" }
}

/// Plays a queue of songs (from a server or this iPhone), in the
/// background too, with the lock screen's controls.
@Observable
final class Player {
    /// The one player (the widget's buttons reach it through CommandBridge).
    static let shared = Player()

    private(set) var queue: [Track] = []
    private(set) var index = 0
    private(set) var playing = false
    var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var shuffle = false
    var repeatMode: RepeatMode = .off
    private(set) var error: String?
    /// The current cover (for the full-screen player's background).
    private(set) var artworkImage: UIImage?

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var original: [Track] = []
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObserver: NSKeyValueObservation?
    @ObservationIgnored private weak var services: Services?
    @ObservationIgnored private weak var library: Library?
    @ObservationIgnored private weak var look: Look?
    @ObservationIgnored private weak var sound: Sound?
    @ObservationIgnored private weak var lastfm: LastFM?
    // Last.fm: how long this song has really been listened to.
    @ObservationIgnored private var listened: Double = 0
    @ObservationIgnored private var lastTick: Double = 0
    @ObservationIgnored private var scrobbled = false
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var sessionReady = false
    @ObservationIgnored private var artTask: Task<Void, Never>?
    /// The song whose cover the widget has.
    @ObservationIgnored private var widgetArtFor: String?
    @ObservationIgnored private var widgetArt: Data?
    /// Small covers (and their colour) for the widget, by song: the next
    /// songs' are fetched ahead so the widget can move on by itself.
    @ObservationIgnored private var widgetCovers: [String: (data: Data, color: RGBA?)] = [:]
    @ObservationIgnored private var widgetFetching: Set<String> = []
    @ObservationIgnored private var widgetReload: DispatchWorkItem?
    /// What the widget was last asked to show (no refresh if nothing changed:
    /// the system only allows so many).
    @ObservationIgnored private var widgetShown = ""
    /// Whether the player is really playing (not waiting for the song to load).
    @ObservationIgnored private var playbackKVO: NSKeyValueObservation?

    /// Whether the widget can be drawn with this song's cover now.
    var widgetReady: Bool {
        guard let t = current, t.artwork != nil else { return true }
        return artworkImage != nil || widgetCovers[t.id] != nil
    }

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }

    /// The exact playback time, read from the player right now (the lyrics
    /// follow this every frame; `position` only updates four times a second).
    var exactTime: Double {
        guard player.currentItem != nil else { return position }
        let t = CMTimeGetSeconds(player.currentTime())
        return t.isFinite ? t : position
    }
    var upNext: [Track] { queue.indices.contains(index + 1) ? Array(queue[(index + 1)...]) : [] }

    func configure(services: Services, library: Library, look: Look, sound: Sound, lastfm: LastFM) {
        self.services = services
        self.library = library
        self.look = look
        self.sound = sound
        self.lastfm = lastfm
        sound.onChange = { [weak self] p in self?.applySound(p) }
        applySound(sound.prefs)
        NotificationCenter.default.addObserver(forName: .starliteLikesChanged, object: nil, queue: .main) { [weak self] _ in
            self?.syncWidget()
        }
        player.automaticallyWaitsToMinimizeStalling = true
        // The widget follows what the player really does: when a song really
        // starts (after loading), stops to load more, or pauses.
        playbackKVO = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            DispatchQueue.main.async { self?.syncWidget() }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] t in
            guard let self else { return }
            self.position = CMTimeGetSeconds(t)
            self.countListening()
            if let d = self.player.currentItem?.duration, d.isNumeric {
                let s = CMTimeGetSeconds(d)
                if s.isFinite, s > 0, abs(s - self.duration) > 0.5 { self.duration = s }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, (n.object as? AVPlayerItem) === self.player.currentItem else { return }
            self.finished()
        }
        remoteCommands()
    }

    // MARK: What plays

    func play(_ list: [Track], at i: Int = 0, shuffled: Bool = false) {
        guard !list.isEmpty else { return }
        original = list
        shuffle = shuffled
        if shuffled {
            var rest = list
            let first = rest.remove(at: min(i, rest.count - 1))
            queue = (shuffled && i == 0 ? list.shuffled() : [first] + rest.shuffled())
            index = 0
        } else {
            queue = list
            index = min(i, list.count - 1)
        }
        playing = true
        load()
    }

    /// Fills the player without playing (the screenshots' demo).
    func show(_ list: [Track], at i: Int, position: Double) {
        queue = list
        index = i
        duration = list[i].duration
        self.position = position
        playing = false
        artworkImage = nil
    }

    /// The screenshots' demo: looks as if it plays (nothing is loaded).
    func demoPlaying() {
        playing = true
    }

    func playNext(_ t: Track) {
        if queue.isEmpty { play([t]); return }
        queue.insert(t, at: index + 1)
    }

    func addToQueue(_ t: Track) {
        if queue.isEmpty { play([t]); return }
        queue.append(t)
    }

    func jump(to i: Int) {
        guard queue.indices.contains(i) else { return }
        index = i
        playing = true
        load()
    }

    func toggle() {
        guard current != nil else { return }
        if playing {
            player.pause()
            playing = false
        } else {
            if player.currentItem == nil { load() }
            activateSession()
            player.play()
            playing = true
        }
        updateNowPlaying()
        syncWidget()
    }

    /// A button in the widget was pressed.
    func handle(_ c: PlayerCommand) {
        switch c {
        case .toggle: toggle()
        case .next: next()
        case .previous: previous()
        case .like:
            if let t = current { library?.toggleLike(t) }
        }
        syncWidget()
        WidgetLog.write("Widget button \(c.rawValue): now “\(current?.title ?? "nothing")” \(playing ? "playing" : "paused") at \(Int(exactTime))s.")
    }

    /// Tells the widget what's playing (and its cover, once per song).
    func syncWidget(reload: Bool = true) {
        var s = WidgetSnapshot()
        if let t = current {
            s.title = t.title
            s.artist = t.artist
            s.album = t.album
            s.hasTrack = true
            // Only while sound really comes out (not while loading).
            s.playing = playing && player.timeControlStatus == .playing
            s.rate = Double(player.defaultRate)
            s.elapsed = exactTime
            s.at = Date()
            s.duration = duration > 0 ? duration : t.duration
            s.liked = library?.isLiked(t) ?? false
            s.upNext = upNext.first.map { "\($0.title) · \($0.artist)" }
            s.art = widgetArtKey(t.id)
            s.upcoming = upNext.prefix(3).map { u in
                WidgetSong(title: u.title, artist: u.artist, album: u.album, duration: u.duration,
                           liked: library?.isLiked(u) ?? false,
                           art: widgetCovers[u.id] != nil ? widgetArtKey(u.id) : nil,
                           color: widgetCovers[u.id]?.color)
            }
        }
        if let look {
            let p = look.palette
            s.themeBackground = RGBA(p.background)
            s.themeText = RGBA(p.text)
            s.themeAccent = RGBA(p.accent)
            // The colour of this song's cover (not the last one's while it loads).
            if artworkImage != nil {
                s.coverColor = look.coverColor.map { RGBA($0) }
            } else if let t = current {
                s.coverColor = widgetCovers[t.id]?.color
            }
        }
        if widgetArtFor != current?.id || (current != nil && artworkImage != nil && !FileManager.default.fileExists(atPath: AppGroup.artworkURL.path)) {
            if let img = artworkImage, let data = img.squareThumbnail(360).jpegData(compressionQuality: 0.85) {
                try? data.write(to: AppGroup.artworkURL, options: .atomic)
                widgetArtFor = current?.id
                widgetArt = data
            } else {
                try? FileManager.default.removeItem(at: AppGroup.artworkURL)
                widgetArtFor = artworkImage == nil ? nil : current?.id
                widgetArt = nil
            }
        }
        // This song's cover: the one loaded for the player, or fetched ahead.
        var covers: [String: Data] = [:]
        if let t = current {
            if let d = widgetArtFor == t.id ? widgetArt : nil {
                covers[widgetArtKey(t.id)] = d
            } else if let c = widgetCovers[t.id] {
                covers[widgetArtKey(t.id)] = c.data
            }
            if covers.isEmpty { s.art = nil }
            if widgetArt != nil, widgetArtFor == t.id, widgetCovers[t.id] == nil {
                widgetCovers[t.id] = (widgetArt!, s.coverColor)
            }
            for u in upNext.prefix(3) {
                if let c = widgetCovers[u.id] { covers[widgetArtKey(u.id)] = c.data }
            }
        }
        writeWidgetCovers(covers)
        AppGroup.write(s, "widget-now.json")
        // Without an App Group, the widget asks the app itself.
        WidgetServer.shared.update(now: s, arts: covers)
        prefetchWidgetCovers()
        if reload { reloadWidgetSoon(s) }
    }

    /// The covers the widget may need, as files in the shared folder (and
    /// the ones it won't need any more gone).
    private func writeWidgetCovers(_ covers: [String: Data]) {
        let fm = FileManager.default
        for (key, data) in covers where !fm.fileExists(atPath: AppGroup.coverURL(key).path) {
            try? data.write(to: AppGroup.coverURL(key), options: .atomic)
        }
        let keep = Set(covers.keys.map { "widget-art-\($0).jpg" })
        for name in (try? fm.contentsOfDirectory(atPath: AppGroup.folder.path)) ?? [] where name.hasPrefix("widget-art-") && !keep.contains(name) {
            try? fm.removeItem(at: AppGroup.folder.appendingPathComponent(name))
        }
    }

    /// One redraw for a burst of changes (a song starting, then its cover
    /// arriving): the system ignores widget reloads that come too often.
    private func reloadWidgetSoon(_ s: WidgetSnapshot) {
        // What can be seen: a seek moves the start by more than 2 seconds.
        let seen = [s.title, s.artist, "\(s.playing)", "\(Int(s.startDate.timeIntervalSince1970.rounded()))", "\(s.liked)",
                    s.art ?? "-", "\(s.coverColor.map { "\($0)" } ?? "-")", s.upcoming.map { "\($0.title)\($0.art ?? "-")" }.joined()].joined(separator: "|")
        guard seen != widgetShown else { return }
        widgetReload?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Fresh state right before asking (things move on during the wait).
            self.syncWidget(reload: false)
            self.widgetShown = seen
            AppGroup.reloadWidgets()
            WidgetServer.shared.askedReload()
            WidgetLog.write("Asked the widget to refresh: “\(s.hasTrack ? s.title : "Not Playing")” \(s.playing ? "playing" : "paused") at \(Int(s.elapsed))s, cover \(s.art == nil ? "not ready" : "ready").")
        }
        widgetReload = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: w)
    }

    /// Fetches the next songs' covers (small) so the widget has them.
    private func prefetchWidgetCovers() {
        let wanted = ([current].compactMap { $0 } + upNext.prefix(3))
        let keep = Set(wanted.map(\.id))
        widgetCovers = widgetCovers.filter { keep.contains($0.key) }
        for t in wanted where widgetCovers[t.id] == nil && !widgetFetching.contains(t.id) {
            guard let u = t.artwork else { continue }
            widgetFetching.insert(t.id)
            Task { [weak self] in
                let data: Data?
                if u.isFileURL {
                    data = try? Data(contentsOf: u)
                } else {
                    data = try? await URLSession.shared.data(from: u).0
                }
                let img = data.flatMap { UIImage(data: $0) }
                let small = img?.squareThumbnail(300).jpegData(compressionQuality: 0.8)
                let color = img?.averageColor.map { RGBA($0) }
                await MainActor.run {
                    guard let self else { return }
                    self.widgetFetching.remove(t.id)
                    guard let small else {
                        WidgetLog.write("Couldn't load the cover of “\(t.title)” for the widget.")
                        return
                    }
                    self.widgetCovers[t.id] = (small, color)
                    self.syncWidget()
                }
            }
        }
    }

    func next() {
        guard !queue.isEmpty else { return }
        if index + 1 < queue.count {
            index += 1
        } else if repeatMode == .all {
            index = 0
        } else {
            return
        }
        load()
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if position > 3 || index == 0 {
            seek(to: 0)
            return
        }
        index -= 1
        load()
    }

    func seek(to seconds: Double) {
        position = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async { self?.syncWidget() }
        }
        updateNowPlaying()
    }

    func setShuffle(_ on: Bool) {
        guard let cur = current else { shuffle = on; return }
        shuffle = on
        if on {
            var rest = queue
            rest.remove(at: index)
            queue = [cur] + rest.shuffled()
            index = 0
        } else {
            queue = original.isEmpty ? queue : original
            index = queue.firstIndex(of: cur) ?? 0
        }
    }

    func cycleRepeat() {
        repeatMode = repeatMode == .off ? .all : repeatMode == .all ? .one : .off
    }

    private func finished() {
        if repeatMode == .one {
            seek(to: 0)
            player.play()
            return
        }
        if index + 1 < queue.count || repeatMode == .all {
            next()
        } else {
            playing = false
            seek(to: 0)
            player.pause()
            syncWidget()
        }
    }

    // MARK: Loading

    private func activateSession() {
        guard !sessionReady else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        sessionReady = true
    }

    private func load() {
        guard let t = current else { return }
        error = nil
        position = 0
        duration = t.duration
        let quality = look?.prefs.stream ?? .original
        // A downloaded copy plays instead of streaming.
        let playable = library?.localCopy(of: t) ?? t
        guard let url = services?.url(for: playable, quality: quality) else {
            error = "Connect \(t.id.hasPrefix("jf:") ? "Jellyfin" : "Navidrome") in Settings to play this song"
            playing = false
            player.replaceCurrentItem(with: nil)
            updateNowPlaying()
            return
        }
        activateSession()
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = (sound?.prefs.keepPitch ?? true) ? .spectral : .varispeed
        // The equalizer and effects go into the song as it plays.
        Task { await AudioFX.attach(to: item) }
        listened = 0
        lastTick = 0
        scrobbled = false
        startedAt = Date()
        lastfm?.nowPlaying(t)
        library?.played(t)
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            DispatchQueue.main.async {
                self?.error = "This song couldn't be played"
                self?.playing = false
            }
        }
        player.replaceCurrentItem(with: item)
        if playing { player.play() }
        updateNowPlaying()
        loadArtwork(t)
        syncWidget()
    }

    /// Speed (and whether the pitch stays) for what plays now and next.
    private func applySound(_ p: SoundPrefs) {
        player.defaultRate = Float(p.speed)
        if playing { player.rate = Float(p.speed) }
        player.currentItem?.audioTimePitchAlgorithm = p.keepPitch ? .spectral : .varispeed
    }

    /// Scrobbles once a song has really been heard: half of it, or 4 minutes.
    private func countListening() {
        let d = position - lastTick
        lastTick = position
        guard playing, d > 0, d < 2, let t = current else { return }
        listened += d
        let length = duration > 0 ? duration : t.duration
        if !scrobbled, length > 30, listened >= min(240, length / 2) {
            scrobbled = true
            lastfm?.scrobble(t, startedAt: startedAt)
        }
    }

    private func loadArtwork(_ t: Track) {
        artTask?.cancel()
        artworkImage = nil
        guard let u = t.artwork else { look?.coverColor = nil; return }
        artTask = Task { [weak self] in
            let data: Data?
            if u.isFileURL {
                data = try? Data(contentsOf: u)
            } else {
                data = try? await URLSession.shared.data(from: u).0
            }
            guard !Task.isCancelled else { return }
            guard let data, let img = UIImage(data: data) else {
                WidgetLog.write("Couldn't load the cover of “\(t.title)”.")
                return
            }
            await MainActor.run {
                guard let self, self.current?.id == t.id else { return }
                self.artworkImage = img
                self.look?.coverColor = img.averageColor
                self.updateNowPlaying()
                self.widgetArtFor = nil
                self.syncWidget()
            }
        }
    }

    // MARK: Lock screen

    private func updateNowPlaying() {
        guard let t = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
        ]
        if let a = t.album { info[MPMediaItemPropertyAlbumTitle] = a }
        if let img = artworkImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func remoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            guard let self, !self.playing else { return .success }
            self.toggle()
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.playing else { return .success }
            self.toggle()
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.toggle()
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            self?.next()
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous()
            return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: e.positionTime)
            return .success
        }
    }
}

extension Notification.Name {
    /// Liked songs changed (the widget shows the heart).
    static let starliteLikesChanged = Notification.Name("starliteLikesChanged")
}

extension UIImage {
    /// A square, smaller copy (the widget's cover).
    func squareThumbnail(_ side: CGFloat) -> UIImage {
        let s = min(size.width, size.height)
        guard s > 0 else { return self }
        let scale = side / s
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            draw(in: CGRect(x: (side - size.width * scale) / 2, y: (side - size.height * scale) / 2, width: size.width * scale, height: size.height * scale))
        }
    }

    /// The picture's average colour, a little livelier (for the accent).
    var averageColor: Color? {
        guard let cg = cgImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: Double(min(1, s * 1.4)), brightness: Double(max(0.55, min(1, b * 1.3))))
    }
}
