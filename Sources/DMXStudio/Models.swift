import Foundation
import SwiftUI

// MARK: - Color

struct RGB: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double

    static let black = RGB(r: 0, g: 0, b: 0)
    static let white = RGB(r: 1, g: 1, b: 1)

    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    /// h, s, v in 0...1
    init(h: Double, s: Double, v: Double) {
        let h6 = (h - floor(h)) * 6
        let i = Int(h6) % 6
        let f = h6 - floor(h6)
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch i {
        case 0: self.init(r: v, g: t, b: p)
        case 1: self.init(r: q, g: v, b: p)
        case 2: self.init(r: p, g: v, b: t)
        case 3: self.init(r: p, g: q, b: v)
        case 4: self.init(r: t, g: p, b: v)
        default: self.init(r: v, g: p, b: q)
        }
    }

    func mix(_ o: RGB, _ t: Double) -> RGB {
        RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t)
    }

    var color: Color { Color(red: r, green: g, blue: b) }
}

// MARK: - Palettes

struct Palette: Identifiable, Hashable {
    let id: String
    let colors: [RGB]

    static let all: [Palette] = [
        Palette(id: "Red Velvet", colors: [RGB(hex: 0xB0001E), RGB(hex: 0xFF2A4D), RGB(hex: 0x6A0DAD), RGB(hex: 0xFF8FA3)]),
        Palette(id: "Fire", colors: [RGB(hex: 0xFF2000), RGB(hex: 0xFF7A00), RGB(hex: 0xFFC400), RGB(hex: 0xFF0040)]),
        Palette(id: "Ocean", colors: [RGB(hex: 0x0040FF), RGB(hex: 0x00C8FF), RGB(hex: 0x00FFC0), RGB(hex: 0x4000FF)]),
        Palette(id: "Neon", colors: [RGB(hex: 0xFF00D4), RGB(hex: 0x00FFF0), RGB(hex: 0xB4FF00), RGB(hex: 0x7A00FF)]),
        Palette(id: "Sunset", colors: [RGB(hex: 0xFF5E3A), RGB(hex: 0xFF2A68), RGB(hex: 0xA020F0), RGB(hex: 0xFFB000)]),
        Palette(id: "Ice", colors: [RGB(hex: 0xFFFFFF), RGB(hex: 0x9FD8FF), RGB(hex: 0x3A7BFF), RGB(hex: 0xC8C8FF)]),
        Palette(id: "Purple Haze", colors: [RGB(hex: 0x5A00FF), RGB(hex: 0xB000FF), RGB(hex: 0xFF00A8), RGB(hex: 0x2000A0)]),
        Palette(id: "Forest", colors: [RGB(hex: 0x00FF40), RGB(hex: 0x80FF00), RGB(hex: 0x00A080), RGB(hex: 0xFFE000)]),
        Palette(id: "Warm White", colors: [RGB(hex: 0xFFC890), RGB(hex: 0xFFE0B0), RGB(hex: 0xFFB060)]),
        Palette(id: "Full White", colors: [RGB.white]),
    ]

    static func named(_ id: String) -> Palette { all.first { $0.id == id } ?? all[0] }

    func color(_ i: Int) -> RGB {
        guard !colors.isEmpty else { return .white }
        let n = colors.count
        return colors[((i % n) + n) % n]
    }
}

// MARK: - Fixtures

enum ChannelRole: String, CaseIterable, Codable {
    case dimmer = "D", red = "R", green = "G", blue = "B", white = "W", amber = "A", uv = "UV"
    case strobe = "S", pan = "P", tilt = "T", panFine = "PF", tiltFine = "TF", speed = "SPD"

    var label: String {
        switch self {
        case .dimmer: return "Dimmer"
        case .red: return "Red"
        case .green: return "Green"
        case .blue: return "Blue"
        case .white: return "White"
        case .amber: return "Amber"
        case .uv: return "UV"
        case .strobe: return "Strobe"
        case .pan: return "Pan"
        case .tilt: return "Tilt"
        case .panFine: return "Pan fine"
        case .tiltFine: return "Tilt fine"
        case .speed: return "Pan/Tilt speed"
        }
    }
}

