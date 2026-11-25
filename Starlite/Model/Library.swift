import AVFoundation
import CryptoKit
import Foundation
import UIKit

/// Your playlists, liked songs and the songs on this iPhone.
@Observable
final class Library {
    var playlists: [Playlist] = [] { didSet { save() } }
    var liked: [Track] = [] { didSet { save() } }
    /// Songs in Documents (downloaded, or put there in the Files app).
    var downloaded: [Track] = []
    /// Downloaded server songs: file name → what it is.
    var downloadInfo: [String: Track] = [:] { didSet { save() } }
    /// What you played last, newest first.
    var recent: [Track] = [] { didSet { save() } }
    /// Server songs being downloaded right now (server key → 0…1).
    var downloading: [String: Double] = [:]

    private struct Saved: Codable {
        var playlists: [Playlist]
        var liked: [Track]
        var downloadInfo: [String: Track]
        var recent: [Track]?
    }
    private var loaded = false

    init() {
        if let s = Storage.load(Saved.self, "library.json") {
            playlists = s.playlists
            liked = s.liked
            downloadInfo = s.downloadInfo
            recent = s.recent ?? []
        }
        loaded = true
    }

    private func save() {
        guard loaded else { return }
        Storage.save(Saved(playlists: playlists, liked: liked, downloadInfo: downloadInfo, recent: recent), "library.json")
    }

    // MARK: Playlists

    @discardableResult
    func create(_ name: String, tracks: [Track] = [], origin: PlaylistOrigin? = nil) -> Playlist {
        let symbols = ["music.note.list", "headphones", "guitars", "pianokeys", "music.mic", "radio", "sparkles", "moon.stars", "flame", "leaf", "heart", "star"]
        let p = Playlist(id: UUID().uuidString, name: name.isEmpty ? "New Playlist" : name, tracks: tracks, symbol: symbols.randomElement()!, origin: origin)
        playlists.insert(p, at: 0)
        return p
    }

    func delete(_ id: String) {
        playlists.removeAll { $0.id == id }
    }

    func rename(_ id: String, to name: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        playlists[i].name = name
    }

    func add(_ tracks: [Track], to id: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        let have = Set(playlists[i].tracks.map(\.id))
        playlists[i].tracks += tracks.filter { !have.contains($0.id) }
    }

