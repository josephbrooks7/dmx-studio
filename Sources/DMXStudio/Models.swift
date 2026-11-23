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
        // Themes
        Palette(id: "Deep Blue", colors: [RGB(hex: 0x0A1AFF), RGB(hex: 0x4B0FA8), RGB(hex: 0x002A6E), RGB(hex: 0x7A5CFF)]),
        Palette(id: "Aurora", colors: [RGB(hex: 0x00FF9C), RGB(hex: 0x00B3A4), RGB(hex: 0x6A3CFF), RGB(hex: 0x2EFF4F)]),
        Palette(id: "Rainbow", colors: [RGB(hex: 0xFF0000), RGB(hex: 0xFF8C00), RGB(hex: 0xFFE600), RGB(hex: 0x00E040), RGB(hex: 0x0070FF), RGB(hex: 0x9B00FF)]),
        Palette(id: "Fairy", colors: [RGB(hex: 0xFFB7E6), RGB(hex: 0xC9A0FF), RGB(hex: 0x9FFFE0), RGB(hex: 0xFFE9A0)]),
        Palette(id: "Fantasy", colors: [RGB(hex: 0x7A00FF), RGB(hex: 0x00D0A0), RGB(hex: 0xFFC040), RGB(hex: 0xFF40C0)]),
        Palette(id: "Galaxy", colors: [RGB(hex: 0x1A00FF), RGB(hex: 0x8A00FF), RGB(hex: 0xFF00C8), RGB(hex: 0x00C8FF)]),
        Palette(id: "Dragon", colors: [RGB(hex: 0xFF2000), RGB(hex: 0xFF8000), RGB(hex: 0xFFC000), RGB(hex: 0x8000FF)]),
        Palette(id: "EDM", colors: [RGB(hex: 0x00FF60), RGB(hex: 0x00E0FF), RGB(hex: 0xFF00E0), RGB.white]),
        Palette(id: "Dubstep", colors: [RGB(hex: 0x7CFF00), RGB(hex: 0x8000FF), RGB(hex: 0xFF0030), RGB.white]),
        Palette(id: "Techno", colors: [RGB.white, RGB(hex: 0xFF0010), RGB(hex: 0x3000FF), RGB.white]),
        Palette(id: "Red Room", colors: [RGB(hex: 0xFF0000), RGB(hex: 0xB00000), RGB(hex: 0xFF2A2A)]),
        Palette(id: "Rave", colors: [RGB(hex: 0xB0FF00), RGB(hex: 0xFF00FF), RGB(hex: 0x00FFFF), RGB(hex: 0x7A00FF)]),
        Palette(id: "Dance", colors: [RGB(hex: 0xFF2A8A), RGB(hex: 0xFFC400), RGB(hex: 0x00B2FF), RGB(hex: 0x9B30FF)]),
        Palette(id: "Disco", colors: [RGB(hex: 0xFFC000), RGB(hex: 0xFF00A0), RGB(hex: 0x00E5FF), RGB(hex: 0xFF6000), RGB.white]),
        Palette(id: "Pop Candy", colors: [RGB(hex: 0xFF4FA0), RGB(hex: 0x4FD0FF), RGB(hex: 0xFFE04F), RGB(hex: 0xB06BFF)]),
        Palette(id: "Lime Club", colors: [RGB(hex: 0x8ACE00), RGB.white, RGB(hex: 0xB8FF2A)]),
        Palette(id: "Psychedelic", colors: [RGB(hex: 0xFF5A00), RGB(hex: 0xFF0070), RGB(hex: 0x8C00FF), RGB(hex: 0xFFB000), RGB(hex: 0x00C0A0)]),
        Palette(id: "Gold", colors: [RGB(hex: 0xFFC34D), RGB(hex: 0xFFE7A0), RGB(hex: 0xFF9F1C), RGB.white]),
        Palette(id: "Christmas", colors: [RGB(hex: 0xFF0020), RGB(hex: 0x00C040), RGB(hex: 0xFFD060), RGB.white]),
    ]

    static func named(_ id: String) -> Palette { all.first { $0.id == id } ?? all[0] }
    static func exists(_ id: String) -> Bool { all.contains { $0.id == id } }

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
            setupTip: "On the light: MENU to C.hnd, ENTER, choose 38CH (every beam separate), ENTER. Then MENU to A.ddr, ENTER, set A.xxx to the address shown here (A.001 for address 1), ENTER. Don't use SL.nd (Auto/Sound/Slave). Chained bars on the same address mirror each other.")
    }()

    static let shehdsBeam9 = FixtureProfile(
        name: "SHEHDS LED Beam 8x12W RGBW — 9ch (all heads together)",
        layout: "T,SPD,0,0,D,R,G,B,W",
        setupTip: "On the light: MENU to C.hnd and choose 9CH (all 8 beams do the same thing), then A.ddr to A.xxx as shown here. For separate beams choose 38CH instead. No strobe channel in this mode, so the app strobes in software.")

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
    var stageX: Double? = nil           // position in the Stage simulation (0 = left, 1 = right)
    var stageY: Double? = nil           // (0 = top, 1 = bottom)
    var stageMount: StageMount? = nil
    var off: Bool? = nil                // switched off in the app (sends dark), nil/false = on
    var tiltSpeed: Double? = nil        // raw value for the light's tilt-speed channel (SHEHDS ch 2), nil = 0
    var moveLeadMs: Double? = nil       // send moves this early so the motor lands on the hit (nil = 300 ms)

    /// Spotlights (color-wheel lights) default to Stationary; everything else to Sequence.
    var isOn: Bool { off != true }
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

    /// What the light's own address display should show. SHEHDS bars: "A.001" is the address;
    /// the channel mode is the separate C.hnd menu (9CH or 38CH).
    var displayCode: String {
        let n = String(format: "%03d", address)
        if isShehdsBar { return "A.\(n)" }
        return n
    }
    /// SHEHDS bars: what the channel-mode menu must be set to.
    var shehdsModeCode: String? {
        if profileName == FixtureProfile.shehdsBeam38.name { return "38CH" }
        if profileName == FixtureProfile.shehdsBeam9.name { return "9CH" }
        return nil
    }
    /// What to set on the light itself so it matches the app (and gets the most control).
    var lightSettings: [(setting: String, value: String)] {
        let n = String(format: "%03d", address)
        if isShehdsBar {
            let mode = profileName == FixtureProfile.shehdsBeam38.name ? "38CH · every beam separate (most control)" : "9CH · all beams together"
            return [("C.hnd (channel mode)", mode),
                    ("A.ddr (address)", "A.\(n)"),
                    ("SL.nd (Auto, Soun, SL 1, SL 2)", "don't use: the bar would ignore the app"),
                    ("r.PAn (reverse tilt)", "no")]
        }
        if profileName == FixtureProfile.chauvetFollowspot75ST.name {
            return [("DMX address", "\(n) (3-channel)"),
                    ("Focus and iris", "by hand on the light")]
        }
        return [("DMX address", n), ("Channel mode", "\(channelCount) channels")]
    }
    /// A better mode the light offers (more control), if it isn't using it.
    var betterMode: String? {
        profileName == FixtureProfile.shehdsBeam9.name ? "Set C.hnd to 38CH on the light so all 8 beams can do their own thing" : nil
    }

    /// Channel mode shown in the app, e.g. "38CH" or "9CH".
    var modeLabel: String { shehdsModeCode ?? "\(channelCount)CH" }

    var isShehdsBar: Bool { profileName == FixtureProfile.shehdsBeam38.name || profileName == FixtureProfile.shehdsBeam9.name }
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
    case soundLevel = "Follows Sound"
    case blackout = "Blackout"
    // per-beam patterns (multi-head bars)
    case wave = "Wave"
    case centerOut = "Center Burst"
    case split = "Split Colors"
    case pixelPop = "Pixel Pop"
    case bounce = "Bounce"
    case gradient = "Color Gradient"
    case ripple = "Ripple"
    case scan = "Scanner"
    case fill = "Fill"
    case fire = "Fire"
    case embers = "Embers"
    case water = "Water Shimmer"
    case tide = "Ocean Tide"
    case magic = "Magic Dust"
    case aurora = "Aurora"
    case glitch = "Glitch"
    case shimmer = "Shimmer"
    case goldDust = "Gold Dust"
    // white accents
    case blinderHits = "Blinder Hits"     // color look, full white on the big drum hits
    case stutter = "Strobe Stutter"       // strobe chops that speed up across each bar
    case riseStrobe = "Rise & Strobe"     // a bar of solid flash, then a bar of strobe (pairs with Rise to Middle)
    var id: String { rawValue }
    /// Uses each beam of a bar separately.
    var perBeam: Bool { [.wave, .centerOut, .split, .pixelPop, .bounce, .gradient, .ripple, .scan, .fill, .fire, .embers, .water, .tide, .magic, .aurora, .glitch, .shimmer, .goldDust, .chase, .alternate, .rainbow, .sparkle, .colorBeat].contains(self) }
}

