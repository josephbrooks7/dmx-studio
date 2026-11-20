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
    static var modelURL: URL { overrideModel ?? modelsDir.appendingPathComponent("DemucsHQ.mlmodelc", isDirectory: true) }
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
        cfg.computeUnits = .cpuOnly          // Intel Macs: CPU only (keeps the AMD graphics chip out of it)
        #else
        cfg.computeUnits = .all
        #endif
        let model = try MLModel(contentsOf: modelURL, configuration: cfg)
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
        let stride = Int(0.75 * Double(segment))
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
            // ---- network
            let inp = try MLDictionaryFeatureProvider(dictionary: ["mix": MLFeatureValue(multiArray: mixArr),
                                                                    "mag": MLFeatureValue(multiArray: magArr)])
            let out = try model.prediction(from: inp)
            guard let spec = out.featureValue(for: "spec")?.multiArrayValue,
                  let wav = out.featureValue(for: "wave")?.multiArrayValue else {
                throw AudioAnalyzer.AnalyzeError.cannotRead("model output")
            }
            let sp = spec.dataPointer.bindMemory(to: Float.self, capacity: spec.count)
            let ss = spec.strides.map(\.intValue)
            let wp = wav.dataPointer.bindMemory(to: Float.self, capacity: wav.count)
            let wst = wav.strides.map(\.intValue)
            // ---- inverse spectrogram + time branch, weighted into the running output
            guard spec.dataType == .float32, wav.dataType == .float32 else { throw AudioAnalyzer.AnalyzeError.cannotRead("model output type") }
            let yScale = 2 * Float(nfft).squareRoot()
            for s in 0..<ns {
                for c in 0..<2 {
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
                    for i in 0..<n {
                        let e = wenv[start + i]
                        let v = (e > 1e-11 ? y[start + i] / e : 0) + wp[s * wst[1] + c * wst[2] + i * wst[3]]
                        acc[s][c][i] += v * weight[i]
                    }
                }
            }
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
        let top = max(wave.map { $0.max() ?? 0 }.max() ?? 0, 1e-6)
        var overview: [String: [Float]] = [:]
        for (s, name) in sources.enumerated() { overview[name] = wave[s].map { (($0 / top) * 1000).rounded() / 1000 } }
        try JSONEncoder().encode(StemOverview(perSecond: StemSplitter.peaksPerSecond, peaks: overview))
            .write(to: outDir.appendingPathComponent("overview.json"))
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
