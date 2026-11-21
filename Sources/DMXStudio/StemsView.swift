import AppKit
import SwiftUI

/// The separated parts of a song (Vocals, Drums, Bass, Other) as lanes: colored waveform, Solo, Mute and
/// a volume slider per part, plus what Learn found on them (drum hits, sung phrases). Hidden until you
/// open the Stems tab.
struct StemsTab: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    @AppStorage("stemsTabOpen") private var open = false
    @AppStorage("hqStems") private var highQuality = true
    @State private var downloading: Double?
    @State private var installedTick = 0
    @State private var offlineNote = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { open.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.caption.bold())
                    Image(systemName: "square.stack.3d.down.right.fill")
                    Text("Stems").font(.headline)
                    if let a = song.analysis {
                        Text(summary(a)).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                HStack(spacing: 10) {
                    Text("Splitting").foregroundColor(.secondary)
                    Picker("", selection: $highQuality) {
                        Text("Fast").tag(false)
                        Text("High Quality AI").tag(true)
                    }
                    .pickerStyle(.segmented).frame(width: 330)
                    if highQuality && !HQSplitter.isInstalled {
                        if let p = downloading {
                            ProgressView(value: p).frame(width: 120)
                            Text("Getting the AI model…").font(.caption).foregroundColor(.secondary)
                        } else {
                            Button("Download AI Model (~70 MB)") {   // only when it isn't built in
                                downloading = 0
                                HQSplitter.download(progress: { downloading = $0 }) { err in
                                    downloading = nil
                                    if let err, AppModel.isOffline(err) { offlineNote = true }
                                    else if let err { ErrorCenter.shared.report(area: "Stems", message: "Couldn't download the High Quality model: \(err.localizedDescription)", details: "\(err)") }
                                    else { installedTick += 1 }
                                }
                            }
                        }
                    }
                    Spacer()
                    Button {
                        if highQuality && song.analysis != nil { model.upgradeToHQ(song.id) } else { model.learn(song.id, rebuildShows: true, split: true) }
                    } label: { Label("Split Again", systemImage: "arrow.triangle.2.circlepath") }
                        .disabled(model.learning[song.id] != nil || model.hqProgress[song.id] != nil || (highQuality && !HQSplitter.isInstalled))
                        .help("Split this song again with the chosen quality, relearn it and rebuild its shows")
                }
                .id(installedTick)
                if offlineNote {
                    Text("No internet right now (on the lights' Wi-Fi?). Connect to the internet once to download the model, then press Download again.")
                        .font(.caption).foregroundColor(.orange)
                }
                if highQuality {
                    Text("High Quality uses Meta's Demucs AI models on this Mac: much cleaner parts (vocals, BG vocals, guitar, piano). Learn doesn't make stems. Deep Learn (or Split Again here) makes them: one song at a time, at low priority.")
                        .font(.caption).foregroundColor(.secondary)
                    if let p = model.hqProgress[song.id] {
                        HStack {
                            ProgressView(value: p).frame(width: 140)
                            Ticking { model.hqCountdown(song.id) }.font(.caption).monospacedDigit()
                            Button("Stop") { model.stopHQ(song.id) }.controlSize(.small).help("Stop the High Quality split (keeps the quick split)")
                        }
                    }
                    Toggle("Also split guitar + piano (6 parts — about twice as slow)", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "hqSixParts") },
                        set: { UserDefaults.standard.set($0, forKey: "hqSixParts"); model.objectWillChange.send() }))
                        .font(.caption)
                }
                if let a = song.analysis, let folder = a.stemsFolder {
                    StemMixerView(song: song, analysis: a, folder: folder)
                } else if model.learning[song.id] != nil {
                    Ticking { "Splitting into parts… " + model.learnCountdown(song.id) }.foregroundColor(.secondary).monospacedDigit()
                } else {
                    HStack {
                        Text("No stems yet: Learn uses the song as it is. Deep Learn splits it into stems and learns from them.").foregroundColor(.secondary)
                        Button("Deep Learn") { model.deepLearn(song.id) }
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }

    func summary(_ a: SongAnalysis) -> String {
        guard a.stemsFolder != nil else { return "not split yet" }
        let hits = a.hits ?? []
        let k = hits.filter { $0.type == .kick }.count, s = hits.filter { $0.type == .snare }.count
        let h = hits.filter { $0.type == .hat }.count
        return "Vocals · Drums · Bass · Other — \(k) kicks, \(s) snares, \(h) hi-hats, \((a.vocalPhrases ?? []).count) sung phrases"
    }
}