/// A fixed color wheel: each slot is a color and the DMX value that selects it.
struct ColorWheel {
    let slots: [(color: RGB, value: UInt8)]

    static let wheels: [String: ColorWheel] = [
        // Chauvet DJ LED Followspot 75ST, channel 2 (from the user manual)
        "CHAUVET-FS75": ColorWheel(slots: [
            (RGB(hex: 0xFFFFFF), 16),   // 000-031 White
            (RGB(hex: 0x0020FF), 48),   // 032-063 Dark blue
            (RGB(hex: 0xFFE000), 80),   // 064-095 Yellow
            (RGB(hex: 0x8000FF), 112),  // 096-127 Purple
            (RGB(hex: 0x00FF30), 144),  // 128-159 Green
            (RGB(hex: 0xFF0000), 176),  // 160-191 Red
            (RGB(hex: 0x40C8FF), 208),  // 192-223 Light blue
            (RGB(hex: 0xFF8000), 240),  // 224-255 Orange
        ]),
    ]

    /// Closest wheel slot to a color (compares hue/saturation, ignoring brightness).
    func nearest(_ c: RGB) -> (color: RGB, value: UInt8) {
        let m = max(c.r, c.g, c.b)
        guard m > 0.001 else { return slots[0] }
        let n = RGB(r: c.r / m, g: c.g / m, b: c.b / m)
        return slots.min { a, b in dist(a.color, n) < dist(b.color, n) } ?? slots[0]
    }

    private func dist(_ a: RGB, _ b: RGB) -> Double {
        let dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b
        return dr * dr + dg * dg + db * db
    }
}

enum ChannelSpec: Equatable {
    case role(ChannelRole, head: Int)   // head is 0-based; single-head fixtures use 0
    case constant(UInt8)
    case strobeRange(open: UInt8, slow: UInt8, fast: UInt8)   // e.g. "S:5:8:215"
    case colorWheel(String)                                    // e.g. "CW:CHAUVET-FS75"

    /// Parses a layout string like "D,R,G,B,W,S" or "T,SPD,0,0,D,S,R1,G1,B1,W1,...".
    /// A number after a color letter (R1, G1 …) picks which head/pixel it belongs to.
    /// A bare number is a channel held at that fixed value.
    static func parse(_ layout: String) -> [ChannelSpec] {
        layout.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
            .map { token in
                if token.hasPrefix("S:") {
                    let n = token.dropFirst(2).split(separator: ":").compactMap { Int($0) }
                    if n.count == 3 {
                        return .strobeRange(open: UInt8(clamping: n[0]), slow: UInt8(clamping: n[1]), fast: UInt8(clamping: n[2]))
                    }
                }
                if token.hasPrefix("CW:") { return .colorWheel(String(token.dropFirst(3))) }
                if let v = Int(token) { return .constant(UInt8(clamping: v)) }
                if let r = ChannelRole(rawValue: token) { return .role(r, head: 0) }
                // split trailing digits: "R12" -> ("R", 12)
                let letters = String(token.prefix { !$0.isNumber })
                let digits = String(token.drop { !$0.isNumber })
                if let r = ChannelRole(rawValue: letters), let h = Int(digits), h >= 1 {
                    return .role(r, head: h - 1)
                }
                return .constant(0)
            }
    }

    static func headCount(_ specs: [ChannelSpec]) -> Int {
        var maxHead = 0
        for s in specs {
            if case .role(let r, let h) = s, [.red, .green, .blue, .white, .amber, .uv].contains(r) {
                maxHead = max(maxHead, h)
            }
        }
        return maxHead + 1
    }
}

