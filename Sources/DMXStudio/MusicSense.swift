import Foundation

// MARK: - Groove: does the song feel half-time, normal or double-time?

enum GrooveFeel: String, Codable {
    case half = "Half-time", normal = "Normal", double = "Double-time"
    /// How fast lighting pulses and movement should run relative to the counted beat.
    var lightRate: Double { switch self { case .half: return 0.5; case .normal: return 1; case .double: return 2 } }
}

extension SongAnalysis {
    /// Where on the beat grid each hit falls (0…3 = beat 1…4 of the bar), nil if far from a beat.
    func beatPhase(_ t: Double) -> Int? {
        guard beats.count > 4 else { return nil }
        var lo = 0, hi = beats.count - 1
        while lo < hi { let m = (lo + hi) / 2; if beats[m] < t { lo = m + 1 } else { hi = m } }
        var i = lo
        if i > 0 && abs(beats[i - 1] - t) < abs(beats[i] - t) { i -= 1 }
        let beatLen = 60 / max(bpm, 30)
        guard abs(beats[i] - t) < beatLen * 0.2 else { return nil }
        return ((i - downbeatOffset) % 4 + 4) % 4
    }

    /// Half-time = the snare/clap lands on beat 3 (once a bar) instead of beats 2 and 4.
    var groove: (feel: GrooveFeel, confidence: Double) {
        let beatsPerSec = max(bpm, 30) / 60
        let kickPerBeat = Double(kicks.count) / max(duration * beatsPerSec, 1)
        var ph = [0, 0, 0, 0]
        for s in snares { if let p = beatPhase(s) { ph[p] += 1 } }
        let total = ph.reduce(0, +)
        if total >= 8 {
            let back = Double(ph[1] + ph[3]) / Double(total), three = Double(ph[2]) / Double(total)
            let snarePerBeat = Double(snares.count) / max(duration * beatsPerSec, 1)
            if three > 0.5 && three > back * 1.5 { return (.half, min(1, three)) }
            if bpm < 100 && snarePerBeat > 0.8 { return (.double, min(1, snarePerBeat - 0.2)) }
            return (.normal, min(1, max(back, 0.5)))
        }
        // Few snares: a fast tempo with sparse kicks still feels half-time
        if bpm >= 130 && kickPerBeat < 0.5 { return (.half, 0.4) }
        return (.normal, 0.4)
    }

    /// The tempo it feels like (70 for a half-time 140 BPM track).
    var feltBPM: Double { bpm * groove.feel.lightRate }

    /// Share of beats with a kick right on them (house / techno "four on the floor").
    var fourOnTheFloor: Double {
        guard !beats.isEmpty, !kicks.isEmpty else { return 0 }
        var hit = 0, j = 0
        for b in beats {
            while j < kicks.count - 1 && kicks[j] < b - 0.05 { j += 1 }
            if abs(kicks[j] - b) < 0.05 || (j > 0 && abs(kicks[j - 1] - b) < 0.05) { hit += 1 }
        }
        return Double(hit) / Double(beats.count)
    }

    /// How much of the music has someone singing (0…1).
    var vocalShare: Double {
        let sung = (vocalPhrases ?? []).reduce(0) { $0 + $1.end - $1.start }
        return min(1, sung / max(musicEnd - musicStart, 1))
    }

    // MARK: Genre with confidence

