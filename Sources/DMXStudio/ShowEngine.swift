import Foundation

// MARK: - Generator: learned analysis + genre -> editable light show

enum ShowGenerator {
    struct Look {
        var effect: LightEffect
        var rate: Double = 1
        var movement: MoveEffect = .none
        var accent: Bool = false
        var intensity: Double = 1
    }

    /// Palette families per genre. Variations rotate through these.
    static func palettes(for style: ShowStyle) -> [String] {
        switch style {
        case .club: return ["Neon", "Purple Haze", "Ocean", "Ice", "Red Velvet", "Sunset"]
        case .hiphop: return ["Red Velvet", "Purple Haze", "Fire", "Ice", "Sunset", "Neon"]
        case .pop: return ["Sunset", "Neon", "Ocean", "Ice", "Red Velvet", "Purple Haze"]
        case .rock: return ["Fire", "Red Velvet", "Full White", "Ice", "Purple Haze", "Warm White"]
        case .chill: return ["Purple Haze", "Ocean", "Warm White", "Sunset", "Red Velvet", "Forest"]
        case .latin: return ["Fire", "Sunset", "Forest", "Neon", "Red Velvet", "Ocean"]
        case .electronic: return ["EDM", "Galaxy", "Neon", "Ice", "Ocean", "Purple Haze"]
        case .dubstep: return ["Dubstep", "Rave", "Purple Haze", "Red Room", "Neon", "Ice"]
        case .techno: return ["Techno", "Red Room", "Full White", "Rave", "Ice", "Purple Haze"]
        case .disco: return ["Disco", "Dance", "Sunset", "Pop Candy", "Neon", "Warm White"]
        case .hyperpop: return ["Lime Club", "Pop Candy", "Full White", "Neon", "Rave", "Ice"]
        case .psychedelic: return ["Psychedelic", "Sunset", "Purple Haze", "Galaxy", "Fire", "Ocean"]
        case .fantasy: return ["Fairy", "Fantasy", "Galaxy", "Ice", "Dragon", "Purple Haze"]
        }
    }

    /// The "signature" look per genre (variation 1).
    static func signature(style: ShowStyle, level: EnergyLevel, isBuild: Bool) -> Look {
        if isBuild {
            switch style {
            case .chill, .fantasy, .psychedelic: return Look(effect: .breathe, movement: .sweep, intensity: 0.8)
            case .rock: return Look(effect: .snareHit, movement: .fan)
            case .dubstep: return Look(effect: .snareHit, rate: 2, movement: .beatNod, intensity: 0.9)
            case .disco: return Look(effect: .sparkle, rate: 2, movement: .circle, intensity: 0.9)
            default: return Look(effect: .chase, rate: 2, movement: .sweep, intensity: 0.9)
            }
        }
        switch (style, level) {
        case (.club, .low): return Look(effect: .breathe, movement: .sweep, intensity: 0.6)
        case (.club, .medium): return Look(effect: .pulse, movement: .sweep, intensity: 0.85)
        case (.club, .high): return Look(effect: .colorBeat, movement: .fan)
        case (.club, .drop): return Look(effect: .kickFlash, movement: .flip, accent: true)

        case (.hiphop, .low): return Look(effect: .steady, intensity: 0.5)
        case (.hiphop, .medium): return Look(effect: .kickFlash, movement: .sweep, intensity: 0.85)
        case (.hiphop, .high): return Look(effect: .alternate, movement: .fan)
        case (.hiphop, .drop): return Look(effect: .kickFlash, movement: .flip, accent: true)

        case (.pop, .low): return Look(effect: .breathe, movement: .sweep, intensity: 0.6)
        case (.pop, .medium): return Look(effect: .pulse, movement: .sweep, intensity: 0.85)
        case (.pop, .high): return Look(effect: .chase, movement: .fullRotate)
        case (.pop, .drop): return Look(effect: .rainbow, movement: .circle, accent: true)

        case (.rock, .low): return Look(effect: .steady, intensity: 0.5)
        case (.rock, .medium): return Look(effect: .kickFlash, movement: .sweep, intensity: 0.9)
        case (.rock, .high): return Look(effect: .alternate, movement: .beatNod)
        case (.rock, .drop): return Look(effect: .snareHit, movement: .beatNod, accent: true)

        case (.chill, .low): return Look(effect: .tide, rate: 0.5, movement: .none, intensity: 0.6)
        case (.chill, .medium): return Look(effect: .water, movement: .sweep, intensity: 0.8)
        case (.chill, .high): return Look(effect: .pulse, rate: 0.5, movement: .sweep, intensity: 0.85)
        case (.chill, .drop): return Look(effect: .colorBeat, rate: 0.5, movement: .circle)

        case (.latin, .low): return Look(effect: .breathe, movement: .sweep, intensity: 0.6)
        case (.latin, .medium): return Look(effect: .snareHit, movement: .fan, intensity: 0.85)  // dembow snare
        case (.latin, .high): return Look(effect: .colorBeat, movement: .beatNod)
        case (.latin, .drop): return Look(effect: .kickFlash, movement: .circle, accent: true)

        case (.electronic, .low): return Look(effect: .breathe, movement: .circle, intensity: 0.6)
        case (.electronic, .medium): return Look(effect: .chase, movement: .sweep, intensity: 0.85)
        case (.electronic, .high): return Look(effect: .colorBeat, movement: .fan)
        case (.electronic, .drop): return Look(effect: .kickFlash, rate: 2, movement: .fullRotate, accent: true)

        case (.dubstep, .low): return Look(effect: .breathe, rate: 0.5, movement: .sweep, intensity: 0.5)
        case (.dubstep, .medium): return Look(effect: .snareHit, movement: .fan, intensity: 0.85)     // half-time snare
        case (.dubstep, .high): return Look(effect: .pulse, rate: 2, movement: .beatNod)               // wobble
        case (.dubstep, .drop): return Look(effect: .kickFlash, movement: .flip, accent: true)

        case (.techno, .low): return Look(effect: .steady, intensity: 0.4)
        case (.techno, .medium): return Look(effect: .kickFlash, movement: .beatNod, intensity: 0.9)
        case (.techno, .high): return Look(effect: .glitch, movement: .sweep)
        case (.techno, .drop): return Look(effect: .kickFlash, movement: .fullRotate, accent: true)

        case (.disco, .low): return Look(effect: .shimmer, movement: .none, intensity: 0.6)
        case (.disco, .medium): return Look(effect: .colorBeat, movement: .circle, intensity: 0.85)
        case (.disco, .high): return Look(effect: .alternate, movement: .circle)
        case (.disco, .drop): return Look(effect: .rainbow, rate: 2, movement: .fullRotate, accent: true)

        case (.hyperpop, .low): return Look(effect: .pulse, movement: .sweep, intensity: 0.6)
        case (.hyperpop, .medium): return Look(effect: .kickFlash, movement: .fan, intensity: 0.9)
        case (.hyperpop, .high): return Look(effect: .glitch, movement: .fan)
        case (.hyperpop, .drop): return Look(effect: .kickFlash, movement: .beatNod, accent: true)

        case (.psychedelic, .low): return Look(effect: .aurora, rate: 0.5, movement: .none, intensity: 0.65)
        case (.psychedelic, .medium): return Look(effect: .rainbow, rate: 0.5, movement: .sweep, intensity: 0.8)
        case (.psychedelic, .high): return Look(effect: .colorBeat, rate: 0.5, movement: .circle)
        case (.psychedelic, .drop): return Look(effect: .rainbow, movement: .fullRotate)

        case (.fantasy, .low): return Look(effect: .magic, rate: 0.5, movement: .none, intensity: 0.7)
        case (.fantasy, .medium): return Look(effect: .aurora, movement: .sweep, intensity: 0.85)
        case (.fantasy, .high): return Look(effect: .magic, rate: 1, movement: .sweep)
        case (.fantasy, .drop): return Look(effect: .goldDust, rate: 2, movement: .sweep, accent: true)
        }
    }

    /// Pools of looks that suit each energy level; later variations pick from these.
    static func pool(level: EnergyLevel, style: ShowStyle) -> [Look] {
        let slow = style == .chill || style == .fantasy || style == .psychedelic
        switch level {
        case .low:
            return [Look(effect: .breathe, rate: slow ? 0.5 : 1, movement: .sweep, intensity: 0.55),
                    Look(effect: .steady, movement: .none, intensity: 0.5),
                    Look(effect: .sparkle, movement: .sweep, intensity: 0.7),
                    Look(effect: .breathe, rate: 0.5, movement: .circle, intensity: 0.6)]
        case .medium:
            return [Look(effect: .pulse, rate: slow ? 0.5 : 1, movement: .sweep, intensity: 0.85),
                    Look(effect: .kickFlash, movement: .fan, intensity: 0.85),
                    Look(effect: .snareHit, movement: .sweep, intensity: 0.85),
                    Look(effect: .chase, rate: slow ? 0.5 : 1, movement: .sweep, intensity: 0.85),
                    Look(effect: .sparkle, movement: .circle, intensity: 0.9)]
        case .high:
            return [Look(effect: .colorBeat, rate: slow ? 0.5 : 1, movement: .fan),
                    Look(effect: .alternate, movement: .beatNod),
                    Look(effect: .chase, rate: slow ? 1 : 2, movement: .sweep),
                    Look(effect: .kickFlash, movement: .circle),
                    Look(effect: .rainbow, rate: slow ? 0.5 : 1, movement: .fan),
                    Look(effect: .colorBeat, movement: .fullRotate)]
        case .drop:
            return [Look(effect: .kickFlash, movement: .beatNod, accent: true),
                    Look(effect: .colorBeat, rate: slow ? 1 : 2, movement: .fan, accent: true),
                    Look(effect: .rainbow, movement: .circle, accent: true),
                    Look(effect: .alternate, rate: slow ? 1 : 2, movement: .beatNod, accent: true),
                    Look(effect: .kickFlash, movement: .flip, accent: true)]
        }
    }

