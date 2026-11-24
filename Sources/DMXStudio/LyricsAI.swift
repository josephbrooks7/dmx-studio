import Foundation
import NaturalLanguage
import Accelerate

// MARK: - Interpretation: emotion, imagery, delivery, repetition (separate from transcription and lighting)

enum LyricEmotion: String, CaseIterable, Codable {
    case celebration = "Celebration", heartbreak = "Heartbreak", anger = "Anger", fear = "Fear", love = "Love",
         confidence = "Confidence", mystery = "Mystery", nostalgia = "Nostalgia", loneliness = "Loneliness",
         hope = "Hope", rebellion = "Rebellion", dream = "Dream"

    /// A few sentences that express it (compared by meaning, not by matching words)
    var examples: [String] {
        switch self {
        case .celebration: return ["we're dancing all night and having the time of our lives", "let's celebrate, put your hands up", "this party is amazing and I feel so good"]
        case .heartbreak: return ["you broke my heart and left me crying", "I miss you and it hurts so much", "tears keep falling since you said goodbye"]
        case .anger: return ["I'm so angry I could scream", "I hate what you did to me", "get out of my face, I'm done with your lies"]
        case .fear: return ["I'm scared and I can't breathe", "something is hiding in the dark and I'm afraid", "my heart is racing, I'm terrified"]
        case .love: return ["I love you and I want to hold you forever", "you are my everything, my darling", "kiss me, I'm falling for you"]
        case .confidence: return ["I'm the queen and nobody can stop me", "I'm strong and I run this town", "watch me shine, I'm unstoppable"]
        case .mystery: return ["secrets hidden in the shadows", "nobody knows what lies behind the door", "strange whispers in the midnight fog"]
        case .nostalgia: return ["I remember the summer when we were young", "those days are gone but I still think about them", "back in the good old days"]
        case .loneliness: return ["I'm all alone and nobody is here", "lost in the darkness by myself", "empty room and silent phone"]
        case .hope: return ["I can finally see the light", "tomorrow will be better, keep holding on", "a new day is rising and I believe"]
        case .rebellion: return ["we won't follow your rules, we're breaking free", "burn it all down, we're not afraid", "rise up and fight back"]
        case .dream: return ["floating through a dream among the stars", "fairy tale magic and glittering skies", "lost in a fantasy world of wonder"]
        }
    }
    var examplesES: [String] {
        switch self {
        case .celebration: return ["bailamos toda la noche y lo pasamos increíble", "vamos a celebrar, manos arriba", "esta fiesta es lo máximo"]
        case .heartbreak: return ["me rompiste el corazón y me dejaste llorando", "te extraño y me duele tanto", "las lágrimas no paran desde que te fuiste"]
        case .anger: return ["estoy tan enojado que quiero gritar", "odio lo que me hiciste", "vete, ya me cansé de tus mentiras"]
        case .fear: return ["tengo miedo y no puedo respirar", "algo se esconde en la oscuridad", "mi corazón se acelera, estoy aterrado"]
        case .love: return ["te amo y quiero abrazarte para siempre", "eres mi todo, mi amor", "bésame, me estoy enamorando"]
        case .confidence: return ["soy la reina y nadie me para", "soy fuerte y mando aquí", "mírame brillar, nadie me detiene"]
        case .mystery: return ["secretos escondidos en las sombras", "nadie sabe lo que hay detrás de la puerta", "susurros extraños en la medianoche"]
        case .nostalgia: return ["recuerdo el verano cuando éramos jóvenes", "esos días se fueron pero aún pienso en ellos", "en los viejos tiempos"]
        case .loneliness: return ["estoy solo y no hay nadie aquí", "perdido en la oscuridad sin nadie", "cuarto vacío y teléfono en silencio"]
        case .hope: return ["por fin puedo ver la luz", "mañana será mejor, sigue adelante", "un nuevo día amanece y yo creo"]
        case .rebellion: return ["no seguiremos tus reglas, nos liberamos", "quemalo todo, no tenemos miedo", "levántate y lucha"]
        case .dream: return ["flotando en un sueño entre las estrellas", "magia de cuento de hadas y cielos brillantes", "perdido en un mundo de fantasía"]
        }
    }
    /// Lighting starting points (from the spec's table — configurable, not rules)
    var color: RGB {
        switch self {
        case .love: return RGB(hex: 0xFF3A6E)
        case .heartbreak, .loneliness: return RGB(hex: 0x1F2FD6)
        case .anger: return RGB(hex: 0xFF0A00)
        case .celebration: return RGB(hex: 0xFF4FD8)
        case .mystery: return RGB(hex: 0x5A10B8)
        case .dream: return RGB(hex: 0xB79CFF)
        case .confidence: return RGB(hex: 0xFFC22E)
        case .fear: return RGB(hex: 0xA8C8FF)
        case .hope: return RGB(hex: 0xFFD27F)
        case .nostalgia: return RGB(hex: 0xFF9D5C)
        case .rebellion: return RGB(hex: 0xFF2A00)
        }
    }
    /// brighter (+) or dimmer (-) than the section look
    var intensity: Double {
        switch self {
        case .heartbreak, .loneliness, .mystery, .fear: return -0.25
        case .celebration, .confidence, .hope: return 0.12
        case .anger, .rebellion: return 0.1
        default: return 0
        }
    }
}

