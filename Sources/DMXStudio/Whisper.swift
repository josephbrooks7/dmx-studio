import Foundation
import AVFoundation
import Accelerate

/// Downloads a file once, with progress (used for the AI models).
final class FileDownloader: NSObject, URLSessionDownloadDelegate {
    private let dest: URL
    private let progress: (Double) -> Void
    private let done: (Error?) -> Void
    private var session: URLSession?
    private static var active: [FileDownloader] = []

    private init(dest: URL, progress: @escaping (Double) -> Void, done: @escaping (Error?) -> Void) {
        self.dest = dest; self.progress = progress; self.done = done
    }

    static func fetch(_ url: URL, to dest: URL, progress: @escaping (Double) -> Void, done: @escaping (Error?) -> Void) {
        let d = FileDownloader(dest: dest, progress: { p in DispatchQueue.main.async { progress(p) } },
                               done: { e in DispatchQueue.main.async { done(e) } })
        active.append(d)
        let s = URLSession(configuration: .default, delegate: d, delegateQueue: nil)
        d.session = s
        s.downloadTask(with: url).resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            if let http = downloadTask.response as? HTTPURLResponse, http.statusCode >= 400 {
                throw NSError(domain: "DMX", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Download failed (\(http.statusCode))."])
            }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: location, to: dest)
            finish(nil)
        } catch { finish(error) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(error) }
    }
    private var finished = false
    private func finish(_ e: Error?) {
        guard !finished else { return }
        finished = true
        done(e)
        session?.finishTasksAndInvalidate()
        DispatchQueue.main.async { FileDownloader.active.removeAll { $0 === self } }
    }
}

/// Lyrics transcription with Whisper (OpenAI's open-source speech model, via whisper.cpp — MIT
/// license), running on this Mac on the separated vocals. Gives every word with its timing and how sure
/// it is. Nothing is sent anywhere.
enum WhisperEngine {
    enum ModelSize: String, CaseIterable, Identifiable {
        case base, small
        var id: String { rawValue }
        var file: String { "ggml-\(rawValue).bin" }
        var label: String { self == .base ? "Standard (built in)" : "Accurate (466 MB download)" }
        var url: URL { URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(file)")! }
    }

