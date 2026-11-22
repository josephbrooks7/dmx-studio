import Foundation

/// Works out a song's parts the way they're actually built: phrases of 4/8 bars; a chorus repeats with
/// the same chords and is usually the loudest sung part; verses repeat with their own chords; a
/// pre-chorus leads into each chorus; a bridge shows up once, late, and sounds different; builds are
/// short rises with no singing; intro/outro sit at the ends.
enum SongStructure {
    private struct Seg {
        var a: Int, b: Int                 // bar range [a, b)
        var start: Double, end: Double
        var energy = 0.0, vocal = 0.0
        var group = -1
        var role = ""
    }

    static func sections(_ an: SongAnalysis, chroma: [[Float]], vocals: [TimeSpan]?) -> [DetectedSection] {
        let duration = an.duration, fps = an.frameRate
        let musicStart = an.musicStart, mEnd = an.musicEnd
        // Bars (4 beats) from the first downbeat
        var bars: [Double] = []
        var i = an.downbeatOffset
        while i < an.beats.count { bars.append(an.beats[i]); i += 4 }
        if bars.isEmpty || bars[0] > 0.5 { bars.insert(0, at: 0) }
        let nb = bars.count
        guard nb >= 6 else {
            return [DetectedSection(start: 0, end: duration, energy: 0.6, level: .medium, name: "Full Song")]
        }
        func barEnd(_ b: Int) -> Double { b + 1 < nb ? bars[b + 1] : duration }
        func mean(_ arr: [Float], _ a: Double, _ b: Double) -> Double {
            let s = max(0, Int(a * fps)), e = min(arr.count, max(s + 1, Int(b * fps)))
            guard e > s else { return 0 }
            return Double(arr[s..<e].reduce(0, +)) / Double(e - s)
        }
        let vox = vocals ?? []
        func vocalFrac(_ a: Double, _ b: Double) -> Double {
            let sung = vox.reduce(0.0) { $0 + max(0, min($1.end, b) - max($1.start, a)) }
            return min(1, sung / max(b - a, 0.01))
        }
        // Per-bar features: loudness/tone, singing, and the chord colour (chroma, minus the song's average key)
        var chromaBar: [[Double]] = []
        var tone: [[Double]] = []
        var voc: [Double] = []
        var eng: [Double] = []
        for b in 0..<nb {
            let a = bars[b], z = barEnd(b)
            let s = max(0, Int(a * fps)), e = min(chroma.count, max(s + 1, Int(z * fps)))
            var c = [Double](repeating: 0, count: 12)
            if e > s { for f in s..<e { for k in 0..<12 { c[k] += Double(chroma[f][k]) } }; for k in 0..<12 { c[k] /= Double(e - s) } }
            chromaBar.append(c)
            eng.append(mean(an.energy, a, z))
            tone.append([mean(an.energy, a, z) * 2, mean(an.bass, a, z), mean(an.mid, a, z), mean(an.high, a, z)])
            voc.append(vocalFrac(a, z))
        }
        var avgC = [Double](repeating: 0, count: 12)
        for c in chromaBar { for k in 0..<12 { avgC[k] += c[k] / Double(nb) } }
        for b in 0..<nb {
            var v = (0..<12).map { chromaBar[b][$0] - avgC[$0] }
            let n = sqrt(v.reduce(0) { $0 + $1 * $1 })
            if n > 1e-9 { v = v.map { $0 / n } }
            chromaBar[b] = v
        }
        func cosine(_ x: [Double], _ y: [Double]) -> Double { zip(x, y).reduce(0) { $0 + $1.0 * $1.1 } }

        // ---- 1. cut the music into 4-bar phrases (songs are built from them) and group the phrases
        //         that are the same part again: same chord pattern, similar loudness, singing or not
        let firstMusicBar = bars.firstIndex { $0 >= musicStart - 0.05 } ?? 0
        let lastBar = min(nb, (bars.lastIndex { $0 < mEnd - 0.05 } ?? (nb - 1)) + 1)
        var blocks: [(a: Int, b: Int)] = []
        var b0 = firstMusicBar
        while b0 < lastBar { blocks.append((b0, min(b0 + 4, lastBar))); b0 += 4 }
        guard !blocks.isEmpty else {
            return [DetectedSection(start: 0, end: duration, energy: 0.6, level: .medium, name: "Full Song")]
        }
        func avg(_ x: (a: Int, b: Int), _ v: [Double]) -> Double {
            (x.a..<x.b).reduce(0.0) { $0 + v[$1] } / Double(max(1, x.b - x.a))
        }
        let eMinB = blocks.map { avg($0, eng) }.min() ?? 0, eMaxB = blocks.map { avg($0, eng) }.max() ?? 1
        func chordSim(_ x: (a: Int, b: Int), _ y: (a: Int, b: Int)) -> Double {
            let n = min(x.b - x.a, y.b - y.a)
            guard n > 0 else { return -1 }
            var c = 0.0
            for j in 0..<n { c += cosine(chromaBar[x.a + j], chromaBar[y.a + j]) }
            return c / Double(n)
        }
        // Many songs loop one chord progression the whole way through (Zedd "Clarity": the same 4 chords
        // in the verse, pre-chorus, chorus and drop; Britney's verse / pre-chorus / chorus share most chords).
        // Then the chords can't tell the parts apart, so loudness and singing decide instead.
        var pairSum = 0.0, pairs = 0
        let stepB = max(1, blocks.count / 24)
        for i in stride(from: 0, to: blocks.count, by: stepB) {
            for j in stride(from: i + stepB, to: blocks.count, by: stepB) { pairSum += chordSim(blocks[i], blocks[j]); pairs += 1 }
        }
        let oneLoop = pairs > 3 && pairSum / Double(pairs) > 0.7
        let eW = oneLoop ? 0.9 : 0.35, vW = oneLoop ? 0.5 : 0.25
        func bsim(_ x: (a: Int, b: Int), _ y: (a: Int, b: Int)) -> Double {
            let c = chordSim(x, y)
            guard c > -1 else { return -1 }
            let de = abs(avg(x, eng) - avg(y, eng)) / max(eMaxB - eMinB, 1e-4)
            return c - eW * de - vW * abs(avg(x, voc) - avg(y, voc))
        }
        var bgroup = [Int](repeating: -1, count: blocks.count)
        var ng = 0
        for i in blocks.indices where bgroup[i] < 0 {
            bgroup[i] = ng
            for j in blocks.indices where j > i && bgroup[j] < 0 && bsim(blocks[i], blocks[j]) > 0.6 { bgroup[j] = ng }
            ng += 1
        }
        // a part = a run of phrases from the same group
        var segs: [Seg] = []
        if musicStart > 0.3 { segs.append(Seg(a: 0, b: firstMusicBar, start: 0, end: musicStart)) }
        var r = 0
        while r < blocks.count {
            var q = r
            while q + 1 < blocks.count && bgroup[q + 1] == bgroup[r] { q += 1 }
            let st = r == 0 ? musicStart : bars[blocks[r].a]
            let en = q == blocks.count - 1 ? mEnd : bars[blocks[q + 1].a]
            var sg = Seg(a: blocks[r].a, b: blocks[q].b, start: st, end: en)
            sg.energy = mean(an.energy, st, en)
            sg.vocal = vocalFrac(st, en)
            sg.group = bgroup[r]
            segs.append(sg)
            r = q + 1
        }
        if mEnd < duration - 0.3 { segs.append(Seg(a: lastBar, b: nb, start: mEnd, end: duration)) }
        func silent(_ s: Seg) -> Bool { s.end <= musicStart + 0.01 || s.start >= mEnd - 0.01 }
        let musical = segs.indices.filter { !silent(segs[$0]) }
        guard !musical.isEmpty else { return [DetectedSection(start: 0, end: duration, energy: 0, level: .low, name: "Silence")] }
        let eMin = musical.map { segs[$0].energy }.min()!, eMax = musical.map { segs[$0].energy }.max()!
        let eRange = max(eMax - eMin, 1e-4)
        func e01(_ s: Seg) -> Double { musical.count == 1 ? 0.6 : (s.energy - eMin) / eRange }

        // ---- 3. name them. Works from the music itself (chord pattern, repetition, loudness), so
        //         backing / performance tracks made to be sung over get verses and choruses too;
        //         singing, when there is some, only nudges the choice.
        let firstM = musical.first!, lastM = musical.last!
        func once(_ i: Int) -> Bool { musical.filter { segs[$0].group == segs[i].group }.count == 1 }
        let introI: Int? = musical.count > 2 && (e01(segs[firstM]) < 0.5 || once(firstM)) ? firstM : nil
        let outroI: Int? = musical.count > 3 && (e01(segs[lastM]) < 0.6 || once(lastM)) ? lastM : nil
        let body = musical.filter { $0 != introI && $0 != outroI }
        var groups: [Int: (count: Int, energy: Double, len: Double, first: Double, vocal: Double)] = [:]
        for i in body {
            let g = segs[i].group, cur = groups[g] ?? (0, 0, 0, segs[i].start, 0)
            groups[g] = (cur.count + 1, cur.energy + e01(segs[i]), cur.len + segs[i].end - segs[i].start,
                         min(cur.first, segs[i].start), cur.vocal + segs[i].vocal)
        }
        let anyRepeat = groups.values.contains { $0.count >= 2 }
        let chorusGroup = groups.filter { !anyRepeat || $0.value.count >= 2 }.max { a, b in
            func score(_ v: (count: Int, energy: Double, len: Double, first: Double, vocal: Double)) -> Double {
                v.energy / Double(v.count) + 0.12 * Double(min(v.count, 4)) + 0.1 * v.vocal / Double(v.count)
            }
            return score(a.value) < score(b.value)
        }?.key ?? -1
        let firstChorus = groups[chorusGroup]?.first ?? duration
        let verseGroup = groups.filter { $0.key != chorusGroup }.max { a, b in
            let pa = (a.value.first < firstChorus ? 1.0 : 0.0) * 1000 + a.value.len
            let pb = (b.value.first < firstChorus ? 1.0 : 0.0) * 1000 + b.value.len
            return pa < pb
        }?.key ?? -1
        let chorusE = groups[chorusGroup].map { $0.energy / Double($0.count) } ?? 0.8
        var chorusesSoFar = 0
        for (n, i) in musical.enumerated() {
            let s = segs[i], e = e01(s)
            let nextI = n + 1 < musical.count ? musical[n + 1] : nil
            let barsLong = s.b - s.a
            var role: String
            if i == introI { role = "Intro" }
            else if i == outroI { role = "Outro" }
            else if s.group == chorusGroup { role = "Chorus" }
            else if s.group == verseGroup && chorusesSoFar < 3 { role = "Verse" }
            // a bridge: comes after two choruses, appears once, and is a full part (not a 4-bar lead-in)
            else if chorusesSoFar >= 2 && once(i) && barsLong >= 6 { role = "Bridge" }
            else if let ni = nextI, segs[ni].group == chorusGroup, barsLong <= 16 { role = "Pre-Chorus" }   // trimmed to its last 4–8 bars below
            else if n > 0, segs[musical[n - 1]].role == "Chorus", e >= chorusE - 0.15, barsLong <= 8 { role = "Post-Chorus" }
            else if chorusesSoFar >= 2 && once(i) { role = "Bridge" }
            else if e < 0.25 { role = "Breakdown" }
            else if e >= chorusE - 0.1 { role = "Chorus" }
            else { role = "Verse" }
            if role == "Chorus" { chorusesSoFar += 1 }
            segs[i].role = role
        }
        let sungSong = vocals != nil && an.vocalShare > 0.08
        // a short sung part at the very start/end is still the intro/outro
        if let f = musical.first, segs[f].role == "Verse", segs[f].b - segs[f].a <= 4, musical.count > 3 { segs[f].role = "Intro" }
        if let l = musical.last, segs[l].role != "Chorus", segs[l].b - segs[l].a <= 8, e01(segs[l]) < 0.6, musical.count > 3 { segs[l].role = "Outro" }

        if ProcessInfo.processInfo.environment["DMX_DEBUG_STRUCTURE"] != nil {
            for s in segs { print(String(format: "seg %.1f-%.1f bars %d-%d e=%.2f vocal=%.2f group=%d role=%@", s.start, s.end, s.a, s.b, silent(s) ? 0 : e01(s), s.vocal, s.group, s.role)) }
            print("chorusGroup=\(chorusGroup) verseGroup=\(verseGroup) sungSong=\(sungSong)")
        }
        // ---- 4. merge neighbours that are the same part, number them, and set the energy level
        var merged: [Seg] = []
        for s in segs {
            if let last = merged.last, !silent(s), !silent(last), last.role == s.role, s.role != "Silence" {
                merged[merged.count - 1].end = s.end
                merged[merged.count - 1].b = s.b
                merged[merged.count - 1].energy = (last.energy + s.energy) / 2
            } else { merged.append(s) }
        }
        // ---- 4b. keep parts to real-song lengths. A pre-chorus is a short lift into the chorus,
        //          usually 4 bars (8 at most); a post-chorus / hook is 4–8. Anything longer than that is
        //          really the end of the verse (or the next verse), so only the last bars keep the name.
        func shorten(_ role: String, keepLastBars: Bool, max cap: Int, rest: String) {
            var fixed: [Seg] = []
            for s in merged {
                let n = s.b - s.a
                guard s.role == role, !silent(s), n > cap, s.a >= 0, s.b <= bars.count else { fixed.append(s); continue }
                let keep = n >= 16 ? cap : min(4, cap)
                let cut = keepLastBars ? s.b - keep : s.a + keep
                guard cut > s.a, cut < s.b, cut < bars.count else { fixed.append(s); continue }
                var first = s, second = s
                first.b = cut; first.end = bars[cut]
                second.a = cut; second.start = bars[cut]
                if keepLastBars { first.role = rest } else { second.role = rest }
                // join the leftover onto a neighbour that's already that part
                if keepLastBars, let last = fixed.last, last.role == rest, !silent(last) {
                    fixed[fixed.count - 1].b = first.b; fixed[fixed.count - 1].end = first.end
                } else { fixed.append(first) }
                fixed.append(second)
            }
            merged = fixed
        }
        shorten("Pre-Chorus", keepLastBars: true, max: 8, rest: "Verse")
        shorten("Post-Chorus", keepLastBars: false, max: 8, rest: "Verse")

        let numbered: Set<String> = ["Verse", "Chorus", "Pre-Chorus"]
        var counts: [String: Int] = [:]
        let totals = Dictionary(grouping: merged.filter { !silent($0) }, by: \.role).mapValues(\.count)
        var out: [DetectedSection] = []
        var prevE: Double?
        for s in merged {
            if silent(s) { out.append(DetectedSection(start: s.start, end: s.end, energy: 0, level: .low, name: "Silence")); continue }
            let e = e01(s)
            var level: EnergyLevel = e < 0.34 ? .low : e < 0.7 ? .medium : .high
            switch s.role {
            case "Chorus": level = e >= 0.5 ? .high : .medium
            case "Drop": level = .drop
            case "Verse", "Pre-Chorus", "Build": if level == .high { level = .medium }
            case "Intro", "Outro", "Breakdown": if level == .high { level = .medium }
            default: break
            }
            if s.role == "Chorus", let p = prevE, e - p > 0.45, !sungSong { level = .drop }
            prevE = e
            counts[s.role, default: 0] += 1
            let c = counts[s.role]!
            let name = (numbered.contains(s.role) || (totals[s.role] ?? 0) > 1) ? "\(s.role) \(c)" : s.role
            out.append(DetectedSection(start: s.start, end: s.end, energy: e, level: level, name: name))
        }
        return out
    }
}