enum LyricImagery: String, CaseIterable, Codable {
    case fire = "Fire", water = "Water", stars = "Stars", night = "Night", sun = "Sun / Light", storm = "Storm",
         ice = "Ice", dream = "Dream", lightning = "Lightning", heart = "Broken Heart"
    var words: [String] {
        switch self {
        case .fire: return ["fire", "burn", "burning", "flame", "flames", "blaze", "ignite"]
        case .water: return ["ocean", "water", "sea", "wave", "waves", "river", "drown", "tide"]
        case .stars: return ["star", "stars", "galaxy", "universe", "cosmos", "constellation"]
        case .night: return ["night", "darkness", "dark", "midnight", "shadow", "shadows"]
        case .sun: return ["sun", "sunrise", "sunshine", "light", "golden", "dawn", "shine", "sunset"]
        case .storm: return ["rain", "storm", "thunder", "hurricane"]
        case .ice: return ["ice", "frozen", "cold", "snow", "freeze"]
        case .dream: return ["dream", "dreaming", "fantasy", "fairy", "magic", "wonderland"]
        case .lightning: return ["lightning", "electric", "electricity", "spark", "sparks", "voltage"]
        case .heart: return ["heartbreak", "heartbroken", "heartache", "broken heart"]
        }
    }
    var wordsES: [String] {
        switch self {
        case .fire: return ["fuego", "arde", "quema", "llama", "llamas", "incendio"]
        case .water: return ["mar", "océano", "agua", "ola", "olas", "río", "marea"]
        case .stars: return ["estrella", "estrellas", "galaxia", "universo", "cosmos"]
        case .night: return ["noche", "oscuridad", "medianoche", "sombra", "sombras"]
        case .sun: return ["sol", "amanecer", "luz", "dorado", "brillar", "atardecer"]
        case .storm: return ["lluvia", "tormenta", "trueno", "huracán"]
        case .ice: return ["hielo", "helado", "frío", "nieve"]
        case .dream: return ["sueño", "soñar", "fantasía", "hadas", "magia"]
        case .lightning: return ["relámpago", "rayo", "eléctrico", "chispa", "chispas"]
        case .heart: return ["corazón roto"]
        }
    }
    var phraseES: String {
        switch self {
        case .fire: return "llamas de fuego ardiendo"
        case .water: return "el agua profunda del océano y las olas"
        case .stars: return "estrellas brillando en la galaxia"
        case .night: return "la oscuridad de la noche"
        case .sun: return "la luz dorada del sol"
        case .storm: return "lluvia y tormenta con truenos"
        case .ice: return "hielo y nieve fría"
        case .dream: return "un sueño mágico de cuento de hadas"
        case .lightning: return "chispas eléctricas de un relámpago"
        case .heart: return "un corazón roto"
        }
    }
    var phrase: String {   // what the imagery means, for checking a line is really about it
        switch self {
        case .fire: return "burning flames of fire"
        case .water: return "deep ocean water and waves"
        case .stars: return "stars shining in the galaxy"
        case .night: return "the dark of night"
        case .sun: return "the bright golden sunlight"
        case .storm: return "rain and a thunder storm"
        case .ice: return "frozen ice and cold snow"
        case .dream: return "a magical fairy tale dream"
        case .lightning: return "electric lightning sparks"
        case .heart: return "a broken heart"
        }
    }
    var color: RGB {
        switch self {
        case .fire: return RGB(hex: 0xFF5A00)
        case .water: return RGB(hex: 0x00C8FF)
        case .stars: return RGB(hex: 0x6A40FF)
        case .night: return RGB(hex: 0x10208A)
        case .sun: return RGB(hex: 0xFFC94A)
        case .storm: return RGB(hex: 0x6F9DFF)
        case .ice: return RGB(hex: 0xD8F2FF)
        case .dream: return RGB(hex: 0xC9A8FF)
        case .lightning: return .white
        case .heart: return RGB(hex: 0x3A2AD6)
        }
    }
}

