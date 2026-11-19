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
        }
    }

    /// The "signature" look per genre (variation 1).
    static func signature(style: ShowStyle, level: EnergyLevel, isBuild: Bool) -> Look {
        if isBuild {
            switch style {
            case .chill: return Look(effect: .breathe, movement: .sweep, intensity: 0.8)
            case .rock: return Look(effect: .snareHit, movement: .fan)
            default: return Look(effect: .chase, rate: 2, movement: .sweep, intensity: 0.9)
            }
        }
        switch (style, level) {
        case (.club, .low): return Look(effect: .breathe, movement: .sweep, intensity: 0.6)
        case (.club, .medium): return Look(effect: .pulse, movement: .sweep, intensity: 0.85)
        case (.club, .high): return Look(effect: .colorBeat, movement: .fan)
        case (.club, .drop): return Look(effect: .kickFlash, movement: .beatNod, accent: true)

        case (.hiphop, .low): return Look(effect: .steady, intensity: 0.5)
        case (.hiphop, .medium): return Look(effect: .kickFlash, movement: .sweep, intensity: 0.85)
        case (.hiphop, .high): return Look(effect: .alternate, movement: .fan)
        case (.hiphop, .drop): return Look(effect: .kickFlash, movement: .beatNod, accent: true)

        case (.pop, .low): return Look(effect: .breathe, movement: .sweep, intensity: 0.6)
        case (.pop, .medium): return Look(effect: .pulse, movement: .sweep, intensity: 0.85)
        case (.pop, .high): return Look(effect: .chase, movement: .fan)
        case (.pop, .drop): return Look(effect: .rainbow, movement: .circle, accent: true)

        case (.rock, .low): return Look(effect: .steady, intensity: 0.5)
        case (.rock, .medium): return Look(effect: .kickFlash, movement: .sweep, intensity: 0.9)
        case (.rock, .high): return Look(effect: .alternate, movement: .beatNod)
        case (.rock, .drop): return Look(effect: .snareHit, movement: .beatNod, accent: true)

        case (.chill, .low): return Look(effect: .breathe, rate: 0.5, movement: .sweep, intensity: 0.5)
        case (.chill, .medium): return Look(effect: .breathe, movement: .sweep, intensity: 0.7)
        case (.chill, .high): return Look(effect: .pulse, rate: 0.5, movement: .sweep, intensity: 0.85)
        case (.chill, .drop): return Look(effect: .colorBeat, rate: 0.5, movement: .circle)

        case (.latin, .low): return Look(effect: .breathe, movement: .sweep, intensity: 0.6)
        case (.latin, .medium): return Look(effect: .snareHit, movement: .fan, intensity: 0.85)  // dembow snare
        case (.latin, .high): return Look(effect: .colorBeat, movement: .beatNod)
        case (.latin, .drop): return Look(effect: .kickFlash, movement: .circle, accent: true)
        }
    }

    /// Pools of looks that suit each energy level; later variations pick from these.
    static func pool(level: EnergyLevel, style: ShowStyle) -> [Look] {
        let slow = style == .chill
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
                    Look(effect: .rainbow, rate: slow ? 0.5 : 1, movement: .fan)]
        case .drop:
            return [Look(effect: .kickFlash, movement: .beatNod, accent: true),
                    Look(effect: .colorBeat, rate: slow ? 1 : 2, movement: .fan, accent: true),
                    Look(effect: .rainbow, movement: .circle, accent: true),
                    Look(effect: .alternate, rate: slow ? 1 : 2, movement: .beatNod, accent: true)]
        }
    }

    /// Variation 1 = the genre's signature look. 2, 3, … mix it up but stay consistent
    /// within a show (every chorus gets the same look, every verse the same, etc.).
    static func generate(_ a: SongAnalysis, style: ShowStyle, variation: Int) -> [ShowSection] {
        let pals = palettes(for: style)
        let shift = max(0, variation - 1)
        var rng = SeededRandom(seed: UInt64(variation) &* 0x9E37_79B9_7F4A_7C15 &+ style.rawValue.utf8.reduce(UInt64(7)) { $0 &* 31 &+ UInt64($1) })
        // Decide one look per (level, build) up front so repeated sections match.
        var looks: [String: Look] = [:]
        func lookFor(_ level: EnergyLevel, _ isBuild: Bool) -> Look {
            let key = "\(level.rawValue)\(isBuild)"
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

        return a.detectedSections.map { d in
            let isBuild = d.name.hasPrefix("Build")
            let l = lookFor(d.level, isBuild)
            let levelSlot: Int
            switch d.level {
            case .high: levelSlot = 0
            case .medium: levelSlot = 1
            case .low: levelSlot = 2
            case .drop: levelSlot = 3
            }
            let pal = pals[(levelSlot + shift) % pals.count]
            return ShowSection(name: d.name, start: d.start, end: d.end, level: d.level,
                               effect: l.effect, palette: pal, intensity: l.intensity,
                               rate: l.rate, movement: l.movement, accentStrobe: l.accent)
        }
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
    let analysis: SongAnalysis
    let sections: [ShowSection]
    let fixtures: [Fixture]
    var idle: IdleLook = IdleLook()

    /// Show + automatic fade to the idle look wherever the song is silent.
    func renderWithIdle(at t: Double) -> [RenderedFixture] {
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
            let fadeOut = s.start <= 0.01 ? 1 : (t - s.start) / 0.5
            let fadeIn = s.end >= analysis.duration - 0.01 ? 1 : (s.end - t) / 0.15
            return max(0, min(1, fadeOut, fadeIn))
        }
        return 0
    }

    private struct Ctx {
        var t: Double
        var beatPos: Double
        var beatLen: Double
        var sinceKick: Double, kickIndex: Int
        var sinceSnare: Double
        var sinceHat: Double, hatIndex: Int
        var energy: Double, bass: Double, high: Double
    }

    func render(at t: Double) -> [RenderedFixture] {
        let ctx = context(t)
        guard let si = sections.lastIndex(where: { $0.start <= t }) ?? (sections.isEmpty ? nil : 0) else {
            return fixtures.map { RenderedFixture(heads: Array(repeating: .off, count: $0.headCount)) }
        }
        let sec = sections[si]
        var out = renderSection(sec, ctx)
        // Smooth crossfade into a new section
        let xf = 0.35
        if si > 0, t - sec.start < xf {
            let prev = renderSection(sections[si - 1], ctx)
            let k = max(0, (t - sec.start) / xf)
            for f in out.indices {
                for h in out[f].heads.indices {
                    out[f].heads[h] = prev[f].heads[h].blended(out[f].heads[h], k)
                }
                out[f].pan = prev[f].pan + (out[f].pan - prev[f].pan) * k
                out[f].tilt = prev[f].tilt + (out[f].tilt - prev[f].tilt) * k
            }
        }
        return out
    }

    // MARK: context

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

    private func renderSection(_ s: ShowSection, _ c: Ctx) -> [RenderedFixture] {
        let pal = Palette.named(s.palette)
        let totalPixels = max(1, fixtures.reduce(0) { $0 + $1.headCount })
        let rb = c.beatPos * s.rate
        let idx = Int(floor(rb))
        let ph = rb - floor(rb)
        let barPos = rb / 4

        let accentOn = s.accentStrobe && (c.t - s.start) < c.beatLen * 4
        var result: [RenderedFixture] = []
        var p = 0
        let moverCount = max(1, fixtures.filter { $0.isMover }.count)
        var moverIdx = 0

        for fx in fixtures {
            var heads: [FixtureState] = []
            for _ in 0..<fx.headCount {
                var st: FixtureState
                if accentOn {
                    st = FixtureState(intensity: 1, color: .white)
                } else {
                    st = effect(s.effect, pal: pal, c: c, rb: rb, idx: idx, ph: ph, p: p, n: totalPixels)
                }
                st.intensity = min(1, max(0, st.intensity * s.intensity))
                heads.append(st)
                p += 1
            }
            var rf = RenderedFixture(heads: heads)
            if accentOn || s.effect == .strobe { rf.strobe = 0.5 + 0.5 * c.energy }
            if fx.isMover {
                let m = movement(s.movement, barPos: barPos, idx: idx, fi: moverIdx, n: moverCount)
                rf.pan = m.pan; rf.tilt = m.tilt
                moverIdx += 1
            }
            result.append(rf)
        }
        return result
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
            return FixtureState(intensity: 0.2 + 0.8 * exp(-ph * 5), color: pal.color(bar))

        case .kickFlash:
            let k = exp(-c.sinceKick * 9)
            return FixtureState(intensity: 0.1 + 0.9 * k, color: pal.color(bar + (p % 2)))

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
            return FixtureState(intensity: 0.55 + 0.45 * exp(-ph * 4), color: pal.color(idx + p))

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
            return FixtureState(intensity: 1, color: pal.color(bar))

        case .blackout:
            return .off
        }
    }

    private func movement(_ m: MoveEffect, barPos: Double, idx: Int, fi: Int, n: Int) -> (pan: Double, tilt: Double) {
        let phase = Double(fi) * 0.6
        switch m {
        case .none:
            return (0.5, 0.5)
        case .sweep:
            let a = 2 * .pi * barPos / 2 + phase
            return (0.5 + 0.35 * sin(a), 0.5 + 0.3 * sin(a))
        case .circle:
            let a = 2 * .pi * barPos + phase
            return (0.5 + 0.3 * sin(a), 0.5 + 0.3 * cos(a))
        case .fan:
            let s = 0.5 - 0.5 * cos(2 * .pi * barPos / 2)
            let dir: Double = fi % 2 == 0 ? 1 : -1
            return (0.5 + dir * 0.3 * s, 0.5 + dir * 0.3 * s)
        case .beatNod:
            let up = (idx + fi) % 2 == 0
            return (0.5, up ? 0.7 : 0.3)
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
            let colorMaster: Double = hasDimmer ? 1 : m

            for (ci, spec) in specs.enumerated() {
                let addr = fx.address - 1 + ci
                guard addr >= 0 && addr < 512 else { continue }
                switch spec {
                case .constant(let v):
                    out[addr] = v
                case .role(let role, let h):
                    let head = rf.heads.indices.contains(h) ? rf.heads[h] : (rf.heads.first ?? .off)
                    let scale = useDimmerForIntensity ? 1.0 : head.intensity
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
                    case .speed: out[addr] = 0
                    }
                }
            }
        }
        return out
    }

    /// Pulls the shared white out of RGB when the fixture has a white LED (brighter, cleaner whites).
    static func colorChannels(_ c: RGB, hasWhite: Bool) -> (r: Double, g: Double, b: Double, w: Double) {
        guard hasWhite else { return (c.r, c.g, c.b, 0) }
        let w = min(c.r, c.g, c.b)
        return (c.r - w, c.g - w, c.b - w, w)
    }

    static func byte(_ v: Double) -> UInt8 { UInt8(clamping: Int((min(1, max(0, v)) * 255).rounded())) }
}
