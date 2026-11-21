import Foundation
import AVFoundation
import Accelerate
import CoreML

/// High Quality stem splitting: Meta's open-source Demucs model (htdemucs_6s, MIT license) running in
/// Core ML on this Mac. Splits a song into vocals, drums, bass, guitar, piano and other. The model is
/// downloaded once (from this app's GitHub release) the first time you pick High Quality.
///
/// The network runs in Core ML; the spectrogram steps around it are done here and match
/// packaging/demucs_dsp.py (which the build checks against Demucs itself).
enum HQSplitter {
    static let releaseURL = URL(string: "https://github.com/josephbrooks7/dmx-studio/releases/download/hq-model-1/DemucsHQ.mlmodelc.zip")!
    static let nfft = 4096, hop = 1024, half = 2048
    static let segment = 343_980                      // 7.8 s at 44.1 kHz (what the model was trained on)
    static let sources = ["drums", "bass", "other", "vocals", "guitar", "piano"]

    static var modelsDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let u = base.appendingPathComponent("DMX Studio/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static var overrideModel: URL?    // tests: use a model from elsewhere
    static var modelURL: URL {
        if let o = overrideModel { return o }
        // built into the app (works offline), else downloaded
        if let b = Bundle.main.resourceURL?.appendingPathComponent("Models/DemucsHQ.mlmodelc", isDirectory: true),
           FileManager.default.fileExists(atPath: b.appendingPathComponent("coremldata.bin").path) { return b }
        return modelsDir.appendingPathComponent("DemucsHQ.mlmodelc", isDirectory: true)
    }
    /// Demucs' fine-tuned vocals specialist (optional, makes the vocal part much cleaner)
    static var voxURL: URL {
        if let b = Bundle.main.resourceURL?.appendingPathComponent("Models/DemucsVox.mlmodelc", isDirectory: true),
           FileManager.default.fileExists(atPath: b.appendingPathComponent("coremldata.bin").path) { return b }
        return (overrideModel?.deletingLastPathComponent() ?? modelsDir).appendingPathComponent("DemucsVox.mlmodelc", isDirectory: true)
    }
    static var isInstalled: Bool { FileManager.default.fileExists(atPath: modelURL.appendingPathComponent("coremldata.bin").path) }

    // MARK: Download (once)

    final class Downloader: NSObject, URLSessionDownloadDelegate {
        var progress: (Double) -> Void
        var done: (Error?) -> Void
        init(progress: @escaping (Double) -> Void, done: @escaping (Error?) -> Void) { self.progress = progress; self.done = done }
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            if totalBytesExpectedToWrite > 0 { progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
        }
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            let zip = HQSplitter.modelsDir.appendingPathComponent("DemucsHQ.zip")
            try? FileManager.default.removeItem(at: zip)
            do {
                try FileManager.default.moveItem(at: location, to: zip)
                try? FileManager.default.removeItem(at: HQSplitter.modelURL)
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                p.arguments = ["-x", "-k", zip.path, HQSplitter.modelsDir.path]
                try p.run(); p.waitUntilExit()
                try? FileManager.default.removeItem(at: zip)
                done(HQSplitter.isInstalled ? nil : NSError(domain: "DMX", code: 1, userInfo: [NSLocalizedDescriptionKey: "The model download was incomplete."]))
            } catch { done(error) }
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error { done(error) }
        }
    }
    private static var activeDownload: (URLSession, Downloader)?

    static func download(progress: @escaping (Double) -> Void, done: @escaping (Error?) -> Void) {
        let d = Downloader(progress: { p in DispatchQueue.main.async { progress(p) } },
                           done: { e in DispatchQueue.main.async { activeDownload = nil; done(e) } })
        let s = URLSession(configuration: .default, delegate: d, delegateQueue: nil)
        activeDownload = (s, d)
        s.downloadTask(with: releaseURL).resume()
    }

