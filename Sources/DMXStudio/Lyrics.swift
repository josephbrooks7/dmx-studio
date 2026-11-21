import Foundation
import Speech
import AVFoundation
import NaturalLanguage

// MARK: - Lyrics: the words being sung, when they're sung, and what the song is about

struct LyricWord: Codable, Hashable {
    var text: String
    var start: Double
    var end: Double
    var confidence: Double          // 0…1 (how sure the listener is; pasted words that were placed by estimate are low)
    var vocalist: String? = nil     // "Lead" or "Background"
}

struct LyricLine: Codable, Hashable, Identifiable {
    var id = UUID()
    var text: String
    var start: Double
    var end: Double
    var confidence: Double
    var sentiment: Double = 0       // -1 (dark) … +1 (bright)
    var vocalist: String? = nil     // "Lead" or "Background"
}

struct Lyrics: Codable, Hashable {
    var lines: [LyricLine]
    var words: [LyricWord]
    var source: String              // "Heard from the vocals" or "Pasted"
    var keywords: [String] = []     // what it's about, most used first
    var themes: [String] = []       // e.g. "Night & Party", "Dreams & Fantasy"
    var mood: Double = 0            // overall -1…+1
    var moodLabel: String = ""
    var insights: [LineInsight]? = nil        // per line: emotion, imagery, delivery, repeated
    var cues: [LyricCue]? = nil               // lighting suggestions made from the lyrics
    var mode: LyricLightingMode? = nil        // nil = Automatic
    var pastedText: String? = nil             // what you pasted (kept so it can be lined up again after a new listen)
    var engine: String? = nil                 // what heard the words ("Whisper base", "Apple speech", "Pasted")

