import Foundation
import AVFoundation
import Accelerate

// MARK: - What Learn finds per hit / phrase, and the per-song detection settings

enum HitType: String, Codable, CaseIterable, Identifiable {
    case kick, snare, hat
    var id: String { rawValue }
    var label: String { switch self { case .kick: return "Kick"; case .snare: return "Snare"; case .hat: return "Hi-hat" } }
}

struct DrumHit: Codable, Hashable, Identifiable {
    var id = UUID()
    var type: HitType
    var time: Double
    var confidence: Double
    var manual: Bool? = nil
}

struct TimeSpan: Codable, Hashable {
    var start: Double
    var end: Double
}

/// Per-song detection settings: frequency ranges, how easily a hit counts, minimum spacing, timing offset.
struct DetectionSettings: Codable, Hashable {
    var kickLow = 35.0, kickHigh = 120.0
    var snareBodyLow = 150.0, snareBodyHigh = 250.0
    var snareSnapLow = 2000.0, snareSnapHigh = 4000.0
    var hatLow = 5000.0, hatHigh = 11000.0
    var kickSensitivity = 1.0, snareSensitivity = 1.0, hatSensitivity = 1.0   // higher = more hits
    var kickSpacing = 0.18, snareSpacing = 0.15, hatSpacing = 0.07            // seconds
    var offsetMs = 0.0                                                        // + = hits later

    init() {}

    enum CodingKeys: String, CodingKey {
        case kickLow, kickHigh, snareBodyLow, snareBodyHigh, snareSnapLow, snareSnapHigh, hatLow, hatHigh
        case kickSensitivity, snareSensitivity, hatSensitivity, kickSpacing, snareSpacing, hatSpacing, offsetMs
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d(_ k: CodingKeys, _ def: Double) -> Double { ((try? c.decodeIfPresent(Double.self, forKey: k)) ?? nil) ?? def }
        let s = DetectionSettings()
        kickLow = d(.kickLow, s.kickLow); kickHigh = d(.kickHigh, s.kickHigh)
        snareBodyLow = d(.snareBodyLow, s.snareBodyLow); snareBodyHigh = d(.snareBodyHigh, s.snareBodyHigh)
        snareSnapLow = d(.snareSnapLow, s.snareSnapLow); snareSnapHigh = d(.snareSnapHigh, s.snareSnapHigh)
        hatLow = d(.hatLow, s.hatLow); hatHigh = d(.hatHigh, s.hatHigh)
        kickSensitivity = d(.kickSensitivity, 1); snareSensitivity = d(.snareSensitivity, 1); hatSensitivity = d(.hatSensitivity, 1)
        kickSpacing = d(.kickSpacing, s.kickSpacing); snareSpacing = d(.snareSpacing, s.snareSpacing); hatSpacing = d(.hatSpacing, s.hatSpacing)
        offsetMs = d(.offsetMs, 0)
    }
}

// MARK: - Built-in stem splitter
//
// Splits a song into Vocals, Drums, Bass and Other on this Mac, then finds the drum hits and sung
// phrases from the separated parts:
//   1. Short-time spectrum of the song (44.1 kHz, 2048-point windows, 1024 apart).
//   2. Drums vs. sustained sound: a sound that's smooth across time is held (harmonic); one that's
//      smooth across frequency is a hit (percussive). Median filters in each direction give soft masks.
//   3. Bass = the held part below ~250 Hz. Vocals = the held part in the voice range, in the centre of
//      the stereo image, while someone is singing. Other = whatever is left.
//   4. Each part is turned back into audio (overlap-add) and saved as an .m4a you can listen to.
// Kicks, snares and hats are found on the drum part only, so sustained bass, vocals and synths
// don't set them off.
enum StemSplitter {
    static let rate = 44100.0
    static let n = 2048
    static let hop = 1024
    static let bins = 1024
    static let stems = ["vocals", "drums", "bass", "other"]
    static let peaksPerSecond = 20.0

    struct Output {
        var hits: [DrumHit]
        var vocalPhrases: [TimeSpan]
        var stemsFolder: String?
    }

    static func frameTime(_ i: Int) -> Double { (Double(i * hop) + Double(n) / 2) / rate }

    // MARK: Run