struct StemStyle {
    let name: String, label: String, icon: String, colors: [Color]
    static let all: [StemStyle] = [
        StemStyle(name: "vocals", label: "VOCALS", icon: "mic.fill",
                  colors: [Color(red: 1.0, green: 0.22, blue: 0.0), Color(red: 1.0, green: 0.42, blue: 0.0)]),
        StemStyle(name: "backing", label: "BG VOCALS", icon: "person.3.fill",
                  colors: [Color(red: 0.75, green: 0.25, blue: 1.0), Color(red: 0.95, green: 0.35, blue: 0.85)]),
        StemStyle(name: "drums", label: "DRUMS", icon: "circle.hexagongrid.fill",
                  colors: [Color(red: 1.0, green: 0.04, blue: 0.24), Color(red: 1.0, green: 0.1, blue: 0.3)]),
        StemStyle(name: "bass", label: "BASS", icon: "guitars.fill",
                  colors: [Color(red: 0.82, green: 0.0, blue: 0.43), Color(red: 0.9, green: 0.0, blue: 0.62)]),
        StemStyle(name: "guitar", label: "GUITAR", icon: "guitars",
                  colors: [Color(red: 0.55, green: 1.0, blue: 0.0), Color(red: 0.2, green: 1.0, blue: 0.45)]),
        StemStyle(name: "piano", label: "PIANO", icon: "pianokeys",
                  colors: [Color(red: 1.0, green: 0.82, blue: 0.0), Color(red: 1.0, green: 0.62, blue: 0.0)]),
        StemStyle(name: "other", label: "OTHER", icon: "music.note.list",
                  colors: [Color(red: 0.1, green: 0.24, blue: 1.0), Color(red: 0.05, green: 0.4, blue: 1.0)]),
    ]
}