    var summary: String {
        var parts: [String] = []
        if !themes.isEmpty { parts.append(themes.joined(separator: ", ")) }
        if !moodLabel.isEmpty { parts.append(moodLabel) }
        if !keywords.isEmpty { parts.append("words: " + keywords.prefix(5).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

enum LyricsError: LocalizedError {
    case notAllowed, unavailable, noVocals
    var errorDescription: String? {
        switch self {
        case .notAllowed: return "Speech recognition isn't allowed. Turn it on in System Preferences → Security & Privacy → Privacy → Speech Recognition."
        case .unavailable: return "Speech recognition isn't available on this Mac right now."
        case .noVocals: return "No sung parts were found in this song."
        }
    }
}

enum LyricsLearner {
    /// Listens to the separated vocals in short pieces (the sung phrases) and returns timed words.
    /// Uses on-device recognition when this Mac supports it, otherwise Apple's speech service.
    static func transcribe(vocals: URL, phrases: [TimeSpan], duration: Double,
                           progress: @escaping (Double) -> Void,
                           done: @escaping (Result<[LyricWord], Error>) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else { DispatchQueue.main.async { done(.failure(LyricsError.notAllowed)) }; return }
            let loc = WhisperEngine.language == .es ? "es-US" : "en-US"
            guard let rec = SFSpeechRecognizer(locale: Locale(identifier: loc)) ?? SFSpeechRecognizer(), rec.isAvailable else {
                DispatchQueue.main.async { done(.failure(LyricsError.unavailable)) }; return
            }
            // Pieces of at most ~45 s, cut between sung phrases
            var chunks: [TimeSpan] = []
            let src = phrases.isEmpty ? stride(from: 0.0, to: duration, by: 40).map { TimeSpan(start: $0, end: min(duration, $0 + 40)) } : phrases
            for p in src {
                let s = max(0, p.start - 0.25), e = min(duration, p.end + 0.35)
                if let last = chunks.last, e - last.start <= 45, s - last.end < 6 { chunks[chunks.count - 1].end = e }
                else { chunks.append(TimeSpan(start: s, end: e)) }
            }
            guard !chunks.isEmpty else { DispatchQueue.main.async { done(.failure(LyricsError.noVocals)) }; return }
            var words: [LyricWord] = []
            func run(_ i: Int) {
                guard i < chunks.count else { DispatchQueue.main.async { done(.success(words)) }; return }
                DispatchQueue.main.async { progress(Double(i) / Double(chunks.count)) }
                let c = chunks[i]
                guard let piece = try? cut(vocals, from: c.start, to: c.end) else { run(i + 1); return }
                let req = SFSpeechURLRecognitionRequest(url: piece)
                req.shouldReportPartialResults = false
                if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
                req.taskHint = .dictation
                var finished = false
                rec.recognitionTask(with: req) { result, error in
                    if finished { return }
                    if let result, result.isFinal {
                        finished = true
                        for seg in result.bestTranscription.segments {
                            words.append(LyricWord(text: seg.substring, start: c.start + seg.timestamp,
                                                   end: c.start + seg.timestamp + max(seg.duration, 0.1),
                                                   confidence: Double(seg.confidence)))
                        }
                        try? FileManager.default.removeItem(at: piece)
                        run(i + 1)
                    } else if error != nil {
                        finished = true                      // nothing understood in this piece: go on
                        try? FileManager.default.removeItem(at: piece)
                        run(i + 1)
                    }
                }
            }
            run(0)
        }
    }

    /// Copies a stretch of an audio file into a temporary WAV.
    static func cut(_ url: URL, from a: Double, to b: Double) throws -> URL {
        let f = try AVAudioFile(forReading: url)
        let sr = f.processingFormat.sampleRate
        let start = AVAudioFramePosition(max(0, a) * sr)
        let count = AVAudioFrameCount(max(0, min(Double(f.length - start), (b - a) * sr)))
        f.framePosition = start
        guard count > 0, let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: count) else { throw LyricsError.noVocals }
        try f.read(into: buf, frameCount: count)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("lyr-\(UUID().uuidString).wav")
        let w = try AVAudioFile(forWriting: out, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sr,
                                                            AVNumberOfChannelsKey: f.processingFormat.channelCount,
                                                            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false],
                                commonFormat: f.processingFormat.commonFormat, interleaved: f.processingFormat.isInterleaved)
        try w.write(from: buf)
        return out
    }

    // MARK: Lines, topic and mood

    /// Groups timed words into lines (a new line at each pause or new sung phrase) and works out what
    /// the song is about.
    static func build(words: [LyricWord], phrases: [TimeSpan], source: String) -> Lyrics {
        var lines: [LyricLine] = []
        var cur: [LyricWord] = []
        func flush() {
            guard let f = cur.first, let l = cur.last else { return }
            lines.append(LyricLine(text: cur.map(\.text).joined(separator: " "), start: f.start, end: l.end,
                                   confidence: cur.map(\.confidence).reduce(0, +) / Double(cur.count),
                                   vocalist: cur.first?.vocalist))
            cur = []
        }
        for w in words.sorted(by: { $0.start < $1.start }) {
            if let last = cur.last {
                let newPhrase = phrases.contains { $0.start > last.end - 0.05 && $0.start <= w.start + 0.05 }
                if w.start - last.end > 0.6 || newPhrase || cur.count >= 12 { flush() }
            }
            cur.append(w)
        }
        flush()
        var ly = Lyrics(lines: lines, words: words, source: source)
        analyze(&ly)
        return ly
    }

    /// Pasted official lyrics: one line per text line, placed on the sung phrases (or on the words
    /// that were heard, when there are some). Placement is an estimate, so confidence is low.
    static func align(text: String, heard: [LyricWord], phrases: [TimeSpan], duration: Double) -> Lyrics {
        let raw = cleanPasted(text)
        guard !raw.isEmpty else { return Lyrics(lines: [], words: [], source: "Pasted") }
        let lineWords = raw.map { $0.split(separator: " ").map(String.init) }
        let total = lineWords.reduce(0) { $0 + $1.count }
        var words: [LyricWord] = []
        var lines: [LyricLine] = []
        if heard.count >= 4, let matched = matchToHeard(lineWords, heard: heard, duration: duration) {
            // the pasted words lined up with the words that were actually heard
            for (li, lw) in matched.enumerated() {
                words += lw
                let c = lw.map(\.confidence).reduce(0, +) / Double(max(1, lw.count))
                lines.append(LyricLine(text: raw[li], start: lw.first?.start ?? 0, end: lw.last?.end ?? 0, confidence: c))
            }
        } else if heard.count >= 4 {
            // spread the pasted words over the heard words in order
            let h = heard.sorted { $0.start < $1.start }
            var k = 0
            for (li, lw) in lineWords.enumerated() {
                var placed: [LyricWord] = []
                for w in lw {
                    let j = min(h.count - 1, Int(Double(k) / Double(max(total, 1)) * Double(h.count)))
                    placed.append(LyricWord(text: w, start: h[j].start, end: h[j].end, confidence: 0.5))
                    k += 1
                }
                words += placed
                lines.append(LyricLine(text: raw[li], start: placed.first?.start ?? 0, end: placed.last?.end ?? 0, confidence: 0.5))
            }
        } else {
            let spans = phrases.isEmpty ? [TimeSpan(start: 0, end: duration)] : phrases
            let totalLen = spans.reduce(0) { $0 + $1.end - $1.start }
            var k = 0
            func timeAt(_ frac: Double) -> Double {
                var left = frac * totalLen
                for s in spans { let l = s.end - s.start; if left <= l { return s.start + left }; left -= l }
                return spans.last?.end ?? 0
            }
            for (li, lw) in lineWords.enumerated() {
                var placed: [LyricWord] = []
                for w in lw {
                    let a = timeAt(Double(k) / Double(total)), b = timeAt(Double(k + 1) / Double(total))
                    placed.append(LyricWord(text: w, start: a, end: b, confidence: 0.3))
                    k += 1
                }
                words += placed
                lines.append(LyricLine(text: raw[li], start: placed.first?.start ?? 0, end: placed.last?.end ?? 0, confidence: 0.3))
            }
        }
        var ly = Lyrics(lines: lines, words: words, source: "Pasted")
        ly.pastedText = text
        analyze(&ly)
        return ly
    }

    /// Lyrics copied from a web page come with extras: "Source: …", songwriter credits, video results,
    /// view counts, "AI can make mistakes", and often the lyrics twice. Keep just one copy of the words.
    static func cleanPasted(_ text: String) -> [String] {
        func isJunk(_ s: String) -> Bool {
            let low = s.lowercased(), n = s.split(separator: " ").count
            if low.range(of: #"^(source|songwriters?|written by|lyrics by|produced by|composers?)\s*:"#, options: .regularExpression) != nil { return true }
            if low.range(of: #"\bviews\b.*\bago\b"#, options: .regularExpression) != nil { return true }
            if low.range(of: #"\(lyrics\)|lyrics\]|\[letra|official (music )?video|lyric video"#, options: .regularExpression) != nil { return true }
            if s.contains("©") || low.hasPrefix("youtube") { return true }
            if s.range(of: #"^\d{1,2}:\d\d$"#, options: .regularExpression) != nil { return true }
            for p in ["ai can make mistakes", "try without personalization", "show more", "show less", "watch a lyric video",
                      "check out lyrics", "learn more", "lyricfind", "musixmatch", "genius.com", "azlyrics", "you might also like",
                      "get tickets", "see live"] where low.contains(p) && n <= 16 { return true }
            if n > 14, low.range(of: #"\b(lyrics|album|video|remix|chords|youtube)\b"#, options: .regularExpression) != nil { return true }
            if low.hasSuffix("lyrics") && n <= 6 { return true }                          // "Lyrics" headings
            return false
        }
        var blocks: [[String]] = [], cur: [String] = []
        for l in text.components(separatedBy: .newlines) {
            let s = l.trimmingCharacters(in: .whitespaces)
            if s.isEmpty || (s.hasPrefix("[") && s.hasSuffix("]")) { continue }   // [Chorus] labels: skip, same block
            if isJunk(s) { if !cur.isEmpty { blocks.append(cur); cur = [] }; continue }
            cur.append(s)
        }
        if !cur.isEmpty { blocks.append(cur) }
        if blocks.count <= 1 { return blocks.first ?? [] }
        blocks = blocks.filter { $0.count >= 2 }
        func wordSet(_ b: [String]) -> Set<String> {
            Set(b.flatMap { $0.split(separator: " ").map { $0.lowercased().filter { $0.isLetter } } })
        }
        func count(_ b: [String]) -> Int { b.reduce(0) { $0 + $1.split(separator: " ").count } }
        // the same lyrics twice: keep the longer copy
        var keep: [[String]] = []
        for b in blocks.sorted(by: { count($0) > count($1) }) {
            let bw = wordSet(b)
            if !keep.contains(where: { Double(bw.intersection(wordSet($0)).count) > 0.6 * Double(bw.count) }) { keep.append(b) }
        }
        return blocks.filter { b in keep.contains(b) }.flatMap { $0 }
    }

    static func normWord(_ t: String) -> String {
        t.lowercased().folding(options: .diacriticInsensitive, locale: nil).filter { $0.isLetter || $0.isNumber }
    }
    /// "the same word, give or take a letter" (Whisper on singing often gets one sound wrong)
    static func sameWord(_ a: String, _ b: String) -> Bool {
        if a == b { return !a.isEmpty }
        if a.count < 3 || b.count < 3 { return false }
        if a.hasPrefix(b) || b.hasPrefix(a) { return min(a.count, b.count) >= 4 }
        guard a.count >= 4, b.count >= 4, abs(a.count - b.count) <= 1 else { return false }
        let x = Array(a), y = Array(b)
        var prev = Array(0...y.count)
        for i in 1...x.count {
            var row = [i] + [Int](repeating: 0, count: y.count)
            for j in 1...y.count { row[j] = min(prev[j] + 1, row[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1)) }
            prev = row
        }
        return prev[y.count] <= 1
    }

    /// Line up pasted words with the heard words (best in-order match, like lining up two texts),
    /// take the heard timing where they match, and fill the rest in between.
    static func matchToHeard(_ lineWords: [[String]], heard: [LyricWord], duration: Double) -> [[LyricWord]]? {
        let h = heard.sorted { $0.start < $1.start }
        let pw = lineWords.enumerated().flatMap { li, ws in ws.map { (li, $0) } }
        let P = pw.map { normWord($0.1) }, H = h.map { normWord($0.text) }
        let n = P.count, m = H.count
        guard n > 0, m > 0, n * m < 4_000_000 else { return nil }
        // score grid: match +2, skip a pasted word -0.6 (not heard), skip a heard word -0.4 (made up / extra)
        var score = [Float](repeating: 0, count: (n + 1) * (m + 1))
        var move = [UInt8](repeating: 0, count: (n + 1) * (m + 1))   // 1 diag-match, 2 skip pasted, 3 skip heard, 4 diag-mismatch
        let w = m + 1
        for i in 1...n { score[i * w] = Float(i) * -0.6; move[i * w] = 2 }
        for j in 1...m { score[j] = Float(j) * -0.4; move[j] = 3 }
        for i in 1...n {
            for j in 1...m {
                let same = sameWord(P[i - 1], H[j - 1])
                let d = score[(i - 1) * w + j - 1] + (same ? 2 : -1)
                let up = score[(i - 1) * w + j] - 0.6
                let left = score[i * w + j - 1] - 0.4
                if d >= up && d >= left { score[i * w + j] = d; move[i * w + j] = same ? 1 : 4 }
                else if up >= left { score[i * w + j] = up; move[i * w + j] = 2 }
                else { score[i * w + j] = left; move[i * w + j] = 3 }
            }
        }
        var anchor = [Int?](repeating: nil, count: n)
        var i = n, j = m
        while i > 0 || j > 0 {
            let mv = move[i * w + j]
            if i > 0 && j > 0 && (mv == 1 || mv == 4) { if mv == 1 { anchor[i - 1] = j - 1 }; i -= 1; j -= 1 }
            else if i > 0 && (mv == 2 || j == 0) { i -= 1 }
            else { j -= 1 }
        }
        let anchors = anchor.enumerated().compactMap { k, a in a.map { (k, $0) } }
        guard anchors.count >= max(4, n / 12) else { return nil }   // too little in common: not the same song / nothing heard
        var t0 = [Double](repeating: 0, count: n), t1 = [Double](repeating: 0, count: n), conf = [Double](repeating: 0.35, count: n)
        for (k, a) in anchors { t0[k] = h[a].start; t1[k] = max(h[a].end, h[a].start + 0.1); conf[k] = 0.75 }
        let perWord = 0.35
        // before the first match and after the last: sing at a normal pace
        let (f, fa) = anchors.first!, (l, la) = anchors.last!
        for k in stride(from: f - 1, through: 0, by: -1) { t1[k] = max(0, t0[k + 1] - 0.02); t0[k] = max(0, t1[k] - perWord) }
        _ = fa; _ = la
        if l + 1 < n { for k in (l + 1)..<n { t0[k] = min(duration, t1[k - 1] + 0.02); t1[k] = min(duration, t0[k] + perWord) } }
        // between matches: spread evenly, unless there's a long gap (an instrumental break) — then keep
        // words with the line they belong to
        for x in 0..<(anchors.count - 1) {
            let (a, _) = anchors[x], (b, _) = anchors[x + 1]
            let gapN = b - a - 1
            guard gapN > 0 else { continue }
            let tA = t1[a], tB = t0[b]
            let step = (tB - tA) / Double(gapN + 1)
            if step <= 0.9 {
                for g in 0..<gapN { let k = a + 1 + g; t0[k] = tA + step * Double(g) + step * 0.5; t1[k] = t0[k] + step * 0.9 }
            } else {
                let lineA = pw[a].0, lineB = pw[b].0
                var tail = tA                       // words still on the line before the gap: right after it
                var k = a + 1
                while k < b && pw[k].0 == lineA { t0[k] = tail + 0.02; t1[k] = t0[k] + perWord; tail = t1[k]; k += 1 }
                var head = tB                       // words on the line after the gap: just before it
                var q = b - 1
                while q >= k && pw[q].0 == lineB { t1[q] = head - 0.02; t0[q] = t1[q] - perWord; head = t0[q]; q -= 1 }
                if q >= k {                          // whole lines in the gap (not heard): spread them over it
                    let s2 = (head - tail) / Double(q - k + 2)
                    for g in k...q { t0[g] = tail + s2 * Double(g - k + 1) - s2 * 0.45; t1[g] = t0[g] + min(s2 * 0.9, 0.6) }
                }
            }
        }
        var out = [[LyricWord]](repeating: [], count: lineWords.count)
        for (k, (li, text)) in pw.enumerated() {
            out[li].append(LyricWord(text: text, start: t0[k], end: max(t1[k], t0[k] + 0.05), confidence: conf[k]))
        }
        return out
    }

    static let themeWords: [(String, [String])] = [
        ("Love & Romance", ["love", "heart", "kiss", "baby", "hold", "touch", "darling", "together", "forever", "lover", "honey"]),
        ("Heartbreak", ["cry", "tear", "alone", "goodbye", "broken", "lonely", "hurt", "pain", "leave", "lost", "sorry", "miss"]),
        ("Night & Party", ["party", "dance", "night", "club", "drink", "tonight", "floor", "dj", "bass", "loud", "move", "jump"]),
        ("Freedom & Escape", ["free", "fly", "run", "wild", "escape", "away", "road", "wings", "high", "sky", "open"]),
        ("Dreams & Fantasy", ["dream", "magic", "fairy", "star", "moon", "wonder", "spell", "glitter", "sparkle", "castle", "angel", "heaven"]),
        ("Sun & Summer", ["sun", "sunset", "summer", "gold", "golden", "warm", "beach", "shine", "sunshine", "light", "fire"]),
        ("Dark & Intense", ["dark", "shadow", "devil", "fear", "death", "blood", "monster", "demon", "scream", "hell", "rage"]),
        ("Power & Confidence", ["queen", "king", "boss", "money", "power", "crown", "strong", "win", "rich", "fame", "bad"]),
    ]

    static let stop: Set<String> = ["the", "a", "an", "and", "or", "but", "i", "you", "me", "my", "your", "we", "it", "is", "be", "am",
                                    "are", "was", "to", "of", "in", "on", "for", "with", "that", "this", "so", "oh", "yeah", "na",
                                    "la", "ooh", "ah", "do", "don't", "just", "all", "get", "got", "can", "now", "know", "like",
                                    "go", "let", "up", "down", "what", "when", "they", "she", "he", "her", "him", "our", "us", "im"]

    static func analyze(_ ly: inout Lyrics) {
        // mood per line and overall
        let tagger = NLTagger(tagSchemes: [.sentimentScore, .lemma, .lexicalClass])
        var sum = 0.0, n = 0.0
        for i in ly.lines.indices {
            let s = ly.lines[i].text
            tagger.string = s
            let (tag, _) = tagger.tag(at: s.startIndex, unit: .paragraph, scheme: .sentimentScore)
            let v = Double(tag?.rawValue ?? "0") ?? 0
            ly.lines[i].sentiment = v
            sum += v; n += 1
        }
        ly.mood = n > 0 ? sum / n : 0
        // what it's about: most-used meaningful words (as their dictionary form)
        let all = ly.lines.map(\.text).joined(separator: "\n")
        tagger.string = all
        let lem = NLTagger(tagSchemes: [.lemma])
        lem.string = all
        var counts: [String: Int] = [:]
        tagger.enumerateTags(in: all.startIndex..<all.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            guard let tag, [.noun, .verb, .adjective].contains(tag) else { return true }
            let lemma = lem.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue ?? String(all[range])
            let w = lemma.lowercased()
            if w.count >= 3 && !stop.contains(w) { counts[w, default: 0] += 1 }
            return true
        }
        ly.keywords = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(8).map(\.key)
        let lowered = all.lowercased()
        let tokens = lowered.split { !$0.isLetter && $0 != "'" }.map(String.init)
        var themeScore: [(String, Int)] = []
        for (name, list) in themeWords {
            let c = tokens.filter { t in list.contains { t == $0 || t.hasPrefix($0) } }.count
            if c > 0 { themeScore.append((name, c)) }
        }
        ly.themes = themeScore.sorted { $0.1 > $1.1 }.prefix(2).filter { $0.1 >= 2 }.map(\.0)
        ly.moodLabel = ly.mood > 0.25 ? "bright / hopeful" : ly.mood < -0.25 ? "dark / heavy" : "mixed / bittersweet"
    }

    /// Colors that fit what the song is about (a suggestion; the show's palette can always be changed).
    static func palette(for themes: [String]) -> String? {
        switch themes.first {
        case "Love & Romance": return "Red Velvet"
        case "Heartbreak": return "Deep Blue"
        case "Night & Party": return "Disco"
        case "Freedom & Escape": return "Aurora"
        case "Dreams & Fantasy": return "Fairy"
        case "Sun & Summer": return "Fire"
        case "Dark & Intense": return "Red Room"
        case "Power & Confidence": return "Gold"
        default: return nil
        }
    }
}