    func remove(_ trackId: String, from id: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].tracks.removeAll { $0.id == trackId }
    }

    func move(in id: String, from: IndexSet, to: Int) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].tracks.move(fromOffsets: from, toOffset: to)
    }

    func playlist(_ id: String) -> Playlist? {
        playlists.first { $0.id == id }
    }

    /// Every song you have (playlists, liked, downloaded), each once.
    var allTracks: [Track] {
        var seen = Set<String>()
        return (liked + downloaded + playlists.flatMap(\.tracks)).filter { seen.insert($0.id).inserted }
    }

    /// Songs by an artist from what you have.
    func songs(by artist: String) -> [Track] {
        let a = artist.lowercased()
        return allTracks.filter {
            let b = $0.artist.lowercased()
            return b == a || b.contains(a) || a.contains(b)
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// A song started playing: first in Recently Played.
    func played(_ t: Track) {
        var r = recent
        r.removeAll { $0.id == t.id }
        r.insert(t, at: 0)
        recent = Array(r.prefix(24))
    }

    // MARK: Liked

    func isLiked(_ t: Track) -> Bool {
        liked.contains { $0.id == t.id }
    }

    func toggleLike(_ t: Track) {
        if isLiked(t) {
            liked.removeAll { $0.id == t.id }
        } else {
            liked.insert(t, at: 0)
        }
        NotificationCenter.default.post(name: .starliteLikesChanged, object: nil)
    }

    // MARK: On this iPhone

    func isDownloaded(_ t: Track) -> Bool {
        if t.isLocal { return true }
        guard let k = t.serverKey else { return false }
        return downloadInfo.values.contains { $0.id == k }
    }

    /// The local copy of a server song, if there is one.
    func localCopy(of t: Track) -> Track? {
        guard let k = t.serverKey, let (name, info) = downloadInfo.first(where: { $0.value.id == k }),
              FileManager.default.fileExists(atPath: Storage.documents.appendingPathComponent(name).path) else { return nil }
        var local = info
        local.source = .file(name: name)
        return local
    }

    static let audioTypes: Set<String> = ["mp3", "m4a", "aac", "flac", "wav", "aif", "aiff", "alac", "caf", "mp4"]

    /// Looks through Documents again (Files app changes, downloads).
    func scan() async {
        if Storage.demo { return }
        let fm = FileManager.default
        let root = Storage.documents
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return }
        var found: [Track] = []
        while let u = e.nextObject() as? URL {
            guard Library.audioTypes.contains(u.pathExtension.lowercased()) else { continue }
            let rel = u.path.replacingOccurrences(of: root.path + "/", with: "")
            if var known = downloadInfo[rel] {
                known.id = "file:\(rel)"
                known.source = .file(name: rel)
                found.append(known)
            } else {
                found.append(await Library.readTags(u, name: rel))
            }
        }
        downloaded = found.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Title, artist, album, length and cover from the file's tags.
    static func readTags(_ url: URL, name: String) async -> Track {
        let asset = AVURLAsset(url: url)
        var title = url.deletingPathExtension().lastPathComponent
        var artist = "Unknown artist"
        var album: String?
        var art: URL?
        let duration = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
        if let items = try? await asset.load(.commonMetadata) {
            for item in items {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle: if let v = try? await item.load(.stringValue), !v.isEmpty { title = v }
                case .commonKeyArtist: if let v = try? await item.load(.stringValue), !v.isEmpty { artist = v }
                case .commonKeyAlbumName: album = try? await item.load(.stringValue)
                case .commonKeyArtwork:
                    if let d = try? await item.load(.dataValue), UIImage(data: d) != nil {
                        let f = Storage.covers.appendingPathComponent(stableName(name) + ".jpg")
                        try? d.write(to: f)
                        art = f
                    }
                default: break
                }
            }
        }
        return Track(id: "file:\(name)", title: title, artist: artist, album: album, duration: duration.isFinite ? duration : 0, artwork: art, source: .file(name: name))
    }

    /// Copies songs picked in Files into Documents.
    func importFiles(_ urls: [URL]) async {
        for u in urls {
            let scoped = u.startAccessingSecurityScopedResource()
            defer { if scoped { u.stopAccessingSecurityScopedResource() } }
            var dst = Storage.documents.appendingPathComponent(u.lastPathComponent)
            var n = 2
            while FileManager.default.fileExists(atPath: dst.path) {
                dst = Storage.documents.appendingPathComponent("\(u.deletingPathExtension().lastPathComponent) \(n).\(u.pathExtension)")
                n += 1
            }
            try? FileManager.default.copyItem(at: u, to: dst)
        }
        await scan()
    }

    func deleteFile(_ t: Track) {
        guard case .file(let name) = t.source else { return }
        try? FileManager.default.removeItem(at: Storage.documents.appendingPathComponent(name))
        downloadInfo[name] = nil
        downloaded.removeAll { $0.id == t.id }
    }

    /// Removes the downloaded copy of a server song.
    func removeDownload(of t: Track) {
        if t.isLocal {
            deleteFile(t)
            return
        }
        guard let k = t.serverKey else { return }
        let names = downloadInfo.filter { $0.value.id == k }.map(\.key)
        for name in names {
            try? FileManager.default.removeItem(at: Storage.documents.appendingPathComponent(name))
            downloadInfo[name] = nil
        }
        downloaded.removeAll {
            if case .file(let n) = $0.source { return names.contains(n) }
            return false
        }
    }

    func download(_ t: Track, services: Services, quality: StreamQuality) {
        guard let key = t.serverKey, downloading[key] == nil, !isDownloaded(t), let (url, ext) = services.downloadURL(for: t, quality: quality) else { return }
        downloading[key] = 0
        Task {
            defer { downloading[key] = nil }
            do {
                let (tmp, resp) = try await URLSession.shared.download(from: url)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
                let folder = Storage.documents.appendingPathComponent("Downloads", isDirectory: true)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let clean = "\(t.artist) - \(t.title)".replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
                var name = "Downloads/\(clean).\(ext)"
                var n = 2
                while FileManager.default.fileExists(atPath: Storage.documents.appendingPathComponent(name).path) {
                    name = "Downloads/\(clean) \(n).\(ext)"
                    n += 1
                }
                try FileManager.default.moveItem(at: tmp, to: Storage.documents.appendingPathComponent(name))
                var info = t
                info.id = key
                // Keep the cover on this iPhone too.
                if let a = t.artwork, let (d, _) = try? await URLSession.shared.data(from: a), UIImage(data: d) != nil {
                    let f = Storage.covers.appendingPathComponent(stableName(key) + ".jpg")
                    try? d.write(to: f)
                    info.artwork = f
                }
                downloadInfo[name] = info
                await scan()
            } catch {}
        }
    }

    /// How much space your songs take.
    func usedBytes() -> Int64 {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: Storage.documents, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        while let u = e.nextObject() as? URL {
            total += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    func deleteAllDownloads() {
        for (name, _) in downloadInfo {
            try? FileManager.default.removeItem(at: Storage.documents.appendingPathComponent(name))
        }
        downloadInfo = [:]
        Task { await scan() }
    }
}

/// A file name that stays the same between launches.
func stableName(_ s: String) -> String {
    SHA256.hash(data: Data(s.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
}