    /// Likely genres with a confidence for each (they add up to 1), best first. A song can be a mix:
    /// these are tendencies, not rules, and you can always pick the genre yourself.
    var genreScores: [(style: ShowStyle, score: Double)] {
        func avg(_ a: [Float]) -> Double { a.isEmpty ? 0 : Double(a.reduce(0, +)) / Double(a.count) }
        func fit(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
            if v >= lo && v <= hi { return 1 }
            return exp(-min(abs(v - lo), abs(v - hi)) / 8)
        }
        let bassAvg = avg(bass), highAvg = avg(high), energyAvg = avg(energy)
        let mean = energyAvg
        let dyn = energy.isEmpty ? 0 : (energy.reduce(0) { $0 + pow(Double($1) - mean, 2) } / Double(energy.count)).squareRoot()
        let g = groove
        let half = g.feel == .half ? g.confidence : 0
        let ff = fourOnTheFloor
        let hatsPerBeat = Double(hats.count) / max(duration * max(bpm, 30) / 60, 1)
        let vocal = vocalShare
        var ph = [0, 0, 0, 0]; for s in snares { if let p = beatPhase(s) { ph[p] += 1 } }
        let backbeat = snares.isEmpty ? 0 : Double(ph[1] + ph[3]) / Double(max(ph.reduce(0, +), 1))
        let raw = bpm, felt = feltBPM
        var s: [ShowStyle: Double] = [:]
        s[.dubstep] = fit(raw, 135, 150) * (0.25 + 0.75 * half) * (0.4 + bassAvg)
        s[.club] = fit(raw, 118, 132) * (0.25 + 0.75 * ff) * (0.5 + bassAvg)
        s[.techno] = fit(raw, 125, 145) * (0.2 + 0.8 * ff) * (1.1 - vocal) * (0.6 + 0.4 * min(1, hatsPerBeat))
        s[.electronic] = fit(raw, 100, 140) * 0.45 * (0.6 + 0.4 * (1 - vocal)) * (0.5 + bassAvg)
        s[.disco] = fit(raw, 110, 130) * (0.3 + 0.7 * ff) * (0.4 + 0.6 * min(1, hatsPerBeat / 2)) * (0.4 + 0.6 * vocal) * 0.8
        s[.hiphop] = fit(felt, 70, 105) * (0.4 + bassAvg) * (0.3 + 0.7 * max(backbeat, half)) * (1 - ff * 0.6)
        s[.latin] = fit(raw, 85, 105) * 0.35 * (0.5 + bassAvg) * (1 - ff * 0.5)
        s[.pop] = fit(raw, 90, 130) * (0.3 + 0.7 * vocal) * 0.75
        s[.rock] = fit(raw, 90, 160) * (0.3 + 0.7 * backbeat) * (0.5 + highAvg) * (1 - ff * 0.5) * (1 - bassAvg * 0.5)
        s[.chill] = (1 - energyAvg) * fit(raw, 60, 110) * 0.9
        s[.hyperpop] = fit(raw, 140, 185) * (0.4 + highAvg) * (0.5 + dyn * 2) * 0.6
        s[.psychedelic] = 0.08
        s[.fantasy] = 0.06
        let total = max(s.values.reduce(0, +), 1e-9)
        return s.map { ($0.key, $0.value / total) }.sorted { $0.1 > $1.1 }.map { (style: $0.0, score: $0.1) }
    }

    /// e.g. "Dubstep / Bass 48% · Club / EDM 22% · Electronic 12%"
    var genreSummary: String {
        genreScores.prefix(3).map { "\($0.style.rawValue) \(Int(($0.score * 100).rounded()))%" }.joined(separator: " · ")
    }
}

// MARK: - Artist-inspired lighting modes (from the lighting design guide, section 9)

/// A design approach learned from how modern concert lighting is done. These teach general principles
/// (restraint, contrast, movement, color, impact), not copies of anyone's show.
enum DesignMode: String, CaseIterable, Codable, Identifiable {
    case automatic = "Automatic"
    case atmospheric = "Atmospheric Emotional"
    case cinematic = "Cinematic Dramatic"
    case industrialClub = "Industrial Club"
    case fantasyTheater = "Fantasy Theater"
    case retroPop = "Retro Pop Performance"
    case organic = "Experimental Organic"
    case interactive = "Interactive Electronic"
    case stadiumPop = "Theatrical Stadium Pop"
    case immersive = "Immersive Electronic"
    case dancePop = "Choreographed Dance-Pop"
    case audienceImmersive = "Audience Immersive"
    case industrialExperimental = "Industrial Experimental"
    var id: String { rawValue }

    var inspiredBy: String {
        switch self {
        case .automatic: return "follows the genre"
        case .atmospheric: return "Billie Eilish"
        case .cinematic: return "The Weeknd"
        case .industrialClub: return "Charli xcx"
        case .fantasyTheater: return "Melanie Martinez"
        case .retroPop: return "Sabrina Carpenter"
        case .organic: return "Björk"
        case .interactive: return "Fred again.."
        case .stadiumPop: return "Taylor Swift"
        case .immersive: return "RÜFÜS DU SOL"
        case .dancePop: return "Dua Lipa"
        case .audienceImmersive: return "Coldplay"
        case .industrialExperimental: return "Nine Inch Nails"
        }
    }

    var blurb: String {
        switch self {
        case .automatic: return "The genre decides."
        case .atmospheric: return "Restraint and darkness; follows the vocal; big changes only at real turning points."
        case .cinematic: return "One consistent color world, strong contrast, dramatic scene changes."
        case .industrialClub: return "Limited palette, hard contrast, sudden cuts, rhythmic repetition."
        case .fantasyTheater: return "Surreal, storybook colors; gentle atmosphere with dramatic moments."
        case .retroPop: return "Warm theatrical washes, polished transitions, playful hits on the hooks."
        case .organic: return "Slow, evolving, textural; doesn't depend on drums."
        case .interactive: return "Follows loops and density; intimate parts vs full-room energy."
        case .stadiumPop: return "A strong visual theme for the song, repeated and varied."
        case .immersive: return "Long builds, layered movement, drama saved for the peaks."
        case .dancePop: return "Tight rhythm, big chorus changes, repeated looks for the hooks."
        case .audienceImmersive: return "Whole-room color moments; big collective peaks."
        case .industrialExperimental: return "Shadows and negative space, geometric patterns, harsh contrast."
        }
    }

