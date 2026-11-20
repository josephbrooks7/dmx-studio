import Foundation
import AVFoundation
import AudioToolbox
import CoreAudio

// MARK: - Looks (presets you can tap any time)

struct LookPreset: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var effect: LightEffect
    var palette: String
    var movement: MoveEffect = .none
    var rate: Double = 1
    var intensity: Double = 1
    var icon: String = "sparkles"
    var group: String? = nil      // theme heading on the presets screen; nil = Essentials

    func asSection(start: Double) -> ShowSection {
        ShowSection(name: name, start: start, end: start + 1e9, level: .high, effect: effect, palette: palette,
                    intensity: intensity, rate: rate, movement: movement, accentStrobe: false)
    }

    /// True if this is one of the looks that ship with the app, unchanged.
    var isBuiltIn: Bool {
        LookPreset.defaults.contains { d in
            d.name == name && d.effect == effect && d.palette == palette && d.movement == movement
                && d.rate == rate && d.intensity == intensity && d.icon == icon
        }
    }

    /// What this look controls, for the little icons on its tile.
    var usesMovement: Bool { movement != .none }
    var usesStrobe: Bool { effect == .strobe }
    var isBeatDriven: Bool { ![.steady, .breathe, .blackout].contains(effect) }

    static var defaults: [LookPreset] { essentials + beamPack + themePack }

    /// Looks that use each of the 8 beams on a bar separately.
    static let beamPack: [LookPreset] = {
        func p(_ n: String, _ e: LightEffect, _ pal: String, _ m: MoveEffect, rate: Double = 1, _ icon: String) -> LookPreset {
            LookPreset(name: n, effect: e, palette: pal, movement: m, rate: rate, intensity: 1, icon: icon, group: "Beam Patterns")
        }
        return [
            p("Wave", .wave, "Ocean", .sweep, "water.waves"),
            p("Center Burst", .centerOut, "Fire", .beatNod, "burst"),
            p("Split Colors", .split, "Neon", .none, "rectangle.split.2x1.fill"),
            p("Pixel Pop", .pixelPop, "Neon", .none, "square.grid.3x3.fill"),
            p("Bounce", .bounce, "EDM", .sweep, "arrow.left.and.right"),
            p("Color Gradient", .gradient, "Sunset", .sweep, rate: 0.5, "slider.horizontal.below.rectangle"),
            p("Rainbow Wave", .wave, "Neon", .circle, rate: 0.5, "rainbow"),
            p("Disco Pixels", .pixelPop, "Disco", .circle, rate: 2, "circle.grid.3x3.fill"),
        ]
    }()

    static let groupOrder = ["Essentials", "Beam Patterns", "Fairy & Fantasy", "EDM & Electronic", "Dubstep & Bass", "Techno & Rave",
                             "Dance & Disco", "Pop & Hyperpop", "Psychedelic", "Holiday"]

    /// Themed looks: the name says the vibe, the palette and movement do the rest.
    static let themePack: [LookPreset] = {
        func p(_ g: String, _ n: String, _ e: LightEffect, _ pal: String, _ m: MoveEffect, rate: Double = 1, i: Double = 1, _ icon: String) -> LookPreset {
            LookPreset(name: n, effect: e, palette: pal, movement: m, rate: rate, intensity: i, icon: icon, group: g)
        }
        return [
            p("Fairy & Fantasy", "Fairy Dust", .sparkle, "Fairy", .sweep, i: 0.85, "sparkle"),
            p("Fairy & Fantasy", "Pixie Twinkle", .sparkle, "Fairy", .none, rate: 0.5, i: 0.75, "star.fill"),
            p("Fairy & Fantasy", "Enchanted", .breathe, "Fantasy", .circle, rate: 0.5, i: 0.8, "wand.and.stars"),
            p("Fairy & Fantasy", "Galaxy Drift", .rainbow, "Galaxy", .circle, rate: 0.5, "moon.stars.fill"),
            p("Fairy & Fantasy", "Dragon Fire", .kickFlash, "Dragon", .flip, "flame.fill"),

            p("EDM & Electronic", "Laser Chase", .chase, "EDM", .fan, rate: 2, "bolt.horizontal.fill"),
            p("EDM & Electronic", "Drop Hits", .kickFlash, "EDM", .flip, "burst.fill"),
            p("EDM & Electronic", "Build-Up", .chase, "EDM", .sweep, rate: 4, "arrow.up.right"),
            p("EDM & Electronic", "Festival Rainbow", .rainbow, "Neon", .fullRotate, rate: 2, "sparkles"),
            p("EDM & Electronic", "Synth Wave", .breathe, "Galaxy", .sweep, "waveform"),

            p("Dubstep & Bass", "Wobble", .pulse, "Dubstep", .beatNod, rate: 2, "waveform.path"),
            p("Dubstep & Bass", "Bass Drop", .kickFlash, "Dubstep", .flip, "speaker.wave.3.fill"),
            p("Dubstep & Bass", "Half-Time Snare", .snareHit, "Dubstep", .fan, "metronome.fill"),
            p("Dubstep & Bass", "Toxic Strobe", .strobe, "Dubstep", .none, "bolt.fill"),

            p("Techno & Rave", "Warehouse", .kickFlash, "Techno", .beatNod, "building.2.fill"),
            p("Techno & Rave", "Red Room", .kickFlash, "Red Room", .sweep, i: 0.9, "square.fill"),
            p("Techno & Rave", "Techno Strobe", .strobe, "Full White", .none, "bolt.circle.fill"),
            p("Techno & Rave", "Acid Rave", .colorBeat, "Rave", .fan, rate: 2, "hare.fill"),
            p("Techno & Rave", "UV Rave", .pulse, "Rave", .sweep, "sun.max.fill"),

            p("Dance & Disco", "Disco Ball", .sparkle, "Disco", .circle, rate: 2, "circle.hexagongrid.fill"),
            p("Dance & Disco", "Disco Fever", .colorBeat, "Disco", .circle, "music.note"),
            p("Dance & Disco", "Dance Floor", .alternate, "Dance", .beatNod, "music.note.list"),
            p("Dance & Disco", "Funk Groove", .pulse, "Disco", .sweep, "hifispeaker.fill"),

            p("Pop & Hyperpop", "Pop Candy", .colorBeat, "Pop Candy", .sweep, "heart.circle.fill"),
            p("Pop & Hyperpop", "Sweet Chorus", .pulse, "Pop Candy", .fan, "star.circle.fill"),
            p("Pop & Hyperpop", "Lime Club", .kickFlash, "Lime Club", .flip, "square.fill"),
            p("Pop & Hyperpop", "Lime Flash", .alternate, "Lime Club", .beatNod, rate: 2, "bolt.square.fill"),

            p("Psychedelic", "Psychedelic Swirl", .rainbow, "Psychedelic", .circle, rate: 0.5, "hurricane"),
            p("Psychedelic", "Lava Lamp", .breathe, "Psychedelic", .sweep, rate: 0.25, i: 0.85, "drop.triangle.fill"),
            p("Psychedelic", "Currents", .colorBeat, "Psychedelic", .sweep, rate: 0.5, "wind"),

            p("Holiday", "Christmas Lights", .alternate, "Christmas", .none, rate: 0.5, "gift.fill"),
            p("Holiday", "Snowfall Sparkle", .sparkle, "Christmas", .sweep, "snowflake"),
        ]
    }()

    static let essentials: [LookPreset] = [
        LookPreset(name: "Red Velvet", effect: .pulse, palette: "Red Velvet", movement: .sweep, icon: "heart.fill"),
        LookPreset(name: "Color Fades", effect: .breathe, palette: "Neon", movement: .sweep, icon: "paintbrush.fill"),
        LookPreset(name: "Club Chase", effect: .chase, palette: "Neon", movement: .fan, rate: 2, icon: "bolt.horizontal.fill"),
        LookPreset(name: "Beat Colors", effect: .colorBeat, palette: "Purple Haze", movement: .beatNod, icon: "metronome.fill"),
        LookPreset(name: "Rainbow Flow", effect: .rainbow, palette: "Neon", movement: .fullRotate, icon: "sparkles"),
        LookPreset(name: "Kick Hits", effect: .kickFlash, palette: "Fire", movement: .flip, icon: "burst.fill"),
        LookPreset(name: "Strobe White", effect: .strobe, palette: "Full White", icon: "bolt.fill"),
        LookPreset(name: "Blue · Orange", effect: .alternate, palette: "Sunset", movement: .fan, icon: "circle.lefthalf.filled"),
        LookPreset(name: "Cyan · Pink", effect: .alternate, palette: "Neon", movement: .sweep, icon: "circle.lefthalf.filled"),
        LookPreset(name: "Slow Burn", effect: .breathe, palette: "Fire", movement: .sweep, rate: 0.5, intensity: 0.8, icon: "flame.fill"),
        LookPreset(name: "Ocean Drift", effect: .breathe, palette: "Ocean", movement: .circle, rate: 0.5, intensity: 0.7, icon: "drop.fill"),
        LookPreset(name: "Warm White", effect: .steady, palette: "Warm White", intensity: 0.9, icon: "lightbulb.fill"),
        LookPreset(name: "Follows Sound", effect: .soundLevel, palette: "Red Velvet", movement: .sweep, icon: "waveform"),
    ]
}