struct StemMixerView: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    let analysis: SongAnalysis
    let folder: String
    @State private var overview: StemOverview?
    static let cardWidth: CGFloat = 250
    static let laneHeight: CGFloat = 74

    var isThisPlaying: Bool { model.playingSongID == song.id && model.isPlaying }
    /// The parts this song was split into (4 with Fast, 6 with High Quality)
    var styles: [StemStyle] {
        let have = overview.map { Set($0.peaks.keys) } ?? Set(StemSplitter.stems)
        return StemStyle.all.filter { have.contains($0.name) }
    }

    var body: some View {
        VStack(spacing: 8) {
            // transport + time
            HStack(spacing: 18) {
                Button {
                    if model.playingSongID == song.id && model.isPlaying { model.pause() }
                    else if model.playingSongID == song.id { model.togglePlay() }
                    else { model.play(song.id, from: 0) }
                } label: {
                    Image(systemName: isThisPlaying ? "pause.fill" : "play.fill").font(.title2).foregroundColor(.white)
                        .frame(width: 36)
                }
                .buttonStyle(.plain)
                LiveReader(model.live) {
                    let t = model.playingSongID == song.id ? model.currentTime : 0
                    HStack(spacing: 14) {
                        Text(Self.clock(t)).foregroundColor(.white)
                        Text("/").foregroundColor(.gray)
                        Text(Self.clock(analysis.duration)).foregroundColor(.gray)
                    }
                    .font(.system(size: 20, weight: .light, design: .monospaced))
                }
                Spacer()
                Button("Reset Mix") { model.stemMixes[song.id] = nil }
                    .disabled(model.stemMixes[song.id] == nil)
            }
            .padding(.horizontal, 14).frame(height: 44)
            .background(Color(white: 0.07))

            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 8) {
                    ForEach(styles, id: \.name) { st in
                        StemCard(style: st, channel: model.stemChannel(song.id, st.name))
                            .frame(width: Self.cardWidth, height: Self.laneHeight)
                    }
                    LaneLabel(title: "DRUM HITS", subtitle: "kick · snare · hi-hat", icon: "waveform.path.ecg")
                        .frame(width: Self.cardWidth, height: 44)
                    LaneLabel(title: "VOCAL PHRASES", subtitle: "where someone sings", icon: "text.quote")
                        .frame(width: Self.cardWidth, height: 30)
                    LaneLabel(title: "LYRICS", subtitle: song.lyrics == nil ? "not learned yet" : "words heard / pasted", icon: "character.bubble")
                        .frame(width: Self.cardWidth, height: 30)
                }
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 8) {
                            ForEach(styles, id: \.name) { st in
                                StemWave(peaks: overview?.peaks[st.name] ?? [], colors: st.colors,
                                         dim: model.stemGain(song.id, st.name) == 0)
                                    .frame(height: Self.laneHeight)
                            }
                            HitsLane(hits: analysis.hits ?? [], duration: analysis.duration).frame(height: 44)
                            PhraseLane(phrases: analysis.vocalPhrases ?? [], duration: analysis.duration).frame(height: 30)
                            LyricsLane(lines: song.lyrics?.lines ?? [], duration: analysis.duration).frame(height: 30)
                        }
                        LiveReader(model.live) {
                            let t = model.playingSongID == song.id ? model.currentTime : 0
                            Rectangle().fill(Color.cyan).frame(width: 2)
                                .offset(x: CGFloat(t / max(analysis.duration, 0.01)) * w)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        let t = Double(max(0, min(g.location.x / max(w, 1), 1))) * analysis.duration
                        if model.playingSongID == song.id { model.seek(to: t) } else { model.play(song.id, from: t) }
                    })
                }
                .frame(height: Self.laneHeight * CGFloat(styles.count) + 8 * CGFloat(styles.count + 2) + 44 + 30 + 30)
                .padding(.leading, 8)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black))
        .onAppear { overview = StemOverview.load(folder: folder) }
        .onChange(of: folder) { overview = StemOverview.load(folder: $0) }
    }

    static func clock(_ t: Double) -> String {
        let ms = Int((max(0, t) * 1000).rounded())
        return String(format: "%02d:%02d:%03d", ms / 60000, (ms / 1000) % 60, ms % 1000)
    }
}

struct StemCard: View {
    let style: StemStyle
    @Binding var channel: AppModel.StemChannel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: style.icon).font(.system(size: 14, weight: .bold)).foregroundColor(style.colors[0])
                    .frame(width: 30, height: 26).background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.6)))
                Text(style.label).font(.system(size: 14, weight: .heavy)).foregroundColor(.white)
                Spacer()
                HStack(spacing: 2) {
                    toggle("S", on: channel.solo, tint: .yellow) { channel.solo.toggle() }
                        .help("Solo: hear only the soloed parts")
                    toggle("M", on: channel.mute, tint: style.colors[0]) { channel.mute.toggle() }
                        .help("Mute this part")
                }
            }
            GradientSlider(value: $channel.volume, colors: style.colors)
                .frame(height: 18)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.11)))
    }

    func toggle(_ t: String, on: Bool, tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 14, weight: .medium))
                .foregroundColor(on ? .black : .gray)
                .frame(width: 28, height: 24)
                .background(RoundedRectangle(cornerRadius: 4).fill(on ? tint : Color.black.opacity(0.5)))
        }
        .buttonStyle(.plain)
    }
}

struct GradientSlider: View {
    @Binding var value: Double
    let colors: [Color]
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, knob: CGFloat = 18
            let x = CGFloat(value) * (w - knob)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08)).frame(height: 8)
                Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: x + knob / 2, height: 8)
                Circle().fill(Color.white).frame(width: knob, height: knob).offset(x: x)
                    .shadow(color: .black.opacity(0.4), radius: 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                value = Double(max(0, min(1, (g.location.x - knob / 2) / max(w - knob, 1))))
            })
            .onTapGesture(count: 2) { value = 1 }
        }
        .help("Volume (double-click for full)")
    }
}

