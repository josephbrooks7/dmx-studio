import SwiftUI

/// The separated parts of a song (Vocals, Drums, Bass, Other) as lanes: colored waveform, Solo, Mute and
/// a volume slider per part, plus what Learn found on them (drum hits, sung phrases). Hidden until you
/// open the Stems tab.
struct StemsTab: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    @AppStorage("stemsTabOpen") private var open = false
    @AppStorage("hqStems") private var highQuality = false
    @State private var downloading: Double?
    @State private var installedTick = 0

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
                        Text("Fast (4 parts)").tag(false)
                        Text("High Quality AI (6 parts)").tag(true)
                    }
                    .pickerStyle(.segmented).frame(width: 330)
                    if highQuality && !HQSplitter.isInstalled {
                        if let p = downloading {
                            ProgressView(value: p).frame(width: 120)
                            Text("Getting the AI model…").font(.caption).foregroundColor(.secondary)
                        } else {
                            Button("Download AI Model (~70 MB)") {
                                downloading = 0
                                HQSplitter.download(progress: { downloading = $0 }) { err in
                                    downloading = nil
                                    if let err { ErrorCenter.shared.report(area: "Stems", message: "Couldn't download the High Quality model: \(err.localizedDescription)", details: "\(err)") }
                                    else { installedTick += 1 }
                                }
                            }
                        }
                    }
                    Spacer()
                    Button { model.learn(song.id, rebuildShows: true) } label: { Label("Split Again", systemImage: "arrow.triangle.2.circlepath") }
                        .disabled(model.learning[song.id] != nil || (highQuality && !HQSplitter.isInstalled))
                        .help("Split this song again with the chosen quality, relearn it and rebuild its shows")
                }
                .id(installedTick)
                if highQuality {
                    Text("High Quality uses Meta's Demucs AI model on this Mac: much cleaner parts (and guitar + piano), a few minutes per song.")
                        .font(.caption).foregroundColor(.secondary)
                }
                if let a = song.analysis, let folder = a.stemsFolder {
                    StemMixerView(song: song, analysis: a, folder: folder)
                } else if model.learning[song.id] != nil {
                    Text("Splitting into vocals, drums, bass and other…").foregroundColor(.secondary)
                } else {
                    HStack {
                        Text("This song hasn't been split into stems yet.").foregroundColor(.secondary)
                        Button("Split & Learn") { model.learn(song.id, rebuildShows: true) }
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
    @AppStorage("lyricsTabOpen") private var open = false
    @State private var pasting = false
    @State private var pasteText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { open.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.caption.bold())
                    Image(systemName: "text.quote")
                    Text("Lyrics").font(.headline)
                    if let p = model.lyricsProgress[song.id] {
                        ProgressView(value: p).frame(width: 90)
                        Text("Listening to the vocals…").font(.caption).foregroundColor(.secondary)
                    } else if let ly = song.lyrics {
                        Text(ly.lines.isEmpty ? "no words understood" : ly.summary).font(.caption).foregroundColor(.secondary).lineLimit(1)
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
                Text("Paste the official lyrics").font(.headline)
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

    @ViewBuilder var content: some View {
        HStack {
            Button { model.learnLyrics(song.id) } label: { Label("Listen for Lyrics", systemImage: "waveform.and.mic") }
                .disabled(model.lyricsProgress[song.id] != nil || song.analysis?.stemsFolder == nil)
                .help("Listens to the separated vocals and writes down the words with their timing")
            Button { pasteText = song.lyrics?.source == "Pasted" ? song.lyrics!.lines.map(\.text).joined(separator: "\n") : ""; pasting = true } label: {
                Label("Paste Lyrics", systemImage: "doc.on.clipboard")
            }
            if let ly = song.lyrics, let pal = LyricsLearner.palette(for: ly.themes), song.activeShow != nil {
                Button { model.applyLyricColors(song.id) } label: { Label("Use Lyric Colors (\(pal))", systemImage: "paintpalette") }
                    .help("Colors the show to fit what the song is about (drops keep their colors)")
            }
            Spacer()
        }
        if let ly = song.lyrics {
            VStack(alignment: .leading, spacing: 4) {
                if !ly.themes.isEmpty { Text("About: " + ly.themes.joined(separator: ", ")).font(.callout.bold()) }
                Text("Mood: \(ly.moodLabel)   ·   \(ly.source)").font(.caption).foregroundColor(.secondary)
                if !ly.keywords.isEmpty { Text("Key words: " + ly.keywords.joined(separator: ", ")).font(.caption).foregroundColor(.secondary) }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(ly.lines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(StemMixerView.clock(line.start).dropLast(4)).font(.caption.monospacedDigit()).foregroundColor(.secondary)
                                .frame(width: 44, alignment: .leading)
                            Text(line.text)
                                .foregroundColor(line.confidence < 0.4 ? .secondary : .primary)
                                .help(line.confidence < 0.4 ? "Not sure about this line (or its timing)" : "")
                            Circle().fill(line.sentiment > 0.25 ? Color.yellow : line.sentiment < -0.25 ? Color.blue : Color.gray.opacity(0.5))
                                .frame(width: 6, height: 6).help(String(format: "line mood %.2f", line.sentiment))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { model.play(song.id, from: max(0, line.start - 0.5)) }
                    }
                }
            }
            .frame(maxHeight: 260)
            Text("Gray lines: not sure of the words or timing. Click a line to play from there.").font(.caption2).foregroundColor(.secondary)
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