// MARK: - Beat clock for live mode (manual tap or microphone)

enum BeatSource: String, CaseIterable, Codable, Identifiable {
    case manual = "Manual (tap)"
    case mic = "Listen (mic or computer audio)"
    var id: String { rawValue }
}

struct BeatClock {
    var bpm: Double = 120
    var anchor: Double = Date().timeIntervalSinceReferenceDate   // a time a beat landed on

    var period: Double { 60 / max(bpm, 30) }

    /// Global beat number at time t (fractional).
    func beatNumber(at t: Double) -> Double { (t - anchor) / period }

    /// A synthetic "song" covering the current moment, so the normal show engine can drive live looks.
    func liveAnalysis(now: Double, onsets: [Double], level: Double, useOnsetsAsKicks: Bool) -> SongAnalysis {
        let k0 = Int(floor(beatNumber(at: now))) - 32
        let beats = (0..<64).map { anchor + Double(k0 + $0) * period }
        let recent = onsets.filter { $0 > now - 20 }
        let kicks = useOnsetsAsKicks && !recent.isEmpty ? recent : beats
        let snares = beats.enumerated().filter { ($0.offset + k0) % 2 != 0 }.map { $0.element }
        let hats = beats.map { $0 + period / 2 }
        let lvl = [Float(min(1, max(0.05, level)))]
        var a = SongAnalysis(duration: now + 3600, bpm: bpm, beats: beats, downbeatOffset: 0, frameRate: 1,
                             energy: lvl, bass: lvl, mid: lvl, high: lvl,
                             kicks: kicks, snares: snares, hats: hats, detectedSections: [], silences: nil)
        a.beatBase = k0
        return a
    }
}