    static func run(url: URL, settings: DetectionSettings, stemsDir: URL?, progress: (Double) -> Void) throws -> Output {
        let (left, right) = try loadStereo(url: url)
        let count = left.count
        guard count > n * 8 else { throw AudioAnalyzer.AnalyzeError.tooShort }
        progress(0.1)
        // Pad so the last frames cover the end
        var L = left; L.append(contentsOf: [Float](repeating: 0, count: n))
        var R = right; R.append(contentsOf: [Float](repeating: 0, count: n))
        let frames = count / hop + 1
        guard let fft = FFT(n: n) else { throw AudioAnalyzer.AnalyzeError.cannotRead("FFT") }

        // ---- 1. spectrum: mono magnitude + how centred each bin is in the stereo image
        var M = [Float](repeating: 0, count: frames * bins)
        var centre = [Float](repeating: 0, count: frames * bins)
        var lre = [Float](repeating: 0, count: bins), lim = [Float](repeating: 0, count: bins)
        var rre = [Float](repeating: 0, count: bins), rim = [Float](repeating: 0, count: bins)
        L.withUnsafeBufferPointer { lp in
            R.withUnsafeBufferPointer { rp in
                for t in 0..<frames {
                    fft.forward(lp.baseAddress! + t * hop, &lre, &lim)
                    fft.forward(rp.baseAddress! + t * hop, &rre, &rim)
                    let base = t * bins
                    for k in 1..<bins {
                        let mr = lre[k] + rre[k], mi = lim[k] + rim[k]
                        M[base + k] = (mr * mr + mi * mi).squareRoot() / 8
                        let en = lre[k] * lre[k] + lim[k] * lim[k] + rre[k] * rre[k] + rim[k] * rim[k] + 1e-12
                        let cr = max(0, lre[k] * rre[k] + lim[k] * rim[k])   // in-phase part of L·R*
                        var c = 2 * cr / en
                        c = c * c; c = c * c
                        centre[base + k] = c
                    }
                }
            }
        }
        progress(0.25)

        // ---- 2. harmonic / percussive split
        var mP = [Float](repeating: 0, count: frames * bins)
        do {
            var H = [Float](repeating: 0, count: frames * bins)
            var P = [Float](repeating: 0, count: frames * bins)
            let rad = 8
            var tmp = [Float](repeating: 0, count: 2 * rad + 1)
            // smooth across time, per bin
            M.withUnsafeBufferPointer { mp in
                for k in 0..<bins {
                    for t in 0..<frames {
                        for j in -rad...rad {
                            let tt = reflect(t + j, frames)
                            tmp[j + rad] = mp[tt * bins + k]
                        }
                        H[t * bins + k] = median(&tmp)
                    }
                }
                // smooth across frequency, per frame
                for t in 0..<frames {
                    let base = t * bins
                    for k in 0..<bins {
                        for j in -rad...rad {
                            let kk = reflect(k + j, bins)
                            tmp[j + rad] = mp[base + kk]
                        }
                        P[base + k] = median(&tmp)
                    }
                }
            }
            for i in 0..<(frames * bins) {
                let p2 = P[i] * P[i], h2 = H[i] * H[i]
                mP[i] = p2 / (p2 + h2 + 1e-12)
            }
        }
        progress(0.45)

        // ---- 3. drum hits from the percussive part
        let fps = rate / Double(hop)
        let binHz = rate / Double(n)
        func band(_ lo: Double, _ hi: Double) -> (Int, Int) {
            let a = max(1, Int(lo / binHz)), b = min(bins, max(2, Int(hi / binHz) + 1))
            return (min(a, b - 1), b)
        }
        let bands = [band(settings.kickLow, settings.kickHigh), band(settings.snareBodyLow, settings.snareBodyHigh),
                     band(settings.snareSnapLow, settings.snareSnapHigh), band(settings.hatLow, settings.hatHigh),
                     band(settings.kickLow, 4000)]   // wide: how much of a hit is low end
        var flux = [[Float]](repeating: [Float](repeating: 0, count: frames), count: bands.count)
        var level = [[Float]](repeating: [Float](repeating: 0, count: frames), count: bands.count)
        var prevLog = [Float](repeating: 0, count: bins), curLog = [Float](repeating: 0, count: bins)
        for t in 0..<frames {
            let base = t * bins
            for k in 0..<bins { curLog[k] = log1pf(M[base + k] * mP[base + k] * 10) }
            for (bi, (a, b)) in bands.enumerated() {
                var f: Float = 0, l: Float = 0
                for k in a..<b {
                    if t > 0 { f += max(0, curLog[k] - prevLog[k]) }
                    l += M[base + k] * mP[base + k]
                }
                flux[bi][t] = f; level[bi][t] = l
            }
            swap(&prevLog, &curLog)
        }
        let kf = norm(flux[0]), bf = norm(flux[1]), sf = norm(flux[2]), hf = norm(flux[3])
        let kl = scaled(level[0], pct: 99), sl = scaled(level[2], pct: 99)
        // A kick is strong down low, or (if quieter) puts most of its punch in the low end; a snare or a
        // chord starting is spread across the spectrum, so it doesn't count as a kick
        let lowShare = zip(level[0], level[4]).map { $0 / ($1 + 1e-9) }
        func mx(_ a: [Float], _ i: Int) -> Float { a[max(0, i - 1)...min(a.count - 1, i + 1)].max() ?? 0 }
        if ProcessInfo.processInfo.environment["DMX_DEBUG_KICK"] != nil {
            print(String(format: "dbg p99.5 kick flux=%.4f p99 kick level=%.4f frames=%d", percentile(flux[0], 99.5), percentile(level[0], 99), frames))
            for p in peaks(kf, fps: fps, gap: settings.kickSpacing, sens: 0.12, extra: nil) {
                print(String(format: "dbgkick i=%d t=%.3f kf=%.3f kl=%.3f share=%.3f M=%.4f mP=%.3f", p.i, frameTime(p.i), kf[p.i], mx(kl, p.i),
                             mx(lowShare, p.i), M[p.i * bins + 3], mP[p.i * bins + 3]))
            }
        }
        let off = settings.offsetMs / 1000
        var hits: [DrumHit] = []
        for p in peaks(kf, fps: fps, gap: settings.kickSpacing, sens: Float(0.12 / max(settings.kickSensitivity, 0.1)),
                       extra: { mx(kl, $0) >= 0.22 || (mx(kl, $0) >= 0.1 && mx(lowShare, $0) >= 0.3) }) {
            hits.append(DrumHit(type: .kick, time: frameTime(p.i) + off, confidence: p.conf))
        }
        let sScore = norm(zip(bf, sf).map { ($0 * $1).squareRoot() })
        for p in peaks(sScore, fps: fps, gap: settings.snareSpacing, sens: Float(0.10 / max(settings.snareSensitivity, 0.1)),
                       extra: { i in
                           let pk = max(sl[i], sl[min(sl.count - 1, i + 1)])
                           let sustain = sl[min(sl.count - 1, i + 3)] / (pk + 1e-9)
                           return mx(sf, i) >= 0.6 && mx(bf, i) >= 0.3 && sustain >= 0.2
                       }) {
            hits.append(DrumHit(type: .snare, time: frameTime(p.i) + off, confidence: p.conf))
        }
        for p in peaks(hf, fps: fps, gap: settings.hatSpacing, sens: Float(0.08 / max(settings.hatSensitivity, 0.1)), extra: nil) {
            hits.append(DrumHit(type: .hat, time: frameTime(p.i) + off, confidence: p.conf))
        }
        hits.sort { $0.time < $1.time }

        // ---- vocal phrases: a voice keeps changing pitch and syllable, sits in the middle of the stereo
        // image, and is held (not a drum hit). Pads and chords are held too but barely change, so they
        // don't count: measure how much the centred, held sound in the voice range keeps moving.
        let (va, vb) = band(250, 3500)
        var vflux = [Float](repeating: 0, count: frames)
        var prevV = [Float](repeating: 0, count: bins), curV = [Float](repeating: 0, count: bins)
        for t in 0..<frames {
            let base = t * bins
            var f: Float = 0
            for k in va..<vb {
                curV[k] = log1pf(M[base + k] * (1 - mP[base + k]) * centre[base + k] * 10)
                if t > 0 { f += max(0, curV[k] - prevV[k]) }
            }
            vflux[t] = f
            swap(&prevV, &curV)
        }
        let pres = scaled(AudioAnalyzer.smooth(vflux, radius: Int(0.12 * fps)), pct: 95)
        var phrases: [TimeSpan] = []
        var i = 0
        while i < frames {
            if pres[i] > 0.3 {
                var j = i
                while j < frames && pres[j] > 0.3 { j += 1 }
                let s = TimeSpan(start: frameTime(i), end: frameTime(j))
                if let last = phrases.last, s.start - last.end < 0.35 { phrases[phrases.count - 1].end = s.end }
                else { phrases.append(s) }
                i = j
            } else { i += 1 }
        }
        phrases = phrases.filter { $0.end - $0.start >= 0.5 }
        progress(0.55)

        guard let stemsDir else { return Output(hits: hits, vocalPhrases: phrases, stemsFolder: nil) }

        // ---- 4. write the four parts as audio
        try? FileManager.default.removeItem(at: stemsDir)
        try FileManager.default.createDirectory(at: stemsDir, withIntermediateDirectories: true)
        let fileSettings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
                                           AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000]
        var files: [AVAudioFile] = []
        for s in stems {
            files.append(try AVAudioFile(forWriting: stemsDir.appendingPathComponent("\(s).m4a"), settings: fileSettings,
                                         commonFormat: .pcmFormatFloat32, interleaved: false))
        }
        let lowm: [Float] = (0..<bins).map { Float(min(max((300 - Double($0) * binHz) / 100, 0), 1)) }
        let vband: [Float] = (0..<bins).map { k in
            let f = Double(k) * binHz
            let low: Double = min(max((f - 150.0) / 100.0, 0.0), 1.0)
            let high: Double = min(max((6000.0 - f) / 1500.0, 0.0), 1.0)
            return Float(low * high)
        }
        let vp: [Float] = pres.map { min(max(($0 - 0.2) / 0.2, 0), 1) }
        let ns = stems.count
        // overlap-add accumulators [stem][channel]
        var acc = [[[Float]]](repeating: [[Float]](repeating: [Float](repeating: 0, count: n), count: 2), count: ns)
        let blockFrames = 64
        var block = [[[Float]]](repeating: [[Float]](repeating: [], count: 2), count: ns)
        for s in 0..<ns { for c in 0..<2 { block[s][c].reserveCapacity(blockFrames * hop) } }
        let peakWin = Int(rate / peaksPerSecond)
        var wave = [[Float]](repeating: [], count: ns)
        var peakCur = [Float](repeating: 0, count: ns), peakFill = 0
        var written = 0
        var masks = [[Float]](repeating: [Float](repeating: 0, count: bins), count: ns)
        var sre = [Float](repeating: 0, count: bins), sim = [Float](repeating: 0, count: bins)
        var outFrame = [Float](repeating: 0, count: n)

