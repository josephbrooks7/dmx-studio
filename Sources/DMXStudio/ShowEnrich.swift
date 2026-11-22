import Foundation

extension ShowGenerator {
    /// Uses the newer tools when a show is built: transitions at the big moments, variety from the effects
    /// library for repeated parts, and phase / mirrored order / beam patterns on the big sections.
    /// Runs before `fit`, so the result still matches what the lights can do.
    static func enrich(_ s: inout [ShowSection], _ a: SongAnalysis, presets: [LookPreset], variation: Int) {
        guard s.count > 1, a.bpm > 30 else { return }
        let beat = 60 / a.bpm
        var rng = SeededRandom(seed: UInt64(max(1, variation)) &* 7919 &+ UInt64(max(0, Int(a.duration * 10))))

        func base(_ name: String) -> String {
            name.components(separatedBy: CharacterSet.decimalDigits).joined()
                .replacingOccurrences(of: "·", with: "").trimmingCharacters(in: .whitespaces)
        }
        let calm: Set<LightEffect> = [.steady, .breathe, .gradient, .aurora, .water, .tide, .shimmer, .magic, .goldDust, .embers]

        // 1. Repeated parts (Verse 2, Chorus 3…) get a different matching effect from the library; colors stay
        var seen: [String: Int] = [:]
        for k in s.indices {
            let b = base(s[k].name)
            guard !b.isEmpty, b != "Silence", s[k].effect != .blackout, s[k].empty != true else { continue }
            seen[b, default: 0] += 1
            guard seen[b]! >= 2, s[k].end - s[k].start >= 4 * beat else { continue }
            let banks: [String]
            switch s[k].level {
            case .low: banks = ["Color FX"]
            case .medium: banks = ["Color FX", "Move FX"]
            case .high: banks = ["Beam FX", "Move FX", "Color FX"]
            case .drop: banks = ["Beam FX", "Strobes & Blinders"]
            }
            let pool = presets.filter { p in
                banks.contains(p.group ?? "") && p.effect != s[k].effect && p.effect != .blackout
                    && (s[k].level == .low ? calm.contains(p.effect) : true)
            }
            guard !pool.isEmpty else { continue }
            let p = pool[rng.next(pool.count)]
            s[k].effect = p.effect
            if p.rate != 1 && s[k].level != .drop { s[k].rate = p.rate }
            // only take the preset's movement where the show already moves (fit trims it for the rig)
            if s[k].movement != .none && p.movement != .none { s[k].movement = p.movement }
        }

        // 2. Big sections: later choruses mirror or roll across the heads; drops get a beam pattern
        var choruses = 0
        for k in s.indices where s[k].empty != true {
            if base(s[k].name) == "Chorus" {
                choruses += 1
                if choruses >= 2 {
                    if choruses % 2 == 0 { s[k].order = .symmetric } else { s[k].phase = 0.35 }
                }
            }
            if s[k].level == .drop && s[k].end - s[k].start >= 8 * beat && rng.next(3) != 0 {
                let patterns: [BeamPattern] = [.chase, .alternate, .centerOut, .bounce, .outsideIn]
                s[k].beamSteps = patterns[(variation + k) % patterns.count].steps
            }
        }

        // 4. Rules learned from a live concert (Robyn, live at the Trocadero):
        //    • the whole song stays in one color family (blue → cyan → green), never a rainbow of looks
        //    • energy shows as how busy the light is, not how bright: quiet breaks are a steady, bright,
        //      saturated wash in a neighboring color; loud parts are darker with fast changes
        //    • the stage goes almost dark for the bars before the band's big entrance
        learnedRules(&s, a, variation: variation)

        // 3. Transitions into the big moments (taken from the end of the block before: nothing moves)
        for k in stride(from: s.count - 1, through: 1, by: -1) {
            let prev = s[k - 1], cur = s[k]
            guard prev.empty != true, prev.transition == nil, prev.effect != .blackout, base(prev.name) != "Silence" else { continue }
            let kind: HitKind?
            if cur.level == .drop && prev.level != .drop {
                kind = .blackout
            } else if base(cur.name) == "Chorus" && base(prev.name) != "Chorus" {
                kind = base(prev.name) == "Pre-Chorus" ? .strobeRamp : .rise
            } else if base(cur.name) == "Bridge" {
                kind = .sweep
            } else if base(cur.name) == "Outro" && k == s.count - 1 {
                kind = .flash
            } else { kind = nil }
            guard let kind else { continue }
            let len = (kind.buildsUp ? 2 : kind.beats) * beat           // build-ups: half a bar
            guard prev.end - prev.start >= len + 4 * beat else { continue }
            var slot = prev
            slot.id = UUID()
            slot.start = cur.start - len
            slot.end = cur.start
            slot.transition = kind
            slot.name = kind.rawValue
            slot.accentStrobe = false
            slot.beamSteps = nil
            s[k - 1].end = slot.start
            s.insert(slot, at: k)
        }
    }