struct StemWave: View {
    let peaks: [Float]
    let colors: [Color]
    var dim = false
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.05)))
            let mid = size.height / 2
            var line = Path(); line.move(to: CGPoint(x: 0, y: mid)); line.addLine(to: CGPoint(x: size.width, y: mid))
            ctx.stroke(line, with: .color(colors[0].opacity(0.6)), lineWidth: 1)
            guard !peaks.isEmpty else { return }
            let cols = max(1, Int(size.width / 1.5))
            var p = Path()
            for c in 0..<cols {
                let a = c * peaks.count / cols, b = max(a + 1, (c + 1) * peaks.count / cols)
                var v: Float = 0
                for i in a..<min(b, peaks.count) { v = max(v, peaks[i]) }
                let h = CGFloat(v.squareRoot()) * (size.height / 2 - 2)   // sqrt: quiet parts still visible
                guard h > 0.3 else { continue }
                let x = CGFloat(c) * size.width / CGFloat(cols)
                p.addRect(CGRect(x: x, y: mid - h, width: max(1, size.width / CGFloat(cols) - 0.3), height: h * 2))
            }
            ctx.fill(p, with: .linearGradient(Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)))
        }
        .opacity(dim ? 0.25 : 1)
    }
}

struct LaneLabel: View {
    let title: String, subtitle: String, icon: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(.gray).frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11, weight: .heavy)).foregroundColor(.white)
                Text(subtitle).font(.system(size: 10)).foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.11)))
    }
}

struct HitsLane: View {
    let hits: [DrumHit]
    let duration: Double
    static func color(_ t: HitType) -> Color {
        switch t { case .kick: return Color(red: 1, green: 0.1, blue: 0.3); case .snare: return .yellow; case .hat: return .cyan }
    }
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.05)))
            let rowH = size.height / 3
            for (row, type) in [HitType.kick, .snare, .hat].enumerated() {
                var p = Path()
                for h in hits where h.type == type {
                    let x = CGFloat(h.time / max(duration, 0.01)) * size.width
                    let hh = rowH * CGFloat(0.4 + 0.6 * h.confidence)
                    p.addRect(CGRect(x: x, y: CGFloat(row) * rowH + (rowH - hh) / 2, width: 1.2, height: hh))
                }
                ctx.fill(p, with: .color(Self.color(type)))
            }
        }
    }
}

struct PhraseLane: View {
    let phrases: [TimeSpan]
    let duration: Double
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.05)))
            var p = Path()
            for s in phrases {
                let x0 = CGFloat(s.start / max(duration, 0.01)) * size.width
                let x1 = CGFloat(s.end / max(duration, 0.01)) * size.width
                p.addRoundedRect(in: CGRect(x: x0, y: 6, width: max(2, x1 - x0), height: size.height - 12), cornerSize: CGSize(width: 3, height: 3))
            }
            ctx.fill(p, with: .color(Color(red: 1, green: 0.42, blue: 0).opacity(0.8)))
        }
    }
}