        func flush() throws {
            let len = block[0][0].count
            guard len > 0 else { return }
            // waveform overview
            for k in 0..<len {
                for s in 0..<ns { peakCur[s] = max(peakCur[s], abs(block[s][0][k]), abs(block[s][1][k])) }
                peakFill += 1
                if peakFill == peakWin {
                    for s in 0..<ns { wave[s].append(peakCur[s]); peakCur[s] = 0 }
                    peakFill = 0
                }
            }
            for s in 0..<ns {
                guard let buf = AVAudioPCMBuffer(pcmFormat: files[s].processingFormat, frameCapacity: AVAudioFrameCount(len)),
                      let ch = buf.floatChannelData else { continue }
                buf.frameLength = AVAudioFrameCount(len)
                for c in 0..<2 {
                    block[s][c].withUnsafeBufferPointer { bp in ch[c].assign(from: bp.baseAddress!, count: len) }
                    block[s][c].removeAll(keepingCapacity: true)
                }
                try files[s].write(from: buf)
            }
        }

        try L.withUnsafeBufferPointer { lp in
            try R.withUnsafeBufferPointer { rp in
                for t in 0..<frames {
                    let base = t * bins
                    for k in 0..<bins {
                        let p = mP[base + k], h = 1 - p
                        let b = h * lowm[k]
                        let v = h * (1 - lowm[k]) * vband[k] * centre[base + k] * vp[t]
                        masks[0][k] = v
                        masks[1][k] = p
                        masks[2][k] = b
                        masks[3][k] = max(0, h - b - v)
                    }
                    for c in 0..<2 {
                        let src = (c == 0 ? lp.baseAddress! : rp.baseAddress!) + t * hop
                        fft.forward(src, &lre, &lim)
                        for s in 0..<ns {
                            for k in 0..<bins { sre[k] = lre[k] * masks[s][k]; sim[k] = lim[k] * masks[s][k] }
                            fft.inverse(&sre, &sim, &outFrame)
                            for j in 0..<n { acc[s][c][j] += outFrame[j] }
                        }
                    }
                    // the first `hop` samples are now complete
                    let take = min(hop, count - written)
                    for s in 0..<ns {
                        for c in 0..<2 {
                            if take > 0 { block[s][c].append(contentsOf: acc[s][c][0..<take]) }
                            acc[s][c].removeFirst(hop)
                            acc[s][c].append(contentsOf: [Float](repeating: 0, count: hop))
                        }
                    }
                    written += max(take, 0)
                    if block[0][0].count >= blockFrames * hop { try flush() }
                    if t % 200 == 0 { progress(0.55 + 0.45 * Double(t) / Double(frames)) }
                }
            }
        }
        try flush()
        if peakFill > 0 { for s in 0..<ns { wave[s].append(peakCur[s]) } }
        files.removeAll()   // closes the files
        var overview: [String: [Float]] = [:]
        let top = max(wave.map { $0.max() ?? 0 }.max() ?? 0, 1e-6)   // one scale, so quiet parts look quiet
        for (s, name) in stems.enumerated() {
            overview[name] = wave[s].map { (($0 / top) * 1000).rounded() / 1000 }
        }
        let po = StemOverview(perSecond: peaksPerSecond, peaks: overview)
        try JSONEncoder().encode(po).write(to: stemsDir.appendingPathComponent("overview.json"))
        progress(1)
        return Output(hits: hits, vocalPhrases: phrases, stemsFolder: stemsDir.path)
    }

    // MARK: Helpers

    /// Mirror an index back into 0..<n at the edges (d c b a | a b c d), so the lowest bins
    /// (where kicks live) aren't smoothed against empty padding.
    @inline(__always) static func reflect(_ i: Int, _ n: Int) -> Int {
        var i = i
        if i < 0 { i = -i - 1 }
        if i >= n { i = 2 * n - i - 1 }
        return min(max(i, 0), n - 1)
    }

    /// Median of a small buffer (sorts it in place).
    static func median(_ a: inout [Float]) -> Float {
        let c = a.count
        for i in 1..<c {
            let v = a[i]; var j = i - 1
            while j >= 0 && a[j] > v { a[j + 1] = a[j]; j -= 1 }
            a[j + 1] = v
        }
        return a[c / 2]
    }

    static func percentile(_ x: [Float], _ q: Double) -> Float {
        guard !x.isEmpty else { return 0 }
        let s = x.sorted()
        let pos = q / 100 * Double(s.count - 1)
        let lo = Int(pos), hi = min(lo + 1, s.count - 1)
        let f = Float(pos - Double(lo))
        return s[lo] * (1 - f) + s[hi] * f
    }

    /// Divide by the 99.5th percentile, clip to 1.5.
    static func norm(_ x: [Float]) -> [Float] {
        var m = percentile(x, 99.5); if m <= 0 { m = 1 }
        return x.map { min(max($0 / m, 0), 1.5) }
    }

    static func scaled(_ x: [Float], pct: Double) -> [Float] {
        var m = percentile(x, pct); if m <= 0 { m = 1 }
        return x.map { $0 / m }
    }

    struct Peak { var i: Int; var v: Float; var conf: Double }

    /// Local maxima clearly above the running average, at least `gap` seconds apart.
    static func peaks(_ x: [Float], fps: Double, gap: Double, sens: Float, extra: ((Int) -> Bool)?) -> [Peak] {
        guard x.count > 5 else { return [] }
        let avg = AudioAnalyzer.smooth(x, radius: Int(fps * 0.5))
        let g = Int(gap * fps)
        var out: [Peak] = []
        var last = -g - 1
        for i in 2..<(x.count - 2) {
            let v = x[i]
            guard v >= x[i - 1], v >= x[i - 2], v > x[i + 1], v >= x[i + 2] else { continue }
            let thr = avg[i] * 1.4 + sens
            guard v > thr else { continue }
            let conf = Double(min(1, max(0.05, 0.3 + 0.7 * (v - thr) / (thr + 0.2))))
            if i - last < g {
                if let l = out.last, v > l.v { out[out.count - 1] = Peak(i: i, v: v, conf: conf) }
                continue
            }
            if let extra, !extra(i) { continue }
            out.append(Peak(i: i, v: v, conf: conf)); last = i
        }
        return out
    }

    /// Reads a file as two channels at 44.1 kHz (a mono file gives the same signal on both).
    static func loadStereo(url: URL) throws -> ([Float], [Float]) {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) } catch { throw AudioAnalyzer.AnalyzeError.cannotRead(error.localizedDescription) }
        let inFormat = file.processingFormat
        let ch: AVAudioChannelCount = inFormat.channelCount >= 2 ? 2 : 1
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: ch, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw AudioAnalyzer.AnalyzeError.cannotRead("unsupported format")
        }
        converter.downmix = inFormat.channelCount > 2
        let inCapacity: AVAudioFrameCount = 32768
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: inCapacity) else {
            throw AudioAnalyzer.AnalyzeError.cannotRead("buffer")
        }
        let ratio = rate / inFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(inCapacity) * ratio) + 2048
        var l: [Float] = [], r: [Float] = []
        l.reserveCapacity(Int(Double(file.length) * ratio) + 4096)
        if ch == 2 { r.reserveCapacity(l.capacity) }
        var reachedEnd = false
        while true {
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity) else { break }
            var convError: NSError?
            let status = converter.convert(to: outBuffer, error: &convError) { _, inputStatus in
                if reachedEnd { inputStatus.pointee = .endOfStream; return nil }
                do { try file.read(into: inBuffer, frameCount: inCapacity) } catch {
                    reachedEnd = true; inputStatus.pointee = .endOfStream; return nil
                }
                if inBuffer.frameLength == 0 { reachedEnd = true; inputStatus.pointee = .endOfStream; return nil }
                inputStatus.pointee = .haveData
                return inBuffer
            }
            if let convError { throw AudioAnalyzer.AnalyzeError.cannotRead(convError.localizedDescription) }
            if outBuffer.frameLength > 0, let d = outBuffer.floatChannelData {
                let len = Int(outBuffer.frameLength)
                l.append(contentsOf: UnsafeBufferPointer(start: d[0], count: len))
                if ch == 2 { r.append(contentsOf: UnsafeBufferPointer(start: d[1], count: len)) }
            }
            if status == .endOfStream || status == .error { break }
            if reachedEnd && outBuffer.frameLength == 0 { break }
        }
        return (l, ch == 2 ? r : l)
    }
}