struct LineInsight: Codable, Hashable {
    var emotions: [String] = []        // up to 2, strongest first
    var emotionScore: Double = 0       // 0…1 how clearly
    var imagery: [String] = []
    var imageryWord: String? = nil     // the word to accent
    var delivery: String = ""          // Soft, Belting, Rapid / Rap, Sustained note, Whisper, Normal
    var repeated: Bool = false
}

enum LyricsInterpreter {
    private static var embeddingEN: NLEmbedding? = NLEmbedding.sentenceEmbedding(for: .english)
    private static var embeddingES: NLEmbedding? = NLEmbedding.sentenceEmbedding(for: .spanish)
    /// Spanish lyrics are read with the Spanish model and Spanish examples
    static var spanish = false
    private static var embedding: NLEmbedding? { spanish ? (embeddingES ?? embeddingEN) : embeddingEN }

    /// how close in meaning (0…1); nil if this Mac has no sentence model
    private static var cache: [String: [Double]] = [:]
    private static func vec(_ s: String) -> [Double]? {
        let k = (spanish ? "es:" : "en:") + s.lowercased()
        if let v = cache[k] { return v }
        guard let v = embedding?.vector(for: s.lowercased()) else { return nil }
        if cache.count > 4000 { cache.removeAll() }
        cache[k] = v
        return v
    }
    static func similarity(_ a: String, _ b: String) -> Double? {
        guard let va = vec(a), let vb = vec(b) else { return nil }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<min(va.count, vb.count) { dot += va[i] * vb[i]; na += va[i] * va[i]; nb += vb[i] * vb[i] }
        return dot / max(1e-9, (na * nb).squareRoot())
    }

    /// Spanish if the lyrics language is set to Spanish, or (auto) the words look Spanish
    static func detectSpanish(_ ly: Lyrics) -> Bool {
        switch WhisperEngine.language {
        case .es: return true
        case .en: return false
        case .auto:
            let r = NLLanguageRecognizer()
            r.processString(ly.lines.map(\.text).joined(separator: " "))
            return r.dominantLanguage == .spanish
        }
    }