/// The words of the song (heard from the separated vocals, or pasted), what it's about, and its mood.
/// Closed until you click it.
struct LyricsTab: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    private var open: Bool { model.lyricsOpen }
    @State private var pasting = false
    @State private var confirmClear = false
    @State private var pasteText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { model.lyricsOpen.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.caption.bold())
                    Image(systemName: "text.quote")
                    Text("Lyrics").font(.headline)
                    if let p = model.lyricsProgress[song.id] {
                        ProgressView(value: p).frame(width: 90)
                        Ticking { (model.lyricsStatus[song.id] ?? "Listening…") + " · " + model.lyricsCountdown(song.id) }
                            .font(.caption).foregroundColor(.secondary).monospacedDigit()
                        Button("Stop") { model.stopLyrics(song.id) }.controlSize(.small)
                    } else if let st = model.lyricsStatus[song.id] {
                        Text(st).font(.caption).foregroundColor(.orange).lineLimit(1)
                    } else if let ly = song.lyrics {
                        Text(ly.lines.isEmpty ? "No lead vocal heard (backing track?) — use Paste / Edit All" : ly.summary).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    } else {
                        Text("not learned yet").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open { content }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
        .sheet(isPresented: $pasting) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Paste or edit the lyrics").font(.headline)
                Text("One line per sung line. Labels like [Chorus] are skipped. They'll be placed on the sung parts of the song.")
                    .font(.caption).foregroundColor(.secondary)
                TextEditor(text: $pasteText).font(.body).frame(minWidth: 460, minHeight: 320)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                HStack {
                    Spacer()
                    Button("Cancel") { pasting = false }
                    Button("Use These Lyrics") { model.pasteLyrics(song.id, text: pasteText); pasting = false }
                        .keyboardShortcut(.defaultAction).disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(18)
        }
    }

    @State private var editing: UUID?
    @State private var editText = ""
    @State private var editStart = ""
    @State private var editEnd = ""

    static func tc(_ t: Double) -> String { String(format: "%d:%04.1f", Int(max(0, t)) / 60, max(0, t).truncatingRemainder(dividingBy: 60)) }
    static func parseTC(_ s: String) -> Double? {
        let p = s.trimmingCharacters(in: .whitespaces).split(separator: ":")
        if p.count == 2, let m = Double(p[0]), let sec = Double(p[1]) { return m * 60 + sec }
        return Double(s.trimmingCharacters(in: .whitespaces))
    }
    var playhead: Double { model.playingSongID == song.id ? model.currentTime : 0 }
    @State private var showCues = true
    @AppStorage("lyricWeightsOpen") private var weightsOpen = false

    @ViewBuilder var content: some View {
        HStack(spacing: 10) {
            Button { model.learnLyrics(song.id) } label: { Label("Transcribe Lyrics from Audio", systemImage: "waveform.and.mic") }
                .disabled(model.lyricsProgress[song.id] != nil)
                .help("Listens to the song and writes down every word with its timing (like auto-captions)")
            if WhisperEngine.isAvailable {
                Picker("", selection: Binding(get: { WhisperEngine.chosen }, set: { WhisperEngine.chosen = $0; model.objectWillChange.send() })) {
                    ForEach(WhisperEngine.ModelSize.allCases) { Text($0.label).tag($0) }
                }
                .frame(width: 170)
                .help("Whisper speech model used for lyrics (downloaded once, runs on this Mac)")
            }
            Picker("", selection: Binding(get: { model.lyricsFromVocalPart }, set: { model.lyricsFromVocalPart = $0 })) {
                Text("Whole song").tag(false)
                Text("Vocal part").tag(true)
            }
            .frame(width: 120)
            .help("Listen to the whole song (fast, no splitting) or to the separated vocal part (cleaner when the split is good)")
            Picker("", selection: Binding(get: { WhisperEngine.language }, set: { WhisperEngine.language = $0; model.objectWillChange.send() })) {
                ForEach(WhisperEngine.Language.allCases) { Text($0.rawValue).tag($0) }
            }
            .frame(width: 120)
            .help("Language of the lyrics")
            Button {
                if let nid = model.addLyricLine(song.id, at: playhead) {
                    editing = nid; editText = "New line"; editStart = Self.tc(playhead); editEnd = Self.tc(playhead + 2.5)
                }
            } label: { Label("Add Line", systemImage: "plus") }
                .disabled(song.analysis == nil)
                .help("Add a lyric line at the playhead (or at the start)")
            Button { pasteText = song.lyrics.map { $0.lines.map(\.text).joined(separator: "\n") } ?? (LyricsLibrary.find(title: song.title)?.text ?? ""); pasting = true } label: {
                Label("Paste / Edit All", systemImage: "doc.on.clipboard")
            }
            Button { model.showLyricsLibrary = true } label: { Label("Lyrics Library", systemImage: "books.vertical") }
                .help("All your saved lyrics")
            Button { model.sendLyricsReport(song.id) } label: { Label("Send Lyrics Report", systemImage: "paperplane") }
                .disabled(song.lyrics == nil)
                .help("Sends what was heard (every line and word with its timing and how sure it was) so it can be checked against the real lyrics. Also copies it to the clipboard")
            Button(role: .destructive) { confirmClear = true } label: { Label("Clear Lyrics", systemImage: "trash") }
                .disabled(song.lyrics == nil)
                .help("Remove these lyrics (and the light cues made from them). Then Listen again or paste the right ones")
                .confirmationDialog("Clear the lyrics of \"\(song.title)\"?", isPresented: $confirmClear) {
                    Button("Clear Lyrics", role: .destructive) { model.clearLyrics(song.id) }
                } message: {
                    Text("The words, their timing and the light cues made from them are removed. Your light show stays.")
                }
            Spacer()
            if let s = model.lyricsStatus[song.id] { Text(s).font(.caption).foregroundColor(.secondary) }
            if WhisperEngine.isAvailable && !WhisperEngine.isInstalled(WhisperEngine.chosen) {
                Button("Use a Model File…") {
                    let p = NSOpenPanel()
                    p.allowsMultipleSelection = false
                    p.message = "Pick a Whisper model file (\(WhisperEngine.chosen.file)) downloaded from huggingface.co/ggerganov/whisper.cpp"
                    if p.runModal() == .OK, let u = p.url { model.installWhisperModel(from: u) }
                }
                .help("No internet here? Download \(WhisperEngine.chosen.file) on another network and pick it")
            }
        }
        if let ly = song.lyrics {
            // lighting from lyrics: mode + weights
            HStack(spacing: 10) {
                Text("Lyric lighting").foregroundColor(.secondary)
                Picker("", selection: Binding(get: { ly.mode ?? .automatic }, set: { model.setLyricMode(song.id, $0) })) {
                    ForEach(LyricLightingMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 290)
                Button { model.refreshLyricLighting(song.id) } label: { Label("Regenerate Cues", systemImage: "arrow.clockwise") }
                Button { weightsOpen.toggle() } label: { Label("Weights", systemImage: "slider.horizontal.3") }
                if let pal = LyricsLearner.palette(for: ly.themes), song.activeShow != nil {
                    Button { model.applyLyricColors(song.id) } label: { Label("Lyric Colors (\(pal))", systemImage: "paintpalette") }
                }
                Spacer()
            }
            Text((ly.mode ?? .automatic).blurb).font(.caption).foregroundColor(.secondary)
            if weightsOpen { LyricWeightsView() }
            VStack(alignment: .leading, spacing: 3) {
                if !ly.themes.isEmpty { Text("About: " + ly.themes.joined(separator: ", ")).font(.callout.bold()) }
                Text("Mood: \(ly.moodLabel)   ·   \(ly.engine ?? ly.source)").font(.caption).foregroundColor(.secondary)
                if !ly.keywords.isEmpty { Text("Key words: " + ly.keywords.joined(separator: ", ")).font(.caption).foregroundColor(.secondary) }
            }
            CoarseReader(model.coarse) {
                let t = model.playingSongID == song.id ? model.coarse.time : -1
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(ly.lines.enumerated()), id: \.element.id) { idx, line in
                            lineRow(ly, idx, line, now: t)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            Text("Click a line to play from there · double-click or ✎ to edit its words and start / end time · ‹ › nudge timing · gray = not sure")
                .font(.caption2).foregroundColor(.secondary)
            if let cues = ly.cues, !cues.isEmpty {
                DisclosureGroup(isExpanded: $showCues) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(cues) { c in cueRow(ly, c) }
                    }
                } label: {
                    Text("Lighting cues from the lyrics (\(cues.count))").font(.callout.bold())
                }
            }
        }
    }

    @ViewBuilder func lineRow(_ ly: Lyrics, _ idx: Int, _ line: LyricLine, now t: Double) -> some View {
        let ins = (ly.insights?.count ?? 0) > idx ? ly.insights![idx] : nil
        let current = t >= line.start && t < line.end
        if editing == line.id {
            // editor: words, start / end time, delete
            VStack(alignment: .leading, spacing: 6) {
                TextField("Words", text: $editText).textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
                    Text("Start").font(.caption).foregroundColor(.secondary)
                    TextField("0:00.0", text: $editStart).textFieldStyle(.roundedBorder).frame(width: 72)
                    Button("Playhead") { editStart = Self.tc(playhead) }.help("Set the start to where the song is now")
                    Text("End").font(.caption).foregroundColor(.secondary)
                    TextField("0:00.0", text: $editEnd).textFieldStyle(.roundedBorder).frame(width: 72)
                    Button("Playhead") { editEnd = Self.tc(playhead) }.help("Set the end to where the song is now")
                    Button { model.play(song.id, from: max(0, (Self.parseTC(editStart) ?? line.start) - 0.5)) } label: { Image(systemName: "play.fill") }
                        .help("Play from this line")
                    Spacer()
                    Button(role: .destructive) { model.deleteLyricLine(song.id, lineID: line.id); editing = nil } label: { Image(systemName: "trash") }
                        .help("Delete this line")
                    Button("Cancel") { editing = nil }
                    Button("Save") {
                        model.editLyricLine(song.id, lineID: line.id, text: editText,
                                            start: Self.parseTC(editStart), end: Self.parseTC(editEnd))
                        editing = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .controlSize(.small)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.pink.opacity(0.08)))
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Self.tc(line.start))–\(Self.tc(line.end))").font(.caption.monospacedDigit()).foregroundColor(.secondary)
                    .frame(width: 92, alignment: .leading)
                // the word being sung lights up, like karaoke captions
                let ws = ly.words.filter { $0.start >= line.start - 0.01 && $0.end <= line.end + 0.01 }
                if current && !ws.isEmpty {
                    ws.reduce(Text("")) { acc, w in
                        let on = t >= w.start && t < w.end + 0.05
                        let done = t >= w.end
                        return acc + Text(w.text + " ").foregroundColor(on ? .pink : done ? .primary : .secondary).bold()
                    }
                } else {
                    Text(line.text).foregroundColor(line.confidence < 0.4 ? .secondary : .primary)
                }
                if line.vocalist == "Background" { chip("background vocal", color: .purple) }
                if let ins {
                    ForEach(ins.emotions, id: \.self) { e in chip(e, color: LyricEmotion(rawValue: e).map { $0.color.color } ?? .gray) }
                    ForEach(ins.imagery, id: \.self) { e in chip(e, color: LyricImagery(rawValue: e).map { $0.color.color } ?? .gray) }
                    if ins.delivery != "Normal" && !ins.delivery.isEmpty { chip(ins.delivery, color: .gray) }
                    if ins.repeated { chip("repeated", color: .gray) }
                }
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    Button("‹") { model.editLyricLine(song.id, lineID: line.id, shift: -0.1) }.help("0.1 s earlier")
                    Button("›") { model.editLyricLine(song.id, lineID: line.id, shift: 0.1) }.help("0.1 s later")
                    Button("✎") { editText = line.text; editStart = Self.tc(line.start); editEnd = Self.tc(line.end); editing = line.id }
                        .help("Edit the words and timing")
                }
                .buttonStyle(.borderless).font(.caption)
            }
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(current ? Color.pink.opacity(0.12) : .clear))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { editText = line.text; editStart = Self.tc(line.start); editEnd = Self.tc(line.end); editing = line.id }
            .onTapGesture { model.play(song.id, from: max(0, line.start - 0.5)) }
        }
    }

    func chip(_ s: String, color: Color) -> some View {
        Text(s).font(.system(size: 9, weight: .semibold)).padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.25))).foregroundColor(.primary)
    }

    @ViewBuilder func cueRow(_ ly: Lyrics, _ c: LyricCue) -> some View {
        let mode = ly.mode ?? .automatic
        let used = mode == .automatic ? (c.accepted != false && c.confidence >= 0.4) : mode == .assisted ? c.accepted == true : false
        HStack(spacing: 8) {
            Text(StemMixerView.clock(c.start).dropLast(4)).font(.caption.monospacedDigit()).foregroundColor(.secondary).frame(width: 44, alignment: .leading)
            Circle().fill(c.color.map { $0.color } ?? .gray).frame(width: 9, height: 9)
            Text("\(c.kind): \(c.label)").font(.caption.bold())
            Text(c.reason).font(.caption).foregroundColor(.secondary).lineLimit(1)
            Text("\(Int(c.confidence * 100))%").font(.caption2.monospacedDigit()).foregroundColor(.secondary)
            Spacer()
            if mode != .manual {
                Toggle("", isOn: Binding(get: { used }, set: { model.setCueAccepted(song.id, cueID: c.id, $0) }))
                    .toggleStyle(.checkbox).help(used ? "Used in the show (uncheck to leave it out)" : "Not used (check to add it to the show)")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.play(song.id, from: max(0, c.start - 1)) }
    }
}

