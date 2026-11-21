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
        // small at 8-bit: 90% of the words right on a real song (base: 78%), about 3× slower
        var file: String { self == .base ? "ggml-base.bin" : "ggml-small-q8_0.bin" }
        var label: String { self == .base ? "Fast" : "Accurate" }
        var url: URL { URL(string: "https://github.com/josephbrooks7/dmx-studio/releases/download/whisper-1/\(file)")! }
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
        get { ModelSize(rawValue: UserDefaults.standard.string(forKey: "whisperModel2") ?? "")
            ?? (isInstalled(.small) ? .small : .base) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "whisperModel2") }
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
                var lastLog = "", lastData = Data()
                func listen(noContext: Bool) throws -> [LyricWord] {
                    let p = Process()
                    p.executableURL = bin
                    p.qualityOfService = .utility
                    // real cores (the doubled-up "hyper-threads" only slow it down)
                    var phys: Int32 = 0; var sz = MemoryLayout<Int32>.size
                    sysctlbyname("hw.physicalcpu", &phys, &sz, nil, 0)
                    // half the real cores: the Mac stays cool and responsive (all cores at once overloaded a 2016 MacBook Pro)
                    let cores = phys > 0 ? Int(phys) : ProcessInfo.processInfo.activeProcessorCount / 2
                    let threads = max(2, min(4, cores / 2))
                    // Settings that make Whisper hear singing in a full song (tested on a real song: from
                    // "[Music]" everywhere to the full lyrics): beam search, no "[Music]"-type tokens, and a hint
                    // that this is a song
                    p.arguments = ["-m", modelPath.path, "-f", wav.path, "-ml", "1", "-sow", "-ojf", "-sns",
                                   "--prompt", language == .es ? "Letra de la canción:" : "Song lyrics:",
                                   "-of", tmp.appendingPathComponent("out").path, "-np", "-pp", "-t", "\(threads)",
                                   // a wider search: tested on a real song, 85% → 89% of the words right
                                   "-bs", "8", "-bo", "8",
                                   // English-only models can only do English
                                   "-l", modelPath.lastPathComponent.contains(".en") ? "en" : language.code]
                    // exact word timing (DTW): the normal timing often stretches the first words of a passage
                    // back to the start of the listening window (a line sung at 0:13 shown at 0:00)
                    if let dtw = dtwName(modelPath) { p.arguments! += ["-dtw", dtw] }
                    // no carried-over context: stops Whisper looping one line for minutes (but it hears
                    // a bit less: 91% → 89% on a real song), so it's the second try
                    if noContext { p.arguments! += ["-mc", "0"] }
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
                    lastLog = errLog; lastData = data
                    // back to song time (silent stretches were cut out to save time)
                    for k in words.indices {
                        words[k].start = mapTime(words[k].start, timeMap)
                        words[k].end = mapTime(words[k].end, timeMap)
                    }
                    return words
                }
                // 1) with context (hears the most); 2) if it got stuck looping, again without
                let first = try listen(noContext: false)
                var words = removeLoops(first)
                if looksPoor(words) || Double(words.count) < Double(first.count) * 0.85 {
                    DispatchQueue.main.async { progress(0) }
                    let second = removeLoops(try listen(noContext: true))
                    if !looksPoor(second) || second.count > words.count { words = second }
                }
                if !trusted.isEmpty {
                    words = words.filter { w in trusted.contains { w.start < $0.end + 0.6 && w.end > $0.start - 0.6 } }
                }
                for k in words.indices { words[k].vocalist = background ? "Background" : "Lead" }
                if ProcessInfo.processInfo.environment["DMX_DEBUG_WHISPER"] != nil {
                    print("whisper stderr: \(lastLog.suffix(3000))")
                    print("whisper json: \(String(decoding: lastData.prefix(1500), as: UTF8.self))")
                    let wavSize = (try? FileManager.default.attributesOfItem(atPath: wav.path)[.size] as? Int) ?? -1
                    print("wav bytes: \(wavSize)")
                }
                DispatchQueue.main.async { done(.success(words)) }
            } catch {
                DispatchQueue.main.async { done(.failure(error)) }
            }
        }
    }

    /// Lines Whisper makes up when it can't hear words (from its training on video subtitles).
    static let madeUp = ["thank you for watching", "thanks for watching", "subtitles by", "please subscribe",
                         "like and subscribe", "see you next time", "i'm not sure what to say",
                         "i don't know what to say", "the end of the world", "music by"]

    /// Whisper's typical failure on songs is looping: one line again and again for a minute.
    /// Keep a repeated phrase at most twice in a row (a real hook is fine twice, a 20× loop isn't),
    /// drop the known made-up lines, and drop the low-confidence copies.
    static func removeLoops(_ input: [LyricWord]) -> [LyricWord] {
        func norm(_ t: String) -> String {
            t.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "'" }
        }
        var w = input
        // 1) made-up subtitle lines
        var keep = [Bool](repeating: true, count: w.count)
        let keys = w.map { norm($0.text) }
        for phrase in madeUp {
            let pw = phrase.split(separator: " ").map { norm(String($0)) }
            guard pw.count <= keys.count, !pw.isEmpty else { continue }
            var i = 0
            while i + pw.count <= keys.count {
                if Array(keys[i..<i + pw.count]) == pw {
                    for k in i..<i + pw.count { keep[k] = false }
                    i += pw.count
                } else { i += 1 }
            }
        }
        w = zip(w, keep).filter { $0.1 }.map { $0.0 }
        // 2) back-to-back repeats of the same phrase (longest phrases first)
        var changed = true
        while changed {
            changed = false
            let k = w.map { norm($0.text) }
            outer: for n in stride(from: min(12, k.count / 3), through: 1, by: -1) {
                let maxRepeats = n >= 3 ? 3 : 6          // "no, no, no, no" can be real; a 5-word line 4× in a row isn't
                var i = 0
                while i + n * (maxRepeats + 1) <= k.count {
                    let unit = Array(k[i..<i + n])
                    if unit.allSatisfy({ $0.isEmpty }) { i += 1; continue }
                    var reps = 1
                    while i + (reps + 1) * n <= k.count && Array(k[i + reps * n..<i + (reps + 1) * n]) == unit { reps += 1 }
                    if reps > maxRepeats {
                        // a real vocal stutter ("ah ah ah ah ah", chopped vocals) is quick: each repeat a fraction
                        // of a second. Whisper's made-up loops repeat whole lines over many seconds.
                        let span = w[i + reps * n - 1].end - w[i].start
                        if n <= 2 && span / Double(reps) < 0.9 { i += reps * n; continue }
                        w.removeSubrange(i + maxRepeats * n..<i + reps * n)
                        changed = true
                        break outer
                    }
                    i += 1
                }
            }
        }
        return w
    }

    /// True when the transcript looks like guessing: a few phrases make up most of it.
    static func looksPoor(_ w: [LyricWord]) -> Bool {
        guard w.count >= 8 else { return true }
        let k = w.map { $0.text.lowercased().filter { $0.isLetter } }
        var grams: [String: Int] = [:]
        for i in 0..<(k.count - 3) { grams[k[i..<i + 4].joined(separator: " "), default: 0] += 1 }
        let top = grams.values.max() ?? 0
        let avgConf = w.map(\.confidence).reduce(0, +) / Double(w.count)
        return Double(top * 4) > Double(k.count) * 0.5 || avgConf < 0.35
    }

    /// The model name whisper.cpp needs for exact word timing ("base", "small", "tiny.en"…), from the file name
    static func dtwName(_ model: URL) -> String? {
        var n = model.deletingPathExtension().lastPathComponent
        if n.hasPrefix("ggml-") { n.removeFirst(5) }
        if let q = n.range(of: #"-q\d.*$"#, options: .regularExpression) { n.removeSubrange(q) }   // quantized copies
        let known = ["tiny", "tiny.en", "base", "base.en", "small", "small.en", "medium", "medium.en", "large.v1", "large.v2", "large.v3", "large.v3.turbo"]
        return known.contains(n) ? n : nil
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
            // exact timing when it was worked out (centiseconds; -1 = none)
            var start = a / 1000, end = max(a, b) / 1000
            if let d = ((s["tokens"] as? [[String: Any]]) ?? []).first(where: { !(($0["text"] as? String) ?? "").hasPrefix("[_") })?["t_dtw"] as? Double,
               d >= 0 {
                start = d / 100
                end = max(start + 0.12, min(end, start + 1.5))
            }
            let w = LyricWord(text: text, start: start, end: end, confidence: conf)
            // Whisper sometimes invents words in silence: keep only words where someone is singing
            if !phrases.isEmpty && !phrases.contains(where: { w.start < $0.end + 0.6 && w.end > $0.start - 0.6 }) { continue }
            out.append(w)
        }
        // exact timing: a word ends where the next one starts (at most 1.5 s later)
        for k in out.indices.dropLast() where out[k + 1].start > out[k].start {
            out[k].end = min(out[k].start + 1.5, max(out[k].start + 0.12, out[k + 1].start - 0.02))
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
