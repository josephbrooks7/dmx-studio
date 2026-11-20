import Foundation
import AVFoundation
import Accelerate

/// Listens to a song file and works out tempo, beats, drum hits, energy and sections.
enum AudioAnalyzer {
    static let sampleRate: Double = 22050
    static let fftSize = 1024
    static let hop = 512

    enum AnalyzeError: LocalizedError {
        case cannotRead(String)
        case tooShort
        var errorDescription: String? {
            switch self {
            case .cannotRead(let s): return "Couldn't read audio: \(s)"
            case .tooShort: return "The song is too short to analyze."
            }
        }
    }

    static func analyze(url: URL, settings: DetectionSettings = DetectionSettings(), stemsDir: URL? = nil, highQuality: Bool = false,
                        progress: @escaping (Double) -> Void) throws -> SongAnalysis {
        var (a, chroma) = try analyzeMix(url: url) { progress($0 * 0.3) }
        // Split into vocals / drums / bass / other, then find the hits and sung phrases on those parts
        do {
            var out: StemSplitter.Output
            if highQuality, HQSplitter.isInstalled, let stemsDir {
                // AI split into 6 parts, then hits from the clean drum part and phrases from the clean vocals
                try HQSplitter.separate(url: url, outDir: stemsDir) { progress(0.3 + $0 * 0.55) }
                // drum hits: the tested method on the full song (on the AI drum part it over-counts kicks)
                let drums = try StemSplitter.run(url: url, settings: settings, stemsDir: nil) { progress(0.85 + $0 * 0.07) }
                let vox = try StemSplitter.run(url: stemsDir.appendingPathComponent("vocals.m4a"), settings: settings, stemsDir: nil) { progress(0.92 + $0 * 0.07) }
                // sung phrases: found on the full song or on the AI vocal part (either one), merged
                let both = (drums.vocalPhrases + audible(vox.vocalPhrases, part: stemsDir.appendingPathComponent("vocals.m4a"), mix: url))
                    .sorted { $0.start < $1.start }
                var phrases: [TimeSpan] = []
                for p in both {
                    if let l = phrases.last, p.start <= l.end + 0.2 { phrases[phrases.count - 1].end = max(l.end, p.end) } else { phrases.append(p) }
                }
                out = StemSplitter.Output(hits: drums.hits, vocalPhrases: phrases, stemsFolder: stemsDir.path)
            } else {
                out = try StemSplitter.run(url: url, settings: settings, stemsDir: stemsDir) { progress(0.3 + $0 * 0.7) }
            }
            a.hits = out.hits
            a.vocalPhrases = out.vocalPhrases
            a.stemsFolder = out.stemsFolder
            a.kicks = out.hits.filter { $0.type == .kick }.map(\.time)
            a.snares = out.hits.filter { $0.type == .snare }.map(\.time)
            a.hats = out.hits.filter { $0.type == .hat }.map(\.time)
            // Song structure from chords, loudness, repetition and where the vocals are
            a.detectedSections = SongStructure.sections(a, chroma: chroma, vocals: out.vocalPhrases)
        } catch {
            a.detectedSections = SongStructure.sections(a, chroma: chroma, vocals: nil)
            FileHandle.standardError.write(Data("stem split skipped: \(error.localizedDescription)\n".utf8))
        }
        a.accents = AccentFinder.find(a)
        progress(1)
        return a
    }

    /// Keeps only phrases where the separated part is actually loud enough to hear in the mix
    /// (a backing track's vocal part is mostly faint leftovers).
    static func audible(_ spans: [TimeSpan], part: URL, mix: URL) -> [TimeSpan] {
        guard let p = try? loadMono(url: part), let m = try? loadMono(url: mix) else { return spans }
        func power(_ x: [Float], _ s: TimeSpan) -> Double {
            let a = max(0, Int(s.start * sampleRate)), b = min(x.count, Int(s.end * sampleRate))
            guard b > a else { return 0 }
            var v: Float = 0
            x.withUnsafeBufferPointer { vDSP_measqv($0.baseAddress! + a, 1, &v, vDSP_Length(b - a)) }
            return Double(v)
        }
        return spans.filter { power(p, $0) >= 0.02 * power(m, $0) }
    }