enum MoveEffect: String, CaseIterable, Codable, Identifiable {
    case none = "Hold"
    case sweep = "Sweep"
    case circle = "Circle"
    case fan = "Fan Out"
    case beatNod = "Beat Nod"
    case fullRotate = "Full Rotate"
    case flip = "Flip on Beat"
    case riseToMiddle = "Rise to Middle"   // from lying flat up to straight up over a bar, then hold a bar
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
    case electronic = "Electronic"
    case dubstep = "Dubstep / Bass"
    case techno = "Techno / Rave"
    case disco = "Dance / Disco"
    case hyperpop = "Hyperpop / Club Pop"
    case psychedelic = "Psychedelic / Indie"
    case fantasy = "Fairy / Fantasy"
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
    var accents: Double? = nil      // how much white blinder / strobe accent use (nil = 1, 0 = none)
    var empty: Bool? = nil          // removed on the timeline: an empty slot (idle look) waiting for a new look
    var transition: HitKind? = nil  // a short transition block: this hit, on top of the look before it
    var phase: Double? = nil        // 0…1: each head runs a little later than the one before (rolls across)
    var order: HeadOrder? = nil     // which way patterns run across the heads
    var fan: Double? = nil          // 0…1: spread the beams of the lights apart
    var beamSteps: [UInt8]? = nil   // beam sequencer: 16 steps, each a mask of which of the 8 heads are on
    var moveSize: Double? = nil     // 0…1: how far the heads swing (nil = full); small = a subtle drift around the aim
    var moveSpeed: Double? = nil    // movement speed (nil = 1; 0.25 = a quarter as fast), separate from the effect speed
    var aim: Double? = nil          // with movement Hold: where the heads point, 0…1 of the tilt (0.5 straight up, 1 = at the audience)
}