/// Listens to the Mac's microphone and finds the beat in real time (for DJ sets, bands, anything not learned).
final class MicBeatTracker {
    private var engine: AVAudioEngine?
    private let lock = NSLock()
    private var onsets: [Double] = []
    private var lowAvg: Float = 0
    private var lastOnset: Double = 0
    private var peak: Float = 0.01
    private var level: Float = 0
    private var lp: Float = 0
    private(set) var bpm: Double = 120
    private(set) var anchor: Double = Date().timeIntervalSinceReferenceDate

    var isRunning: Bool { engine?.isRunning ?? false }

    func start(device: AudioDeviceID? = nil) throws {
        stop()
        let e = AVAudioEngine()
        let input = e.inputNode
        // Listen to a chosen input (built-in mic, USB mic, or BlackHole for computer audio)
        if let device, let au = input.audioUnit {
            var d = device
            let status = AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                              &d, UInt32(MemoryLayout<AudioDeviceID>.size))
            if status != noErr {
                throw NSError(domain: "DMXStudio", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Couldn't switch to that audio input (error \(status))."])
            }
        }
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else {
            throw NSError(domain: "DMXStudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone input is available."])
        }
        let sr = Float(fmt.sampleRate)
        let a = 1 - exp(-2 * Float.pi * 150 / sr)   // one-pole low-pass ~150 Hz: the kick drum
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
            guard let self, let ch = buf.floatChannelData?[0] else { return }
            let n = Int(buf.frameLength)
            guard n > 0 else { return }
            var lowE: Float = 0, fullE: Float = 0
            var y = self.lp
            for i in 0..<n {
                let x = ch[i]
                y += a * (x - y)
                lowE += y * y
                fullE += x * x
            }
            self.lp = y
            lowE /= Float(n); fullE /= Float(n)
            self.process(low: lowE, full: sqrt(fullE), at: Date().timeIntervalSinceReferenceDate)
        }
        try e.start()
        engine = e
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    private func process(low: Float, full: Float, at t: Double) {
        lock.lock(); defer { lock.unlock() }
        peak = max(full, peak * 0.9995)
        level = min(1, full / max(peak, 0.0001))
        let isOnset = low > lowAvg * 1.6 + 1e-7 && t - lastOnset > 0.25 && level > 0.08
        lowAvg = lowAvg * 0.95 + low * 0.05
        guard isOnset else { return }
        lastOnset = t
        onsets.append(t)
        onsets.removeAll { $0 < t - 12 }
        // Tempo from the spacing between hits, folded into a danceable range
        var iois: [Double] = []
        for (a, b) in zip(onsets, onsets.dropFirst()) {
            var d = b - a
            guard d > 0.2, d < 2 else { continue }
            while d < 0.375 { d *= 2 }
            while d > 0.75 { d /= 2 }
            iois.append(d)
        }
        if iois.count >= 4 {
            let med = iois.sorted()[iois.count / 2]
            let est = 60 / med
            bpm = abs(est - bpm) < 8 ? bpm * 0.8 + est * 0.2 : est
        }
        anchor = t
    }

    /// Automated tests: feed the tracker as if the mic heard something.
    func injectTest(low: Float, full: Float, at t: Double) { process(low: low, full: full, at: t) }

    func snapshot() -> (bpm: Double, anchor: Double, onsets: [Double], level: Double) {
        lock.lock(); defer { lock.unlock() }
        return (bpm, anchor, onsets, Double(level))
    }
}