    /// Tempo, beats, energy and sections from the full mix (plus first-guess drum hits).
    static func analyzeMix(url: URL, progress: @escaping (Double) -> Void) throws -> (SongAnalysis, [[Float]]) {
        let samples = try loadMono(url: url)
        progress(0.2)
        guard samples.count > fftSize * 8 else { throw AnalyzeError.tooShort }
        let duration = Double(samples.count) / sampleRate
        let fps = sampleRate / Double(hop)

        // ---- Spectral features --------------------------------------------------
        let f = spectralFeatures(samples)
        progress(0.6)

        let onset = normalize(f.flux)
        let bassOnset = normalize(f.bassFlux)
        let midOnset = normalize(f.midFlux)
        let highOnset = normalize(f.highFlux)

        // ---- Tempo + beats ------------------------------------------------------
        // Weight the low end so beats land on the kick, not the hi-hat off-beats.
        let beatOnset = normalize(zip(onset, bassOnset).map { $0 + 1.5 * $1 })
        var bpm = estimateTempo(beatOnset, fps: fps)
        var beatFrames = trackBeats(beatOnset, fps: fps, bpm: bpm)
        var beats = beatFrames.map { frameTime($0) }
        if beats.count < 8 {
            // Not much rhythm (ambient / spoken word): fall back to a steady grid.
            bpm = 120
            beats = stride(from: 0.0, to: duration, by: 0.5).map { $0 }
            beatFrames = beats.map { Int($0 * fps) }
        } else {
            // Refine BPM with a straight-line fit through all beat times (finer than one analysis frame)
            let n = Double(beats.count)
            let meanI = (n - 1) / 2
            let meanT = beats.reduce(0, +) / n
            var num = 0.0, den = 0.0
            for (i, t) in beats.enumerated() {
                num += (Double(i) - meanI) * (t - meanT)
                den += (Double(i) - meanI) * (Double(i) - meanI)
            }
            if den > 0, num > 0 { bpm = 60 / (num / den) }
        }

        // Downbeat: the beat phase (of 4) that gets the most kick energy
        var phaseScore = [Float](repeating: 0, count: 4)
        for (i, fr) in beatFrames.enumerated() where fr < bassOnset.count {
            phaseScore[i % 4] += bassOnset[fr]
        }
        let downbeatOffset = phaseScore.indices.max { phaseScore[$0] < phaseScore[$1] } ?? 0
        progress(0.75)

        // ---- Drum hits ----------------------------------------------------------
        let kicks = pickPeaks(bassOnset, fps: fps, minGap: 0.18, sensitivity: 0.12)
        // Snares: need both "body" (150-600 Hz) and "crack" (600-2500 Hz). High frequencies are
        // ignored on purpose, because that's where hi-hats live. Kicks have body but little crack.
        let body = normalize(f.bodyFlux), crack = normalize(f.crackFlux)
        let snareScore = normalize(zip(body, crack).map { 0.6 * $0 + 0.4 * $1 })
        if ProcessInfo.processInfo.environment["DMX_DEBUG_SNARE"] != nil {
            for t in pickPeaks(snareScore, fps: fps, minGap: 0.15, sensitivity: 0.14) {
                let i = min(max(Int(((t * sampleRate - Double(fftSize) / 2) / Double(hop)).rounded()), 0), body.count - 1)
                let lo = max(0, i - 1), hi = min(body.count - 1, i + 1)
                print(String(format: "cand t=%.3f body=%.2f crack=%.2f bass=%.2f high=%.2f", t,
                             body[lo...hi].max() ?? 0, crack[lo...hi].max() ?? 0, bassOnset[lo...hi].max() ?? 0, highOnset[lo...hi].max() ?? 0))
            }
        }
        let snares = pickPeaks(snareScore, fps: fps, minGap: 0.15, sensitivity: 0.14).filter { t in
            let i = min(max(Int(((t * sampleRate - Double(fftSize) / 2) / Double(hop)).rounded()), 0), body.count - 1)
            let lo = max(0, i - 1), hi = min(body.count - 1, i + 1)
            return (body[lo...hi].max() ?? 0) >= 0.45 && (crack[lo...hi].max() ?? 0) >= 0.88
        }
        let hats = pickPeaks(highOnset, fps: fps, minGap: 0.07, sensitivity: 0.10)

        // ---- Energy curves (smoothed, 0-1) -------------------------------------
        let energy = normalize(smooth(f.rms, radius: Int(fps * 0.25)))
        let bassLvl = normalize(smooth(f.bassLevel, radius: 2))
        let midLvl = normalize(smooth(f.midLevel, radius: 2))
        let highLvl = normalize(smooth(f.highLevel, radius: 2))

        // ---- Sections -----------------------------------------------------------
        let silences = detectSilences(rms: f.rms, fps: fps, duration: duration)
        let musicStart = (silences.first.map { $0.start <= 0.05 ? $0.end : 0 }) ?? 0
        let musicEnd = (silences.last.map { $0.end >= duration - 0.05 && $0.start > musicStart ? $0.start : duration }) ?? duration
        let sections = detectSections(beats: beats, downbeatOffset: downbeatOffset, duration: duration, fps: fps,
                                      energy: normalize(f.rms), bass: bassLvl, mid: midLvl, high: highLvl,
                                      musicStart: musicStart, musicEnd: musicEnd)
        progress(1.0)

        return (SongAnalysis(duration: duration, bpm: (bpm * 10).rounded() / 10, beats: beats,
                            downbeatOffset: downbeatOffset, frameRate: fps,
                            energy: energy, bass: bassLvl, mid: midLvl, high: highLvl,
                            kicks: kicks, snares: snares, hats: hats, detectedSections: sections,
                            silences: silences), f.chroma)
    }

