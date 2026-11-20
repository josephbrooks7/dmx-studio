import Foundation

/// A big moment in the song that gets a white accent on top of the section's color look:
/// a blinder hit, a strobe stutter on a drum fill, or a strobe that speeds up into a drop.
enum AccentKind: String, Codable { case blinder, stutter, ramp }

struct Accent: Codable, Hashable {
    var kind: AccentKind
    var start: Double
    var end: Double
    var division: Double = 1      // flashes per beat (2 = 8ths, 3 = triplets, 4 = 16ths …)
    var reason: String = ""
}

/// Finds where white accents belong. Used sparingly: drops and choruses get them, quiet parts never do.
enum AccentFinder {
    static func find(_ a: SongAnalysis) -> [Accent] {
        guard a.bpm > 30 else { return [] }
        let beat = 60 / a.bpm, bar = beat * 4
        let secs = a.detectedSections
        func rank(_ l: EnergyLevel) -> Int { switch l { case .low: return 0; case .medium: return 1; case .high: return 2; case .drop: return 3 } }
        func section(at t: Double) -> DetectedSection? { secs.last { $0.start <= t + 0.01 } }
        func nearestHit(_ t: Double, within w: Double) -> Double {
            var best = t, bd = w
            for k in a.kicks + a.snares where abs(k - t) < bd { bd = abs(k - t); best = k }
            return best
        }
        var out: [Accent] = []

        // 1. Into a drop / big section: the strobe speeds up over the last bars, then a blinder hit
        for i in secs.indices.dropFirst() {
            let cur = secs[i], prev = secs[i - 1]
            guard rank(cur.level) >= 2, rank(cur.level) > rank(prev.level), cur.end - cur.start >= bar * 2 else { continue }
            let hit = nearestHit(cur.start, within: 0.15)
            if cur.level == .drop || rank(cur.level) - rank(prev.level) >= 2, prev.end - prev.start >= bar * 2 {
                let len = min(bar * 2, (prev.end - prev.start) / 2)
                out.append(Accent(kind: .ramp, start: hit - len, end: hit, division: 1, reason: "build into the \(cur.name)"))
            }
            out.append(Accent(kind: .blinder, start: hit, end: hit + 0.6, reason: "\(cur.name) hits"))
        }

        // 2. Drum fills / snare rolls inside lively parts: a strobe stutter at the roll's own speed
        let sn = a.snares
        var i = 0
        while i < sn.count {
            var j = i
            while j + 1 < sn.count && sn[j + 1] - sn[j] <= max(0.17, beat / 3) { j += 1 }
            if j - i + 1 >= 4, sn[j] - sn[i] >= 0.45, let s = section(at: sn[i]), rank(s.level) >= 1 {
                let gaps = (i..<j).map { sn[$0 + 1] - sn[$0] }.sorted()
                let per = beat / gaps[gaps.count / 2]
                let div = [2.0, 3, 4, 6, 8].min { abs($0 - per) < abs($1 - per) } ?? 4
                out.append(Accent(kind: .stutter, start: sn[i], end: sn[j] + beat / div, division: div, reason: "drum fill"))
            }
            i = j + 1
        }

        // 3. Hardest hits in high-energy parts: a sudden jump in loudness on a kick/snare
        var lastBlinder = -99.0
        for t in (a.kicks + a.snares).sorted() {
            guard let s = section(at: t), rank(s.level) >= 2 else { continue }
            if out.contains(where: { abs($0.start - t) < bar * 2 }) || t - lastBlinder < bar * 4 { continue }
            let now = a.value(a.energy, at: t + 0.1)
            var before = 0.0, n = 0
            var u = t - 1.5
            while u < t - 0.25 { before += a.value(a.energy, at: u); n += 1; u += 0.1 }
            before /= Double(max(n, 1))
            let together = a.kicks.contains { abs($0 - t) < 0.04 } && a.snares.contains { abs($0 - t) < 0.04 }
            if now - before > 0.22 || (together && now > 0.85 && now - before > 0.1) {
                out.append(Accent(kind: .blinder, start: t, end: t + 0.6, reason: together ? "kick + snare impact" : "big hit"))
                lastBlinder = t
            }
        }
        return out.sorted { $0.start < $1.start }
    }
}