    // MARK: Separate

    /// Splits the song and writes <name>.m4a for each part plus overview.json into `outDir`.
    static func separate(url: URL, outDir: URL, progress: (Double) -> Void) throws {
        let cfg = MLModelConfiguration()
        #if arch(x86_64)
        // Intel Macs: CPU only unless you turn on the graphics chip (it caused a freeze on the 3D stage before)
        cfg.computeUnits = UserDefaults.standard.bool(forKey: "aiUseGPU") ? .cpuAndGPU : .cpuOnly
        #else
        cfg.computeUnits = .all
        #endif
        // "Vocals focus" (default, about twice as fast): just the vocals specialist, which also gives drums,
        // bass and other. "Full 6 parts" adds the 6-part model for guitar + piano (two models: slower).
        let haveVox = FileManager.default.fileExists(atPath: voxURL.appendingPathComponent("coremldata.bin").path)
        let full = UserDefaults.standard.bool(forKey: "hqSixParts") || !haveVox
        let model = try MLModel(contentsOf: full ? modelURL : voxURL, configuration: cfg)
        let voxModel = full && haveVox ? try? MLModel(contentsOf: voxURL, configuration: cfg) : nil
        let sources = full ? HQSplitter.sources : ["drums", "bass", "other", "vocals"]
        let voxIndex = 3    // htdemucs_ft parts: drums, bass, other, vocals
        let (left, right) = try StemSplitter.loadStereo(url: url)
        let L = left.count
        guard L > hop * 8 else { throw AudioAnalyzer.AnalyzeError.tooShort }
        // normalize like Demucs does
        var mono = [Float](repeating: 0, count: L)
        for i in 0..<L { mono[i] = (left[i] + right[i]) / 2 }
        var mu: Float = 0, sd: Float = 0
        vDSP_meanv(mono, 1, &mu, vDSP_Length(L))
        var msq: Float = 0
        vDSP_measqv(mono, 1, &msq, vDSP_Length(L))
        sd = max(1e-5, (msq - mu * mu).squareRoot())
        let chans = [left.map { ($0 - mu) / sd }, right.map { ($0 - mu) / sd }]

        guard let fft = FFT(n: nfft) else { throw AudioAnalyzer.AnalyzeError.cannotRead("FFT") }
        let le = Int((Double(segment) / Double(hop)).rounded(.up))           // 336 frames
        let pad = hop / 2 * 3
        let stride = Int(0.85 * Double(segment))       // windows overlap 15 % (blended), fewer windows to run
        var weight = [Float](repeating: 0, count: segment)
        for i in 0..<segment { weight[i] = Float(i < segment / 2 ? i + 1 : segment - i) }
        let wmax = weight.max() ?? 1
        for i in 0..<segment { weight[i] /= wmax }
        let ns = sources.count

        // outputs, written as they become final (each window overlaps the next by 25 %)
        let fileSettings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: StemSplitter.rate,
                                           AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000]
        try? FileManager.default.removeItem(at: outDir)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var files: [AVAudioFile] = []
        for s in sources {
            files.append(try AVAudioFile(forWriting: outDir.appendingPathComponent("\(s).m4a"), settings: fileSettings,
                                         commonFormat: .pcmFormatFloat32, interleaved: false))
        }
        var acc = [[[Float]]](repeating: [[Float]](repeating: [Float](repeating: 0, count: segment), count: 2), count: ns)
        var wsum = [Float](repeating: 0, count: segment)
        let peakWin = Int(StemSplitter.rate / StemSplitter.peaksPerSecond)
        var wave = [[Float]](repeating: [], count: ns)
        var peakCur = [Float](repeating: 0, count: ns), peakFill = 0