    /// Variation 1 = the genre's signature look. 2, 3, … mix it up but stay consistent
    /// within a show (every chorus gets the same look, every verse the same, etc.).
    /// Tailor a generated show to the lights it will run on: no movement without moving heads,
    /// and no chases or sparkles when there are only one or two light points to spread them across.
    static func fit(_ secs: inout [ShowSection], to lights: [Fixture]) {
        guard !lights.isEmpty else { return }
        func has(_ f: Fixture, _ roles: [ChannelRole]) -> Bool {
            f.channels.contains { if case .role(let r, _) = $0 { return roles.contains(r) }; return false }
        }
        let movers = lights.contains { $0.isMover }
        let canPan = lights.contains { has($0, [.pan]) }
        let mixesColor = lights.contains { has($0, [.red, .green, .blue]) }
        let wheelOnly = !mixesColor && lights.contains { $0.colorWheel != nil }
        let noColor = !mixesColor && !wheelOnly          // dimmer-only / white-only lights
        for i in secs.indices {
            // Move only where the music calls for it: quiet parts hold still, medium parts sweep gently,
            // big moves (flips, full swings) are saved for the high points.
            // Beams carry the show; tilting is an accent. Quiet and mid parts (verses, pre-choruses, builds)
            // hold still and let the beams cycle; choruses tilt only on every other phrase; drops move.
            let calm = ["Verse", "Pre-Chorus", "Build", "Intro", "Outro", "Breakdown", "Bridge", "Groove", "Break"].contains { secs[i].name.hasPrefix($0) }
            // Movement comes in steps, not all or nothing:
            //   still (hold at an angle) · subtle (a small, slow drift) · gentle (half the swing, half speed)
            //   · full (end to end, every phrase) · big (drops)
            // Soft parts are mostly still or subtle, and the amount changes from part to part.
            let isLift = secs[i].name.hasPrefix("Pre-Chorus") || secs[i].name.hasPrefix("Build")
            let holdAims = [0.62, 0.5, 0.78, 0.55, 0.7, 0.86]   // straight up to toward the crowd, never at the back
            let aimHere = holdAims[i % holdAims.count]
            func still() { secs[i].movement = .none; secs[i].aim = aimHere; secs[i].moveSize = nil; secs[i].moveSpeed = nil }
            func subtle() { secs[i].movement = .sweep; secs[i].aim = aimHere; secs[i].moveSize = 0.2; secs[i].moveSpeed = 0.25 }
            func gentle(_ m: MoveEffect) { secs[i].movement = m; secs[i].moveSize = 0.5; secs[i].moveSpeed = 0.5 }
            switch secs[i].level {
            case .low:
                if i % 3 == 1 { subtle() } else { still() }
            case .medium:
                if isLift { secs[i].movement = .riseToMiddle }
                else if secs[i].name.hasPrefix("Intro") || secs[i].name.hasPrefix("Outro") { if i % 2 == 0 { still() } else { subtle() } }
                else {
                    switch i % 3 { case 0: subtle(); case 1: gentle(.sweep); default: still() }
                }
            case .high:
                if isLift { secs[i].movement = .riseToMiddle }
                else if calm { gentle(i % 2 == 0 ? .sweep : .fan) }
                else if [.flip, .fullRotate, .beatNod].contains(secs[i].movement) || secs[i].movement == .none {
                    secs[i].movement = i % 2 == 0 ? .sweep : .fan
                    secs[i].moveSize = 0.85
                }
            case .drop:
                if secs[i].movement == .fullRotate || secs[i].movement == .none { secs[i].movement = .fan }
            }
            // Tilt-only bars (like the SHEHDS beam bars): moves that need pan become tilt moves
            if movers && !canPan {
                switch secs[i].movement {
                case .circle: secs[i].movement = .sweep
                default: break
                }
            }
            // A color wheel can't change color every beat or blend: hold colors, let brightness do the work
            if wheelOnly {
                switch secs[i].effect {
                case .colorBeat, .rainbow, .gradient, .split, .pixelPop, .wave: secs[i].effect = .pulse
                case .sparkle: secs[i].effect = .kickFlash
                default: break
                }
            }
            // No color at all: it's all brightness and strobe
            if noColor {
                switch secs[i].effect {
                case .colorBeat, .rainbow, .gradient, .split: secs[i].effect = .pulse
                default: break
                }
                secs[i].palette = "Full White"
            }
        }
        var seen = Set<String>(), points = 0
        for f in lights where seen.insert("\(f.address)|\(f.layout)|\(f.outputKey ?? "")").inserted { points += max(1, f.headCount) }
        for i in secs.indices {
            if !movers { secs[i].movement = .none }
            // Many beams: swap about half the all-together looks for per-beam patterns, so the bars
            // actually use their 8 separate heads (alternating keeps contrast between sections).
            // Bars with 8 separate beams (38CH): every section uses the beams individually,
            // with a mix of patterns so the song keeps changing.
            if points >= 6, secs[i].name != "Silence" {
                let v = i % 4
                switch secs[i].effect {
                case .pulse: secs[i].effect = [.wave, .ripple, .scan, .bounce][v]
                case .steady: secs[i].effect = [.wave, .gradient, .ripple, .wave][v]; secs[i].rate = min(secs[i].rate, 0.5)
                case .breathe: secs[i].effect = [.wave, .ripple, .wave, .gradient][v]; secs[i].rate = min(secs[i].rate, 0.5)
                case .kickFlash: secs[i].effect = [.centerOut, .fill, .scan, .ripple][v]
                case .snareHit: secs[i].effect = [.ripple, .bounce, .centerOut, .scan][v]
                case .colorBeat: secs[i].effect = [.scan, .chase, .fill, .pixelPop][v]
                case .chase: secs[i].effect = [.chase, .bounce, .scan, .chase][v]
                case .alternate: secs[i].effect = [.fill, .chase, .alternate, .ripple][v]
                case .soundLevel: secs[i].effect = .wave
                default: break
                }
            }
            if points <= 2 {
                switch secs[i].effect {
                case .chase, .rainbow: secs[i].effect = points == 2 ? .alternate : .colorBeat
                case .sparkle: secs[i].effect = .kickFlash
                case .alternate where points < 2: secs[i].effect = .pulse
                default: break
                }
            }
        }
    }

    /// `peakStyle`: a second genre for the big parts (choruses / drops), e.g. an electronic song with dubstep
    /// in the chorus: verses use the song's style, choruses and drops get dubstep looks.
    static func generate(_ a: SongAnalysis, style: ShowStyle, variation: Int, peakStyle: ShowStyle? = nil) -> [ShowSection] {
        let pals = palettes(for: style)
        let shift = max(0, variation - 1)
        var rng = SeededRandom(seed: UInt64(variation) &* 0x9E37_79B9_7F4A_7C15 &+ style.rawValue.utf8.reduce(UInt64(7)) { $0 &* 31 &+ UInt64($1) })
        // Decide one look per (level, build) up front so repeated sections match.
        var looks: [String: Look] = [:]
        // the genre of the part being built (a part can sound different from the song: a dubstep chorus
        // in an electronic song, a rap verse in a pop song)
        var partStyle: ShowStyle? = nil
        func lookFor(_ level: EnergyLevel, _ isBuild: Bool) -> Look {
            let style = (level == .high || level == .drop) && !isBuild ? (peakStyle ?? partStyle ?? style) : (partStyle ?? style)
            let key = "\(level.rawValue)\(isBuild)\(style.rawValue)"
            if let l = looks[key] { return l }
            var l: Look
            if variation <= 1 {
                l = signature(style: style, level: level, isBuild: isBuild)
            } else if isBuild {
                l = [Look(effect: .chase, rate: 2, movement: .sweep, intensity: 0.9),
                     Look(effect: .pulse, rate: 2, movement: .fan, intensity: 0.9),
                     Look(effect: .snareHit, movement: .sweep, intensity: 0.9)][rng.next(3)]
            } else {
                let p = pool(level: level, style: style)
                l = p[rng.next(p.count)]
            }
            looks[key] = l
            return l
        }

        // Bar start times, for splitting long sections into 8-bar phrases
        var barTimes: [Double] = []
        var bi = a.downbeatOffset
        while bi < a.beats.count { barTimes.append(a.beats[bi]); bi += 4 }

        // A second look per level, used on alternating phrases so long sections keep moving
        var altLooks: [String: Look] = [:]
        func altFor(_ level: EnergyLevel, _ base: Look) -> Look {
            let key = level.rawValue
            if let l = altLooks[key] { return l }
            let options = pool(level: level, style: style).filter { $0.effect != base.effect }
            var l = options.isEmpty ? base : options[rng.next(options.count)]
            l.accent = false
            l.intensity = base.intensity
            altLooks[key] = l
            return l
        }

        var out: [ShowSection] = []
        for d in ShowGenerator.edmNamed(a.detectedSections, style: style) {
            if d.name == "Silence" {
                // A short break inside the song: keep the sequence going (repeat the section before)
                let inside = d.start > a.musicStart + 1 && d.end < a.musicEnd - 1
                if inside && d.end - d.start < 2.5, !out.isEmpty {
                    out[out.count - 1].end = d.end
                    continue
                }
                // Real silence: lights rest on the idle look
                out.append(ShowSection(name: "Silence", start: d.start, end: d.end, level: .low,
                                       effect: .blackout, palette: pals[0], intensity: 1))
                continue
            }
            let isBuild = d.name.hasPrefix("Build") || d.name.hasPrefix("Pre-Chorus")
            partStyle = ShowGenerator.partGenre(a, d, songStyle: style)
            // a bridge gets a contrasting look; everything else keeps one look per kind of part
            let l = d.name.hasPrefix("Bridge") ? altFor(d.level, lookFor(d.level, false)) : lookFor(d.level, isBuild)
            let levelSlot: Int
            switch d.level {
            case .high: levelSlot = 0
            case .medium: levelSlot = 1
            case .low: levelSlot = 2
            case .drop: levelSlot = 3
            }
            let pal = pals[(levelSlot + shift) % pals.count]

            // Changes inside a part: where the music itself gets louder or quieter (so a part that was named
            // wrong, or a build / break that was missed, still changes when the music does), and otherwise
            // every 8 bars in parts of 12+ bars, so a long part never sits on one look.
            let inner = barTimes.filter { $0 > d.start + 0.1 && $0 < d.end - 0.1 }
            let barLen = barTimes.count > 1 ? (barTimes.last! - barTimes.first!) / Double(barTimes.count - 1) : 2.0
            func barLoud(_ from: Double, _ to: Double) -> Double {
                let fps = a.frameRate
                let s = max(0, Int(from * fps)), e = min(a.energy.count, max(s + 1, Int(to * fps)))
                guard e > s else { return 0 }
                return Double(a.energy[s..<e].reduce(0, +)) / Double(e - s)
            }
            let songLoud = barLoud(a.musicStart, a.musicEnd)
            var cuts: [Double] = []
            if !isBuild && inner.count >= 3 {
                let pts = [d.start] + inner + [d.end]
                // a 2-bar window before and after each bar line: a big change in loudness is a new part
                var last = d.start
                for j in 2..<(pts.count - 2) {
                    let before = barLoud(pts[j - 2], pts[j]), after = barLoud(pts[j], pts[j + 2])
                    let change = abs(after - before) / max(songLoud, 1e-6)
                    if change > 0.35, pts[j] - last >= 4 * (barLen > 0 ? barLen : 2), d.end - pts[j] >= 2 * (barLen > 0 ? barLen : 2) {
                        cuts.append(pts[j]); last = pts[j]
                    }
                }
            }
            if inner.count + 1 >= 12 && !isBuild {
                var k = 8
                while k < inner.count - 3 {
                    let t = inner[k - 1]
                    if !cuts.contains(where: { abs($0 - t) < 3.5 * (barLen > 0 ? barLen : 2) }) { cuts.append(t) }
                    k += 8
                }
            }
            cuts.sort()
            let edges = [d.start] + cuts + [d.end]
            let secLoud = barLoud(d.start, d.end)
            for p in 0..<(edges.count - 1) {
                // a stretch much louder or quieter than the rest of the part gets the look for that energy
                let here = barLoud(edges[p], edges[p + 1])
                let rel = (here - secLoud) / max(songLoud, 1e-6)
                let lvl: EnergyLevel = rel > 0.3 ? (d.level == .low ? .medium : .high) : rel < -0.3 ? (d.level == .high || d.level == .drop ? .medium : .low) : d.level
                // same energy: same effect, the color moves on (the big changes are saved for the part changes)
                let look = lvl != d.level ? altFor(lvl, lookFor(lvl, false)) : l
                out.append(ShowSection(name: p == 0 ? d.name : "\(d.name) ·\(p + 1)",
                                       start: edges[p], end: edges[p + 1], level: lvl,
                                       effect: look.effect, palette: pal, intensity: look.intensity,
                                       rate: look.rate, movement: look.movement,
                                       accentStrobe: p == 0 && look.accent,
                                       colorShift: p == 0 ? nil : p))
            }
        }
        return out
    }
}