/// Ready-made beam sequencer patterns (16 steps × 8 heads, bit 0 = left head)
enum BeamPattern: String, CaseIterable, Identifiable {
    case chase = "Chase", bounce = "Bounce", alternate = "Alternate", centerOut = "Center Out", outsideIn = "Outside In",
         oddEven = "Odd / Even", pairs = "Pairs", fill = "Fill Up", random = "Random"
    var id: String { rawValue }
    var steps: [UInt8] {
        func bit(_ i: Int) -> UInt8 { UInt8(1 << (i & 7)) }
        switch self {
        case .chase: return (0..<16).map { bit($0 % 8) }
        case .bounce: return (0..<16).map { s in let p = s % 14; return bit(p < 8 ? p : 14 - p) }
        case .alternate: return (0..<16).map { $0 % 2 == 0 ? 0x0F : 0xF0 }
        case .centerOut: return (0..<16).map { s in let k = s % 4; return bit(3 - k) | bit(4 + k) }
        case .outsideIn: return (0..<16).map { s in let k = s % 4; return bit(k) | bit(7 - k) }
        case .oddEven: return (0..<16).map { $0 % 2 == 0 ? 0x55 : 0xAA }
        case .pairs: return (0..<16).map { s in let k = s % 4; return bit(2 * k) | bit(2 * k + 1) }
        case .fill: return (0..<16).map { s in UInt8((1 << ((s % 8) + 1)) - 1) }
        case .random: return [0x91, 0x24, 0x4A, 0x18, 0xC2, 0x05, 0x60, 0x89, 0x32, 0x44, 0x0C, 0xA1, 0x50, 0x86, 0x13, 0x68]
        }
    }
}

enum HeadOrder: String, Codable, CaseIterable, Identifiable {
    case forward = "Forward", backward = "Backward", symmetric = "Symmetric"
    var id: String { rawValue }
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
    var hits: [DrumHit]? = nil           // drum hits found on the separated drum part (type, time, confidence)
    var vocalPhrases: [TimeSpan]? = nil  // where someone is singing (from the separated vocals)
    var stemsFolder: String? = nil       // the separated parts (vocals/drums/bass/other .m4a)
    var accents: [Accent]? = nil         // white blinder hits / strobe stutters on the big moments
    var lyricCues: [LyricCue]? = nil     // lyric-driven cues in use (set from the song's lyrics + mode)
    var stemLevels: [String: [Float]]? = nil   // loudness (0…1, smoothed) of each separated part: vocals, drums, bass, other

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
    var builtFor: String? = nil      // lights + channel modes it was programmed for, e.g. "Beam Bar 1 · 38CH"
    var design: DesignBlend? = nil   // artist-inspired lighting mode(s) it was made with
    var hits: [ShowHit]? = nil       // short one-time transition hits placed on the timeline (on top of the blocks)