/// A light model + mode. Built-ins live here; more can be added later.
struct FixtureProfile: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let layout: String
    let setupTip: String

    static let shehdsBeam38: FixtureProfile = {
        var parts = ["T", "SPD", "0", "0", "D", "S"]
        for h in 1...8 { parts += ["R\(h)", "G\(h)", "B\(h)", "W\(h)"] }
        return FixtureProfile(
            name: "SHEHDS LED Beam 8x12W RGBW — 38ch (each head separate)",
            layout: parts.joined(separator: ","),
            setupTip: "On the light's menu choose \"a001\" (38-channel mode) and set it to the start address shown here.")
    }()

    static let shehdsBeam9 = FixtureProfile(
        name: "SHEHDS LED Beam 8x12W RGBW — 9ch (all heads together)",
        layout: "T,SPD,0,0,D,R,G,B,W",
        setupTip: "On the light's menu choose \"addr\" (9-channel mode) and set it to the start address shown here. This mode has no strobe channel, so the app strobes it in software.")

    static let chauvetFollowspot75ST = FixtureProfile(
        name: "Chauvet DJ LED Followspot 75ST — 3ch",
        layout: "D,CW:CHAUVET-FS75,S:5:8:215",
        setupTip: "On the followspot, press FUNCTION SELECT until 001 shows, then use UP/DOWN to set the starting address shown here. Focus and iris are the knobs on the light itself; DMX controls brightness, the 8-color wheel and strobe.")

    static let all: [FixtureProfile] = [
        shehdsBeam38,
        shehdsBeam9,
        chauvetFollowspot75ST,
        FixtureProfile(name: "Generic RGB Par (3ch)", layout: "R,G,B", setupTip: ""),
        FixtureProfile(name: "Generic Dimmer + RGB (4ch)", layout: "D,R,G,B", setupTip: ""),
        FixtureProfile(name: "Generic RGBW Par (4ch)", layout: "R,G,B,W", setupTip: ""),
        FixtureProfile(name: "Generic Dimmer + RGBW + Strobe (6ch)", layout: "D,R,G,B,W,S", setupTip: ""),
        FixtureProfile(name: "Generic RGBWA+UV Par (6ch)", layout: "R,G,B,W,A,UV", setupTip: ""),
        FixtureProfile(name: "Generic Strobe (2ch)", layout: "D,S", setupTip: ""),
    ]

    static func named(_ name: String) -> FixtureProfile? { all.first { $0.name == name } }
}

struct Fixture: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var address: Int          // 1...512
    var profileName: String
    var layout: String        // channel layout, see ChannelSpec.parse
    var wheelFollowsShow: Bool? = nil   // color-wheel lights in Sequence mode: follow show colors (default) or stay white
    var behavior: LightBehavior? = nil
    var stationary: StationaryLook? = nil
    var outputKey: String? = nil        // which DMX device this light is wired to; nil = main device

    /// Spotlights (color-wheel lights) default to Stationary; everything else to Sequence.
    var effectiveBehavior: LightBehavior { behavior ?? (colorWheel != nil ? .stationary : .sequence) }
    var stationaryLook: StationaryLook { stationary ?? StationaryLook() }

    var channels: [ChannelSpec] { ChannelSpec.parse(layout) }
    var colorWheel: ColorWheel? {
        for c in channels { if case .colorWheel(let name) = c { return ColorWheel.wheels[name] } }
        return nil
    }
    var channelCount: Int { channels.count }
    var headCount: Int { ChannelSpec.headCount(channels) }
    var lastAddress: Int { address + max(channelCount, 1) - 1 }
    var isMover: Bool { channels.contains { if case .role(let r, _) = $0 { return r == .pan || r == .tilt }; return false } }
    var hasStrobeChannel: Bool {
        channels.contains {
            if case .role(.strobe, _) = $0 { return true }
            if case .strobeRange = $0 { return true }
            return false
        }
    }
    var profile: FixtureProfile? { FixtureProfile.named(profileName) }
}

/// What a fixture should be doing right now, independent of its channel layout.
struct FixtureState: Equatable {
    var intensity: Double = 0   // 0...1
    var color: RGB = .black
    var strobe: Double = 0      // 0 = off, else 0...1 speed
    var pan: Double = 0.5
    var tilt: Double = 0.5

    static let off = FixtureState()

    func blended(_ o: FixtureState, _ t: Double) -> FixtureState {
        FixtureState(intensity: intensity + (o.intensity - intensity) * t,
                     color: color.mix(o.color, t),
                     strobe: t < 0.5 ? strobe : o.strobe,
                     pan: pan + (o.pan - pan) * t,
                     tilt: tilt + (o.tilt - tilt) * t)
    }
}

// MARK: - Show content

