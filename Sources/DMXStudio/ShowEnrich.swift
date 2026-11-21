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
}