/// Small deterministic RNG so a given variation always produces the same show.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xDEADBEEF : seed }
    mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func next(_ upper: Int) -> Int { Int(nextUInt64() % UInt64(max(upper, 1))) }
}

// MARK: - Renderer: time -> what every head should look like

struct RenderedFixture: Equatable {
    var heads: [FixtureState]
    var pan: Double = 0.5
    var tilt: Double = 0.5
    var strobe: Double = 0   // 0 = off
}

struct ShowRenderer {
    /// Fastest flashing allowed (flashes per second). 0 = no flashing at all; 3 = gentle (the default,
    /// within photosensitivity guidance); higher only when the user turns on fast strobes.
    static var maxFlashHz: Double = 3

    let analysis: SongAnalysis
    let sections: [ShowSection]
    let fixtures: [Fixture]
    var idle: IdleLook = IdleLook()
    var rig: RigMode = .together
    var hits: [ShowHit] = []        // transition hits placed on the timeline

    /// Show + automatic fade to the idle look wherever the song is silent.
    func renderWithIdle(at t: Double) -> [RenderedFixture] {
        // an empty slot on the timeline (block removed, nothing put there yet): the idle look
        if let s = sections.last(where: { $0.start <= t }), s.empty == true, t < s.end {
            return idle.render(fixtures: fixtures, time: t)
        }
        let k = silenceAmount(t)
        if k >= 1 { return idle.render(fixtures: fixtures, time: t) }
        let show = render(at: t)
        if k <= 0 { return show }
        return blendRendered(show, idle.render(fixtures: fixtures, time: t), k)
    }

    /// 0 = music, 1 = silence. Fades out over 0.5 s, and since the whole song is known
    /// ahead of time, fades back in so the lights hit right as the music returns.
    func silenceAmount(_ t: Double) -> Double {
        if t < 0 || t > analysis.duration { return 1 }
        for s in analysis.silences ?? [] where t >= s.start && t <= s.end {
            // short breaks inside the song don't stop the lights
            let inside = s.start > analysis.musicStart + 1 && s.end < analysis.musicEnd - 1
            if inside && s.end - s.start < 2.5 { continue }
            let fadeOut = s.start <= 0.01 ? 1 : (t - s.start) / 0.5
            let fadeIn = s.end >= analysis.duration - 0.01 ? 1 : (s.end - t) / 0.15
            return max(0, min(1, fadeOut, fadeIn))
        }
        return 0
    }

    fileprivate struct Ctx {
        var t: Double
        var beatPos: Double
        var beatLen: Double
        var sinceKick: Double, kickIndex: Int
        var sinceSnare: Double
        var sinceHat: Double, hatIndex: Int
        var energy: Double, bass: Double, high: Double
        var rate: Double = 1
        var vocal: Double = 0, drums: Double = 0.7, bassPart: Double = 0.5, otherPart: Double = 0.5
        var hasStems = false
    }

    func render(at t: Double) -> [RenderedFixture] {
        let ctx = context(t)
        guard let si0 = sections.lastIndex(where: { $0.start <= t }) ?? (sections.isEmpty ? nil : 0) else {
            return fixtures.map { RenderedFixture(heads: Array(repeating: .off, count: $0.headCount)) }
        }
        var si = si0
        // a short break merged away still points at the section before it
        while si > 0 && sections[si].name == "Silence" && sections[si].end - sections[si].start < 2.5
                && sections[si].start > analysis.musicStart + 1 { si -= 1 }
        let sec = sections[si]
        let next = si + 1 < sections.count ? sections[si + 1] : nil
        var out = renderSection(sec, ctx, next: next)
        shapeAcrossHeads(&out, sec, t: t, ctx: ctx, next: next)
        // Brightness follows the song: verses lower, builds rise, choruses/drops brightest
        let dyn = dynamics(at: t, si: si, ctx: ctx)
        if dyn < 0.999 {
            for f in out.indices { for h in out[f].heads.indices { out[f].heads[h].intensity *= dyn } }
        }
        // The separated parts shape it: singing calms the movement, sustained bass makes the look breathe,
        // the drum part's loudness sets how hard the beat hits
        if ctx.hasStems { shapeByParts(&out, ctx, sec) }
        // Crossfade into a new section: a beat-long fade, except a drop hits right away
        let xf = sec.level == .drop ? 0.05 : max(0.35, ctx.beatLen)
        if si > 0, t - sec.start < xf {
            var prev = renderSection(sections[si - 1], ctx, next: sec)
            let pd = Self.levelBrightness(sections[si - 1])
            for f in prev.indices { for h in prev[f].heads.indices { prev[f].heads[h].intensity *= pd } }
            let k = max(0, (t - sec.start) / xf)
            for f in out.indices {
                for h in out[f].heads.indices {
                    out[f].heads[h] = prev[f].heads[h].blended(out[f].heads[h], k)
                }
                out[f].pan = prev[f].pan + (out[f].pan - prev[f].pan) * k
                out[f].tilt = prev[f].tilt + (out[f].tilt - prev[f].tilt) * k
            }
        }
        applyLyricCues(&out, t: t)
        applyAccents(&out, t: t, beatLen: ctx.beatLen)
        applyHits(&out, t: t, beatLen: ctx.beatLen)
        return out
    }

