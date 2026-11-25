import AVFoundation
import Foundation
import MediaToolbox

/// How songs sound: speed, bass, clarity, balance, mono and a 10-band
/// equalizer. All neutral by default (then the sound passes untouched).
struct SoundPrefs: Codable, Equatable {
    var speed: Double = 1
    var keepPitch = true
    var bass: Double = 0
    var clarity: Double = 0
    var balance: Double = 0
    var mono = false
    var eqOn = false
    var preamp: Double = 0
    var eq: [Double] = Array(repeating: 0, count: 10)

    static let bands: [Double] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    /// Nothing to change: the audio is left exactly as it is.
    var neutral: Bool {
        bass == 0 && clarity == 0 && balance == 0 && !mono && (!eqOn || (preamp == 0 && eq.allSatisfy { $0 == 0 }))
    }

    static let presets: [(String, [Double])] = [
        ("Flat", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        ("Bass", [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
        ("Vocal", [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1]),
        ("Rock", [4, 3, 1, -1, -1, 1, 3, 4, 4, 4]),
        ("Electronic", [5, 4, 1, 0, -2, 1, 0, 2, 4, 5]),
        ("Acoustic", [3, 2, 1, 1, 2, 2, 3, 3, 2, 1]),
        ("Late Night", [2, 2, 1, 0, -1, -1, -2, -3, -4, -5]),
    ]
}

/// Keeps the sound settings and hands them to whatever is playing.
@Observable
final class Sound {
    var prefs: SoundPrefs {
        didSet {
            Storage.save(prefs, "sound.json")
            FXShared.shared.update(prefs)
            onChange?(prefs)
        }
    }
    @ObservationIgnored var onChange: ((SoundPrefs) -> Void)?

    init() {
        prefs = Storage.loadMerged(SoundPrefs.self, "sound.json", defaults: SoundPrefs()) ?? SoundPrefs()
        FXShared.shared.update(prefs)
    }
}

// MARK: - The processing (runs on the audio thread)

/// The settings as the audio thread sees them.
final class FXShared: @unchecked Sendable {
    static let shared = FXShared()
    private let lock = NSLock()
    private var prefs = SoundPrefs()
    private var version = 1

    func update(_ p: SoundPrefs) {
        lock.lock()
        prefs = p
        version += 1
        lock.unlock()
    }

    /// The settings if they changed since `seen` (never waits on the lock).
    func changed(since seen: Int) -> (SoundPrefs, Int)? {
        guard lock.try() else { return nil }
        defer { lock.unlock() }
        return version == seen ? nil : (prefs, version)
    }
}

/// One biquad filter (RBJ's cookbook), one state per channel.
private struct Biquad {
    var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    var z1 = [0.0, 0.0], z2 = [0.0, 0.0]

    static func peak(_ f: Double, _ db: Double, q: Double, rate: Double) -> Biquad {
        let a = pow(10, db / 40), w = 2 * Double.pi * f / rate, al = sin(w) / (2 * q)
        let a0 = 1 + al / a
        return Biquad(b0: (1 + al * a) / a0, b1: -2 * cos(w) / a0, b2: (1 - al * a) / a0, a1: -2 * cos(w) / a0, a2: (1 - al / a) / a0)
    }

    static func shelf(_ f: Double, _ db: Double, high: Bool, rate: Double) -> Biquad {
        let a = pow(10, db / 40), w = 2 * Double.pi * f / rate
        let cw = cos(w), al = sin(w) / 2 * sqrt(2), sa = 2 * sqrt(a) * al
        if high {
            let a0 = (a + 1) - (a - 1) * cw + sa
            return Biquad(b0: a * ((a + 1) + (a - 1) * cw + sa) / a0, b1: -2 * a * ((a - 1) + (a + 1) * cw) / a0, b2: a * ((a + 1) + (a - 1) * cw - sa) / a0, a1: 2 * ((a - 1) - (a + 1) * cw) / a0, a2: ((a + 1) - (a - 1) * cw - sa) / a0)
        }
        let a0 = (a + 1) + (a - 1) * cw + sa
        return Biquad(b0: a * ((a + 1) - (a - 1) * cw + sa) / a0, b1: 2 * a * ((a - 1) - (a + 1) * cw) / a0, b2: a * ((a + 1) - (a - 1) * cw - sa) / a0, a1: -2 * ((a - 1) + (a + 1) * cw) / a0, a2: ((a + 1) + (a - 1) * cw - sa) / a0)
    }

    mutating func run(_ x: Double, _ c: Int) -> Double {
        let y = b0 * x + z1[c]
        z1[c] = b1 * x - a1 * y + z2[c]
        z2[c] = b2 * x - a2 * y
        return y
    }

    /// New settings, same state (no click when a slider moves).
    mutating func take(_ o: Biquad) {
        b0 = o.b0; b1 = o.b1; b2 = o.b2; a1 = o.a1; a2 = o.a2
    }
}

/// The filters for one playing song.
final class FXProcessor {
    private var rate = 44100.0
    private var seen = 0
    private var prefs = SoundPrefs()
    private var filters: [Biquad] = []
    private var gain = 1.0

    func prepare(sampleRate: Double) {
        rate = sampleRate
        seen = 0
        filters = []
    }

    private func rebuild() {
        var f: [Biquad] = []
        if prefs.bass != 0 { f.append(.shelf(110, prefs.bass, high: false, rate: rate)) }
        if prefs.clarity != 0 { f.append(.shelf(5500, prefs.clarity, high: true, rate: rate)) }
        if prefs.eqOn {
            for (k, db) in prefs.eq.enumerated() where db != 0 && SoundPrefs.bands[k] < rate / 2 {
                f.append(.peak(SoundPrefs.bands[k], db, q: 1.1, rate: rate))
            }
        }
        if f.count == filters.count {
            for k in f.indices { filters[k].take(f[k]) }
        } else {
            filters = f
        }
        gain = prefs.eqOn ? pow(10, prefs.preamp / 20) : 1
        // Headroom for boosts, so they don't clip.
        let boost = max(0, prefs.bass, prefs.clarity, prefs.eqOn ? (prefs.eq.max() ?? 0) + prefs.preamp : 0)
        gain *= pow(10, -boost * 0.5 / 20)
    }

    func process(_ buffers: UnsafeMutableAudioBufferListPointer, frames: Int) {
        if let (p, v) = FXShared.shared.changed(since: seen) {
            prefs = p
            seen = v
            rebuild()
        }
        guard !prefs.neutral, frames > 0 else { return }
        let chans = buffers.count
        guard chans >= 1 else { return }
        let ptrs = (0..<chans).compactMap { buffers[$0].mData?.assumingMemoryBound(to: Float.self) }
        guard ptrs.count == chans else { return }
        let left = prefs.balance > 0 ? 1 - prefs.balance : 1
        let right = prefs.balance < 0 ? 1 + prefs.balance : 1
        for i in 0..<frames {
            var l = Double(ptrs[0][i])
            var r = chans > 1 ? Double(ptrs[1][i]) : l
            for k in filters.indices {
                l = filters[k].run(l, 0)
                r = filters[k].run(r, 1)
            }
            if prefs.mono {
                let m = (l + r) * 0.5
                l = m
                r = m
            }
            ptrs[0][i] = Float(l * gain * left)
            if chans > 1 { ptrs[1][i] = Float(r * gain * right) }
        }
    }
}

// The audio tap's callbacks (plain C functions).
private let tapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, storageOut in
    storageOut.pointee = clientInfo
}

private let tapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
    Unmanaged<FXProcessor>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private let tapPrepare: MTAudioProcessingTapPrepareCallback = { tap, _, format in
    let fx = Unmanaged<FXProcessor>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    fx.prepare(sampleRate: format.pointee.mSampleRate)
}

private let tapUnprepare: MTAudioProcessingTapUnprepareCallback = { _ in }

private let tapProcess: MTAudioProcessingTapProcessCallback = { tap, frames, _, buffers, framesOut, flagsOut in
    guard MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, nil, framesOut) == noErr else { return }
    let fx = Unmanaged<FXProcessor>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    fx.process(UnsafeMutableAudioBufferListPointer(buffers), frames: Int(framesOut.pointee))
}

enum AudioFX {
    /// Puts the sound settings into a song as it plays (files and plain
    /// streams; a song that can't take them plays as it is).
    static func attach(to item: AVPlayerItem) async {
        guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first else { return }
        let fx = FXProcessor()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(fx).toOpaque()),
            init: tapInit, finalize: tapFinalize, prepare: tapPrepare, unprepare: tapUnprepare, process: tapProcess)
        var tap: MTAudioProcessingTap?
        guard MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap) == noErr, let tap else {
            Unmanaged<FXProcessor>.fromOpaque(callbacks.clientInfo!).release()
            return
        }
        let params = AVMutableAudioMixInputParameters(track: track)
        params.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        await MainActor.run { item.audioMix = mix }
    }
}