    static var binary: URL? {
        guard let u = Bundle.main.url(forResource: "whisper-cli", withExtension: nil),
              FileManager.default.isExecutableFile(atPath: u.path) else { return nil }
        return u
    }
    static var isAvailable: Bool { binary != nil }
    static var overrideModel: URL?   // tests
    static var running: Process?     // the transcription in progress (for Stop)
    static func modelURL(_ m: ModelSize) -> URL {
        if let o = overrideModel { return o }
        // built into the app (works offline), else downloaded
        if let b = Bundle.main.resourceURL?.appendingPathComponent("Models/\(m.file)"), FileManager.default.fileExists(atPath: b.path) { return b }
        return HQSplitter.modelsDir.appendingPathComponent(m.file)
    }
    static func isInstalled(_ m: ModelSize) -> Bool {
        ((try? FileManager.default.attributesOfItem(atPath: modelURL(m).path)[.size] as? Int) ?? 0) > 10_000_000
    }
    enum Language: String, CaseIterable, Identifiable {
        case en = "English", es = "Spanish", auto = "Auto-detect"
        var id: String { rawValue }
        var code: String { switch self { case .en: return "en"; case .es: return "es"; case .auto: return "auto" } }
    }
    static var language: Language {
        get { Language(rawValue: UserDefaults.standard.string(forKey: "lyricsLanguage") ?? "") ?? .en }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "lyricsLanguage") }
    }
    static var chosen: ModelSize {
        get { ModelSize(rawValue: UserDefaults.standard.string(forKey: "whisperModel") ?? "") ?? .base }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "whisperModel") }
    }

    /// Transcribes the vocals. Runs in the background; `done` is called on the main thread.
    static func transcribe(vocals: URL, extra: [URL] = [], phrases: [TimeSpan], model: ModelSize, background: Bool = false,
                           progress: @escaping (Double) -> Void,
                           done: @escaping (Result<[LyricWord], Error>) -> Void) {
        guard let bin = binary else { done(.failure(LyricsError.unavailable)); return }
        let modelPath = modelURL(model)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("whisper-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tmp) }
                let wav = tmp.appendingPathComponent("vocals.wav")
                // Only silence the non-sung parts when singing was clearly found; on backing tracks with
                // faint or partial vocals, let Whisper hear the whole vocal part
                let dur = (try? AVAudioFile(forReading: vocals)).map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0
                let sung = phrases.reduce(0) { $0 + $1.end - $1.start }
                let trusted = !background && dur > 0 && sung / dur >= 0.15 ? phrases : []
                let timeMap = try writeSpeechWav([vocals] + extra, to: wav, keep: trusted, boost: background)
                let p = Process()
                p.executableURL = bin
                // real cores (the doubled-up "hyper-threads" only slow it down)
                var phys: Int32 = 0; var sz = MemoryLayout<Int32>.size
                sysctlbyname("hw.physicalcpu", &phys, &sz, nil, 0)
                let threads = max(2, min(8, phys > 0 ? Int(phys) : ProcessInfo.processInfo.activeProcessorCount / 2))
                p.arguments = ["-m", modelPath.path, "-f", wav.path, "-ml", "1", "-sow", "-ojf", "-bs", "1", "-bo", "1",
                               "-of", tmp.appendingPathComponent("out").path, "-np", "-pp", "-t", "\(threads)",
                               // English-only models can only do English
                               "-l", modelPath.lastPathComponent.contains(".en") ? "en" : language.code]
                let err = Pipe()
                p.standardError = err
                p.standardOutput = FileHandle.nullDevice
                try p.run()
                running = p
                defer { running = nil }
                // progress lines on stderr: "...progress = 42%"
                var pending = "", errLog = ""
                while true {
                    let chunk = err.fileHandleForReading.availableData
                    if chunk.isEmpty { break }
                    pending += String(decoding: chunk, as: UTF8.self)
                    errLog += String(decoding: chunk, as: UTF8.self)
                    if errLog.count > 20000 { errLog = String(errLog.suffix(6000)) }
                    while let r = pending.range(of: "progress =") {
                        let rest = pending[r.upperBound...]
                        guard let pct = rest.firstIndex(of: "%") else { break }
                        if let v = Double(rest[..<pct].trimmingCharacters(in: .whitespaces)) {
                            DispatchQueue.main.async { progress(v / 100) }
                        }
                        pending = String(rest[rest.index(after: pct)...])
                    }
                    if pending.count > 4000 { pending = String(pending.suffix(200)) }
                }
                p.waitUntilExit()
                guard p.terminationStatus == 0 else { throw LyricsError.unavailable }
                let data = try Data(contentsOf: tmp.appendingPathComponent("out.json"))
                var words = parse(data, phrases: [], minConfidence: background ? 0.2 : 0.3)
                // back to song time (silent stretches were cut out to save time)
                for k in words.indices {
                    words[k].start = mapTime(words[k].start, timeMap)
                    words[k].end = mapTime(words[k].end, timeMap)
                }
                if !trusted.isEmpty {
                    words = words.filter { w in trusted.contains { w.start < $0.end + 0.6 && w.end > $0.start - 0.6 } }
                }
                for k in words.indices { words[k].vocalist = background ? "Background" : "Lead" }
                if ProcessInfo.processInfo.environment["DMX_DEBUG_WHISPER"] != nil {
                    print("whisper stderr: \(errLog.suffix(3000))")
                    print("whisper json: \(String(decoding: data.prefix(1500), as: UTF8.self))")
                    let wavSize = (try? FileManager.default.attributesOfItem(atPath: wav.path)[.size] as? Int) ?? -1
                    print("wav bytes: \(wavSize)")
                }
                DispatchQueue.main.async { done(.success(words)) }
            } catch {
                DispatchQueue.main.async { done(.failure(error)) }
            }
        }
    }

    /// whisper.cpp "full" JSON: one segment per word (-ml 1 -sow), with token probabilities.
    static func parse(_ data: Data, phrases: [TimeSpan], minConfidence: Double = 0.3) -> [LyricWord] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let segs = root["transcription"] as? [[String: Any]] else { return [] }
        var out: [LyricWord] = []
        for s in segs {
            guard let off = s["offsets"] as? [String: Any], let a = off["from"] as? Double, let b = off["to"] as? Double,
                  var text = s["text"] as? String else { continue }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !text.hasPrefix("["), !text.hasPrefix("("), text != "-" else { continue }   // [Music], (singing)…
            var ps: [Double] = []
            for t in (s["tokens"] as? [[String: Any]]) ?? [] {
                if let tt = t["text"] as? String, tt.hasPrefix("[_") { continue }
                if let p = t["p"] as? Double { ps.append(p) }
            }
            let conf = ps.isEmpty ? 0.5 : ps.reduce(0, +) / Double(ps.count)
            if conf < minConfidence { continue }      // very unsure: probably hearing words in the music
            let w = LyricWord(text: text, start: a / 1000, end: max(a, b) / 1000, confidence: conf)
            // Whisper sometimes invents words in silence: keep only words where someone is singing
            if !phrases.isEmpty && !phrases.contains(where: { w.start < $0.end + 0.6 && w.end > $0.start - 0.6 }) { continue }
            out.append(w)
        }
        return out
    }

    /// 16 kHz mono WAV of the vocals (what Whisper takes). Outside the sung phrases it's silent, so the
    /// timing stays the same but Whisper isn't tempted to "hear" words in the music.
    private static func read16k(_ src: URL, _ outFmt: AVAudioFormat) throws -> [Float] {
        let f = try AVAudioFile(forReading: src)
        guard let conv = AVAudioConverter(from: f.processingFormat, to: outFmt),
              let inBuf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: 32768) else { throw LyricsError.unavailable }
        conv.downmix = true
        var ended = false
        var all: [Float] = []
        while true {
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: 16384) else { break }
            var e: NSError?
            let st = conv.convert(to: outBuf, error: &e) { _, status in
                if ended { status.pointee = .endOfStream; return nil }
                do { try f.read(into: inBuf, frameCount: 32768) } catch { ended = true; status.pointee = .endOfStream; return nil }
                if inBuf.frameLength == 0 { ended = true; status.pointee = .endOfStream; return nil }
                status.pointee = .haveData
                return inBuf
            }
            if let e { throw e }
            let n = Int(outBuf.frameLength)
            if n > 0, let ch = outBuf.floatChannelData { all.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: n)) }
            if st == .endOfStream || st == .error || (ended && n == 0) { break }
        }
        return all
    }

    /// (where a piece starts in the shortened file, where it is in the song, how long) — seconds
    typealias TimeMap = [(out: Double, src: Double, len: Double)]
    static func mapTime(_ t: Double, _ map: TimeMap) -> Double {
        guard !map.isEmpty else { return t }
        let piece = map.last { $0.out <= t + 1e-6 } ?? map[0]
        return piece.src + (t - piece.out)
    }

    @discardableResult
    static func writeSpeechWav(_ srcs: [URL], to dst: URL, keep: [TimeSpan], boost: Bool = false) throws -> TimeMap {
        guard let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            throw LyricsError.unavailable
        }
        // the vocal-related parts, mixed together, at 16 kHz mono
        var all: [Float] = []
        for (n, src) in srcs.enumerated() {
            guard let part = try? read16k(src, outFmt) else { if n == 0 { throw LyricsError.unavailable } else { continue } }
            if all.count < part.count { all.append(contentsOf: [Float](repeating: 0, count: part.count - all.count)) }
            for i in part.indices { all[i] += part[i] }
        }
        if !keep.isEmpty {
            for i in all.indices {
                let t = Double(i) / 16000
                if !keep.contains(where: { t >= $0.start - 0.4 && t <= $0.end + 0.4 }) { all[i] = 0 }
            }
        }
        // Level the vocals so quiet singing (and background vocals) is loud enough for Whisper:
        // bring the louder sung stretches to a steady level, with a soft limit on peaks
        let win = 8000
        var rms: [Float] = []
        var i = 0
        while i < all.count {
            let e = min(all.count, i + win)
            var v: Float = 0
            all[i..<e].withUnsafeBufferPointer { vDSP_rmsqv($0.baseAddress!, 1, &v, vDSP_Length(e - i)) }
            rms.append(v); i = e
        }
        let loud = rms.filter { $0 > 1e-5 }.sorted()
        if !loud.isEmpty {
            let ref = loud[min(loud.count - 1, Int(Double(loud.count) * (boost ? 0.9 : 0.8)))]
            let gain = min(boost ? 60 : 12, max(1, (boost ? 0.15 : 0.1) / max(ref, 1e-6)))
            if gain > 1.05 { for k in all.indices { all[k] = tanhf(all[k] * gain) } }
        }
        // Cut out the silent stretches (no point making Whisper listen to them): keep everything with
        // sound in 0.5 s windows (plus a little either side), joined with short gaps
        var map: TimeMap = []
        let sr = 16000.0, step = 8000
        var levels: [Float] = []
        var j = 0
        while j < all.count {
            let e = min(all.count, j + step)
            var v: Float = 0
            all[j..<e].withUnsafeBufferPointer { vDSP_rmsqv($0.baseAddress!, 1, &v, vDSP_Length(e - j)) }
            levels.append(v); j = e
        }
        let peak = levels.max() ?? 0
        let gate = max(0.004, peak * 0.03)
        var keepWin = levels.map { $0 > gate }
        for (k, on) in keepWin.enumerated() where on {         // half a second of margin either side
            if k > 0 { keepWin[k - 1] = true }
            if k + 1 < keepWin.count { keepWin[k + 1] = true }
        }
        let kept = keepWin.filter { $0 }.count
        if kept > 0 && kept < keepWin.count * 9 / 10 {
            var out: [Float] = []
            let gap = [Float](repeating: 0, count: Int(0.3 * sr))
            var k = 0
            while k < keepWin.count {
                guard keepWin[k] else { k += 1; continue }
                var e = k
                while e < keepWin.count && keepWin[e] { e += 1 }
                let a = k * step, b = min(all.count, e * step)
                if !out.isEmpty { out += gap }
                map.append((out: Double(out.count) / sr, src: Double(a) / sr, len: Double(b - a) / sr))
                out.append(contentsOf: all[a..<b])
                k = e
            }
            all = out
        }
        let w = try AVAudioFile(forWriting: dst, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
                                                            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                                                            AVLinearPCMIsFloatKey: false],
                                commonFormat: .pcmFormatFloat32, interleaved: false)
        if ProcessInfo.processInfo.environment["DMX_DEBUG_WHISPER"] != nil { print("speech samples: \(all.count)") }
        // write in blocks (one huge buffer isn't written reliably)
        let block = 16384
        guard let buf = AVAudioPCMBuffer(pcmFormat: w.processingFormat, frameCapacity: AVAudioFrameCount(block)),
              let ch = buf.floatChannelData else { throw LyricsError.unavailable }
        var pos = 0
        while pos < all.count {
            let n = min(block, all.count - pos)
            for k in 0..<n { ch[0][k] = all[pos + k] }
            buf.frameLength = AVAudioFrameCount(n)
            try w.write(from: buf)
            pos += n
        }
        return map
    }
}