    /// Transition hits you placed: short one-time effects on top of whatever block is playing
    private func applyHits(_ out: inout [RenderedFixture], t: Double, beatLen: Double) {
        let bl = max(beatLen, 0.05)
        // transition blocks on the timeline are hits that last their block (a rise builds into its end)
        let fromBlocks: [ShowHit] = sections.compactMap { s in
            s.transition.map { k in ShowHit(time: k.buildsUp ? s.end : s.start, kind: k, beats: max(0.25, (s.end - s.start) / bl)) }
        }
        for hit in hits + fromBlocks {
            let len = hit.beats * bl
            // a rise builds into its moment; everything else starts at it
            let start = hit.kind.buildsUp ? hit.time - len : hit.time
            guard t >= start - 0.001 && t < start + len else { continue }
            let dt = t - start, frac = dt / max(len, 0.01)
            func all(_ body: (inout FixtureState) -> Void) {
                for f in out.indices { for h in out[f].heads.indices { body(&out[f].heads[h]) } }
            }
            let gentle = Self.maxFlashHz <= 0
            // every head with its place along the rig (0 = far left, 1 = far right)
            let total = max(1, out.reduce(0) { $0 + $1.heads.count })
            func each(_ body: (inout FixtureState, Double, Int) -> Void) {
                var n = 0
                for f in out.indices { for h in out[f].heads.indices {
                    body(&out[f].heads[h], total > 1 ? Double(n) / Double(total - 1) : 0.5, n); n += 1
                } }
            }
            /// a quick white hit with a soft decay
            func pulse(_ since: Double) -> Double { since < 0 ? 0 : min(1, since / 0.02) * exp(-since / 0.09) }
            /// n flashes across the hit, if the flash limit allows that speed; otherwise one soft flash
            func flashes(_ n: Int) {
                let spacing = len / Double(n)
                if gentle || 1 / spacing > Self.maxFlashHz {
                    let k = (gentle ? 0.5 : 0.9) * exp(-dt / 0.25)
                    all { $0.color = $0.color.mix(.white, k); $0.intensity = max($0.intensity, k) }
                } else {
                    let since = dt - floor(dt / spacing) * spacing
                    let k = pulse(since)
                    all { $0.color = $0.color.mix(.white, k); $0.intensity = max($0.intensity, k) }
                }
            }
            switch hit.kind {
            case .paparazzi:
                // camera flashes: single heads pop at random, more and more of them into the moment
                let step = Int(dt / (bl / 4))
                let since = dt - Double(step) * (bl / 4)
                let chance = UInt64(2 + Int(frac * 6))           // 2/16 of the heads → 8/16 near the end
                let k = (gentle ? 0.5 : 1) * pulse(since)
                each { s, _, n in
                    var x = UInt64(truncatingIfNeeded: (n &* 2246822519) ^ (step &* 3266489917) ^ Int(hit.time * 977))
                    x ^= x >> 15; x = x &* 0xBF58476D1CE4E5B9; x ^= x >> 31
                    guard x % 16 < chance else { s.intensity *= 0.7; return }
                    s.color = s.color.mix(.white, k); s.intensity = max(s.intensity, k)
                }
            case .doubleFlash: flashes(2)
            case .tripleFlash: flashes(3)
            case .strobeRamp:
                // like a rise, with strobes that speed up (quarter notes → 16ths) into the moment
                let div: Double = frac < 0.5 ? 1 : frac < 0.75 ? 2 : 4
                guard let on = gate(dt / bl, div: div, beatLen: bl) else {
                    all { $0.color = $0.color.mix(.white, frac * 0.6); $0.intensity = max($0.intensity, 0.4 + 0.6 * frac) }
                    continue
                }
                all { s in if on { s.color = s.color.mix(.white, 0.5 + 0.4 * frac); s.intensity = 1 } else { s.intensity *= 0.15 } }
            case .sweep, .chaseRun:
                // a band running left → right across all the heads
                let width = hit.kind == .sweep ? 0.22 : 0.08
                let center = -width + frac * (1 + 2 * width)
                each { s, pos, _ in
                    let k = max(0, 1 - abs(pos - center) / width) * (gentle ? 0.6 : 1)
                    let c: RGB = hit.kind == .sweep ? .white : s.color.mix(.white, 0.4)
                    s.color = s.color.mix(c, k); s.intensity = max(s.intensity * (hit.kind == .chaseRun ? 0.35 : 1), k)
                }
            case .centerBurst:
                let radius = frac * 0.6
                each { s, pos, _ in
                    let d = abs(pos - 0.5)
                    let k = max(0, 1 - abs(d - radius) / 0.15) * (1 - frac * 0.5) * (gentle ? 0.6 : 1)
                    s.color = s.color.mix(.white, k); s.intensity = max(s.intensity, k)
                }
            case .splitFlash:
                let leftHalf = frac < 0.5
                let since = leftHalf ? dt : dt - len / 2
                let k = (gentle ? 0.5 : 1) * pulse(since) * 1.0
                each { s, pos, _ in
                    guard (pos < 0.5) == leftHalf else { return }
                    s.color = s.color.mix(.white, k); s.intensity = max(s.intensity, k)
                }
            case .sparkle:
                // random heads, a new set every 16th note
                let step = Int(dt / (bl / 4))
                each { s, _, n in
                    var x = UInt64(truncatingIfNeeded: (n &* 2654435761) ^ (step &* 40503) ^ Int(hit.time * 1000))
                    x ^= x >> 13; x = x &* 0x9E3779B97F4A7C15; x ^= x >> 29
                    guard x % 3 == 0 else { return }
                    let k = (gentle ? 0.5 : 1) * (1 - frac * 0.4)
                    s.color = s.color.mix(.white, k); s.intensity = max(s.intensity, k)
                }
            case .rainbowFlash:
                let k = min(1, dt / 0.03) * exp(-max(0, dt - 0.03) / 0.35) * (gentle ? 0.6 : 1)
                each { s, pos, _ in
                    let h = pos * 6, i = Int(h) % 6, f = h - floor(h)
                    let rgb: RGB = [RGB(r: 1, g: f, b: 0), RGB(r: 1 - f, g: 1, b: 0), RGB(r: 0, g: 1, b: f),
                                    RGB(r: 0, g: 1 - f, b: 1), RGB(r: f, g: 0, b: 1), RGB(r: 1, g: 0, b: 1 - f)][i]
                    s.color = s.color.mix(rgb, k); s.intensity = max(s.intensity, k)
                }
            case .fadeOut:
                let k = frac
                all { $0.intensity *= (1 - k) }
            case .fadeIn:
                let k = 1 - frac
                all { $0.intensity *= (1 - k) }
            case .tiltSnap:
                // beams snap up, then ease back to where the look has them
                let k = dt < 0.08 ? 1 : exp(-(dt - 0.08) / max(0.1, len * 0.4))
                for f in out.indices { out[f].tilt = out[f].tilt + (0.0 - out[f].tilt) * k }
                all { $0.intensity = max($0.intensity, 0.6 * k + $0.intensity * (1 - k)) }
            case .flash, .blinder:
                let decay = hit.kind == .flash ? 0.16 : 0.45
                let hold = hit.kind == .blinder ? min(0.25, len * 0.3) : 0
                var k = dt < hold ? 1 : exp(-(dt - hold) / decay)
                if gentle { k *= 0.6 }
                all { $0.color = $0.color.mix(.white, k); $0.intensity = max($0.intensity, k) }
            case .strobeBurst, .stutter:
                guard let on = gate(dt / bl, div: hit.kind == .strobeBurst ? 4 : 2, beatLen: bl) else {
                    all { $0.color = $0.color.mix(.white, 0.5 * (1 - frac)); $0.intensity = max($0.intensity, 1 - frac) }
                    continue
                }
                all { s in if on { s.color = s.color.mix(.white, 0.9); s.intensity = 1 } else { s.intensity *= 0.05 } }
            case .blackout:
                let k = frac < 0.85 ? 1 : (1 - frac) / 0.15
                all { $0.intensity *= (1 - k) }
            case .colorPop:
                let k = min(1, dt / 0.04) * exp(-max(0, dt - 0.04) / 0.3)
                all { s in
                    let c = s.color
                    let brightest = max(c.r, max(c.g, c.b), 0.01)
                    let pop = RGB(r: c.r / brightest, g: c.g / brightest, b: c.b / brightest)
                    s.color = c.mix(pop, k); s.intensity = max(s.intensity, k)
                }
            case .rise:
                all { $0.color = $0.color.mix(.white, frac * 0.6); $0.intensity = max($0.intensity, 0.4 + 0.6 * frac) }
            }
        }
    }

    private func shapeByParts(_ out: inout [RenderedFixture], _ c: Ctx, _ sec: ShowSection) {
        let quiet = sec.level == .low || sec.level == .medium
        // vocals: while someone sings in a calmer part, movement narrows toward the centre (focus on the singer)
        let calm = quiet ? 0.45 * c.vocal : 0.15 * c.vocal
        // bass: a slow breathing of brightness with the bass part (not a flash per note)
        let breathe = 0.88 + 0.12 * c.bassPart
        // drums: a quiet drum part = softer beat hits (dark beams stay dark)
        let hit = 0.8 + 0.2 * c.drums
        for f in out.indices {
            out[f].pan = 0.5 + (out[f].pan - 0.5) * (1 - calm)
            out[f].tilt = 0.5 + (out[f].tilt - 0.5) * (1 - calm)
            for h in out[f].heads.indices {
                let i = out[f].heads[h].intensity
                out[f].heads[h].intensity = min(1, max(0, i * hit * breathe))
            }
        }
    }

    /// How much the lyrics may steer the look (set in the Lyrics panel).
    static var lyricWeights = LyricLighting.Weights.current

    /// Lyric cues tint and shape the section look (they never replace it): a feeling colors the line,
    /// imagery words get a short swell, delivery makes it brighter or softer.
    private func applyLyricCues(_ out: inout [RenderedFixture], t: Double) {
        guard let cues = analysis.lyricCues, !cues.isEmpty else { return }
        let w = Self.lyricWeights
        for c in cues where t >= c.start - 0.35 && t < c.end + 0.7 {
            let env: Double
            if c.accent {
                let dt = t - c.start
                env = dt < 0 ? 0 : min(1, dt / 0.08) * exp(-max(0, dt - 0.08) / 0.4)
            } else {
                let fin = min(1, max(0, (t - c.start + 0.35) / 0.35))
                let fout = min(1, max(0, (c.end + 0.7 - t) / 0.7))
                env = fin * fout
            }
            let weight = c.kind == "Emotion" ? w.emotion : c.kind == "Imagery" ? w.imagery : w.delivery
            let k = env * weight
            guard k > 0.001 else { continue }
            for f in out.indices {
                for h in out[f].heads.indices {
                    if let col = c.color { out[f].heads[h].color = out[f].heads[h].color.mix(col, min(1, c.amount * k)) }
                    var inten = out[f].heads[h].intensity * (1 + c.intensity * k)
                    if c.accent && c.intensity > 0 { inten = max(inten, 0.85 * k) }
                    out[f].heads[h].intensity = min(1, max(0, inten))
                }
            }
        }
    }

    /// Strobe gate on the beat grid: true = flash on. nil = flashing isn't allowed.
    /// Slows to half/quarter speed if the chosen speed is faster than the flashing limit.
    func gate(_ beatsIn: Double, div: Double, beatLen: Double) -> Bool? {
        guard Self.maxFlashHz > 0 else { return nil }
        var d = div
        while d / max(beatLen, 0.05) > min(10, Self.maxFlashHz) { d /= 2 }
        let ph = (beatsIn * d).truncatingRemainder(dividingBy: 1)
        return ph < 0.4
    }

    /// White accents on top of the color look (they never replace it: they flash and hand back).
    private func applyAccents(_ out: inout [RenderedFixture], t: Double, beatLen: Double) {
        guard let acc = analysis.accents, !acc.isEmpty else { return }
        for a in acc where t >= a.start - 0.001 && t < a.end {
            // the lighting mode decides how much accent use a part gets (Atmospheric: little, Club: lots)
            let amount = sections.last(where: { $0.start <= a.start + 0.01 })?.accents ?? 1
            if amount < 0.25 || (a.kind != .blinder && a.kind != .swell && amount < 0.6) { continue }
            switch a.kind {
            case .blinder:
                let dt = t - a.start
                let soft = Self.maxFlashHz <= 0
                let k = soft ? 0.6 * exp(-dt / 0.3) : exp(-dt / 0.13)
                for f in out.indices {
                    for h in out[f].heads.indices {
                        out[f].heads[h].color = out[f].heads[h].color.mix(.white, k)
                        out[f].heads[h].intensity = max(out[f].heads[h].intensity, k)
                    }
                }
            case .swell:
                // a single swell of white on the hit: fast rise, then fades back into the color
                let dt = t - a.start
                let rise = min(1, dt / 0.05)
                var k = rise * exp(-max(0, dt - 0.05) / 0.32) * 0.8
                if Self.maxFlashHz <= 0 { k *= 0.6 }
                for f in out.indices {
                    for h in out[f].heads.indices {
                        out[f].heads[h].color = out[f].heads[h].color.mix(.white, k)
                        out[f].heads[h].intensity = max(out[f].heads[h].intensity, k)
                    }
                }
            case .stutter, .ramp:
                let beatsIn = (t - a.start) / max(beatLen, 0.05)
                var div = a.division
                if a.kind == .ramp {
                    // speeds up: quarters, eighths, sixteenths, thirty-seconds over the last bars
                    let frac = (t - a.start) / max(a.end - a.start, 0.01)
                    div = frac < 0.5 ? 1 : frac < 0.75 ? 2 : frac < 0.875 ? 4 : 8
                }
                guard let on = gate(beatsIn, div: div, beatLen: beatLen) else {
                    if a.kind == .ramp {   // no flashing: the build just gets brighter and whiter
                        let frac = (t - a.start) / max(a.end - a.start, 0.01)
                        for f in out.indices { for h in out[f].heads.indices {
                            out[f].heads[h].color = out[f].heads[h].color.mix(.white, frac * 0.5)
                            out[f].heads[h].intensity = max(out[f].heads[h].intensity, frac)
                        } }
                    }
                    continue
                }
                let mixW = a.kind == .ramp ? 0.5 + 0.5 * (t - a.start) / max(a.end - a.start, 0.01) : 0.85
                for f in out.indices {
                    for h in out[f].heads.indices {
                        if on {
                            out[f].heads[h].color = out[f].heads[h].color.mix(.white, mixW)
                            out[f].heads[h].intensity = 1
                        } else {
                            out[f].heads[h].intensity *= 0.05
                        }
                    }
                }
            }
        }
    }