        func emit(_ count: Int) throws {
            guard count > 0 else { return }
            for s in 0..<ns {
                guard let buf = AVAudioPCMBuffer(pcmFormat: files[s].processingFormat, frameCapacity: AVAudioFrameCount(count)),
                      let ch = buf.floatChannelData else { continue }
                buf.frameLength = AVAudioFrameCount(count)
                for c in 0..<2 {
                    for i in 0..<count { ch[c][i] = acc[s][c][i] / max(wsum[i], 1e-6) * sd + mu }
                }
                try files[s].write(from: buf)
            }
            for i in 0..<count {
                for s in 0..<ns {
                    let v = max(abs(acc[s][0][i]), abs(acc[s][1][i])) / max(wsum[i], 1e-6) * sd
                    peakCur[s] = max(peakCur[s], v)
                }
                peakFill += 1
                if peakFill == peakWin { for s in 0..<ns { wave[s].append(peakCur[s]); peakCur[s] = 0 }; peakFill = 0 }
            }
        }

        let mixArr = try MLMultiArray(shape: [1, 2, NSNumber(value: segment)], dataType: .float32)
        let magArr = try MLMultiArray(shape: [1, 4, NSNumber(value: half), NSNumber(value: le)], dataType: .float32)
        // window envelope of the inverse transform (le frames + 2 empty ones each side)
        let frames = le + 4
        let total = nfft + hop * (frames - 1)
        var wenv = [Float](repeating: 0, count: total)
        for f in 0..<frames { for j in 0..<nfft { wenv[f * hop + j] += fft.windowValue(j) * fft.windowValue(j) } }
        var offset = 0
        var segIndex = 0
        let segCount = Int((Double(L) / Double(stride)).rounded(.up))
        var re = [Float](repeating: 0, count: half), im = [Float](repeating: 0, count: half)
        var frame = [Float](repeating: 0, count: nfft)
        while offset < L {
            let n = min(segment, L - offset)
            // ---- input window (zero-padded at the end)
            var seg = [[Float]](repeating: [Float](repeating: 0, count: segment), count: 2)
            for c in 0..<2 { for i in 0..<n { seg[c][i] = chans[c][offset + i] } }
            let mixP = mixArr.dataPointer.bindMemory(to: Float.self, capacity: 2 * segment)
            let ms = mixArr.strides.map(\.intValue)
            for c in 0..<2 { for i in 0..<segment { mixP[c * ms[1] + i * ms[2]] = seg[c][i] } }
            // ---- spectrogram (Demucs: reflect-pad, centred STFT, normalized, drop Nyquist, frames 2..<2+le)
            let magP = magArr.dataPointer.bindMemory(to: Float.self, capacity: 4 * half * le)
            let gs = magArr.strides.map(\.intValue)
            let scale = 1 / (2 * Float(nfft).squareRoot())
            for c in 0..<2 {
                var x = reflectPad(seg[c], pad, pad + le * hop - segment)
                x = reflectPad(x, nfft / 2, nfft / 2)
                x.withUnsafeBufferPointer { xp in
                    for t in 0..<le {
                        fft.forward(xp.baseAddress! + (t + 2) * hop, &re, &im)
                        for k in 0..<half {
                            let r = re[k] * scale, iv = k == 0 ? 0 : im[k] * scale
                            magP[(c * 2) * gs[1] + k * gs[2] + t * gs[3]] = r
                            magP[(c * 2 + 1) * gs[1] + k * gs[2] + t * gs[3]] = iv
                        }
                    }
                }
            }
            // ---- network(s)
            let inp = try MLDictionaryFeatureProvider(dictionary: ["mix": MLFeatureValue(multiArray: mixArr),
                                                                    "mag": MLFeatureValue(multiArray: magArr)])
            /// one part of a network's output, back to audio for this window (n samples, normalized scale)
            func render(_ out: MLFeatureProvider, _ s: Int, _ c: Int) throws -> [Float] {
                guard let spec = out.featureValue(for: "spec")?.multiArrayValue,
                      let wav = out.featureValue(for: "wave")?.multiArrayValue,
                      spec.dataType == .float32, wav.dataType == .float32 else {
                    throw AudioAnalyzer.AnalyzeError.cannotRead("model output")
                }
                let sp = spec.dataPointer.bindMemory(to: Float.self, capacity: spec.count)
                let ss = spec.strides.map(\.intValue)
                let wp = wav.dataPointer.bindMemory(to: Float.self, capacity: wav.count)
                let wst = wav.strides.map(\.intValue)
                let yScale = 2 * Float(nfft).squareRoot()
                var y = [Float](repeating: 0, count: total)
                for f in 2..<(2 + le) {
                    let t = f - 2
                    for k in 0..<half {
                        re[k] = sp[s * ss[1] + (c * 2) * ss[2] + k * ss[3] + t * ss[4]] * yScale
                        im[k] = k == 0 ? 0 : sp[s * ss[1] + (c * 2 + 1) * ss[2] + k * ss[3] + t * ss[4]] * yScale
                    }
                    fft.inverse(&re, &im, &frame)
                    for j in 0..<nfft { y[f * hop + j] += frame[j] * fft.windowValue(j) }
                }
                let start = nfft / 2 + pad
                var o = [Float](repeating: 0, count: n)
                for i in 0..<n {
                    let e = wenv[start + i]
                    o[i] = (e > 1e-11 ? y[start + i] / e : 0) + wp[s * wst[1] + c * wst[2] + i * wst[3]]
                }
                return o
            }
            let out = try model.prediction(from: inp)
            var parts = [[[Float]]](repeating: [[], []], count: ns)
            for s in 0..<ns { for c in 0..<2 { parts[s][c] = try render(out, s, c) } }
            // The vocals specialist (fine-tuned Demucs) hears more of the singing — backing vocals, doubles,
            // chops that the 6-part model leaves in "other": use its vocals, and take that difference out of "other"
            // only where the first model hears singing (saves most of the time on backing tracks)
            func power(_ x: [Float]) -> Float { var v: Float = 0; vDSP_measqv(x, 1, &v, vDSP_Length(x.count)); return v }
            let vi0 = sources.firstIndex(of: "vocals") ?? 3
            let vocalPower = power(parts[vi0][0]) + power(parts[vi0][1])
            let mixPower = power(Array(seg[0][0..<n])) + power(Array(seg[1][0..<n]))
            let hasSinging = vocalPower > 0.0005 * mixPower
            if hasSinging, let vox = voxModel, let vi = sources.firstIndex(of: "vocals"), let oi = sources.firstIndex(of: "other") {
                let vout = try vox.prediction(from: inp)
                for c in 0..<2 {
                    let better = try render(vout, voxIndex, c)
                    for i in 0..<n { parts[oi][c][i] += parts[vi][c][i] - better[i] }
                    parts[vi][c] = better
                }
            }
            for s in 0..<ns { for c in 0..<2 { for i in 0..<n { acc[s][c][i] += parts[s][c][i] * weight[i] } } }
            for i in 0..<n { wsum[i] += weight[i] }
            // ---- everything before the next window is final
            let last = offset + stride >= L
            let ready = last ? n : stride
            try emit(ready)
            if !last {
                for s in 0..<ns { for c in 0..<2 {
                    acc[s][c].removeFirst(ready); acc[s][c].append(contentsOf: [Float](repeating: 0, count: ready))
                } }
                wsum.removeFirst(ready); wsum.append(contentsOf: [Float](repeating: 0, count: ready))
            }
            offset += stride
            segIndex += 1
            progress(Double(segIndex) / Double(max(segCount, 1)))
        }
        if peakFill > 0 { for s in 0..<ns { wave[s].append(peakCur[s]) } }
        files.removeAll()
        // Vocals focus: the specialist's vocals are excellent but its drums/bass are rough — split the
        // instrumental (everything but the vocals) with the quick splitter instead (seconds)
        if !full {
            let parts = ["drums", "bass", "other"].map { outDir.appendingPathComponent("\($0).m4a") }
            let inst = outDir.appendingPathComponent("instrumental.m4a")
            try mixFiles(parts, to: inst)
            let tmp = outDir.appendingPathComponent("inst-split", isDirectory: true)
            _ = try StemSplitter.run(url: inst, settings: DetectionSettings(), stemsDir: tmp) { _ in }
            for name in ["drums", "bass"] {
                let dst = outDir.appendingPathComponent("\(name).m4a")
                try? FileManager.default.removeItem(at: dst)
                try FileManager.default.moveItem(at: tmp.appendingPathComponent("\(name).m4a"), to: dst)
            }
            // other = the rest of the instrumental (+ anything the quick splitter called "vocals")
            try mixFiles([tmp.appendingPathComponent("other.m4a"), tmp.appendingPathComponent("vocals.m4a")],
                         to: outDir.appendingPathComponent("other.m4a"))
            try? FileManager.default.removeItem(at: tmp)
            try? FileManager.default.removeItem(at: inst)
            // waveform overviews for the new parts
            for (k, name) in sources.enumerated() where name != "vocals" {
                if let lr = try? StemSplitter.loadStereo(url: outDir.appendingPathComponent("\(name).m4a")) {
                    let (l, r) = lr
                    var pk: [Float] = []
                    var i = 0
                    while i < l.count {
                        let e = min(l.count, i + peakWin)
                        var p: Float = 0
                        for j in i..<e { p = max(p, abs(l[j]), abs(r[j])) }
                        pk.append(p); i = e
                    }
                    wave[k] = pk
                }
            }
        }
        // Lead vocal vs background vocals: the lead sits in the centre, backing vocals / doubles / stacks
        // are spread wider. Split the vocal part into vocals (lead) + backing.
        var names = sources
        if let vi = sources.firstIndex(of: "vocals"), let lb = try? splitLeadBacking(outDir) {
            wave[vi] = lb.0
            wave.append(lb.1)
            names.append("backing")
        }
        let top = max(wave.map { $0.max() ?? 0 }.max() ?? 0, 1e-6)
        var overview: [String: [Float]] = [:]
        for (s, name) in names.enumerated() where s < wave.count { overview[name] = wave[s].map { (($0 / top) * 1000).rounded() / 1000 } }
        try JSONEncoder().encode(StemOverview(perSecond: StemSplitter.peaksPerSecond, peaks: overview))
            .write(to: outDir.appendingPathComponent("overview.json"))
    }

    /// Splits vocals.m4a into the centred lead (written back as vocals.m4a) and the wider backing vocals
    /// (backing.m4a). Returns their waveform overviews (peaks per 1/20 s).
    static func splitLeadBacking(_ dir: URL) throws -> ([Float], [Float]) {
        let src = dir.appendingPathComponent("vocals.m4a")
        let (l, r) = try StemSplitter.loadStereo(url: src)
        let count = l.count
        let n = 2048, hop = 1024, bins = 1024
        guard count > n, let fft = FFT(n: n) else { throw AudioAnalyzer.AnalyzeError.tooShort }
        var L = l; L.append(contentsOf: [Float](repeating: 0, count: n))
        var R = r; R.append(contentsOf: [Float](repeating: 0, count: n))
        let frames = count / hop + 1
        var out = [[[Float]]](repeating: [[Float]](repeating: [Float](repeating: 0, count: count + n), count: 2), count: 2)  // [lead/back][ch]
        var lre = [Float](repeating: 0, count: bins), lim = lre, rre = lre, rim = lre
        var mre = lre, mim = lre, frame = [Float](repeating: 0, count: n)
        var mask = [Float](repeating: 0, count: bins)
        L.withUnsafeBufferPointer { lp in
            R.withUnsafeBufferPointer { rp in
                for t in 0..<frames {
                    fft.forward(lp.baseAddress! + t * hop, &lre, &lim)
                    fft.forward(rp.baseAddress! + t * hop, &rre, &rim)
                    for k in 0..<bins {
                        let en = lre[k] * lre[k] + lim[k] * lim[k] + rre[k] * rre[k] + rim[k] * rim[k] + 1e-12
                        var c = 2 * max(0, lre[k] * rre[k] + lim[k] * rim[k]) / en
                        c = c * c
                        mask[k] = c
                    }
                    for (side, srcRe, srcIm) in [(0, lre, lim), (1, rre, rim)] {
                        for which in 0..<2 {
                            for k in 0..<bins {
                                let m = which == 0 ? mask[k] : 1 - mask[k]
                                mre[k] = srcRe[k] * m; mim[k] = srcIm[k] * m
                            }
                            fft.inverse(&mre, &mim, &frame)
                            let base = t * hop
                            for j in 0..<n { out[which][side][base + j] += frame[j] }
                        }
                    }
                }
            }
        }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: StemSplitter.rate,
                                       AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000]
        var peaks: [[Float]] = [[], []]
        let peakWin = Int(StemSplitter.rate / StemSplitter.peaksPerSecond)
        for (which, name) in ["vocals", "backing"].enumerated() {
            let url = dir.appendingPathComponent("\(name).m4a")
            try? FileManager.default.removeItem(at: url)
            let f = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let block = 32768
            guard let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(block)),
                  let ch = buf.floatChannelData else { continue }
            var pos = 0
            while pos < count {
                let m = min(block, count - pos)
                for c in 0..<2 { for i in 0..<m { ch[c][i] = out[which][c][pos + i] } }
                buf.frameLength = AVAudioFrameCount(m)
                try f.write(from: buf)
                pos += m
            }
            var i = 0
            while i < count {
                let e = min(count, i + peakWin)
                var p: Float = 0
                for k in i..<e { p = max(p, abs(out[which][0][k]), abs(out[which][1][k])) }
                peaks[which].append(p)
                i = e
            }
        }
        return (peaks[0], peaks[1])
    }

    /// Sums audio files (same length / rate) into one stereo .m4a.
    static func mixFiles(_ srcs: [URL], to dst: URL) throws {
        var l: [Float] = [], r: [Float] = []
        for u in srcs where FileManager.default.fileExists(atPath: u.path) {
            let (a, b) = try StemSplitter.loadStereo(url: u)
            if l.count < a.count { l += [Float](repeating: 0, count: a.count - l.count); r += [Float](repeating: 0, count: a.count - r.count) }
            for i in a.indices { l[i] += a[i]; r[i] += b[i] }
        }
        try? FileManager.default.removeItem(at: dst)
        let f = try AVAudioFile(forWriting: dst, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: StemSplitter.rate,
                                                            AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000],
                                commonFormat: .pcmFormatFloat32, interleaved: false)
        let block = 32768
        guard let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(block)),
              let ch = buf.floatChannelData else { return }
        var pos = 0
        while pos < l.count {
            let m = min(block, l.count - pos)
            for i in 0..<m { ch[0][i] = l[pos + i]; ch[1][i] = r[pos + i] }
            buf.frameLength = AVAudioFrameCount(m)
            try f.write(from: buf)
            pos += m
        }
    }

    /// numpy-style "reflect" padding (mirror without repeating the edge sample).
    static func reflectPad(_ x: [Float], _ left: Int, _ right: Int) -> [Float] {
        let n = x.count
        var out = [Float](repeating: 0, count: n + left + right)
        for i in 0..<out.count {
            var j = i - left
            // reflect back into range (repeat for pads longer than the signal)
            while j < 0 || j >= n {
                if j < 0 { j = -j }
                if j >= n { j = 2 * (n - 1) - j }
            }
            out[i] = x[j]
        }
        return out
    }
}