    static func normalized(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0 == " " }.split(separator: " ").joined(separator: " ")
    }

    /// "ah ah ah ah", "a-a-a-a-a", "la la la la": the same short sound again and again
    static func isStutter(_ text: String) -> Bool {
        let parts = text.lowercased().split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "," })
            .map { $0.filter { $0.isLetter } }.filter { !$0.isEmpty }
        guard parts.count >= 4 else { return false }
        var run = 1, best = 1
        for k in 1..<parts.count {
            run = (parts[k] == parts[k - 1] && parts[k].count <= 4) ? run + 1 : 1
            best = max(best, run)
        }
        return best >= 4
    }

    /// Emotion (in context of the lines around it), imagery, delivery and repetition for every line.
    static func interpret(_ ly: inout Lyrics, vocalLevel: [Float]? = nil, levelRate: Double = 0) {
        spanish = detectSpanish(ly)
        let n = ly.lines.count
        guard n > 0 else { return }
        // raw emotion scores per line
        var raw: [[Double]] = Array(repeating: Array(repeating: 0, count: LyricEmotion.allCases.count), count: n)
        for (i, line) in ly.lines.enumerated() {
            for (k, em) in LyricEmotion.allCases.enumerated() {
                let sims = (spanish ? em.examplesES : em.examples).compactMap { similarity(line.text, $0) }
                raw[i][k] = sims.max() ?? 0
            }
        }
        // context: each line leans a little toward its neighbours (meaning carries across lines)
        var ctx = raw
        for i in 0..<n {
            for k in raw[i].indices {
                var v = raw[i][k] * 0.6, w = 0.6
                if i > 0 { v += raw[i - 1][k] * 0.2; w += 0.2 }
                if i + 1 < n { v += raw[i + 1][k] * 0.2; w += 0.2 }
                ctx[i][k] = v / w
            }
        }
        // repeated lines (choruses / hooks)
        var counts: [String: Int] = [:]
        for l in ly.lines { counts[normalized(l.text), default: 0] += 1 }
        // loudness of each line on the vocal part (for delivery)
        func level(_ a: Double, _ b: Double) -> Double {
            guard let v = vocalLevel, levelRate > 0, !v.isEmpty else { return 0 }
            let s = max(0, Int(a * levelRate)), e = min(v.count, max(s + 1, Int(b * levelRate)))
            guard e > s else { return 0 }
            var m: Float = 0
            v[s..<e].withUnsafeBufferPointer { vDSP_measqv($0.baseAddress!, 1, &m, vDSP_Length(e - s)) }
            return 10 * log10(Double(m) + 1e-12)
        }
        let levels = ly.lines.map { level($0.start, $0.end) }
        let sortedLv = levels.sorted()
        let medLv = sortedLv[sortedLv.count / 2]
        var insights: [LineInsight] = []
        for (i, line) in ly.lines.enumerated() {
            var ins = LineInsight()
            let order = ctx[i].indices.sorted { ctx[i][$0] > ctx[i][$1] }
            let best = ctx[i][order[0]]
            // only call it if it's clearly one feeling (the best stands out from the average)
            let mean = ctx[i].reduce(0, +) / Double(ctx[i].count)
            ins.emotionScore = max(0, min(1, (best - mean) * 6))
            if ins.emotionScore >= 0.2 {
                ins.emotions = order.prefix(2).filter { ctx[i][$0] >= best - 0.03 }.map { LyricEmotion.allCases[$0].rawValue }
            }
            // imagery: the word is there AND the line is really about it (not "you're on fire tonight")
            let words = Set(normalized(line.text).split(separator: " ").map(String.init))
            let negated = words.contains("not") || words.contains("no") || words.contains("never") || words.contains("nunca")
                || line.text.lowercased().contains("n't")
            for im in LyricImagery.allCases {
                let list = spanish ? im.wordsES : im.words
                guard let hit = list.first(where: { words.contains($0) || ($0.contains(" ") && line.text.lowercased().contains($0)) }) else { continue }
                let about = similarity(line.text, spanish ? im.phraseES : im.phrase) ?? 0.5
                if about >= 0.22 && !negated {
                    ins.imagery.append(im.rawValue)
                    if ins.imageryWord == nil { ins.imageryWord = hit }
                }
            }
            // delivery from the vocal part
            let dur = max(0.1, line.end - line.start)
            let wordCount = line.text.split(separator: " ").count
            let lineWords = ly.words.filter { $0.start >= line.start - 0.01 && $0.end <= line.end + 0.01 }
            let longest = lineWords.map { $0.end - $0.start }.max() ?? 0
            let rel = levels[i] - medLv
            if LyricsInterpreter.isStutter(line.text) { ins.delivery = "Vocal stutter" }
            else if vocalLevel != nil && rel < -12 { ins.delivery = "Whisper" }
            else if vocalLevel != nil && rel < -5 { ins.delivery = "Soft" }
            else if Double(wordCount) / dur > 3.4 { ins.delivery = "Rapid / Rap" }
            else if vocalLevel != nil && rel > 4 { ins.delivery = "Belting" }
            else if longest >= 1.3 { ins.delivery = "Sustained note" }
            else { ins.delivery = "Normal" }
            ins.repeated = (counts[normalized(line.text)] ?? 0) >= 2
            insights.append(ins)
        }
        ly.insights = insights
    }
}