    // MARK: dynamics

    /// How bright each kind of section runs (so the chorus/drop is the peak).
    static func levelBrightness(_ s: ShowSection) -> Double {
        if s.name.hasPrefix("Chorus") { return 1 }
        switch s.level {
        case .low: return 0.45
        case .medium: return 0.7
        case .high: return 0.9
        case .drop: return 1
        }
    }

    /// The brightness envelope at time t: the section's level, rising through a build toward the next,
    /// easing in from the section before, and breathing a little with the music's loudness.
    private func dynamics(at t: Double, si: Int, ctx: Ctx) -> Double {
        let sec = sections[si]
        if sec.name == "Silence" { return 1 }
        var level = Self.levelBrightness(sec)
        let len = max(0.1, sec.end - sec.start)
        let into = max(0, min(1, (t - sec.start) / len))
        // rising into a bigger section: ramp up over the second half (the build)
        if si + 1 < sections.count {
            let nxt = Self.levelBrightness(sections[si + 1])
            if nxt > level {
                let ramp = (sec.name.hasPrefix("Build") || sec.name.hasPrefix("Pre-Chorus")) ? into : max(0, (into - 0.5) * 2)
                level += (nxt - level) * ramp * ramp
            }
        }
        // coming down from a bigger section: ease down over 2 beats instead of dropping instantly
        if si > 0 {
            let prevL = Self.levelBrightness(sections[si - 1])
            let fade = min(1, (t - sec.start) / max(0.2, ctx.beatLen * 2))
            if prevL > level { level = prevL + (level - prevL) * fade }
        }
        // follow the loudness a little so quieter bars dip and louder bars lift
        return min(1, level * (0.8 + 0.25 * ctx.energy))
    }

    // MARK: context

    /// Phase (each head a little later), Order (forward / backward / mirrored) and Fan (beams spread) for a block
    private func shapeAcrossHeads(_ out: inout [RenderedFixture], _ sec: ShowSection, t: Double, ctx: Ctx, next: ShowSection?) {
        let total = out.reduce(0) { $0 + $1.heads.count }
        guard total > 1 else { return }
        // Phase: up to 2 beats of delay from the first head to the last (4 steps, so it stays light on the CPU)
        if let ph = sec.phase, ph > 0.01 {
            var samples: [Int: [RenderedFixture]] = [0: out]
            var n = 0
            for f in out.indices {
                for h in out[f].heads.indices {
                    let q = Int((Double(n) / Double(total - 1) * 3).rounded())
                    if samples[q] == nil { samples[q] = renderSection(sec, context(t - Double(q) / 3 * ph * 2 * ctx.beatLen), next: next) }
                    if let s = samples[q], f < s.count, h < s[f].heads.count { out[f].heads[h] = s[f].heads[h] }
                    n += 1
                }
            }
        }
        // Order: run the pattern the other way, or mirrored from the middle
        if let o = sec.order, o != .forward {
            var flat = out.flatMap { $0.heads }
            if o == .backward { flat.reverse() }
            else { for i in 0..<(flat.count / 2) { flat[flat.count - 1 - i] = flat[i] } }
            var n = 0
            for f in out.indices { for h in out[f].heads.indices { out[f].heads[h] = flat[n]; n += 1 } }
        }
        // Beam sequencer: 16 steps (two per beat); only the heads ticked for the current step show the look
        if let steps = sec.beamSteps, steps.count == 16 {
            let step = ((Int(floor(ctx.beatPos * sec.rate * 2)) % 16) + 16) % 16
            let mask = steps[step]
            for f in out.indices {
                for h in out[f].heads.indices where mask & UInt8(1 << (h & 7)) == 0 {
                    out[f].heads[h].intensity = 0
                }
            }
        }
        // Fan: spread the lights' beams apart (left light leans left, right light leans right)
        if let fan = sec.fan, fan > 0.01, out.count > 1 {
            for f in out.indices {
                let pos = Double(f) / Double(out.count - 1) - 0.5
                out[f].pan = max(0, min(1, out[f].pan + pos * fan * 0.6))
            }
        }
    }

    private func context(_ t: Double) -> Ctx {
        let beats = analysis.beats
        var beatPos = 0.0
        var beatLen = 60 / max(analysis.bpm, 1)
        if beats.count >= 2 {
            let i = lastIndex(beats, atOrBefore: t)
            if i < 0 {
                beatLen = beats[1] - beats[0]
                beatPos = (t - beats[0]) / beatLen
            } else if i >= beats.count - 1 {
                beatLen = beats[beats.count - 1] - beats[beats.count - 2]
                beatPos = Double(beats.count - 1) + (t - beats[beats.count - 1]) / beatLen
            } else {
                beatLen = beats[i + 1] - beats[i]
                beatPos = Double(i) + (t - beats[i]) / beatLen
            }
        }
        // Align beat counting so bars start on the detected downbeat
        beatPos += Double(analysis.beatBase ?? 0)
        beatPos -= Double(analysis.downbeatOffset)

        let ki = lastIndex(analysis.kicks, atOrBefore: t)
        let si = lastIndex(analysis.snares, atOrBefore: t)
        let hi = lastIndex(analysis.hats, atOrBefore: t)
        return Ctx(t: t, beatPos: beatPos, beatLen: beatLen,
                   sinceKick: ki >= 0 ? t - analysis.kicks[ki] : 99, kickIndex: max(ki, 0),
                   sinceSnare: si >= 0 ? t - analysis.snares[si] : 99,
                   sinceHat: hi >= 0 ? t - analysis.hats[hi] : 99, hatIndex: max(hi, 0),
                   energy: analysis.value(analysis.energy, at: t),
                   bass: analysis.value(analysis.bass, at: t),
                   high: analysis.value(analysis.high, at: t))
            .withStems(analysis, t)
    }