enum LightEffect: String, CaseIterable, Codable, Identifiable {
    case steady = "Steady"
    case breathe = "Breathe"
    case pulse = "Beat Pulse"
    case kickFlash = "Kick Flash"
    case snareHit = "Snare Hit"
    case chase = "Chase"
    case alternate = "Alternate"
    case colorBeat = "Color per Beat"
    case rainbow = "Rainbow"
    case sparkle = "Hi-Hat Sparkle"
    case strobe = "Strobe"
    case blackout = "Blackout"
    var id: String { rawValue }
}

enum MoveEffect: String, CaseIterable, Codable, Identifiable {
    case none = "Hold"
    case sweep = "Sweep"
    case circle = "Circle"
    case fan = "Fan Out"
    case beatNod = "Beat Nod"
    case fullRotate = "Full Rotate"
    case flip = "Flip on Beat"
    var id: String { rawValue }
}

enum EnergyLevel: String, Codable, CaseIterable {
    case low = "Low", medium = "Medium", high = "High", drop = "Drop"
}

enum ShowStyle: String, CaseIterable, Codable, Identifiable {
    case club = "Club / EDM"
    case hiphop = "Hip-Hop / Trap"
    case pop = "Pop"
    case rock = "Rock"
    case chill = "Chill / R&B"
    case latin = "Latin / Reggaeton"
    var id: String { rawValue }
}

struct ShowSection: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var start: Double
    var end: Double
    var level: EnergyLevel
    var effect: LightEffect
    var palette: String
    var intensity: Double = 1.0
    var rate: Double = 1.0          // beats multiplier: 0.5 = half time, 2 = double time
    var movement: MoveEffect = .none
    var accentStrobe: Bool = false  // strobe hit on the first bar
    var colorShift: Int? = nil      // rotates the palette so repeated phrases look different
}

struct SongAnalysis: Codable {
    var duration: Double
    var bpm: Double
    var beats: [Double]
    var downbeatOffset: Int
    var frameRate: Double
    var energy: [Float]
    var bass: [Float]
    var mid: [Float]
    var high: [Float]
    var kicks: [Double]
    var snares: [Double]
    var hats: [Double]
    var detectedSections: [DetectedSection]
    var silences: [SilenceSpan]? = nil   // stretches with no music (start, gaps, end)
    var beatBase: Int? = nil             // live mode: global number of beats[0]

    func value(_ arr: [Float], at t: Double) -> Double {
        guard !arr.isEmpty else { return 0 }
        let i = min(max(Int(t * frameRate), 0), arr.count - 1)
        return Double(arr[i])
    }
}

struct SilenceSpan: Codable, Hashable {
    var start: Double
    var end: Double
}

struct DetectedSection: Codable, Hashable {
    var start: Double
    var end: Double
    var energy: Double
    var level: EnergyLevel
    var name: String
}

/// One generated (and possibly hand-tweaked) light show for a song.
struct LightShow: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var style: ShowStyle
    var variation: Int
    var sections: [ShowSection]
    var fixtureIDs: [UUID]? = nil   // lights linked to this show; nil = all lights

    func includes(_ fx: Fixture) -> Bool { fixtureIDs?.contains(fx.id) ?? true }
}

struct Song: Identifiable, Codable {
    var id = UUID()
    var title: String
    var path: String
    var artist: String? = nil
    var genre: ShowStyle?            // what you tagged it as (nil = use the suggestion)
    var syncOffsetMs: Double = 0     // positive = lights fire earlier
    var analysis: SongAnalysis?      // what the app learned
    var shows: [LightShow] = []
    var activeShowID: UUID?

    var url: URL { URL(fileURLWithPath: path) }
    var isLearned: Bool { analysis != nil }
    var artistName: String { (artist?.isEmpty == false) ? artist! : "Unknown Artist" }
    var displayName: String { artist?.isEmpty == false ? "\(artist!) — \(title)" : title }
    var activeShow: LightShow? { shows.first { $0.id == activeShowID } ?? shows.first }
    var activeShowIndex: Int? {
        if let id = activeShowID, let i = shows.firstIndex(where: { $0.id == id }) { return i }
        return shows.isEmpty ? nil : 0
    }
    var effectiveGenre: ShowStyle { genre ?? analysis?.suggestedStyle ?? .pop }
}