/// The waveform overview saved next to the stems (drawn in the Stems tab without reading the audio).
struct StemOverview: Codable {
    var perSecond: Double
    var peaks: [String: [Float]]

    static func load(folder: String) -> StemOverview? {
        let u = URL(fileURLWithPath: folder).appendingPathComponent("overview.json")
        return (try? Data(contentsOf: u)).flatMap { try? JSONDecoder().decode(StemOverview.self, from: $0) }
    }
}

/// Real FFT of a fixed size with a periodic Hann window (vDSP packed format: re[0] = DC, im[0] = Nyquist).
final class FFT {
    let n: Int, half: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var window: [Float]
    private var buf: [Float]

    init?(n: Int) {
        self.n = n; half = n / 2
        log2n = vDSP_Length(log2(Double(n)))
        guard let s = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        setup = s
        window = (0..<n).map { Float(0.5 * (1 - cos(2 * Double.pi * Double($0) / Double(n)))) }
        buf = [Float](repeating: 0, count: n)
    }
    deinit { vDSP_destroy_fftsetup(setup) }
    @inline(__always) func windowValue(_ j: Int) -> Float { window[j] }

    /// Windowed forward transform of src[0..<n] (values are 2× the textbook DFT, as vDSP gives them).
    func forward(_ src: UnsafePointer<Float>, _ re: inout [Float], _ im: inout [Float]) {
        vDSP_vmul(src, 1, window, 1, &buf, 1, vDSP_Length(n))
        let h = half, lg = log2n, st = setup
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                buf.withUnsafeBufferPointer { bp in
                    bp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: h) { cp in
                        vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(h))
                    }
                }
                vDSP_fft_zrip(st, &split, 1, lg, FFTDirection(FFT_FORWARD))
            }
        }
    }

    /// Inverse of `forward` (without the window): exact for overlap-add with hop n/2. Modifies re/im.
    func inverse(_ re: inout [Float], _ im: inout [Float], _ out: inout [Float]) {
        let h = half, lg = log2n, st = setup, nn = n
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_fft_zrip(st, &split, 1, lg, FFTDirection(FFT_INVERSE))
                out.withUnsafeMutableBufferPointer { op in
                    op.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: h) { cp in
                        vDSP_ztoc(&split, 1, cp, 2, vDSP_Length(h))
                    }
                    var s = Float(1) / Float(2 * nn)
                    vDSP_vsmul(op.baseAddress!, 1, &s, op.baseAddress!, 1, vDSP_Length(nn))
                }
            }
        }
    }
}