    /// Binary search: index of the last element <= t, or -1.
    private func lastIndex(_ arr: [Double], atOrBefore t: Double) -> Int {
        var lo = 0, hi = arr.count - 1, ans = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if arr[mid] <= t { ans = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return ans
    }

    // MARK: effects

    private static func rank(_ l: EnergyLevel) -> Int {
        switch l { case .low: return 0; case .medium: return 1; case .high: return 2; case .drop: return 3 }
    }

    private func renderSection(_ s: ShowSection, _ c: Ctx, next: ShowSection? = nil) -> [RenderedFixture] {
        var c = c
        c.rate = s.rate
        // Colors rotate per phrase, and keep evolving every 8 bars inside a section
        let startBeat = context(s.start).beatPos
        let evolve = max(0, Int(floor((c.beatPos - startBeat) / 32)))
        let base = Palette.named(s.palette)
        let shiftBy = (s.colorShift ?? 0) + evolve
        let pal: Palette = {
            guard shiftBy != 0, base.colors.count > 1 else { return base }
            let n = base.colors.count, k = shiftBy % n
            return Palette(id: base.id, colors: Array(base.colors[k...] + base.colors[..<k]))
        }()
        // Build-up fill: last beat before a bigger section flickers in 16ths
        let fillOn: Bool? = {
            guard let next, Self.rank(next.level) > Self.rank(s.level), s.end - c.t < c.beatLen, s.end > c.t else { return nil }
            let into = c.t - (s.end - c.beatLen)
            return gate(into / max(c.beatLen, 0.05), div: 4, beatLen: c.beatLen) ?? true
        }()
        let totalPixels = max(1, fixtures.reduce(0) { $0 + $1.headCount })
        let rb = c.beatPos * s.rate
        let idx = Int(floor(rb))
        let ph = rb - floor(rb)
        let barPos = rb / 4

        let accentOn = s.accentStrobe && (c.t - s.start) < c.beatLen * 4
        // Movement runs a little ahead so the heads (motor + smoothing) arrive right on the beat
        var result: [RenderedFixture] = []
        var p = 0
        let moverCount = max(1, fixtures.filter { $0.isMover }.count)
        var moverIdx = 0

        for (fi, fx) in fixtures.enumerated() {
            var heads: [FixtureState] = []
            let reversed = rig == .mirror && fi % 2 == 1
            for h in 0..<fx.headCount {
                var st: FixtureState
                // In mirror mode every other light runs its heads in reverse, so chases meet in the middle.
                let pixel = reversed ? p + (fx.headCount - 1 - h) : p + h
                if accentOn {
                    st = FixtureState(intensity: 1, color: .white)
                } else {
                    st = effect(s.effect, pal: pal, c: c, rb: rb, idx: idx, ph: ph, p: pixel, n: totalPixels)
                }
                st.intensity = min(1, max(0, st.intensity * s.intensity * beamMask(s, c: c, head: h, of: fx.headCount)))
                if let on = fillOn {
                    st.intensity = on ? 1 : 0.1
                    st.color = st.color.mix(.white, 0.35)
                }
                heads.append(st)
            }
            p += fx.headCount
            if fx.colorWheel != nil {
                // A color wheel is mechanical: hold one color per section instead of changing every beat.
                let follow = fx.wheelFollowsShow ?? true
                let col: RGB = (accentOn || !follow) ? .white : pal.color(0)
                for h in heads.indices { heads[h].color = col }
            }
            var rf = RenderedFixture(heads: heads)
            // Programmed strobes use the intensity gate above, not fixture-specific shutter commands.
            if fx.isMover {
                // Each light's motor needs its own head start (set per light: Movement Timing),
                // plus the app's own smoothing of the move (~70 ms)
                let lead = ((fx.moveLeadMs ?? 300) / 1000 + 0.07) / max(c.beatLen, 0.1)
                let mBeats = (c.beatPos + lead) * s.rate * (s.moveSpeed ?? 1)
                let mBar = mBeats / 4
                let mIdx = Int(floor(mBeats))
                switch rig {
                case .together:
                    let m = movement(s.movement, barPos: mBar, idx: mIdx, fi: 0, n: 1)
                    rf.pan = m.pan; rf.tilt = m.tilt
                case .mirror:
                    let m = movement(s.movement, barPos: mBar, idx: mIdx, fi: 0, n: 1)
                    let flip = moverIdx % 2 == 1
                    rf.pan = flip ? 1 - m.pan : m.pan
                    // tilt-only bars: mirror the swing around center so the pair opens and closes
                    rf.tilt = flip && s.movement != .none ? 1 - m.tilt : m.tilt
                case .independent:
                    let m = movement(s.movement, barPos: mBar, idx: mIdx, fi: moverIdx, n: moverCount)
                    rf.pan = m.pan; rf.tilt = m.tilt
                }
                // Moves stay in front: from a little behind straight up (0.42) out to the audience (1),
                // never swinging over to shoot at the back of the stage
                // Hold with an aim: the heads stay tilted there (e.g. at the crowd)
                if s.movement == .none, let aim = s.aim { rf.tilt = max(0, min(1, aim)); rf.pan = 0.5 }
                else if s.movement != .none {
                    // a smaller swing: drift around the aim (or the middle) instead of end to end
                    if let size = s.moveSize, size < 1 {
                        rf.tilt = 0.5 + (rf.tilt - 0.5) * size
                        rf.pan = max(0, min(1, 0.5 + (rf.pan - 0.5) * size))
                    }
                    // the full 180°; a small swing is centred on the aim
                    if let size = s.moveSize, size < 1, let aim = s.aim { rf.tilt += aim - 0.5 }
                    rf.tilt = max(0, min(1, rf.tilt))
                }
                moverIdx += 1
            }
            result.append(rf)
        }
        return result
    }

    /// Which beams of a multi-beam bar are lit right now. Bigger song sections switch patterns
    /// (odd/even, outside/inside, left/right…) so beams turn on and off instead of all glowing at once.
    private func beamMask(_ s: ShowSection, c: Ctx, head h: Int, of n: Int) -> Double {
        guard n >= 4 else { return 1 }
        // effects that already pick their own beams
        if [.chase, .bounce, .pixelPop, .centerOut, .sparkle, .alternate, .split, .wave, .ripple, .scan, .fill, .gradient, .fire, .embers, .water, .tide, .magic, .aurora, .glitch, .shimmer, .goldDust, .blackout].contains(s.effect) { return 1 }
        let barN = Int(floor(c.beatPos * s.rate / 4))
        let pattern: Int
        switch s.level {
        case .low, .medium: return 1
        case .high: pattern = [1, 2][((Int(floor(c.beatPos * s.rate / 2)) % 2) + 2) % 2]   // odd / even every 2 beats
        case .drop: pattern = 1 + ((Int(floor(c.beatPos * s.rate)) % 4) + 4) % 4            // drops: punchier groups every beat
        }
        let half = n / 2
        let on: Bool
        switch pattern {
        case 1: on = h % 2 == 0                         // odd beams (1, 3, 5, 7)
        case 2: on = h % 2 == 1                         // even beams
        case 3: on = h < 2 || h >= n - 2                // the outside beams
        case 4: on = h >= half - 1 && h <= half         // the middle beams
        case 5: on = (h < half) == ((barN % 2) == 0)   // left half / right half
        default: on = true
        }
        return on ? 1 : 0
    }

    private func effect(_ e: LightEffect, pal: Palette, c: Ctx, rb: Double, idx: Int, ph: Double, p: Int, n: Int) -> FixtureState {
        let bar = Int(floor(rb / 4))
        switch e {
        case .steady:
            let col = pal.color(pal.colors.count > 1 ? p % 2 : 0)
            return FixtureState(intensity: 0.7 + 0.3 * c.energy, color: col)

        case .breathe:
            let s = 0.5 - 0.5 * cos(2 * .pi * rb / 8)
            let cp = rb / 16 + Double(p) / Double(n) * 0.5
            let col = pal.color(Int(floor(cp))).mix(pal.color(Int(floor(cp)) + 1), cp - floor(cp))
            return FixtureState(intensity: 0.25 + 0.75 * s, color: col)

        case .pulse:
            return FixtureState(intensity: exp(-ph * 4), color: pal.color(bar))

        case .kickFlash:
            let k = exp(-c.sinceKick * 9)
            return FixtureState(intensity: k, color: pal.color(bar + (p % 2)))

        case .snareHit:
            let k = exp(-c.sinceSnare * 8)
            let col = pal.color(0).mix(pal.color(1).mix(.white, 0.4), k)
            return FixtureState(intensity: 0.3 + 0.7 * k, color: col)

        case .chase:
            let stepsPerBeat = max(1.0, Double(n) / 4)
            let pos = rb * stepsPerBeat
            let head = pos.truncatingRemainder(dividingBy: Double(n))
            var dist = head - Double(p)
            if dist < 0 { dist += Double(n) }
            let level = exp(-dist * 1.3)
            return FixtureState(intensity: 0.05 + 0.95 * level, color: pal.color(Int(pos / Double(n))))

        case .alternate:
            let on = (idx + p) % 2 == 0
            return FixtureState(intensity: on ? 1 : 0.06, color: pal.color(idx / 2 + (on ? 0 : 1)))

        case .colorBeat:
            return FixtureState(intensity: 0.3 + 0.7 * exp(-ph * 4), color: pal.color(idx + p))

        case .rainbow:
            let hue = rb / 16 + Double(p) / Double(n)
            return FixtureState(intensity: 0.8 + 0.2 * c.energy, color: RGB(h: hue, s: 1, v: 1))

        case .sparkle:
            let h1 = (c.hatIndex &* 2_654_435_761) % max(n, 1)
            let h2 = (c.hatIndex &* 40_503 &+ 7) % max(n, 1)
            let chosen = p == abs(h1) || (n > 3 && p == abs(h2))
            let k = chosen ? exp(-c.sinceHat * 14) : 0
            let col = pal.color(0).mix(.white, k * 0.7)
            return FixtureState(intensity: 0.12 + 0.88 * k, color: col)

        case .strobe:
            // rate = flashes per beat: 1 = quarters, 2 = eighths, 3 = triplets, 4 = sixteenths, 8 = 32nds
            let col = pal.color(bar)
            guard let on = gate(rb / max(c.rate, 0.01), div: c.rate, beatLen: c.beatLen) else {
                return FixtureState(intensity: 0.55 + 0.45 * exp(-ph * 3), color: col)   // no flashing: a pulse
            }
            return FixtureState(intensity: on ? 1 : 0, color: on ? col.mix(.white, 0.5) : col)

        case .stutter:
            // chops that speed up across each bar: eighths, eighths, sixteenths, thirty-seconds
            let beatInBar = (rb / max(c.rate, 0.01)).truncatingRemainder(dividingBy: 4)
            let div: Double = beatInBar < 2 ? 2 : beatInBar < 3 ? 4 : 8
            let col = pal.color(bar)
            guard let on = gate(rb / max(c.rate, 0.01), div: div, beatLen: c.beatLen) else {
                return FixtureState(intensity: 0.3 + 0.7 * beatInBar / 4, color: col.mix(.white, beatInBar / 8))
            }
            return FixtureState(intensity: on ? 1 : 0, color: on ? col.mix(.white, 0.6) : col)

        case .riseStrobe:
            // 2-bar cycle: a solid flash for a bar (while the head rises to the middle), then a strobe
            let beats = rb / max(c.rate, 0.01)
            let cyc = beats.truncatingRemainder(dividingBy: 8)
            let col = pal.color(0)
            if cyc < 4 {
                let punch = exp(-cyc * 3)   // a bright hit at the start that settles to solid
                return FixtureState(intensity: 1, color: col.mix(.white, 0.25 + 0.5 * punch))
            }
            // rapid strobe: 32nd notes (as fast as the Flashing setting allows)
            guard let on = gate(beats, div: 8, beatLen: c.beatLen) else {
                return FixtureState(intensity: 1, color: col.mix(.white, 0.5))   // flashing turned off: stay solid
            }
            return FixtureState(intensity: on ? 1 : 0, color: on ? col.mix(.white, 0.7) : col)

        case .blinderHits:
            // the palette's color look, and on strong snares / kick+snare hits a white blinder flash
            let base = pal.color(p % max(1, min(2, pal.colors.count)))
            let snareK = exp(-c.sinceSnare * 9)
            let k = Self.maxFlashHz > 0 ? snareK : snareK * 0.4
            return FixtureState(intensity: 0.55 + 0.45 * max(k, exp(-c.sinceKick * 8) * 0.5), color: base.mix(.white, k))

        case .soundLevel:
            // Brightness rides the volume (voice, room, or computer audio); louder = warmer palette color
            let e = c.energy
            let col = pal.color(0).mix(pal.color(1), min(1, e * 1.2))
            return FixtureState(intensity: 0.04 + 0.96 * e, color: col)

        case .blackout:
            return .off

        // ---- Per-beam patterns: each head does something different ----
        case .wave:
            // a bright wave rolls across the beams, colors blend from one end to the other
            let x = Double(p) / Double(max(n, 1))
            let s = 0.5 + 0.5 * sin(2 * .pi * (rb / 4 - x))
            let base = Int(floor(rb / 8))
            let col = pal.color(base).mix(pal.color(base + 1), x)
            return FixtureState(intensity: s * s * s, color: col)

        case .centerOut:
            // every kick bursts from the middle beams out to the ends
            let center = Double(n - 1) / 2
            let d = abs(Double(p) - center) / max(center, 0.5)
            let r = min(1.3, c.sinceKick / max(0.05, c.beatLen * 0.45))
            let k = exp(-abs(d - r) * 4.5) * exp(-c.sinceKick * 1.6)
            return FixtureState(intensity: 0.05 + 0.95 * k, color: pal.color(c.kickIndex + (d > 0.5 ? 1 : 0)))

        case .split:
            // left half one color, right half another; they swap every bar and pulse on the beat
            let left = p < (n + 1) / 2
            let swap = (idx / 4) % 2 == 1
            // one half lights on the beat, the other half on the off-beat
            let lit = (left != swap) == (idx % 2 == 0)
            return FixtureState(intensity: lit ? exp(-ph * 2.5) : 0, color: pal.color(left != swap ? 0 : 1))

        case .pixelPop:
            // random beams pop on every 8th note
            let step = Int(floor(rb * 2))
            let hsh = abs((step &* 2_654_435_761) &+ (p &* 40_503) &+ 977) % 997
            let on = hsh % 3 == 0
            let since = (rb * 2 - floor(rb * 2)) * c.beatLen / 2
            let k = on ? exp(-since * 9) : 0
            return FixtureState(intensity: 0.06 + 0.94 * k, color: pal.color(step + p))

        case .bounce:
            // one beam (with a short trail) bounces end to end, once per bar
            guard n > 1 else { return FixtureState(intensity: 0.5 + 0.5 * exp(-ph * 4), color: pal.color(bar)) }
            let period = Double(2 * (n - 1))
            let pos = (rb / 4 * period).truncatingRemainder(dividingBy: period)
            let x = pos <= Double(n - 1) ? pos : period - pos
            let level = exp(-abs(x - Double(p)) * 1.5)
            return FixtureState(intensity: 0.04 + 0.96 * level, color: pal.color(bar))

        case .ripple:
            // rings of light spread from the middle beams out to the ends, one every 2 beats
            let center = Double(n - 1) / 2
            let d = abs(Double(p) - center) / max(center, 0.5)
            let w = 0.5 + 0.5 * cos(2 * .pi * (d * 0.9 - rb / 2))
            return FixtureState(intensity: pow(w, 4), color: pal.color(Int(floor(rb / 2)) + (d > 0.5 ? 1 : 0)))

        case .scan:
            // one beam steps across the bar and back, every 8th note, with a faint trail
            guard n > 1 else { return FixtureState(intensity: exp(-ph * 4), color: pal.color(bar)) }
            let period = 2 * (n - 1)
            let step = ((Int(floor(rb * 2)) % period) + period) % period
            let x = step < n ? step : period - step
            let dist = abs(p - x)
            return FixtureState(intensity: dist == 0 ? 1 : (dist == 1 ? 0.12 : 0), color: pal.color(bar))

        case .fill:
            // beams switch on one after another across the bar, then off again (direction flips each bar)
            let f = rb / 4 - floor(rb / 4)
            let count = f < 0.5 ? f * 2 * Double(n) : (1 - f) * 2 * Double(n)
            let pos = bar % 2 == 0 ? p : n - 1 - p
            let on = Double(pos) < count
            return FixtureState(intensity: on ? 1 : 0, color: pal.color(bar + (pos * pal.colors.count) / max(n, 1)))

        case .fire:
            // flames: every beam flickers on its own, hotter (brighter, yellower) with the music's energy
            let slice = Int(floor(c.t * 14))
            func noise(_ k: Int) -> Double { Double(abs((k &* 2_654_435_761) &+ (p &* 97_531)) % 1000) / 1000 }
            let a = noise(slice), b = noise(slice + 1)
            let f = c.t * 14 - floor(c.t * 14)
            let flick = a + (b - a) * f
            let heat = min(1, 0.35 + 0.65 * flick * (0.6 + 0.6 * c.energy))
            let col = pal.color(0).mix(pal.color(1), heat).mix(pal.color(2), max(0, heat - 0.75) * 2)
            return FixtureState(intensity: 0.25 + 0.75 * heat, color: col)

        case .embers:
            // glowing coals: slow, deep flicker with an occasional spark
            let slow = 0.5 + 0.5 * sin(c.t * 1.3 + Double(p) * 1.7) * sin(c.t * 0.7 + Double(p))
            let spark = (Int(floor(c.t * 3)) &* 31 &+ p &* 7) % 23 == 0 ? 1.0 : 0
            return FixtureState(intensity: 0.15 + 0.55 * slow + 0.3 * spark, color: pal.color(0).mix(pal.color(1), slow * 0.6 + spark * 0.4))

        case .water:
            // shimmering water: two ripples at different speeds cross over each other
            let x = Double(p) / Double(max(n, 1))
            let w1 = sin(2 * .pi * (x * 1.3 - rb / 6)), w2 = sin(2 * .pi * (x * 0.7 + rb / 9) + 1.3)
            let s = 0.5 + 0.25 * w1 + 0.25 * w2
            let col = pal.color(0).mix(pal.color(1), 0.5 + 0.5 * w2).mix(.white, max(0, s - 0.85) * 2)
            return FixtureState(intensity: 0.15 + 0.85 * s * s, color: col)

        case .tide:
            // the light rises along the bar and falls back like a tide, once every 2 bars, with a soft edge
            let level = 0.5 - 0.5 * cos(2 * .pi * rb / 8)           // 0…1…0 over 8 beats
            let edge = level * Double(n) - Double(p)
            let k = max(0, min(1, edge + 0.5))
            return FixtureState(intensity: 0.08 + 0.92 * k, color: pal.color(0).mix(pal.color(1), Double(p) / Double(max(n - 1, 1))))

        case .magic:
            // magic dust: beams twinkle in and out slowly in shifting colors, with a glitter on the hi-hats
            let ph1 = c.t * 0.9 + Double((p &* 7_919) % 97) * 0.37
            let tw = pow(0.5 + 0.5 * sin(ph1), 3)
            let glitter = (c.hatIndex &+ p) % 5 == 0 ? exp(-c.sinceHat * 12) : 0
            let cp = rb / 8 + Double(p) * 0.37
            let col = pal.color(Int(floor(cp))).mix(pal.color(Int(floor(cp)) + 1), cp - floor(cp)).mix(.white, glitter * 0.8)
            return FixtureState(intensity: min(1, 0.05 + 0.8 * tw + glitter), color: col)

        case .aurora:
            // northern lights: slow flowing curtains of color drifting along the bar
            let x = Double(p) / Double(max(n - 1, 1))
            let flow = sin(2 * .pi * (x * 0.8 - rb / 16)) + 0.5 * sin(2 * .pi * (x * 1.9 + rb / 11))
            let s = 0.5 + 0.33 * flow
            let cp = x * 1.5 + rb / 24
            let col = pal.color(Int(floor(cp))).mix(pal.color(Int(floor(cp)) + 1), cp - floor(cp))
            return FixtureState(intensity: max(0.05, min(1, s)), color: col)

        case .glitch:
            // digital glitch: beams stutter and drop out in quick bursts, colors jump, hits on the beat
            let slice = Int(floor(rb * 8))                       // 32nd notes
            let r = abs((slice &* 1_103_515_245) &+ (p &* 12_345) &+ 77) % 100
            let burst = abs((Int(floor(rb)) &* 2_246_822_519) &+ 3) % 3 == 0   // some beats glitch hard
            let on = burst ? r < 45 : r < 85
            let shift = burst && r % 4 == 0
            let col = shift ? pal.color(slice + 1).mix(.white, 0.3) : pal.color(Int(floor(rb / 4)))
            return FixtureState(intensity: on ? (0.6 + 0.4 * exp(-ph * 3)) : 0, color: col)

        case .shimmer:
            // a fast fine sparkle over all the beams, like light on sequins
            let fast = sin(c.t * 37 + Double(p) * 2.3) * sin(c.t * 23 + Double(p) * 5.1)
            let s = 0.7 + 0.3 * fast
            return FixtureState(intensity: s * (0.75 + 0.25 * c.energy), color: pal.color(0).mix(.white, max(0, fast) * 0.5))

        case .goldDust:
            // sprinkled light: random beams sparkle and the sparkles drift along the bar
            let slice = Int(floor(c.t * 10))
            var k = 0.0
            for back in 0..<4 {                                  // each sparkle fades as it drifts one beam per slice
                let s0 = slice - back
                let start = abs((s0 &* 2_654_435_761) &+ 991) % max(n, 1)
                let pos = (start + back) % max(n, 1)
                if pos == p {
                    let age = c.t * 10 - Double(s0)
                    k = max(k, exp(-age * 0.9))
                }
            }
            let twinkle = 0.12 + 0.1 * sin(c.t * 3 + Double(p))
            return FixtureState(intensity: min(1, twinkle + k), color: pal.color(0).mix(.white, k * 0.6))

        case .gradient:
            // the palette spread across the beams, slowly drifting
            let x = Double(p) / Double(max(n - 1, 1))
            let cp = x * Double(max(1, pal.colors.count - 1)) + rb / 16
            let col = pal.color(Int(floor(cp))).mix(pal.color(Int(floor(cp)) + 1), cp - floor(cp))
            return FixtureState(intensity: 0.7 + 0.3 * c.energy, color: col)
        }
    }

    /// Ping-pong between 0 and 1: each leg takes exactly `legBeats` beats, eases in and out,
    /// and lands on a beat (so swings arrive with the music).
    private func leg(_ beats: Double, _ legBeats: Double, offset: Double = 0) -> Double {
        let k = beats / legBeats + offset
        let i = floor(k), f = k - i
        let e = f * f * (3 - 2 * f)
        return Int(i) % 2 == 0 ? e : 1 - e
    }

    private func movement(_ m: MoveEffect, barPos: Double, idx: Int, fi: Int, n: Int) -> (pan: Double, tilt: Double) {
        let phase = Double(fi) * 0.6
        let beats = barPos * 4
        switch m {
        case .none:
            return (0.5, 0.5)
        case .sweep:
            // end to end in one bar (4 beats), arriving on the downbeat
            // the whole 180° of the SHEHDS head (DMX 0–255 = one end to the other)
            let v = leg(beats, 4, offset: Double(fi) * 0.5)
            return (v, v)
        case .circle:
            let a = 2 * .pi * barPos + phase
            return (0.5 + 0.5 * sin(a), 0.5 + 0.5 * cos(a))
        case .fan:
            // open out and back in, 2 beats each way
            let s = leg(beats, 2)
            let dir: Double = fi % 2 == 0 ? 1 : -1
            return (0.5 + dir * 0.5 * s, 0.5 + dir * 0.5 * s)
        case .beatNod:
            // up and down, 2 beats each way, landing on the beat
            let v = 0.15 + 0.7 * leg(beats, 2, offset: Double(fi))
            return (0.5, v)
        case .fullRotate:
            // the whole 180°, one way per 2 bars (8 beats)
            let v = leg(beats, 8, offset: Double(fi) * 0.5)
            return (v, v)
        case .riseToMiddle:
            // from lying flat (one end of the 180°) up to straight up over a bar, then hold there a bar
            let cyc = beats.truncatingRemainder(dividingBy: 8)
            let x = min(1, cyc / 4)
            let v = 0.5 * x * x * (3 - 2 * x)
            return (v, v)
        case .flip:
            // Snap end to end on every other beat
            let side = ((idx / 4) + fi) % 2 == 0   // once a bar
            return (side ? 0 : 1, side ? 0 : 1)
        }
    }
}

// MARK: - Mapper: rendered looks -> 512 DMX values

enum DMXMapper {
    static func frame(fixtures: [Fixture], rendered: [RenderedFixture], master: Double, blackout: Bool, time: Double) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 512)
        for (fx, rf) in zip(fixtures, rendered) {
            let specs = fx.channels
            let multiHead = fx.headCount > 1
            let hasColor = specs.contains { if case .role(let r, _) = $0 { return [.red, .green, .blue, .white].contains(r) }; return false }
            let hasDimmer = specs.contains { if case .role(.dimmer, _) = $0 { return true }; return false }
            let useDimmerForIntensity = hasDimmer && (!multiHead || !hasColor)

            // Software strobe for fixtures without a strobe channel
            var gate = 1.0
            if rf.strobe > 0 && !fx.hasStrobeChannel {
                let hz = 6 + 8 * rf.strobe
                gate = Int(time * hz * 2) % 2 == 0 ? 1 : 0
            }
            let m = blackout ? 0 : master * gate
            // Master goes through the dimmer channel when there is one, otherwise into the colors.
            let colorMaster: Double = m <= 0 ? 0 : (hasDimmer ? 1 : m)

            for (ci, spec) in specs.enumerated() {
                let addr = fx.address - 1 + ci
                guard addr >= 0 && addr < 512 else { continue }
                switch spec {
                case .constant(let v):
                    out[addr] = v
                case .strobeRange(let open, let slow, let fast):
                    if rf.strobe > 0 && !blackout {
                        out[addr] = UInt8(clamping: Int(Double(slow) + (Double(fast) - Double(slow)) * min(1, rf.strobe)))
                    } else {
                        out[addr] = open
                    }
                case .colorWheel(let name):
                    let head = rf.heads.first ?? .off
                    out[addr] = ColorWheel.wheels[name]?.nearest(head.color).value ?? 0
                case .role(let role, let h):
                    let head = rf.heads.indices.contains(h) ? rf.heads[h] : (rf.heads.first ?? .off)
                    let scale = head.intensity <= 0 ? 0 : (useDimmerForIntensity ? 1.0 : head.intensity)
                    let c = colorChannels(head.color, hasWhite: specs.contains(.role(.white, head: h)))
                    switch role {
                    case .dimmer:
                        if useDimmerForIntensity {
                            let maxI = rf.heads.map(\.intensity).max() ?? 0
                            out[addr] = byte((hasColor ? maxI : head.intensity) * m)
                        } else {
                            out[addr] = byte(m)
                        }
                    case .red: out[addr] = byte(c.r * scale * colorMaster)
                    case .green: out[addr] = byte(c.g * scale * colorMaster)
                    case .blue: out[addr] = byte(c.b * scale * colorMaster)
                    case .white: out[addr] = byte(c.w * scale * colorMaster)
                    case .amber, .uv: out[addr] = 0
                    case .strobe: out[addr] = (rf.strobe > 0 && !blackout) ? byte(0.55 + 0.4 * rf.strobe) : 0
                    case .pan: out[addr] = UInt8(clamping: Int(rf.pan * 65535) >> 8)
                    case .tilt: out[addr] = UInt8(clamping: Int(rf.tilt * 65535) >> 8)
                    case .panFine: out[addr] = UInt8(clamping: Int(rf.pan * 65535) & 0xFF)
                    case .tiltFine: out[addr] = UInt8(clamping: Int(rf.tilt * 65535) & 0xFF)
                    case .speed: out[addr] = UInt8(clamping: Int(fx.tiltSpeed ?? 0))   // set per light (Tilt Speed + Tilt Test)
                    }
                }
            }
        }
        return out
    }

    /// Screen colors → LED levels. LEDs are linear (half the DMX value looks much brighter than half on a
    /// screen), so colors are gamma-corrected or oranges turn yellow and purples turn pink. The white LED
    /// only takes over for near-white colors; saturated and pastel colors stay in RGB so they keep their hue.
    static func colorChannels(_ c: RGB, hasWhite: Bool) -> (r: Double, g: Double, b: Double, w: Double) {
        func lin(_ v: Double) -> Double { pow(min(1, max(0, v)), 2.2) }
        var r = lin(c.r), g = lin(c.g), b = lin(c.b)
        guard hasWhite else { return (r, g, b, 0) }
        let mx = max(r, g, b), mn = min(r, g, b)
        guard mx > 0 else { return (0, 0, 0, 0) }
        let sat = (mx - mn) / mx
        let share = max(0, min(1, 1 - sat * 2.5))     // 1 for white/greys, 0 once the color is clearly tinted
        let w = mn * share
        r -= w; g -= w; b -= w
        return (r, g, b, w)
    }

    static func byte(_ v: Double) -> UInt8 { UInt8(clamping: Int((min(1, max(0, v)) * 255).rounded())) }
}


