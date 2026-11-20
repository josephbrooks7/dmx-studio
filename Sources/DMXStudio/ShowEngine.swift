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
        for d in a.detectedSections {
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

            // Phrase boundaries every 8 bars inside sections of 16+ bars
            let inner = barTimes.filter { $0 > d.start + 0.1 && $0 < d.end - 0.1 }
            var cuts: [Double] = []
            if inner.count + 1 >= 16 && !isBuild {
                var k = 8
                while k < inner.count - 3 { cuts.append(inner[k - 1]); k += 8 }
            }
            let edges = [d.start] + cuts + [d.end]
            for p in 0..<(edges.count - 1) {
                let look = p % 2 == 0 ? l : altFor(d.level, l)
                out.append(ShowSection(name: p == 0 ? d.name : "\(d.name) ·\(p + 1)",
                                       start: edges[p], end: edges[p + 1], level: d.level,
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
    let analysis: SongAnalysis
    let sections: [ShowSection]
    let fixtures: [Fixture]
    var idle: IdleLook = IdleLook()
    var rig: RigMode = .together

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
        let next = si + 1 < sections.count ? sections[si + 1] : nil
        var out = renderSection(sec, ctx, next: next)
        // Smooth crossfade into a new section
        let xf = 0.35
        if si > 0, t - sec.start < xf {
            let prev = renderSection(sections[si - 1], ctx, next: sec)
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

    private static func rank(_ l: EnergyLevel) -> Int {
        switch l { case .low: return 0; case .medium: return 1; case .high: return 2; case .drop: return 3 }
    }

    private func renderSection(_ s: ShowSection, _ c: Ctx, next: ShowSection? = nil) -> [RenderedFixture] {
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
            return Int(into / (c.beatLen / 4)) % 2 == 0
        }()
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
                st.intensity = min(1, max(0, st.intensity * s.intensity))
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
            if accentOn || s.effect == .strobe { rf.strobe = 0.5 + 0.5 * c.energy }
            if fx.isMover {
                switch rig {
                case .together:
                    let m = movement(s.movement, barPos: barPos, idx: idx, fi: 0, n: 1)
                    rf.pan = m.pan; rf.tilt = m.tilt
                case .mirror:
                    let m = movement(s.movement, barPos: barPos, idx: idx, fi: 0, n: 1)
                    let flip = moverIdx % 2 == 1
                    rf.pan = flip ? 1 - m.pan : m.pan
                    // tilt-only bars: mirror the swing around center so the pair opens and closes
                    rf.tilt = flip && s.movement != .none ? 1 - m.tilt : m.tilt
                case .independent:
                    let m = movement(s.movement, barPos: barPos, idx: idx, fi: moverIdx, n: moverCount)
                    rf.pan = m.pan; rf.tilt = m.tilt
                }
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