    func includes(_ fx: Fixture) -> Bool { fixtureIDs?.contains(fx.id) ?? true }
}

struct Song: Identifiable, Codable {
    var id = UUID()
    var title: String
    var path: String
    var artist: String? = nil
    var genre: ShowStyle?            // what you tagged it as (nil = use the suggestion)
    var peakGenre: ShowStyle?        // a different genre for the choruses / drops (nil = automatic)
    var syncOffsetMs: Double = 0     // positive = lights fire earlier
    var analysis: SongAnalysis?      // what the app learned
    var shows: [LightShow] = []
    var activeShowID: UUID?
    var detection: DetectionSettings? = nil   // per-song drum detection settings (nil = standard)
    var lyrics: Lyrics? = nil                 // words learned from the vocals (or pasted), timed to the song

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

    /// The most likely genre (see `genreScores` for the full list with confidences).
    /// When the guess is a near tie, a niche style (chill, hip-hop, latin…) isn't forced on the song:
    /// it falls back to Pop, the most general show, and the app says it isn't sure.
    var suggestedStyle: ShowStyle {
        let g = genreScores
        guard let top = g.first else { return .pop }
        if genreUnsure && ![.pop, .club, .electronic].contains(top.style) { return .pop }
        return top.style
    }
    /// A second genre for the big parts: an electronic / pop song where dubstep scores almost as high
    /// (half-time, heavy bass) gets dubstep looks in its choruses and drops.
    var suggestedPeakStyle: ShowStyle? {
        let g = genreScores
        guard let top = g.first, top.style != .dubstep,
              let dub = g.first(where: { $0.style == .dubstep }), dub.score >= 0.12, dub.score >= top.score * 0.55 else { return nil }
        return .dubstep
    }
    /// The top two genres are within a few percent, or the best one is weak.
    var genreUnsure: Bool {
        let g = genreScores
        guard g.count > 1 else { return false }
        return g[0].score < 0.26 || g[0].score - g[1].score < 0.04
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
    var universeAuto: Bool? = nil              // send on universes 0 AND 1 (default) so any PKnight setting works
    var alsoSendSACN: Bool? = nil              // also send sACN universe 1 (default on)
    var audioInputName: String? = nil          // what the beat tracker listens to (nil = system default input)

    var sendUniverses: [Int] {
        (universeAuto ?? true) ? Array(Set([0, 1, artNetUniverse])).sorted() : [artNetUniverse]
    }
}

// MARK: - Lineups

struct LineupEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var songID: UUID
    var showID: UUID?     // which saved show to run; nil = the song's current show
    // Blocks between songs (no song): silence or a built-in transition
    var block: SetBlockKind? = nil
    var seconds: Double? = nil
    var transition: TransitionStyle? = nil
    var palette: String? = nil
    var fadeMusic: Bool? = nil   // transitions: fade the song before out, and the next one in
    var waitForCue: Bool? = nil  // continuous sets: stop before this entry and wait for Space / →
    var autoFit: Bool? = nil     // transitions: size and place automatically over the outro / intro

    var isBlock: Bool { block != nil }
    var blockSeconds: Double { seconds ?? (block == .silence ? 5 : 8) }
    var blockLabel: String {
        switch block {
        case .silence: return "Silence · \(Int(blockSeconds)) s"
        case .transition: return "\(transition?.rawValue ?? "Transition") · \(Int(blockSeconds)) s"
        case nil: return ""
        }
    }

    static func silence(_ seconds: Double = 5) -> LineupEntry {
        LineupEntry(songID: UUID(), showID: nil, block: .silence, seconds: seconds, transition: .idle)
    }
    static func transition(_ style: TransitionStyle) -> LineupEntry {
        LineupEntry(songID: UUID(), showID: nil, block: .transition, seconds: style.defaultSeconds, transition: style,
                    palette: style.defaultPalette, fadeMusic: style.fadesMusicByDefault,
                    autoFit: style.fadesMusicByDefault ? true : nil)
    }
}

