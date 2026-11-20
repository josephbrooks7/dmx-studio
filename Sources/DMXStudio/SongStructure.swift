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

        // ---- 1. where the parts change: loudness/tone, singing on/off, and chord pattern
        let k = nb >= 32 ? 4 : 2
        var novelty = [Double](repeating: 0, count: nb)
        if nb > 2 * k {
            for b in k...(nb - k) {
                var d = 0.0
                for f in 0..<4 {
                    var before = 0.0, after = 0.0
                    for j in 0..<k { before += tone[b - 1 - j][f]; after += tone[min(nb - 1, b + j)][f] }
                    d += pow((after - before) / Double(k), 2)
                }
                var vb = 0.0, va = 0.0
                for j in 0..<k { vb += voc[b - 1 - j]; va += voc[min(nb - 1, b + j)] }
                d += pow((va - vb) / Double(k), 2) * 0.6
                // chord pattern: how unlike the bars after are from the bars before
                var cs = 0.0
                for j in 0..<k { cs += cosine(chromaBar[b - 1 - j], chromaBar[min(nb - 1, b + j)]) }
                d += max(0, 0.5 - cs / Double(k)) * 0.35
                novelty[b] = sqrt(d)
            }
        }
        let nMean = novelty.reduce(0, +) / Double(nb)
        let nStd = sqrt(novelty.map { pow($0 - nMean, 2) }.reduce(0, +) / Double(nb))
        let minBars = 4
        // phrase grid: songs change on 4-bar phrases; snap to it
        let firstMusicBar = bars.firstIndex { $0 >= musicStart - 0.05 } ?? 0
        let cands = (1..<nb).filter { novelty[$0] > nMean + 0.35 * nStd }.sorted { novelty[$0] > novelty[$1] }
        var chosen: [Int] = []
        for c in cands {
            var cc = c
            let off = (c - firstMusicBar) % 4
            if off == 1 { cc = c - 1 } else if off == 3 { cc = c + 1 }
            guard cc > 0, cc < nb, chosen.allSatisfy({ abs($0 - cc) >= minBars }),
                  cc >= 2, nb - cc >= 2 else { continue }
            chosen.append(cc)
        }
        // where singing starts or stops for a while is always a boundary (on the nearest phrase line)
        for b in 1..<nb where (voc[b] > 0.4) != (voc[b - 1] > 0.4) {
            let run = (b..<min(nb, b + 4)).allSatisfy { (voc[$0] > 0.4) == (voc[b] > 0.4) }
            guard run else { continue }
            var cc = b
            let off = (b - firstMusicBar) % 4
            if off == 1 { cc = b - 1 } else if off == 3 { cc = b + 1 }
            if cc > 0, cc < nb, chosen.allSatisfy({ abs($0 - cc) >= 2 }) { chosen.append(cc) }
        }
        chosen.sort()
        // edges in seconds, plus the start / end of the music
        var edges: [Double] = [0]
        edges += chosen.map { bars[$0] }.filter { $0 > musicStart + 2 && $0 < mEnd - 2 }
        if musicStart > 0.3 { edges.append(musicStart) }
        edges.append(mEnd)
        if mEnd < duration - 0.3 { edges.append(duration) }
        edges = Array(Set(edges.map { ($0 * 1000).rounded() / 1000 })).sorted()
        func barIndex(_ t: Double) -> Int { (bars.lastIndex { $0 <= t + 0.05 }) ?? 0 }
        var segs: [Seg] = []
        for j in 0..<(edges.count - 1) {
            let a = edges[j], b = edges[j + 1]
            guard b - a > 0.3 else { continue }
            var s = Seg(a: barIndex(a), b: max(barIndex(a) + 1, barIndex(b)), start: a, end: b)
            s.energy = mean(an.energy, a, b)
            s.vocal = vocalFrac(a, b)
            segs.append(s)
        }
        func silent(_ s: Seg) -> Bool { s.end <= musicStart + 0.01 || s.start >= mEnd - 0.01 }
        let musical = segs.indices.filter { !silent(segs[$0]) }
        guard !musical.isEmpty else { return [DetectedSection(start: 0, end: duration, energy: 0, level: .low, name: "Silence")] }
        let eMin = musical.map { segs[$0].energy }.min()!, eMax = musical.map { segs[$0].energy }.max()!
        let eRange = max(eMax - eMin, 1e-4)
        func e01(_ s: Seg) -> Double { musical.count == 1 ? 0.6 : (s.energy - eMin) / eRange }

        // ---- 2. which parts are the same part again (same chord pattern, similar loudness and singing)
        func sim(_ x: Seg, _ y: Seg) -> Double {
            let n = min(x.b - x.a, y.b - y.a)
            guard n > 0 else { return -1 }
            var best = -1.0
            for o in 0..<min(4, max(1, (y.b - y.a) - n + 1)) {     // allow a slightly different start
                var c = 0.0
                for j in 0..<n { c += cosine(chromaBar[min(nb - 1, x.a + j)], chromaBar[min(nb - 1, y.a + o + j)]) }
                best = max(best, c / Double(n))
            }
            return best - 0.7 * abs(e01(x) - e01(y)) - 0.5 * abs(x.vocal - y.vocal)
        }
        var group = 0
        for i in musical where segs[i].group < 0 {
            segs[i].group = group
            for j in musical where j > i && segs[j].group < 0 && sim(segs[i], segs[j]) > 0.45 { segs[j].group = group }
            group += 1
        }

        // ---- 3. name them
        let sungSong = vocals != nil && an.vocalShare > 0.08
        let sung = musical.filter { segs[$0].vocal >= 0.3 }
        var chorusGroup = -1, verseGroup = -1
        if sungSong && !sung.isEmpty {
            var groups: [Int: (count: Int, energy: Double, len: Double, first: Double)] = [:]
            for i in sung {
                let g = segs[i].group, cur = groups[g] ?? (0, 0, 0, segs[i].start)
                groups[g] = (cur.count + 1, cur.energy + e01(segs[i]), cur.len + segs[i].end - segs[i].start, min(cur.first, segs[i].start))
            }
            let median = sung.map { e01(segs[$0]) }.sorted()[sung.count / 2]
            chorusGroup = groups.max { a, b in
                let sa = a.value.energy / Double(a.value.count) + 0.12 * Double(min(a.value.count, 4))
                let sb = b.value.energy / Double(b.value.count) + 0.12 * Double(min(b.value.count, 4))
                return sa < sb
            }.map { g in g.value.energy / Double(g.value.count) >= median - 0.05 ? g.key : -1 } ?? -1
            let firstChorus = groups[chorusGroup]?.first ?? duration
            verseGroup = groups.filter { $0.key != chorusGroup }
                .max { a, b in
                    let pa = (a.value.first < firstChorus ? 1.0 : 0.0) * 1000 + a.value.len
                    let pb = (b.value.first < firstChorus ? 1.0 : 0.0) * 1000 + b.value.len
                    return pa < pb
                }?.key ?? -1
        }
        let chorusE = chorusGroup >= 0 ? sung.filter { segs[$0].group == chorusGroup }.map { e01(segs[$0]) }.reduce(0, +)
            / Double(max(1, sung.filter { segs[$0].group == chorusGroup }.count)) : 0.8
        let groupCount = Dictionary(grouping: musical, by: { segs[$0].group }).mapValues(\.count)
        var chorusesSoFar = 0
        let firstM = musical.first!, lastM = musical.last!
        for (n, i) in musical.enumerated() {
            let s = segs[i], e = e01(s)
            let nextI = n + 1 < musical.count ? musical[n + 1] : nil
            let nextE = nextI.map { e01(segs[$0]) } ?? 0
            let barsLong = s.b - s.a
            var role: String
            if sungSong && s.vocal >= 0.3 {
                if s.group == chorusGroup { role = "Chorus" }
                else if s.group == verseGroup && chorusesSoFar < 3 { role = "Verse" }
                else if let ni = nextI, segs[ni].group == chorusGroup, barsLong <= 12, segs[ni].vocal >= 0.3 { role = "Pre-Chorus" }
                else if n > 0, segs[musical[n - 1]].role == "Chorus", e >= chorusE - 0.15, barsLong <= 8 { role = "Post-Chorus" }
                else if chorusesSoFar >= 2 && (groupCount[s.group] ?? 1) == 1 { role = "Bridge" }
                else if chorusGroup >= 0 && e >= chorusE - 0.1 { role = "Chorus" }
                else { role = "Verse" }
            } else {
                // no singing here
                if i == firstM { role = "Intro" }
                else if i == lastM { role = "Outro" }
                else if barsLong <= 16, nextE - e > 0.2, e < 0.75 { role = "Build" }
                else if e >= 0.7 {
                    let prevE = n > 0 ? e01(segs[musical[n - 1]]) : 0
                    role = (e - prevE > 0.3 || !sungSong) ? "Drop" : "Instrumental"
                } else if e < 0.34 { role = "Breakdown" }
                else { role = sungSong ? "Instrumental" : "Groove" }
            }
            if role == "Chorus" { chorusesSoFar += 1 }
            segs[i].role = role
        }
        // a short sung part at the very start/end is still the intro/outro
        if let f = musical.first, segs[f].role == "Verse", segs[f].b - segs[f].a <= 4, musical.count > 3 { segs[f].role = "Intro" }
        if let l = musical.last, segs[l].role != "Chorus", segs[l].b - segs[l].a <= 8, e01(segs[l]) < 0.6, musical.count > 3 { segs[l].role = "Outro" }

        // ---- 4. merge neighbours that are the same part, number them, and set the energy level
        var merged: [Seg] = []
        for s in segs {
            if let last = merged.last, !silent(s), !silent(last), last.role == s.role, s.role != "Silence" {
                merged[merged.count - 1].end = s.end
                merged[merged.count - 1].b = s.b
                merged[merged.count - 1].energy = (last.energy + s.energy) / 2
            } else { merged.append(s) }
        }
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