    // MARK: - Concert rules

    /// What real concerts taught the show builder. Runs for every new show (with or without the library).
    static func learnedRules(_ s: inout [ShowSection], _ a: SongAnalysis, variation: Int) {
        guard s.count > 1, a.bpm > 30 else { return }
        let beat = 60 / a.bpm
        concertRules(&s, beat: beat, variation: variation)
        // Rules from an electronic live show (Röyksopp & Jamie Irrepressibles, P3 Gull 2014)
        if [.club, .electronic].contains(a.suggestedStyle) { electronicRules(&s, a, beat: beat) }
        // Electro-funk band (Chromeo, live on CBC Music)
        if a.suggestedStyle == .disco { funkRules(&s) }
        // Hyperpop / club pop (Charli xcx, live at Primavera Sound)
        if a.suggestedStyle == .hyperpop { hyperpopRules(&s) }
    }

    /// Funk: the groove never stops. Cool white / lavender light all song, a pulse on every beat in
    /// the groove parts (no long washes), and the song ends on a hard cut to black on the last hit.
    private static func funkRules(_ s: inout [ShowSection]) {
        let live = s.indices.filter { s[$0].empty != true && s[$0].effect != .blackout && s[$0].transition == nil }
        for (n, k) in live.enumerated() {
            s[k].palette = n % 3 == 2 ? "Purple Haze" : "Ice"
            if s[k].level == .medium || s[k].level == .high {
                s[k].effect = .pulse; s[k].rate = 1
            }
        }
        // no fade-out at the end: the last part stays up and stops dead
        if let last = live.last, s[last].effect == .breathe || s[last].effect == .steady || s[last].level == .low {
            s[last].effect = .pulse; s[last].rate = 1
            s[last].intensity = max(s[last].intensity, 0.9)
        }
    }

    /// Hyperpop: stark white in haze almost all song, a still white wash while singing, and one bold
    /// deep-red moment late in the song.
    private static func hyperpopRules(_ s: inout [ShowSection]) {
        let live = s.indices.filter { s[$0].empty != true && s[$0].effect != .blackout && s[$0].transition == nil }
        guard !live.isEmpty else { return }
        for k in live {
            s[k].palette = "Full White"
            if s[k].level == .low || s[k].level == .medium { s[k].effect = .steady; s[k].movement = .none }
        }
        let total = s.last?.end ?? 0
        if let k = live.filter({ s[$0].start > total * 0.5 && s[$0].level != .drop })
            .max(by: { (s[$0].end - s[$0].start) < (s[$1].end - s[$1].start) }) {
            s[k].palette = "Red Room"; s[k].effect = .steady
        }
    }

    /// Main hue of a palette in degrees, and how spread its colors are (rainbows are wide)
    static func hueInfo(_ name: String) -> (hue: Double, spread: Double, white: Bool) {
        let cols = Palette.named(name).colors
        var x = 0.0, y = 0.0, sat = 0.0
        for c in cols {
            let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
            let d = mx - mn
            sat += mx > 0 ? d / mx : 0
            guard d > 0.0001 else { continue }
            var h: Double
            if mx == c.r { h = (c.g - c.b) / d } else if mx == c.g { h = 2 + (c.b - c.r) / d } else { h = 4 + (c.r - c.g) / d }
            h = (h * 60).truncatingRemainder(dividingBy: 360); if h < 0 { h += 360 }
            x += cos(h * .pi / 180); y += sin(h * .pi / 180)
        }
        let n = Double(max(1, cols.count))
        let len = sqrt(x * x + y * y) / n
        var hue = atan2(y, x) * 180 / .pi; if hue < 0 { hue += 360 }
        return (hue, 1 - len, sat / n < 0.25)
    }

    static func hueGap(_ a: Double, _ b: Double) -> Double { let d = abs(a - b).truncatingRemainder(dividingBy: 360); return min(d, 360 - d) }