enum SetBlockKind: String, Codable, Hashable { case silence, transition }

/// How a set list moves from one song to the next.
enum SetPlayMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case continuous = "Continuous"
    case cued = "Cued"
    var id: String { rawValue }
    var help: String {
        switch self {
        case .continuous: return "Plays straight through: each song (and block) starts on its own"
        case .cued: return "You're in control: after each song the next one waits, ready, until you press Space or →"
        }
    }
}

/// Built-in transitions you can drop between songs in a set list.
enum TransitionStyle: String, CaseIterable, Codable, Identifiable, Hashable {
    case idle = "Idle Look"
    case blackout = "Blackout"
    case colorWash = "Color Wash"
    case sweep = "Light Sweep"
    case buildUp = "Build-Up"
    case strobeHit = "Strobe Hit"
    case whiteFlash = "Fade Through White"
    case rainbow = "Rainbow Spin"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .idle: return "moon.stars.fill"
        case .blackout: return "lightbulb.slash.fill"
        case .colorWash: return "paintbrush.fill"
        case .sweep: return "arrow.left.and.right"
        case .buildUp: return "arrow.up.right"
        case .strobeHit: return "bolt.fill"
        case .whiteFlash: return "sun.max.fill"
        case .rainbow: return "sparkles"
        }
    }
    var defaultSeconds: Double {
        switch self {
        case .strobeHit: return 3
        case .whiteFlash, .blackout: return 4
        case .buildUp: return 8
        default: return 6
        }
    }
    var defaultPalette: String? {
        switch self {
        case .colorWash: return "Ocean"
        case .sweep: return "Neon"
        case .buildUp: return "EDM"
        case .rainbow: return "Neon"
        default: return nil
        }
    }
    var fadesMusicByDefault: Bool { self != .strobeHit }
    var usesPalette: Bool { defaultPalette != nil }
    var blurb: String {
        switch self {
        case .idle: return "Your idle look"
        case .blackout: return "Fade to dark"
        case .colorWash: return "Slow color fades"
        case .sweep: return "A chase across the lights"
        case .buildUp: return "Speeds up and brightens, ends on a flash"
        case .strobeHit: return "A burst of strobe, then dark"
        case .whiteFlash: return "Up to bright white and back down"
        case .rainbow: return "Spinning rainbow"
        }
    }
}

struct Lineup: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var entries: [LineupEntry] = []
    var gapSeconds: Double = 2     // idle look between songs
    var skipDeadAir: Bool? = nil   // start each song where the music starts, move on when it ends (default on)
    var playMode: SetPlayMode? = nil   // continuous (default) or cued: wait for Space / → before each next song
    var mode: SetPlayMode { playMode ?? .continuous }
    /// Lights while a cued song waits for Space / →: "idle" (default), "dark", or a preset's name.
    var waitLook: String? = nil
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
    var stage: StageLayout? = nil

    /// Your standard rig: two daisy-chained SHEHDS bars (both set to A.001) + the Chauvet followspot.
    static func standardRig() -> [Fixture] {
        [Fixture(name: "Beam Bar 1", address: 1, profileName: FixtureProfile.shehdsBeam38.name, layout: FixtureProfile.shehdsBeam38.layout),
         Fixture(name: "Beam Bar 2", address: 1, profileName: FixtureProfile.shehdsBeam38.name, layout: FixtureProfile.shehdsBeam38.layout),
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

// MARK: - Stage simulation placement

enum StageMount: String, CaseIterable, Codable, Identifiable {
    case floor = "On the floor (beams up)"
    case hanging = "Hanging (beams down)"
    case upright = "Upright on a truss leg (beams sweep side to side)"
    case frontOfHouse = "Front of house (aims at the stage)"
    var id: String { rawValue }
}

// MARK: - 3D venue (saved with each session)

enum PropKind: String, CaseIterable, Codable, Identifiable {
    case stage = "Stage Platform"
    case truss = "Truss (straight)"
    case trussTower = "Truss Tower"
    case circleTruss = "Circle Truss"
    case lightStand = "Light Stand"
    case micStand = "Mic Stand"
    case speaker = "Speaker"
    case djBooth = "DJ Booth"
    case performer = "Performer"
    case trussFrame = "Truss Frame (box)"
    case ledWall = "LED Video Wall"
    case backdrop = "LED Backdrop (artist name)"
    case drumKit = "Drum Kit"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .stage: return "rectangle.fill"
        case .truss: return "line.3.horizontal"
        case .trussTower: return "building.columns"
        case .circleTruss: return "circle"
        case .lightStand: return "lamp.floor"
        case .micStand: return "mic"
        case .speaker: return "hifispeaker"
        case .djBooth: return "music.note.house"
        case .performer: return "person.fill"
        case .trussFrame: return "cube"
        case .ledWall: return "tv"
        case .backdrop: return "rectangle.inset.filled"
        case .drumKit: return "music.quarternote.3"
        }
    }
}