extension SongAnalysis {
    /// When the music actually starts (end of any silent lead-in).
    var musicStart: Double {
        if let s = silences?.first, s.start <= 0.05 { return min(s.end, duration) }
        return 0
    }
    /// When the music actually ends (start of any silent tail).
    var musicEnd: Double {
        if let s = silences?.last, s.end >= duration - 0.05, s.start > musicStart { return s.start }
        return duration
    }

    /// A best guess at the genre from tempo and how bass-heavy / bright / dynamic the song is.
    var suggestedStyle: ShowStyle {
        func avg(_ a: [Float]) -> Double { a.isEmpty ? 0 : Double(a.reduce(0, +)) / Double(a.count) }
        let bassAvg = avg(bass), highAvg = avg(high), energyAvg = avg(energy)
        let kickRate = Double(kicks.count) / max(duration, 1) * 60  // kicks per minute
        if energyAvg < 0.35 && bpm < 105 { return .chill }
        if bpm >= 118 && bpm <= 150 && kickRate > bpm * 0.6 && bassAvg > 0.45 { return .club }
        if bpm >= 160 && bpm <= 180 && bassAvg > 0.45 { return .club }          // drum & bass / dubstep feel
        if (bpm >= 70 && bpm < 112) && bassAvg > 0.5 { return .hiphop }
        if highAvg > 0.55 && energyAvg > 0.5 && kickRate < bpm * 0.6 { return .rock }
        if energyAvg < 0.4 { return .chill }
        return .pop
    }
}

// MARK: - Output settings

enum OutputKind: String, CaseIterable, Codable, Identifiable {
    case enttecPro = "Enttec DMX USB Pro (or compatible)"
    case openDMX = "Open DMX / FTDI cable"
    case artNet = "Art-Net (network node)"
    var id: String { rawValue }
}

struct OutputSettings: Codable, Equatable {
    var kind: OutputKind = .enttecPro
    var serialPath: String = ""
    var artNetIP: String = "255.255.255.255"
    var artNetUniverse: Int = 0
    var autoConnect: Bool = true
    var rememberedDevice: ArtNetNode? = nil   // the wireless box you paired with (main output)
    var extraDevices: [ArtNetNode]? = nil      // more wireless boxes, for lights wired to them
    var autoScan: Bool = true                  // keep looking for wireless devices in the background
}

// MARK: - Lineups

struct LineupEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var songID: UUID
    var showID: UUID?     // which saved show to run; nil = the song's current show
}

struct Lineup: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var entries: [LineupEntry] = []
    var gapSeconds: Double = 2     // idle look between songs
    var skipDeadAir: Bool? = nil   // start each song where the music starts, move on when it ends (default on)
}

// MARK: - Idle look (no music: before play, between songs, silences)

enum IdleMode: String, CaseIterable, Codable, Identifiable {
    case off = "Off (dark)"
    case solid = "Solid Color"
    case breathe = "Slow Breathe"
    case colorFade = "Slow Color Fade"
    var id: String { rawValue }
}

struct IdleLook: Codable, Equatable {
    var mode: IdleMode = .solid
    var color: RGB = RGB(hex: 0xB0001E)    // Red Velvet red
    var brightness: Double = 0.35
    var palette: String = "Red Velvet"     // used by Slow Color Fade
    var tilt: Double = 0.5

    func render(fixtures: [Fixture], time t: Double) -> [RenderedFixture] {
        var p = 0
        let total = max(1, fixtures.reduce(0) { $0 + $1.headCount })
        return fixtures.map { fx in
            var heads: [FixtureState] = []
            for _ in 0..<fx.headCount {
                let st: FixtureState
                switch mode {
                case .off:
                    st = .off
                case .solid:
                    st = FixtureState(intensity: brightness, color: color)
                case .breathe:
                    let k = 0.5 - 0.5 * cos(2 * .pi * t / 6)
                    st = FixtureState(intensity: brightness * (0.3 + 0.7 * k), color: color)
                case .colorFade:
                    let pal = Palette.named(palette)
                    let cp = t / 8 + Double(p) / Double(total)
                    let c = pal.color(Int(floor(cp))).mix(pal.color(Int(floor(cp)) + 1), cp - floor(cp))
                    st = FixtureState(intensity: brightness, color: c)
                }
                heads.append(st)
                p += 1
            }
            var rf = RenderedFixture(heads: heads)
            rf.tilt = tilt
            return rf
        }
    }
}