private extension ShowRenderer.Ctx {
    func withStems(_ a: SongAnalysis, _ t: Double) -> ShowRenderer.Ctx {
        guard let st = a.stemLevels, !st.isEmpty else { return self }
        var c = self
        c.hasStems = true
        let v = st["vocals"].map { a.value($0, at: t) } ?? 0
        let b = st["backing"].map { a.value($0, at: t) } ?? 0
        c.vocal = min(1, max(v, b * 0.6))
        c.drums = st["drums"].map { a.value($0, at: t) } ?? 0.7
        c.bassPart = st["bass"].map { a.value($0, at: t) } ?? 0.5
        c.otherPart = st["other"].map { a.value($0, at: t) } ?? 0.5
        return c
    }
}


extension ShowGenerator {
    /// Section names by genre (from the song-structure guide): pop keeps Verse / Pre-Chorus / Chorus;
    /// house & EDM are Intro → Groove → Build → Drop → Breakdown → Build → Drop → Outro; dubstep / bass music
    /// the same with a Break; techno is Groove → Break → Peak. A chorus is a songwriting part and a drop is an
    /// energy part, so in dance-pop a chorus that hits like a drop keeps both names ("Chorus 2 · Drop").
    static func edmNamed(_ secs: [DetectedSection], style: ShowStyle) -> [DetectedSection] {
        let rename: [String: String]
        switch style {
        case .electronic: rename = ["Verse": "Groove", "Chorus": "Drop", "Post-Chorus": "Drop", "Pre-Chorus": "Build", "Bridge": "Breakdown"]
        case .dubstep:    rename = ["Verse": "Groove", "Chorus": "Drop", "Post-Chorus": "Drop", "Pre-Chorus": "Build", "Bridge": "Break", "Breakdown": "Break"]
        case .techno:     rename = ["Verse": "Groove", "Chorus": "Peak", "Post-Chorus": "Peak", "Pre-Chorus": "Build", "Bridge": "Break", "Breakdown": "Break"]
        default:
            // dance-pop: the chorus can be the drop too
            guard [.pop, .club, .hyperpop, .latin, .disco].contains(style) else { return secs }
            return secs.map { d in
                var d = d
                if d.level == .drop, d.name.hasPrefix("Chorus") || d.name.hasPrefix("Post-Chorus") { d.name += " · Drop" }
                return d
            }
        }
        func role(_ n: String) -> String {
            for r in ["Pre-Chorus", "Post-Chorus"] where n.hasPrefix(r) { return r }
            return n.split(separator: " ").first.map(String.init) ?? n
        }
        var out: [DetectedSection] = []
        for var d in secs {
            d.name = rename[role(d.name)] ?? role(d.name)
            if (d.name == "Drop" || d.name == "Peak"), d.level == .medium { d.level = .high }
            // a drop right after a drop (old chorus + post-chorus) is one longer drop
            if let last = out.last, last.name == d.name, d.name == "Drop" || d.name == "Peak" || d.name == "Groove" {
                out[out.count - 1] = DetectedSection(start: last.start, end: d.end, energy: max(last.energy, d.energy), level: last.level, name: last.name)
                continue
            }
            out.append(d)
        }
        // number them again: Drop 1, Drop 2, Build 1 …
        let totals = Dictionary(grouping: out.filter { $0.name != "Silence" }, by: \.name).mapValues(\.count)
        var counts: [String: Int] = [:]
        for i in out.indices where out[i].name != "Silence" {
            let n = out[i].name
            counts[n, default: 0] += 1
            if (totals[n] ?? 0) > 1 { out[i].name = "\(n) \(counts[n]!)" }
        }
        return out
    }
}


extension ShowGenerator {
    /// The genre a part sounds like, when it clearly differs from the song's: only for parts of 8+ bars,
    /// and only when that genre wins in this part by a clear margin and is a real step away from the song's
    /// (so a show doesn't flip style on noise). nil = the song's genre.
    static func partGenre(_ a: SongAnalysis, _ d: DetectedSection, songStyle: ShowStyle) -> ShowStyle? {
        let bar = 240 / max(a.bpm, 30)
        guard d.name != "Silence", d.end - d.start >= 8 * bar else { return nil }
        let g = a.genreScores(from: d.start, to: d.end)
        guard g.count > 1, let top = g.first, top.style != songStyle,
              ![.psychedelic, .fantasy].contains(top.style) else { return nil }
        let songHere = g.first { $0.style == songStyle }?.score ?? 0
        guard top.score >= 0.24, top.score - g[1].score >= 0.04, top.score >= songHere * 1.35 else { return nil }
        return top.style
    }
}