/// One thing in the venue: either a prop, or one of the session's lights.
struct StageItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var prop: PropKind? = nil
    var fixtureID: UUID? = nil
    var x: Double = 0          // meters, left/right (audience view)
    var z: Double = 0          // meters, + toward the audience
    var y: Double = 0          // height off the floor
    var rotation: Double = 0   // degrees around vertical
    var size: Double = 1       // length / scale
    var hanging: Bool = false  // lights: upside down on a truss
    var upright: Bool? = nil   // bars: standing on end (on a truss leg, with the foot brackets) — tilt sweeps side to side
    var onStand: Bool? = nil   // followspot: on its tripod (default) or just the light on its yoke
}

struct StageLayout: Codable, Hashable {
    var items: [StageItem] = []
    var haze: Double = 0.6

    /// Venues made before the LED backdrop: the circle truss (and the two narrow screens beside it) behind
    /// the performer become one wide LED backdrop that shows the artist's name.
    mutating func useBackdrop() {
        guard !items.contains(where: { $0.prop == .backdrop }),
              let ring = items.firstIndex(where: { $0.prop == .circleTruss && abs($0.x) < 1 }) else { return }
        let r = items[ring]
        items.removeAll { $0.prop == .ledWall && abs($0.z - r.z) < 0.5 && abs($0.x) < 3 }
        if let k = items.firstIndex(where: { $0.prop == .circleTruss && abs($0.x) < 1 }) {
            items[k].prop = .backdrop; items[k].size = 1
        }
    }

    /// A starter venue: stage, goal-post truss, LED backdrop, mic stand, performer — then your lights placed on it.
    static func starter(for fixtures: [Fixture]) -> StageLayout {
        var items: [StageItem] = [
            StageItem(prop: .stage, x: 0, z: -2, size: 1),
            StageItem(prop: .trussTower, x: -3.2, z: -3.6, size: 3.5),
            StageItem(prop: .trussTower, x: 3.2, z: -3.6, size: 3.5),
            StageItem(prop: .truss, x: 0, z: -3.6, y: 3.5, size: 6.7),
            StageItem(prop: .backdrop, x: 0, z: -3.9, y: 0.6, size: 1),
            StageItem(prop: .drumKit, x: -1.0, z: -2.9, y: 0.6),
            StageItem(prop: .micStand, x: 0, z: -0.8, y: 0.6),
            StageItem(prop: .performer, x: 0.45, z: -1.1, y: 0.6),
            StageItem(prop: .speaker, x: -3.6, z: 0.2),
            StageItem(prop: .speaker, x: 3.6, z: 0.2),
        ]
        var bar = 0
        for fx in fixtures {
            if fx.colorWheel != nil {
                items.append(StageItem(fixtureID: fx.id, x: 2.6, z: 4.5, y: 0, rotation: 0))
            } else {
                let side: Double = bar % 2 == 0 ? -1 : 1
                let row = Double(bar / 2)
                items.append(StageItem(fixtureID: fx.id, x: side * (1.9 + row * 0.2), z: -2.6 + row * 0.6, y: 0.6, rotation: 0))
                bar += 1
            }
        }
        return StageLayout(items: items)
    }
}


// MARK: - Transition hits (short one-time effects on top of the timeline blocks)

enum HitKind: String, Codable, CaseIterable, Identifiable {
    case flash = "White Flash"
    case doubleFlash = "Double Flash"
    case tripleFlash = "Triple Flash"
    case strobeBurst = "Strobe Burst"
    case stutter = "Stutter"
    case strobeRamp = "Strobe Ramp"
    case blinder = "Blinder"
    case paparazzi = "Paparazzi"
    case sweep = "Sweep Hit"
    case centerBurst = "Center Burst Hit"
    case splitFlash = "Split Flash"
    case sparkle = "Sparkle Burst"
    case chaseRun = "Chase Run"
    case colorPop = "Color Pop"
    case rainbowFlash = "Rainbow Flash"
    case blackout = "Blackout Drop"
    case fadeOut = "Fade Out"
    case fadeIn = "Fade In"
    case rise = "Quick Rise"
    case tiltSnap = "Tilt Snap"
    var id: String { rawValue }