func blendRendered(_ a: [RenderedFixture], _ b: [RenderedFixture], _ k: Double) -> [RenderedFixture] {
    guard k > 0 else { return a }
    guard k < 1 else { return b }
    var out = a
    for f in out.indices where f < b.count {
        for h in out[f].heads.indices where h < b[f].heads.count {
            out[f].heads[h] = a[f].heads[h].blended(b[f].heads[h], k)
        }
        out[f].pan = a[f].pan + (b[f].pan - a[f].pan) * k
        out[f].tilt = a[f].tilt + (b[f].tilt - a[f].tilt) * k
        out[f].strobe = k < 0.5 ? a[f].strobe : b[f].strobe
    }
    return out
}

// MARK: - Rig: how multiple lights work together

enum RigMode: String, CaseIterable, Codable, Identifiable {
    case together = "Linked: move together"
    case mirror = "Linked: mirror each other"
    case independent = "Independent"
    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .together: return "All lights aim the same way at the same time, and effects like chases flow across every head as one long strip."
        case .mirror: return "Lights work as a pair: every other light moves and chases in the opposite direction, so the look is symmetrical."
        case .independent: return "Each light moves a little out of step with the others, for a looser, scattered look."
        }
    }
}

// MARK: - Sequence vs Stationary lights

enum LightBehavior: String, CaseIterable, Codable, Identifiable {
    case sequence = "Sequence"
    case stationary = "Stationary"
    var id: String { rawValue }
    var explanation: String {
        switch self {
        case .sequence: return "Follows the light show: colors, effects and movement change with the music."
        case .stationary: return "Holds the settings below for the whole show, like a spotlight on a performer."
        }
    }
}

struct StationaryLook: Codable, Hashable {
    var brightness: Double = 1
    var color: RGB = .white
    var strobe: Double = 0          // 0 = off
    var pan: Double = 0.5
    var tilt: Double = 0.5
    var onWhenIdle: Bool = true     // stay on before the show / between songs

    func render(_ fx: Fixture) -> RenderedFixture {
        var rf = RenderedFixture(heads: Array(repeating: FixtureState(intensity: brightness, color: color), count: fx.headCount))
        rf.strobe = strobe
        rf.pan = pan
        rf.tilt = tilt
        return rf
    }
}

// MARK: - Sessions (a complete setup you can save and recall)

struct Session: Identifiable, Codable {
    var id = UUID()
    var name: String
    var created = Date()
    var modified = Date()
    var fixtures: [Fixture]
    var lineups: [Lineup]
    var presets: [LookPreset]? = nil
    var idle: IdleLook = IdleLook()
    var rigMode: RigMode? = nil

    /// Your standard rig: two daisy-chained SHEHDS bars + the Chauvet followspot.
    static func standardRig() -> [Fixture] {
        [Fixture(name: "Beam Bar 1", address: 1, profileName: FixtureProfile.shehdsBeam38.name, layout: FixtureProfile.shehdsBeam38.layout),
         Fixture(name: "Beam Bar 2", address: 39, profileName: FixtureProfile.shehdsBeam38.name, layout: FixtureProfile.shehdsBeam38.layout),
         Fixture(name: "Followspot", address: 77, profileName: FixtureProfile.chauvetFollowspot75ST.name, layout: FixtureProfile.chauvetFollowspot75ST.layout)]
    }
}

// MARK: - Hands-on control of one light (from the Show screen's control panel)

struct ManualControl: Equatable {
    var dimmer: Double? = nil
    var color: RGB? = nil
    var strobe: Double? = nil
    var pan: Double? = nil
    var tilt: Double? = nil
    var isEmpty: Bool { dimmer == nil && color == nil && strobe == nil && pan == nil && tilt == nil }
}