    private static func concertRules(_ s: inout [ShowSection], beat: Double, variation: Int) {
        let live = s.indices.filter { s[$0].empty != true && s[$0].effect != .blackout && s[$0].transition == nil }
        guard live.count >= 3 else { return }
        // the song's color family: the palette the show uses the longest (weighted toward the loud parts)
        var weight: [String: Double] = [:]
        for k in live {
            let w = (s[k].end - s[k].start) * (s[k].level == .high || s[k].level == .drop ? 1.5 : 1)
            weight[s[k].palette, default: 0] += w
        }
        guard let main = weight.max(by: { $0.value < $1.value })?.key else { return }
        let fam = hueInfo(main)
        guard !fam.white, fam.spread < 0.5 else { return }      // a white or rainbow song: leave it
        let family = Palette.all.map(\.id).filter { id in
            let h = hueInfo(id); return !h.white && h.spread < 0.5 && hueGap(h.hue, fam.hue) <= 70
        }
        guard !family.isEmpty else { return }
        let neighbors = family.filter { $0 != main }

        var loudSeen = false
        for (n, k) in live.enumerated() {
            let h = hueInfo(s[k].palette)
            // keep every part in the family (white / gold accents are fine)
            if !h.white && (h.spread >= 0.5 || hueGap(h.hue, fam.hue) > 70) {
                s[k].palette = family[(n + variation) % family.count]
            }
            let loud = s[k].level == .high || s[k].level == .drop
            if loud { loudSeen = true; continue }
            // a quiet break after loud parts: a steady, bright, saturated wash in a neighboring color
            if loudSeen && s[k].level == .low && s[k].end - s[k].start >= 8 * beat {
                s[k].effect = n % 2 == 0 ? .steady : .breathe
                s[k].movement = .none
                s[k].intensity = max(s[k].intensity, 0.95)
                s[k].beamSteps = nil
                s[k].phase = nil
                if let nb = neighbors.isEmpty ? nil : neighbors[(n + variation) % neighbors.count] { s[k].palette = nb }
            }
        }

        // the bars before the band's first big entrance go almost dark
        if let first = s.indices.first(where: { (s[$0].level == .high || s[$0].level == .drop) && s[$0].empty != true }), first > 0 {
            let p = first - 1
            let hush = 8 * beat   // two bars
            if s[p].empty != true, s[p].transition == nil, s[p].effect != .blackout, s[p].end - s[p].start >= hush + 8 * beat {
                var slot = s[p]
                slot.id = UUID()
                slot.start = s[p].end - hush
                slot.name = "Hush"
                slot.effect = .breathe
                slot.movement = .none
                slot.intensity = 0.18
                slot.beamSteps = nil
                slot.accentStrobe = false
                s[p].end = slot.start
                s.insert(slot, at: first)
            }
        }
    }

    /// Electronic acts: the singer gets a warm wash in the sung parts, the band's instrumental peaks
    /// are cool; peaks are one color with white hits locked to every other beat; the break before
    /// the build has no flashing at all; the song ends on a steady, bright single color.
    private static func electronicRules(_ s: inout [ShowSection], _ a: SongAnalysis, beat: Double) {
        let phrases = a.vocalPhrases ?? []
        func sung(_ x: ShowSection) -> Double {
            guard x.end > x.start else { return 0 }
            let total = phrases.reduce(0.0) { acc, p in acc + max(0, min(p.end, x.end) - max(p.start, x.start)) }
            return total / (x.end - x.start)
        }
        let warm = ["Sunset", "Red Room", "Warm White", "Gold"].filter { Palette.all.map(\.id).contains($0) }
        let cool = ["Deep Blue", "Ice", "Ocean", "Purple Haze"].filter { Palette.all.map(\.id).contains($0) }
        guard !warm.isEmpty, !cool.isEmpty else { return }
        let live = s.indices.filter { s[$0].empty != true && s[$0].effect != .blackout && s[$0].transition == nil }
        for (n, k) in live.enumerated() {
            let loud = s[k].level == .high || s[k].level == .drop
            if loud {
                // one cool color, white hits on every other beat (half-time, on the beat)
                s[k].palette = cool[n % cool.count]
                if s[k].level == .drop { s[k].effect = .pulse; s[k].rate = 0.5; s[k].accentStrobe = true }
            } else if !phrases.isEmpty && sung(s[k]) > 0.45 {
                // a sung, quieter part: warm on the singer
                s[k].palette = warm[n % warm.count]
            }
        }
        // the break right before a build or peak: no flashing, one dim color
        for k in s.indices.dropLast() where s[k].level == .low && (s[k + 1].level == .high || s[k + 1].level == .drop) && s[k].empty != true {
            if [.strobe, .stutter, .kickFlash, .snareHit, .riseStrobe, .blinderHits].contains(s[k].effect) { s[k].effect = .breathe }
            s[k].accentStrobe = false
            s[k].intensity = min(s[k].intensity, 0.55)
        }
        // the last part: steady and bright in one color, nothing flashing
        if let last = s.indices.last(where: { s[$0].empty != true && s[$0].effect != .blackout && s[$0].transition == nil }),
           s[last].level == .low || s[last].name.hasPrefix("Outro") {
            s[last].effect = .steady
            s[last].movement = .none
            s[last].accentStrobe = false
            s[last].intensity = max(s[last].intensity, 0.85)
        }
    }
}