struct LyricWeightsView: View {
    @State private var w = LyricLighting.Weights.current
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("Lyric feeling (color)", \.emotion)
            row("Imagery words (accents)", \.imagery)
            row("Vocal delivery (brightness)", \.delivery)
            Text("Rhythm, energy and song structure always drive the show; these set how much the lyrics steer it.")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }
    func row(_ label: String, _ kp: WritableKeyPath<LyricLighting.Weights, Double>) -> some View {
        HStack {
            Text(label).font(.caption).frame(width: 190, alignment: .leading)
            Slider(value: Binding(get: { w[keyPath: kp] }, set: {
                w[keyPath: kp] = $0; LyricLighting.Weights.current = w; ShowRenderer.lyricWeights = w
            }), in: 0...1)
            Text("\(Int(w[keyPath: kp] * 100))%").font(.caption.monospacedDigit()).frame(width: 40)
        }
    }
}

struct LyricsLane: View {
    let lines: [LyricLine]
    let duration: Double
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.05)))
            var lastX: CGFloat = -1000
            for l in lines {
                let x = CGFloat(l.start / max(duration, 0.01)) * size.width
                let x1 = CGFloat(l.end / max(duration, 0.01)) * size.width
                ctx.fill(Path(CGRect(x: x, y: size.height - 4, width: max(2, x1 - x), height: 3)),
                         with: .color(Color(red: 1, green: 0.42, blue: 0).opacity(l.confidence < 0.4 ? 0.4 : 0.9)))
                guard x - lastX > 60 else { continue }
                ctx.draw(Text(l.text).font(.system(size: 10)).foregroundColor(.white.opacity(l.confidence < 0.4 ? 0.5 : 0.9)),
                         at: CGPoint(x: x + 2, y: size.height / 2 - 2), anchor: .leading)
                lastX = x
            }
        }
        .clipped()
    }
}