    static func frameTime(_ frame: Int) -> Double {
        (Double(frame * hop) + Double(fftSize) / 2) / sampleRate
    }

    // MARK: - Loading

    static func loadMono(url: URL) throws -> [Float] {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) } catch { throw AnalyzeError.cannotRead(error.localizedDescription) }
        let inFormat = file.processingFormat
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw AnalyzeError.cannotRead("unsupported format")
        }
        converter.downmix = true

        let inCapacity: AVAudioFrameCount = 32768
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: inCapacity) else {
            throw AnalyzeError.cannotRead("buffer")
        }
        let ratio = sampleRate / inFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(inCapacity) * ratio) + 2048

        var result: [Float] = []
        result.reserveCapacity(Int(Double(file.length) * ratio) + 4096)
        var reachedEnd = false

        while true {
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity) else { break }
            var convError: NSError?
            let status = converter.convert(to: outBuffer, error: &convError) { _, inputStatus in
                if reachedEnd { inputStatus.pointee = .endOfStream; return nil }
                do {
                    try file.read(into: inBuffer, frameCount: inCapacity)
                } catch {
                    reachedEnd = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                if inBuffer.frameLength == 0 {
                    reachedEnd = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return inBuffer
            }
            if let convError { throw AnalyzeError.cannotRead(convError.localizedDescription) }
            if outBuffer.frameLength > 0, let ch = outBuffer.floatChannelData {
                result.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: Int(outBuffer.frameLength)))
            }
            if status == .endOfStream || status == .error { break }
            if reachedEnd && outBuffer.frameLength == 0 { break }
        }
        return result
    }

    // MARK: - Spectrum

    struct Features {
        var flux: [Float] = [], bassFlux: [Float] = [], midFlux: [Float] = [], highFlux: [Float] = []
        var bodyFlux: [Float] = [], crackFlux: [Float] = []   // snare body (150-600 Hz) and crack (600-2500 Hz)
        var bassLevel: [Float] = [], midLevel: [Float] = [], highLevel: [Float] = []
        var rms: [Float] = []
        var chroma: [[Float]] = []   // per frame: energy of each of the 12 notes (C, C#, … B), for chord changes
    }

    static func spectralFeatures(_ samples: [Float]) -> Features {
        let n = fftSize, half = n / 2
        let log2n = vDSP_Length(log2(Double(n)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return Features() }
        defer { vDSP_destroy_fftsetup(setup) }

        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))

        let binHz = sampleRate / Double(n)
        let bassEnd = Int(150 / binHz)          // ~20-150 Hz: kick, bass
        let midEnd = Int(2500 / binHz)          // 150-2500 Hz: snare body, vocals
        let bodyEnd = Int(600 / binHz)          // snare "body" up to here, "crack" above
        // above: hats, cymbals

        let frameCount = (samples.count - n) / hop + 1
        var out = Features()

        var windowed = [Float](repeating: 0, count: n)
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var mags = [Float](repeating: 0, count: half)
        var logMag = [Float](repeating: 0, count: half)
        var prevLog = [Float](repeating: 0, count: half)
        // which of the 12 notes each frequency bin belongs to (80 Hz - 5 kHz)
        let binHz2 = sampleRate / Double(n)
        let pitchClass: [Int] = (0..<half).map { k in
            let f = Double(k) * binHz2
            guard f >= 80, f <= 5000 else { return -1 }
            let midi = Int((12 * log2(f / 440) + 69).rounded())
            return ((midi % 12) + 12) % 12
        }

        samples.withUnsafeBufferPointer { sp in
            for fi in 0..<frameCount {
                let start = sp.baseAddress! + fi * hop
                var rms: Float = 0
                vDSP_rmsqv(start, 1, &rms, vDSP_Length(n))
                vDSP_vmul(start, 1, window, 1, &windowed, 1, vDSP_Length(n))

                real.withUnsafeMutableBufferPointer { rp in
                    imag.withUnsafeMutableBufferPointer { ip in
                        var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                        windowed.withUnsafeBufferPointer { wp in
                            wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { cp in
                                vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(half))
                            }
                        }
                        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                        vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(half))
                    }
                }
                mags[0] = 0 // packed DC / Nyquist

                var flux: Float = 0, bF: Float = 0, mF: Float = 0, hF: Float = 0, bodyF: Float = 0, crackF: Float = 0
                var bL: Float = 0, mL: Float = 0, hL: Float = 0
                for k in 1..<half {
                    let lm = log1pf(mags[k] * 10)
                    logMag[k] = lm
                    let d = max(0, lm - prevLog[k])
                    flux += d
                    if k <= bassEnd { bF += d; bL += mags[k] }
                    else if k <= midEnd {
                        mF += d; mL += mags[k]
                        if k <= bodyEnd { bodyF += d } else { crackF += d }
                    }
                    else { hF += d; hL += mags[k] }
                }
                swap(&logMag, &prevLog)
                var ch = [Float](repeating: 0, count: 12)
                for k in 1..<half where pitchClass[k] >= 0 { ch[pitchClass[k]] += mags[k] }
                let tot = ch.reduce(0, +)
                if tot > 0 { for c in 0..<12 { ch[c] /= tot } }
                out.chroma.append(ch)

                out.flux.append(flux)
                out.bassFlux.append(bF)
                out.midFlux.append(mF)
                out.highFlux.append(hF)
                out.bodyFlux.append(bodyF)
                out.crackFlux.append(crackF)
                out.bassLevel.append(log1pf(bL))
                out.midLevel.append(log1pf(mL))
                out.highLevel.append(log1pf(hL))
                out.rms.append(rms)
            }
        }
        return out
    }

    // MARK: - Tempo

    static func estimateTempo(_ onset: [Float], fps: Double) -> Double {
        let n = onset.count
        let mean = onset.reduce(0, +) / Float(max(n, 1))
        let x = onset.map { $0 - mean }
        let minLag = Int(fps * 60 / 200), maxLag = min(Int(fps * 60 / 60), n - 1)
        guard maxLag > minLag else { return 120 }

        var ac = [Float](repeating: 0, count: maxLag + 2)
        x.withUnsafeBufferPointer { xp in
            for lag in minLag...maxLag {
                var s: Float = 0
                vDSP_dotpr(xp.baseAddress!, 1, xp.baseAddress! + lag, 1, &s, vDSP_Length(n - lag))
                ac[lag] = s / Float(n - lag)
            }
        }
        // Prefer tempos near 120 BPM (perceptual weighting), like most beat trackers
        var bestLag = minLag
        var best = -Float.infinity
        for lag in minLag...maxLag {
            let bpm = 60 * fps / Double(lag)
            let w = Float(exp(-0.5 * pow(log2(bpm / 120) / 1.0, 2)))
            let v = ac[lag] * w
            if v > best { best = v; bestLag = lag }
        }
        // Parabolic interpolation for sub-frame accuracy
        var lagF = Double(bestLag)
        if bestLag > minLag && bestLag < maxLag {
            let a = Double(ac[bestLag - 1]), b = Double(ac[bestLag]), c = Double(ac[bestLag + 1])
            let denom = a - 2 * b + c
            if abs(denom) > 1e-9 { lagF += 0.5 * (a - c) / denom }
        }
        var bpm = 60 * fps / lagF
        while bpm < 75 { bpm *= 2 }
        while bpm > 185 { bpm /= 2 }
        return bpm
    }

    /// Dynamic-programming beat tracker (Ellis 2007).
    static func trackBeats(_ onset: [Float], fps: Double, bpm: Double) -> [Int] {
        let n = onset.count
        let period = fps * 60 / bpm
        guard n > Int(period * 4) else { return [] }

        // Local score: onset strength, lightly smoothed
        let local = smooth(onset, radius: 1)
        let tightness: Float = 100
        var score = [Float](repeating: 0, count: n)
        var back = [Int](repeating: -1, count: n)
        let pF = Float(period)

        for t in 0..<n {
            let lo = max(0, t - Int((2 * period).rounded()))
            let hi = t - Int((period / 2).rounded())
            var best = -Float.infinity
            var bi = -1
            if hi >= lo && hi >= 0 {
                for p in lo...hi {
                    let r = logf(Float(t - p) / pF)
                    let s = score[p] - tightness * r * r
                    if s > best { best = s; bi = p }
                }
            }
            score[t] = local[t] + (bi >= 0 ? best : 0)
            back[t] = bi
        }

        // Start from the best-scoring frame in the last beat period
        let tailStart = max(0, n - Int(period))
        var t = (tailStart..<n).max { score[$0] < score[$1] } ?? (n - 1)
        var beats: [Int] = []
        while t >= 0 {
            beats.append(t)
            t = back[t]
        }
        beats.reverse()

        // Trim weak leading/trailing beats (silence at start/end)
        let threshold = (local.reduce(0, +) / Float(n)) * 0.3
        let windowR = Int(period / 2)
        func strong(_ b: Int) -> Bool {
            let a = max(0, b - windowR), z = min(n - 1, b + windowR)
            return local[a...z].max() ?? 0 > threshold
        }
        while let first = beats.first, !strong(first) { beats.removeFirst() }
        while let last = beats.last, !strong(last) { beats.removeLast() }
        return beats
    }

    // MARK: - Peaks

    static func pickPeaks(_ x: [Float], fps: Double, minGap: Double, sensitivity: Float) -> [Double] {
        let n = x.count
        guard n > 10 else { return [] }
        let avgRadius = Int(fps * 0.5)
        let avg = smooth(x, radius: avgRadius)
        let gapFrames = Int(minGap * fps)
        var peaks: [Double] = []
        var lastPeak = -gapFrames - 1
        for i in 2..<(n - 2) {
            let v = x[i]
            guard v >= x[i - 1], v >= x[i - 2], v > x[i + 1], v >= x[i + 2] else { continue }
            guard v > avg[i] * 1.4 + sensitivity else { continue }
            if i - lastPeak < gapFrames { continue }
            peaks.append(frameTime(i))
            lastPeak = i
        }
        return peaks
    }

    // MARK: - Sections

    static func detectSections(beats: [Double], downbeatOffset: Int, duration: Double, fps: Double,
                               energy: [Float], bass: [Float], mid: [Float], high: [Float],
                               musicStart: Double = 0, musicEnd: Double? = nil) -> [DetectedSection] {
        let mEnd = musicEnd ?? duration
        // Bars of 4 beats starting at the first downbeat
        var barStarts: [Double] = []
        var i = downbeatOffset
        while i < beats.count { barStarts.append(beats[i]); i += 4 }
        if barStarts.isEmpty || barStarts[0] > 0.5 { barStarts.insert(0, at: 0) }

        func meanOf(_ arr: [Float], _ a: Double, _ b: Double) -> Double {
            let s = max(0, Int(a * fps)), e = min(arr.count, max(s + 1, Int(b * fps)))
            guard e > s else { return 0 }
            return Double(arr[s..<e].reduce(0, +)) / Double(e - s)
        }

        let barCount = barStarts.count
        guard barCount >= 4 else {
            return [DetectedSection(start: 0, end: duration, energy: 0.6, level: .medium, name: "Full Song")]
        }
        // Feature vector per bar
        var feats: [[Double]] = []
        for b in 0..<barCount {
            let a = barStarts[b], z = b + 1 < barCount ? barStarts[b + 1] : duration
            feats.append([meanOf(energy, a, z) * 2, meanOf(bass, a, z), meanOf(mid, a, z), meanOf(high, a, z)])
        }

        // Novelty: how different the next few bars are from the previous few
        let k = barCount >= 32 ? 4 : 2
        var novelty = [Double](repeating: 0, count: barCount)
        for b in k..<(barCount - k + 1) where b < barCount {
            var d = 0.0
            for f in 0..<4 {
                var before = 0.0, after = 0.0
                for j in 0..<k { before += feats[b - 1 - j][f]; after += feats[min(barCount - 1, b + j)][f] }
                d += pow((after - before) / Double(k), 2)
            }
            novelty[b] = sqrt(d)
        }
        let nMean = novelty.reduce(0, +) / Double(barCount)
        let nStd = sqrt(novelty.map { pow($0 - nMean, 2) }.reduce(0, +) / Double(barCount))
        let thresh = nMean + 0.5 * nStd

        // Pick boundaries: strongest first, at least 8 bars apart (4 for short songs)
        let minBars = barCount >= 48 ? 8 : 4
        let candidates = (1..<barCount).filter { novelty[$0] > thresh }.sorted { novelty[$0] > novelty[$1] }
        var chosen: [Int] = []
        for c in candidates where chosen.allSatisfy({ abs($0 - c) >= minBars }) && c >= minBars / 2 && barCount - c >= minBars / 2 {
            // Snap to a 4-bar phrase if one is within 1 bar and not taken
            var cc = c
            for snap in [c - 1, c + 1] where snap > 0 && snap < barCount && snap % 4 == 0 && c % 4 != 0 { cc = snap }
            if chosen.allSatisfy({ abs($0 - cc) >= minBars }) { chosen.append(cc) }
        }
        chosen.sort()

        // Section edges: detected changes inside the music, plus where the music starts and ends
        var edges: [Double] = [0]
        edges += chosen.map { barStarts[$0] }.filter { $0 > musicStart + 2 && $0 < mEnd - 2 }
        if musicStart > 0.3 { edges.append(musicStart) }
        edges.append(mEnd)
        if mEnd < duration - 0.3 { edges.append(duration) }
        edges = Array(Set(edges.map { ($0 * 1000).rounded() / 1000 })).sorted()
        // Fold slivers shorter than 4 s into the previous section
        var bounds: [Double] = [edges[0]]
        for b in edges.dropFirst() {
            let keep = abs(b - musicStart) < 0.01 || abs(b - mEnd) < 0.01 || abs(b - duration) < 0.01
            if b - bounds[bounds.count - 1] < 4 && !keep && bounds.count > 1 { bounds[bounds.count - 1] = b } else { bounds.append(b) }
        }
        func isSilent(_ a: Double, _ b: Double) -> Bool { b <= musicStart + 0.01 || a >= mEnd - 0.01 }

        // Measure each section
        var raw: [(start: Double, end: Double, energy: Double, bass: Double)] = []
        for s in 0..<(bounds.count - 1) {
            raw.append((bounds[s], bounds[s + 1], meanOf(energy, bounds[s], bounds[s + 1]), meanOf(bass, bounds[s], bounds[s + 1])))
        }
        // Compare loudness only across the music (silence would make everything look loud)
        let musical = raw.filter { !isSilent($0.start, $0.end) }
        let eMin = musical.map { $0.energy }.min() ?? 0, eMax = musical.map { $0.energy }.max() ?? 1
        let range = max(eMax - eMin, 0.0001)

        var result: [DetectedSection] = []
        var counts: [String: Int] = [:]
        var prevE: Double? = nil
        for (idx, r) in raw.enumerated() {
            if isSilent(r.start, r.end) {
                result.append(DetectedSection(start: r.start, end: r.end, energy: 0, level: .low, name: "Silence"))
                continue
            }
            let e = musical.count == 1 ? 0.6 : (r.energy - eMin) / range
            var level: EnergyLevel = e < 0.34 ? .low : (e < 0.7 ? .medium : .high)
            if level == .high, let p = prevE, e - p > 0.35 { level = .drop }
            prevE = e
            let firstMusical = result.allSatisfy { $0.name == "Silence" }
            let lastMusical = raw[(idx + 1)...].allSatisfy { isSilent($0.start, $0.end) }
            var name: String
            switch level {
            case .low: name = firstMusical ? "Intro" : (lastMusical ? "Outro" : "Breakdown")
            case .medium:
                let nextE = idx + 1 < raw.count && !isSilent(raw[idx + 1].start, raw[idx + 1].end)
                    ? (raw[idx + 1].energy - eMin) / range : 0
                name = firstMusical ? "Intro" : (nextE - e > 0.25 ? "Build" : "Verse")
            case .high: name = "Chorus"
            case .drop: name = "Drop"
            }
            if lastMusical && level != .high && level != .drop && !firstMusical { name = "Outro" }
            counts[name, default: 0] += 1
            let c = counts[name]!
            if c > 1 { name += " \(c)" }
            result.append(DetectedSection(start: r.start, end: r.end, energy: e, level: level, name: name))
        }
        return result
    }

    // MARK: - Silence

    /// Finds stretches of (near) silence at least 0.6 s long — lead-in, gaps, and the tail.
    static func detectSilences(rms: [Float], fps: Double, duration: Double) -> [SilenceSpan] {
        guard !rms.isEmpty else { return [] }
        let sorted = rms.sorted()
        let loud = sorted[Int(Double(sorted.count) * 0.9)]
        // -36 dB below the song's loud level, with an absolute floor
        let threshold = max(loud * 0.016, 0.0008)
        let minFrames = Int(0.6 * fps)
        var spans: [SilenceSpan] = []
        var runStart: Int? = nil
        for i in 0...rms.count {
            let quiet = i < rms.count && rms[i] < threshold
            if quiet {
                if runStart == nil { runStart = i }
            } else if let s = runStart {
                if i - s >= minFrames {
                    let a = s == 0 ? 0 : frameTime(s)
                    let b = i == rms.count ? duration : frameTime(i)
                    spans.append(SilenceSpan(start: a, end: b))
                }
                runStart = nil
            }
        }
        return spans
    }

    // MARK: - Helpers

    static func normalize(_ x: [Float]) -> [Float] {
        guard !x.isEmpty else { return x }
        let sorted = x.sorted()
        let lo = sorted[Int(Double(sorted.count) * 0.02)]
        let hi = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.99))]
        let range = max(hi - lo, 1e-6)
        return x.map { min(1, max(0, ($0 - lo) / range)) }
    }

    /// Moving average with the given radius (in frames).
    static func smooth(_ x: [Float], radius: Int) -> [Float] {
        guard radius > 0, !x.isEmpty else { return x }
        var prefix = [Float](repeating: 0, count: x.count + 1)
        for i in 0..<x.count { prefix[i + 1] = prefix[i] + x[i] }
        return (0..<x.count).map { i in
            let a = max(0, i - radius), b = min(x.count, i + radius + 1)
            return (prefix[b] - prefix[a]) / Float(b - a)
        }
    }
}