    /// Builds up INTO its moment (ends on the block's end) instead of starting on it
    var buildsUp: Bool { self == .rise || self == .strobeRamp || self == .paparazzi }

    var icon: String {
        switch self {
        case .flash: return "bolt.fill"
        case .doubleFlash: return "2.circle.fill"
        case .tripleFlash: return "3.circle.fill"
        case .strobeBurst: return "bolt.horizontal.fill"
        case .stutter: return "bolt.circle.fill"
        case .strobeRamp: return "arrow.up.right.circle.fill"
        case .blinder: return "sun.max.fill"
        case .paparazzi: return "camera.fill"
        case .sweep: return "arrow.right.to.line"
        case .centerBurst: return "arrow.left.and.right"
        case .splitFlash: return "square.split.2x1"
        case .sparkle: return "sparkles"
        case .chaseRun: return "hare.fill"
        case .colorPop: return "paintpalette.fill"
        case .rainbowFlash: return "rainbow"
        case .blackout: return "moon.fill"
        case .fadeOut: return "arrow.down.right.circle"
        case .fadeIn: return "arrow.up.right.circle"
        case .rise: return "arrow.up.right"
        case .tiltSnap: return "arrow.up.to.line"
        }
    }
    var color: RGB {
        switch self {
        case .flash, .blinder, .doubleFlash, .tripleFlash, .paparazzi: return RGB(r: 1, g: 1, b: 1)
        case .strobeBurst, .stutter, .strobeRamp: return RGB(r: 0.85, g: 0.9, b: 1)
        case .sweep, .centerBurst, .splitFlash: return RGB(r: 0.7, g: 0.95, b: 1)
        case .sparkle, .chaseRun: return RGB(r: 1, g: 0.95, b: 0.6)
        case .blackout, .fadeOut: return RGB(r: 0.2, g: 0.2, b: 0.25)
        case .fadeIn: return RGB(r: 0.45, g: 0.45, b: 0.55)
        case .colorPop: return RGB(r: 1, g: 0.2, b: 0.6)
        case .rainbowFlash: return RGB(r: 0.6, g: 0.4, b: 1)
        case .rise: return RGB(r: 1, g: 0.75, b: 0.3)
        case .tiltSnap: return RGB(r: 0.5, g: 1, b: 0.6)
        }
    }
    /// Default length in beats
    var beats: Double {
        switch self {
        case .flash, .doubleFlash, .tripleFlash, .colorPop, .rainbowFlash, .blackout, .sweep, .centerBurst, .splitFlash, .tiltSnap: return 1
        case .strobeBurst, .stutter, .blinder, .sparkle, .chaseRun, .fadeOut, .fadeIn: return 2
        case .rise, .strobeRamp, .paparazzi: return 4
        }
    }
    var blurb: String {
        switch self {
        case .flash: return "one white flash that fades back"
        case .doubleFlash: return "two quick white hits"
        case .tripleFlash: return "three quick white hits"
        case .strobeBurst: return "fast white strobe"
        case .stutter: return "strobe chops on the beat grid"
        case .strobeRamp: return "strobes that speed up into the moment"
        case .blinder: return "full white, then fades"
        case .paparazzi: return "camera-flash pops on random heads, getting busier into the moment"
        case .sweep: return "a white band runs across the light"
        case .centerBurst: return "bursts from the middle outward"
        case .splitFlash: return "left half, then right half"
        case .sparkle: return "random heads sparkle"
        case .chaseRun: return "one bright dot runs across the heads"
        case .colorPop: return "a burst of the look's brightest color"
        case .rainbowFlash: return "every head a different color for a moment"
        case .blackout: return "all lights out, then back"
        case .fadeOut: return "dips to black"
        case .fadeIn: return "rises back up from black"
        case .rise: return "builds brighter and whiter into the moment"
        case .tiltSnap: return "the beams snap up, then fall back"
        }
    }
}

struct ShowHit: Identifiable, Codable, Hashable {
    var id = UUID()
    var time: Double
    var kind: HitKind
    var beats: Double
}