// MARK: - Lighting from lyrics (separate module: uses the interpretation, makes cues)

struct LyricCue: Codable, Hashable, Identifiable {
    var id = UUID()
    var start: Double
    var end: Double
    var kind: String                 // "Emotion", "Imagery", "Delivery"
    var label: String                // e.g. "Hope", "Fire", "Belting"
    var color: RGB?
    var amount: Double               // how strongly it tints the look (0…1)
    var intensity: Double            // brightness change (-1…+1)
    var accent: Bool = false         // a short swell on a word
    var lyric: String
    var reason: String
    var confidence: Double
    var accepted: Bool? = nil        // Assisted mode: nil = not decided, true = use, false = don't
}

enum LyricLightingMode: String, CaseIterable, Codable, Identifiable {
    case automatic = "Automatic", assisted = "Assisted", manual = "Manual"
    var id: String { rawValue }
    var blurb: String {
        switch self {
        case .automatic: return "Lyric cues are added to the show by themselves (sure ones only)."
        case .assisted: return "Lyric cues are suggested; you pick which ones to use."
        case .manual: return "Lyrics and their meaning are shown, but nothing changes the lights by itself."
        }
    }
}

enum LyricLighting {
    struct Weights: Codable, Equatable {
        var emotion = 0.6, imagery = 0.6, delivery = 0.5
        static var current: Weights {
            get { (UserDefaults.standard.data(forKey: "lyricWeights")).flatMap { try? JSONDecoder().decode(Weights.self, from: $0) } ?? Weights() }
            set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "lyricWeights") }
        }
    }

    /// Literal visual images deserve a sustained palette, even when mentioned only once.
    static func visualCues(_ ly: Lyrics) -> [LyricCue] {
        let images: [(String, Set<String>, UInt32)] = [
            ("Sunset", ["sunset","sundown","atardecer","dusk"], 0xFF7838),
            ("Unicorn", ["unicorn","unicorns","unicornio","unicornios"], 0xD68BFF),
            ("Bliss", ["bliss","blissful","euphoria","euphoric","dicha"], 0xFFD9A0),
            ("Heartache", ["heartache","heartbreak","heartbroken","heartaches","desamor","broken heart"], 0x2639C8),
            ("Sunrise", ["sunrise","dawn","amanecer"], 0xFFD078),
            ("Fire", ["fire","flames","flame","fuego"], 0xFF4310),
            ("Ocean", ["ocean","sea","waves","océano"], 0x00A8E8),
            ("Moonlight", ["moon","moonlight","luna"], 0x829DFF),
            ("Stars", ["stars","starlight","galaxy","estrellas"], 0x9470FF),
            ("Ice", ["ice","snow","frozen","hielo"], 0xBBEEFF),
            ("Rose", ["rose","roses","rosas"], 0xFF4080),
            ("Heaven", ["heaven","heavenly","angel","angels","paradise"], 0xD9C9FF),
            ("Glistening", ["glistening","glisten","glitter","sparkling","shimmering"], 0xE6F6FF)
        ]
        var result: [LyricCue] = []
        for line in ly.lines {
            let words = ly.words.filter { $0.start >= line.start - 0.05 && $0.start < line.end + 0.05 }
            for (index, word) in words.enumerated() where word.confidence >= 0.3 {
                let token = LyricsInterpreter.normalized(word.text)
                let next = index + 1 < words.count ? LyricsInterpreter.normalized(words[index + 1].text) : ""
                let cake = token == "birthday cake" || (token == "birthday" && next == "cake")
                let match = images.first(where: { $0.1.contains(token) || $0.1.contains(token + " " + next) })
                guard let image = cake ? ("Birthday Cake", Set<String>(), UInt32(0xFF8BCB)) : match else { continue }
                guard !result.contains(where: { $0.label == image.0 && abs($0.start - word.start) < 1.5 }) else { continue }
                result.append(LyricCue(start: word.start, end: max(word.end + 1.2, min(line.end, word.start + 4)),
                    kind: "Imagery", label: image.0, color: RGB(hex: image.2), amount: 1,
                    intensity: image.0 == "Heartache" ? -0.22 : 0.08, lyric: line.text, reason: "Timed visual palette: " + word.text,
                    confidence: max(0.4, word.confidence)))
            }
        }
        return result
    }

    /// Cues for a song. One per sung line at most for emotion (no color change on every word), short accents
    /// only on clear imagery words, and nothing from low-confidence words.
    static func cues(_ ly: Lyrics, analysis a: SongAnalysis) -> [LyricCue] {
        guard let ins = ly.insights, ins.count == ly.lines.count else { return visualCues(ly) }
        var out: [LyricCue] = []
        var lastEmotion: String?
        for (i, line) in ly.lines.enumerated() {
            let info = ins[i]
            let sure = line.confidence >= 0.45
            if let em = info.emotions.first.flatMap(LyricEmotion.init(rawValue:)), info.emotionScore >= 0.25, sure {
                // merge with the cue before when the feeling continues
                if lastEmotion == em.rawValue, let l = out.lastIndex(where: { $0.kind == "Emotion" }), line.start - out[l].end < 4 {
                    out[l].end = line.end
                } else {
                    out.append(LyricCue(start: line.start, end: line.end, kind: "Emotion", label: em.rawValue, color: em.color,
                                        amount: 0.35 + 0.35 * info.emotionScore, intensity: em.intensity, lyric: line.text,
                                        reason: "the line feels like \(em.rawValue.lowercased())" + (info.repeated ? " (repeated hook)" : ""),
                                        confidence: min(1, info.emotionScore * line.confidence * 1.6)))
                }
                lastEmotion = em.rawValue
            } else { lastEmotion = nil }
            if let im = info.imagery.first.flatMap(LyricImagery.init(rawValue:)), let word = info.imageryWord, sure,
               let w = ly.words.first(where: { $0.start >= line.start - 0.01 && LyricsInterpreter.normalized($0.text) == word }),
               w.confidence >= 0.5 {
                out.append(LyricCue(start: w.start, end: w.start + 1.2, kind: "Imagery", label: im.rawValue, color: im.color,
                                    amount: 0.8, intensity: im == .night ? -0.2 : 0.25, accent: true, lyric: line.text,
                                    reason: "\"\(w.text)\" — \(im.rawValue.lowercased()) imagery", confidence: w.confidence))
            }
            switch info.delivery {
            case "Belting":
                out.append(LyricCue(start: line.start, end: line.end, kind: "Delivery", label: "Belting", color: .white, amount: 0.15,
                                    intensity: 0.15, lyric: line.text, reason: "powerful vocal", confidence: 0.7))
            case "Soft", "Whisper":
                out.append(LyricCue(start: line.start, end: line.end, kind: "Delivery", label: info.delivery, color: nil, amount: 0,
                                    intensity: info.delivery == "Whisper" ? -0.35 : -0.2, lyric: line.text,
                                    reason: "\(info.delivery.lowercased()) vocal", confidence: 0.65))
            case "Vocal stutter":
                // a short white hit on each syllable ("ah ah ah", "a-a-a-a"), no faster than the flash limit allows
                let hz = max(0.5, ShowRenderer.maxFlashHz)
                var last = -9.0
                let syl = ly.words.filter { $0.start >= line.start - 0.01 && $0.start <= line.end + 0.01 }
                if ShowRenderer.maxFlashHz > 0 {
                    for wd in syl where wd.start - last >= 1 / hz {
                        out.append(LyricCue(start: wd.start, end: wd.start + 0.15, kind: "Delivery", label: "Vocal stutter", color: .white,
                                            amount: 0.6, intensity: 0.5, accent: true, lyric: line.text,
                                            reason: "vocal stutter \"\(wd.text)\"", confidence: 0.6))
                        last = wd.start
                    }
                }
            case "Sustained note":
                out.append(LyricCue(start: line.start, end: line.end, kind: "Delivery", label: "Sustained note", color: nil, amount: 0,
                                    intensity: 0.12, lyric: line.text, reason: "long held note: slow build", confidence: 0.6))
            default: break
            }
        }
        return out + visualCues(ly)
    }
}