    /// How this mode shapes a show.
    struct Traits {
        var restraint = 0.0        // 0…1: dims and calms the quieter parts
        var movement = 1.0         // multiplier on how much the heads move (0 = still)
        var accents = 1.0          // 0…1.5: how much blinder / strobe accent use
        var palette: String? = nil // one color world for the whole song (nil = genre palettes)
        var peakPalette: String? = nil
        var darkBetween = false    // dark gaps / hard cuts at section changes
        var slow = false           // slower, evolving effects
    }

    var traits: Traits {
        switch self {
        case .automatic: return Traits()
        case .atmospheric: return Traits(restraint: 0.8, movement: 0.4, accents: 0.4, palette: "Deep Blue", peakPalette: nil, darkBetween: true, slow: true)
        case .cinematic: return Traits(restraint: 0.5, movement: 0.7, accents: 0.8, palette: "Red Velvet", darkBetween: true)
        case .industrialClub: return Traits(restraint: 0.3, movement: 0.6, accents: 1.4, palette: "Lime Club", darkBetween: true)
        case .fantasyTheater: return Traits(restraint: 0.4, movement: 0.8, accents: 0.6, palette: "Fantasy", peakPalette: "Fairy")
        case .retroPop: return Traits(restraint: 0.3, movement: 0.8, accents: 0.8, palette: "Gold", peakPalette: "Pop Candy")
        case .organic: return Traits(restraint: 0.6, movement: 0.6, accents: 0.3, palette: "Aurora", slow: true)
        case .interactive: return Traits(restraint: 0.4, movement: 1.0, accents: 1.0)
        case .stadiumPop: return Traits(restraint: 0.2, movement: 1.1, accents: 1.0)
        case .immersive: return Traits(restraint: 0.5, movement: 1.0, accents: 0.7, palette: "Galaxy", slow: true)
        case .dancePop: return Traits(restraint: 0.2, movement: 1.2, accents: 1.0, peakPalette: "Disco")
        case .audienceImmersive: return Traits(restraint: 0.3, movement: 1.0, accents: 1.1, peakPalette: "Rainbow")
        case .industrialExperimental: return Traits(restraint: 0.6, movement: 0.7, accents: 1.2, palette: "Red Room", darkBetween: true)
        }
    }
}

/// One mode for the whole song, or one for the quieter parts and another for the peaks
/// (e.g. Atmospheric Emotional verses with Cinematic Dramatic choruses).
struct DesignBlend: Codable, Hashable {
    var base: DesignMode = .automatic
    var peaks: DesignMode? = nil
    func mode(for level: EnergyLevel) -> DesignMode {
        (level == .high || level == .drop) ? (peaks ?? base) : base
    }
    var isAutomatic: Bool { base == .automatic && (peaks == nil || peaks == .automatic) }
    var label: String {
        if let p = peaks, p != base { return "\(base.rawValue) → \(p.rawValue) peaks" }
        return base.rawValue
    }
}

extension ShowGenerator {
    /// A show for the song in a genre, shaped by its groove and the chosen lighting mode(s).
    static func generateShaped(_ a: SongAnalysis, style: ShowStyle, variation: Int, design: DesignBlend?) -> [ShowSection] {
        var secs = generate(a, style: style, variation: variation)
        shape(&secs, analysis: a, design: design)
        return secs
    }

    /// Applies the groove (half-time slows pulses and movement) and the lighting mode to a show.
    static func shape(_ sections: inout [ShowSection], analysis a: SongAnalysis, design: DesignBlend?) {
        let feel = a.groove
        if feel.feel != .normal && feel.confidence >= 0.5 {
            for i in sections.indices where ![.strobe, .stutter, .sparkle, .blackout].contains(sections[i].effect) {
                sections[i].rate *= feel.feel.lightRate
            }
        }
        guard let design, !design.isAutomatic else { return }
        for i in sections.indices {
            let m = design.mode(for: sections[i].level)
            let t = m.traits
            let quiet = sections[i].level == .low || sections[i].level == .medium
            if quiet {
                sections[i].intensity *= 1 - 0.45 * t.restraint
                if t.restraint >= 0.6 && sections[i].level == .low { sections[i].movement = .none }
            }
            if t.movement < 0.5 && sections[i].level != .drop { sections[i].movement = .none }
            if t.slow && quiet { sections[i].rate *= 0.5 }
            if let p = (quiet ? nil : t.peakPalette) ?? t.palette, Palette.exists(p) { sections[i].palette = p }
            sections[i].accents = t.accents
            if t.darkBetween && !quiet && i > 0 && sections[i - 1].level != sections[i].level {
                sections[i].accentStrobe = false     // a hard cut in, no strobe intro
            }
        }
    }
}