/// Text that refreshes every second (for countdowns).
struct Ticking: View {
    let text: () -> String
    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { _ in Text(text()) }
    }
}


// MARK: - New song: how to get its lyrics

struct LyricsPromptSheet: View {
    @EnvironmentObject var model: AppModel
    let songID: UUID
    @State private var text = ""
    @State private var fromLibrary = false

    var body: some View {
        let song = model.song(songID)
        let waiting = model.lyricsPrompt.count
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "text.quote").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lyrics for \"\(song?.title ?? "new song")\"").font(.title3.bold())
                    Text(waiting > 1 ? "New song · \(waiting) waiting" : "New song").font(.caption).foregroundColor(.secondary)
                }
            }
            Text(fromLibrary
                 ? "Found these in your Lyrics Library. Use them (most accurate: timed to the song by listening), edit them, or transcribe from the audio instead."
                 : "Have the lyrics? Paste them here: they're used word for word and timed to the song (most accurate). Or let the app transcribe them by listening (works best on clear vocals).")
                .font(.callout).foregroundColor(fromLibrary ? .green : .secondary).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text)
                .font(.body)
                .frame(minWidth: 520, minHeight: 260)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.15)))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Paste the lyrics (one line per sung line; [Verse] labels and web-page extras are cleaned up)")
                            .foregroundColor(.secondary).padding(8).allowsHitTesting(false)
                    }
                }
            HStack {
                Button("Skip (no lyrics)") { model.answerLyricsPrompt(songID, .skip) }
                    .help("Learn the music only (instrumentals)")
                if waiting > 1 {
                    Button("Transcribe All \(waiting) from Audio") { model.answerAllLyricsPrompts(.transcribe) }
                        .help("Don't ask for the others: transcribe every waiting song")
                }
                Spacer()
                Button {
                    model.answerLyricsPrompt(songID, .transcribe)
                } label: { Label("Transcribe Lyrics from Audio", systemImage: "waveform.and.mic") }
                Button {
                    model.answerLyricsPrompt(songID, .paste(text))
                } label: { Label("Use These Lyrics", systemImage: "checkmark") }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .onAppear {
            if text.isEmpty, let s = song, let e = LyricsLibrary.find(title: s.title) { text = e.text; fromLibrary = true }
        }
    }
}
