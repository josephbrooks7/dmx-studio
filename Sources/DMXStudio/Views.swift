import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Bindings by id (safe when items are deleted)

extension AppModel {
    func songBinding(_ id: UUID) -> Binding<Song> {
        Binding(get: { self.songs.first { $0.id == id } ?? Song(title: "", path: "") },
                set: { new in if let i = self.index(of: id) { self.songs[i] = new } })
    }

    func lineupBinding(_ id: UUID) -> Binding<Lineup> {
        Binding(get: { self.lineups.first { $0.id == id } ?? Lineup(name: "") },
                set: { new in if let i = self.lineupIndex(id) { self.lineups[i] = new } })
    }

    func fixtureBinding(_ id: UUID) -> Binding<Fixture> {
        Binding(get: { self.fixtures.first { $0.id == id } ?? Fixture(name: "", address: 1, profileName: "", layout: "") },
                set: { new in if let i = self.fixtures.firstIndex(where: { $0.id == id }) { self.fixtures[i] = new } })
    }
}

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08)))
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.largeTitle.bold())
            Text(subtitle).foregroundColor(.secondary)
        }
    }
}

// MARK: - Song: Learn, create shows, edit sections

struct SongView: View {
    @EnvironmentObject var model: AppModel
    let songID: UUID
    @State private var renaming: UUID?
    @State private var renameText = ""

    var body: some View {
        let binding = model.songBinding(songID)
        let song = binding.wrappedValue
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(song)
                if let a = song.analysis {
                    showsBar(binding, a)
                    if let si = song.activeShowIndex {
                        TimelineView(song: song, show: song.shows[si], analysis: a)
                            .frame(height: 150)
                        StagePreview()
                        sectionEditor(binding, si)
                    }
                } else {
                    learnPrompt(song)
                }
            }
            .padding(24)
        }
    }

    // Header with Learn + genre
    @ViewBuilder func header(_ song: Song) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(song.title).font(.largeTitle.bold()).lineLimit(1)
                TextField("Artist", text: Binding(get: { song.artist ?? "" },
                                                  set: { model.songBinding(song.id).wrappedValue.artist = $0 }))
                    .textFieldStyle(.plain).font(.title3).foregroundColor(.secondary)
                if let a = song.analysis {
                    HStack(spacing: 14) {
                        Label("\(Int(a.bpm.rounded())) BPM", systemImage: "metronome")
                        Label(formatTime(a.duration), systemImage: "clock")
                        Label("\(a.detectedSections.count) sections", systemImage: "rectangle.split.3x1")
                        Label("\(a.kicks.count) kicks", systemImage: "circle.fill")
                    }
                    .font(.callout).foregroundColor(.secondary)
                    HStack(spacing: 14) {
                        Label("Music starts \(formatTime(a.musicStart))" + (a.musicStart >= 0.3 ? String(format: " (%.1f s lead-in)", a.musicStart) : ""),
                              systemImage: "arrow.right.to.line")
                        Label("ends \(formatTime(a.musicEnd))" + (a.duration - a.musicEnd >= 0.3 ? String(format: " (%.1f s silent tail)", a.duration - a.musicEnd) : ""),
                              systemImage: "arrow.left.to.line")
                    }
                    .font(.callout).foregroundColor(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                HStack {
                    if let p = model.learning[song.id] {
                        ProgressView(value: p).frame(width: 120)
                        Text("Learning…").foregroundColor(.secondary)
                    } else {
                        Button {
                            model.learn(song.id)
                        } label: {
                            Label(song.isLearned ? "Learn Again" : "Learn", systemImage: "waveform.badge.magnifyingglass")
                        }
                        .controlSize(.large)
                    }
                    Button {
                        if model.playingSongID == song.id && model.isPlaying { model.pause() }
                        else if model.playingSongID == song.id { model.togglePlay() }
                        else { model.play(song.id, from: 0) }
                    } label: {
                        Label(model.playingSongID == song.id && model.isPlaying ? "Pause" : "Play",
                              systemImage: model.playingSongID == song.id && model.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .controlSize(.large)
                }
                HStack {
                    Text("Genre:").foregroundColor(.secondary)
                    Picker("", selection: model.songBinding(song.id).genre) {
                        if let s = song.analysis?.suggestedStyle {
                            Text("Auto (sounds like \(s.rawValue))").tag(ShowStyle?.none)
                        } else {
                            Text("Auto").tag(ShowStyle?.none)
                        }
                        Divider()
                        ForEach(ShowStyle.allCases) { s in Text(s.rawValue).tag(ShowStyle?.some(s)) }
                    }
                    .labelsHidden()
                    .frame(width: 260)
                }
            }
        }
    }

    @ViewBuilder func learnPrompt(_ song: Song) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Press Learn to let DMX Studio listen to this song.").font(.headline)
                Text("It finds the tempo, every beat, kick, snare and hi-hat, the quiet and loud parts, and where the song changes (intro, verse, build, chorus, drop). Then it builds a light show for you automatically. It takes a few seconds.")
                    .foregroundColor(.secondary)
            }
        }
    }

    // Shows for this song
    @ViewBuilder func showsBar(_ binding: Binding<Song>, _ a: SongAnalysis) -> some View {
        let song = binding.wrappedValue
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Light Shows").font(.headline)
                    Text("saved automatically").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Menu {
                        Button("New show in \(song.effectiveGenre.rawValue) (this song's genre)") {
                            model.createShow(for: song.id)
                        }
                        Divider()
                        ForEach(ShowStyle.allCases) { s in
                            Button("New \(s.rawValue) show") { model.createShow(for: song.id, style: s) }
                        }
                    } label: {
                        Label("Create Show", systemImage: "wand.and.stars")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Menu {
                        ForEach(model.lineups) { l in
                            Button(l.name) { model.addToLineup(l.id, songID: song.id, showID: song.activeShow?.id) }
                        }
                        Divider()
                        Button("New Set List…") {
                            let id = model.newLineup()
                            model.addToLineup(id, songID: song.id, showID: song.activeShow?.id)
                        }
                    } label: {
                        Label("Add to Set List", systemImage: "text.badge.plus")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(song.shows.isEmpty)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(song.shows) { show in
                            let active = show.id == song.activeShow?.id
                            Button {
                                binding.wrappedValue.activeShowID = show.id
                                if model.playingSongID == song.id { model.playingShowID = show.id }
                            } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(Palette.named(show.sections.first?.palette ?? "").color(0).color).frame(width: 10, height: 10)
                                    Text(show.name)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Capsule().fill(active ? Color.pink.opacity(0.35) : Color.white.opacity(0.07)))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Rename…") { renaming = show.id; renameText = show.name }
                                Button("Duplicate") { model.duplicateShow(songID: song.id, showID: show.id) }
                                Button("Delete", role: .destructive) { model.deleteShow(songID: song.id, showID: show.id) }
                            }
                        }
                    }
                }
                if let rid = renaming {
                    HStack {
                        TextField("Show name", text: $renameText).frame(width: 260)
                        Button("Save") {
                            if let i = binding.wrappedValue.shows.firstIndex(where: { $0.id == rid }) {
                                binding.wrappedValue.shows[i].name = renameText
                            }
                            renaming = nil
                        }
                        Button("Cancel") { renaming = nil }
                    }
                }
                if let si = song.activeShowIndex, !model.fixtures.isEmpty {
                    HStack(spacing: 8) {
                        Text("Lights in this show").foregroundColor(.secondary)
                        ForEach(model.fixtures) { fx in
                            let picked = song.shows[si].includes(fx)
                            let on = picked && fx.isOn
                            if !fx.isOn {
                                Button { model.setLightOn(fx.id, true) } label: {
                                    Label("\(fx.name) · off", systemImage: "power")
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(Capsule().fill(Color.white.opacity(0.04)))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("This light is switched off, so the show plays on the other lights. Click to turn it back on.")
                            } else {
                            Button {
                                var ids = song.shows[si].fixtureIDs ?? model.fixtures.map(\.id)
                                if picked { ids.removeAll { $0 == fx.id } } else { ids.append(fx.id) }
                                binding.wrappedValue.shows[si].fixtureIDs = ids
                            } label: {
                                Label(fx.name, systemImage: on ? "checkmark.circle.fill" : "circle")
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().fill(on ? Color.pink.opacity(0.3) : Color.white.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                            .help(fx.effectiveBehavior == .stationary ? "Stationary lights hold their own settings" : "Tap to include or leave out")
                            }
                        }
                    }
                }
                HStack {
                    Text("Sync nudge").foregroundColor(.secondary)
                    Slider(value: binding.syncOffsetMs, in: -300...300, step: 10).frame(width: 220)
                    Text("\(Int(song.syncOffsetMs)) ms").monospacedDigit().frame(width: 60, alignment: .leading)
                    Text("Only if this song's lights feel early or late.").font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    // Per-section editor
    @ViewBuilder func sectionEditor(_ binding: Binding<Song>, _ si: Int) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Sections").font(.headline)
                    Text("Tweak any part. Click a time to jump there.").font(.caption).foregroundColor(.secondary)
                }
                ForEach(binding.shows[si].sections) { $sec in
                    SectionRow(section: $sec, songID: binding.wrappedValue.id)
                    Divider()
                }
            }
        }
    }
}

struct SectionRow: View {
    @EnvironmentObject var model: AppModel
    @Binding var section: ShowSection
    let songID: UUID

    var levelColor: Color {
        switch section.level {
        case .low: return .blue
        case .medium: return .yellow
        case .high: return .orange
        case .drop: return .red
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if model.playingSongID == songID { model.seek(to: section.start) }
                else { model.play(songID, from: section.start) }
            } label: {
                Text(formatTime(section.start)).monospacedDigit().frame(width: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            TextField("", text: $section.name).frame(width: 110)
            Text(section.level.rawValue).font(.caption.bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(levelColor.opacity(0.3)))
                .frame(width: 64)

            Picker("", selection: $section.effect) {
                ForEach(LightEffect.allCases) { Text($0.rawValue).tag($0) }
            }.labelsHidden().frame(width: 140)

            Picker("", selection: $section.palette) {
                ForEach(Palette.all) { p in
                    Text(p.id).tag(p.id)
                }
            }.labelsHidden().frame(width: 120)
            HStack(spacing: 2) {
                ForEach(0..<min(4, Palette.named(section.palette).colors.count), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2).fill(Palette.named(section.palette).color(i).color).frame(width: 8, height: 16)
                }
            }

            Picker("", selection: $section.movement) {
                ForEach(MoveEffect.allCases) { Text($0.rawValue).tag($0) }
            }.labelsHidden().frame(width: 96)

            Picker("", selection: $section.rate) {
                Text("½ speed").tag(0.5)
                Text("Normal").tag(1.0)
                Text("2× speed").tag(2.0)
            }.labelsHidden().frame(width: 90)

            Slider(value: $section.intensity, in: 0.1...1).frame(width: 80)
            Toggle("Hit", isOn: $section.accentStrobe).help("Strobe hit on the first bar")
            Menu {
                Button("Split in two") { model.splitSection(songID: songID, sectionID: section.id) }
                Button("Merge with next") { model.mergeWithNext(songID: songID, sectionID: section.id) }
            } label: { Image(systemName: "scissors") }
            .menuStyle(.borderlessButton).fixedSize()
        }
        .font(.callout)
    }
}

// MARK: - Timeline

struct TimelineView: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    let show: LightShow
    let analysis: SongAnalysis

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let dur = max(analysis.duration, 1)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    // Section bands
                    for s in show.sections {
                        let x0 = CGFloat(s.start / dur) * size.width
                        let x1 = CGFloat(s.end / dur) * size.width
                        let rect = CGRect(x: x0, y: 0, width: max(1, x1 - x0 - 1), height: size.height)
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 4),
                                 with: .color(Palette.named(s.palette).color(0).color.opacity(0.28)))
                        ctx.draw(Text(s.name).font(.caption.bold()).foregroundColor(.white),
                                 at: CGPoint(x: x0 + 6, y: 10), anchor: .leading)
                        ctx.draw(Text(s.effect.rawValue).font(.caption2).foregroundColor(.white.opacity(0.7)),
                                 at: CGPoint(x: x0 + 6, y: 24), anchor: .leading)
                    }
                    // Silences
                    for s in analysis.silences ?? [] {
                        let x0 = CGFloat(s.start / dur) * size.width
                        let x1 = CGFloat(s.end / dur) * size.width
                        ctx.fill(Path(CGRect(x: x0, y: size.height - 6, width: max(1, x1 - x0), height: 6)),
                                 with: .color(.gray.opacity(0.6)))
                    }
                    // Bar lines
                    var bi = analysis.downbeatOffset
                    while bi < analysis.beats.count {
                        let x = CGFloat(analysis.beats[bi] / dur) * size.width
                        ctx.fill(Path(CGRect(x: x, y: size.height - 18, width: 1, height: 10)), with: .color(.white.opacity(0.25)))
                        bi += 4
                    }
                    // Energy curve
                    if !analysis.energy.isEmpty {
                        var path = Path()
                        let n = analysis.energy.count
                        let step = max(1, n / Int(size.width))
                        path.move(to: CGPoint(x: 0, y: size.height))
                        var i = 0
                        while i < n {
                            let x = CGFloat(i) / CGFloat(n) * size.width
                            let y = size.height - CGFloat(analysis.energy[i]) * (size.height - 40) - 4
                            path.addLine(to: CGPoint(x: x, y: y))
                            i += step
                        }
                        path.addLine(to: CGPoint(x: size.width, y: size.height))
                        path.closeSubpath()
                        ctx.fill(path, with: .color(.white.opacity(0.16)))
                    }
                    // Music start / end markers
                    for (t, label) in [(analysis.musicStart, "▶ music"), (analysis.musicEnd, "end ◀")]
                    where t > 0.25 && t < dur - 0.25 {
                        let x = CGFloat(t / dur) * size.width
                        ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(.green.opacity(0.8)))
                        ctx.draw(Text(label).font(.caption2.bold()).foregroundColor(.green),
                                 at: CGPoint(x: x, y: size.height - 26), anchor: label.hasPrefix("▶") ? .leading : .trailing)
                    }
                    // Kicks
                    for k in analysis.kicks {
                        let x = CGFloat(k / dur) * size.width
                        ctx.fill(Path(CGRect(x: x, y: size.height - 4, width: 1, height: 4)), with: .color(.pink.opacity(0.8)))
                    }
                }
                if model.playingSongID == song.id {
                    LiveReader(model.live) {
                    Rectangle().fill(Color.white).frame(width: 2, height: h)
                        .offset(x: CGFloat(model.currentTime / dur) * w)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                let t = Double(v.location.x / w) * dur
                if model.playingSongID == song.id { model.seek(to: t) } else { model.play(song.id, from: t) }
            })
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.4)))
        }
    }
}

// MARK: - Stage preview (what your lights are doing right now)

struct StagePreview: View {
    @EnvironmentObject var model: AppModel

    var body: some View { LiveReader(model.live) { inner } }

    private var inner: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Live Preview").font(.headline)
                if model.fixtures.isEmpty {
                    Text("No lights added yet — go to My Lights.").foregroundColor(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 24) {
                            ForEach(Array(model.fixtures.enumerated()), id: \.element.id) { idx, fx in
                                let rf = idx < model.preview.count ? model.preview[idx] : nil
                                VStack(spacing: 6) {
                                    HStack(spacing: 4) {
                                        ForEach(0..<fx.headCount, id: \.self) { h in
                                            let st = rf.flatMap { h < $0.heads.count ? $0.heads[h] : nil } ?? .off
                                            let lit = st.intensity * (model.blackout ? 0 : model.master)
                                            Circle()
                                                .fill(st.color.color.opacity(max(0.05, lit)))
                                                .frame(width: 20, height: 20)
                                                .shadow(color: st.color.color.opacity(lit), radius: 8 * lit)
                                                .overlay(Circle().stroke(Color.white.opacity(0.15)))
                                        }
                                    }
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.black))
                                    .rotation3DEffect(.degrees(((rf?.tilt ?? 0.5) - 0.5) * 120), axis: (x: 1, y: 0, z: 0))
                                    Text(fx.name).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }
}

// MARK: - Lineup

struct LineupView: View {
    @EnvironmentObject var model: AppModel
    let lineupID: UUID
    @State private var dropTargeted = false
    @State private var importingHere = false

    var body: some View {
        HStack(spacing: 0) {
            main
            Divider()
            SetListLibraryPanel(lineupID: lineupID)
        }
    }

    @ViewBuilder private var main: some View {
        let binding = model.lineupBinding(lineupID)
        let lineup = binding.wrappedValue
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                TextField("Set list name", text: binding.name)
                    .font(.largeTitle.bold())
                    .textFieldStyle(.plain)
                Spacer()
                Button {
                    if model.playingLineupID == lineupID && model.isPlaying { model.pause() }
                    else if model.playingLineupID == lineupID { model.togglePlay() }
                    else { model.playLineup(lineupID, from: 0) }
                } label: {
                    Label(model.playingLineupID == lineupID && model.isPlaying ? "Pause" : "Play Set",
                          systemImage: model.playingLineupID == lineupID && model.isPlaying ? "pause.fill" : "play.fill")
                        .frame(minWidth: 120)
                }
                .controlSize(.large)
                .disabled(lineup.entries.isEmpty)
            }
            HStack {
                Button { importingHere = true } label: { Label("Add Files…", systemImage: "plus") }
                    .help("Import new WAV / MP3 files. Songs already in your library: use the Song Library on the right.")
                if let a = model.mainArtist(of: lineup.entries.map(\.songID)), lineup.name != a {
                    Button("Name it \"\(a)\"") { binding.wrappedValue.name = model.uniqueSetListName(a) }
                }
                Spacer()
                Text("Gap between songs").foregroundColor(.secondary)
                Stepper("\(Int(lineup.gapSeconds)) s", value: binding.gapSeconds, in: 0...30, step: 1)
                Toggle("Skip dead air", isOn: Binding(get: { lineup.skipDeadAir ?? true },
                                                      set: { binding.wrappedValue.skipDeadAir = $0 }))
                    .help("Start each song where its music starts and move on as soon as the music ends")
            }

            if lineup.entries.isEmpty {
                Card {
                    VStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 40)).foregroundColor(.pink)
                        Text("Add songs from your library on the right").font(.title3.bold())
                        Text("Click + next to a song (or drag it here). You can also drag new WAV or MP3 files or a folder here: they're named from their tags, learned, and given a light show. A new set list is named after the artist.")
                            .multilineTextAlignment(.center).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(30)
                }
                Spacer()
            } else {
                List {
                    ForEach(Array(lineup.entries.enumerated()), id: \.element.id) { idx, entry in
                        LineupRow(lineupID: lineupID, index: idx, entry: entry)
                    }
                    .onMove { from, to in binding.wrappedValue.entries.move(fromOffsets: from, toOffset: to) }
                    .onDelete { set in binding.wrappedValue.entries.remove(atOffsets: set) }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                Text("Drag songs up or down (or use ▲▼) to reorder. Each song plays with the light show linked to it.").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(24)
        .onDrop(of: [UTType.fileURL, UTType.plainText], isTargeted: $dropTargeted) { providers in
            handleSongDrop(providers, model: model, lineupID: lineupID)
            return true
        }
        .overlay(dropTargeted ? RoundedRectangle(cornerRadius: 12).stroke(Color.pink, lineWidth: 3).padding(6) : nil)
        .fileImporter(isPresented: $importingHere, allowedContentTypes: [.audio, .mp3, .wav, .folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.importSongs(urls, into: lineupID) }
        }
    }
}

struct LineupRow: View {
    @EnvironmentObject var model: AppModel
    let lineupID: UUID
    let index: Int
    let entry: LineupEntry

    var body: some View {
        if entry.isBlock { BlockRow(lineupID: lineupID, index: index, entry: entry) } else { songRow }
    }

    @ViewBuilder private var songRow: some View {
        let song = model.song(entry.songID)
        let isNow = model.playingLineupID == lineupID && model.playingEntryIndex == index
        HStack(spacing: 12) {
            Text("\(index + 1)").monospacedDigit().foregroundColor(.secondary).frame(width: 24)
            Image(systemName: isNow ? (model.inGap ? "hourglass" : "speaker.wave.2.fill") : "music.note")
                .foregroundColor(isNow ? .pink : .secondary)
            VStack(alignment: .leading) {
                Text(song?.title ?? "Missing song").font(.headline)
                if let a = song?.artist, !a.isEmpty { Text(a).font(.caption).foregroundColor(.secondary) }
                if let a = song?.analysis {
                    Text("\(Int(a.bpm.rounded())) BPM · \(formatTime(a.duration))").font(.caption).foregroundColor(.secondary)
                } else {
                    Text("Not learned yet: lights will use the idle look").font(.caption).foregroundColor(.orange)
                }
            }
            Spacer()
            if let song, !song.shows.isEmpty {
                Image(systemName: "link").foregroundColor(.pink).help("This song is linked to the light show picked here")
                Picker("Light show", selection: Binding(
                    get: { entry.showID ?? song.activeShow?.id },
                    set: { new in
                        if let li = model.lineupIndex(lineupID), li < model.lineups.count, index < model.lineups[li].entries.count {
                            model.lineups[li].entries[index].showID = new
                        }
                    })) {
                    ForEach(song.shows) { s in Text(s.name).tag(UUID?.some(s.id)) }
                }
                .frame(width: 220)
            }
            VStack(spacing: 2) {
                Button { model.moveEntry(lineupID: lineupID, from: index, by: -1) } label: { Image(systemName: "chevron.up") }
                    .disabled(index == 0)
                Button { model.moveEntry(lineupID: lineupID, from: index, by: 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(index >= (model.lineups.first { $0.id == lineupID }?.entries.count ?? 1) - 1)
            }
            .buttonStyle(.borderless)
            .help("Move up / down (or drag the row)")
            Button { model.playLineup(lineupID, from: index) } label: { Image(systemName: "play.circle") }
                .buttonStyle(.borderless)
                .help("Start the set from here")
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Move Up") { model.moveEntry(lineupID: lineupID, from: index, by: -1) }
            Button("Move Down") { model.moveEntry(lineupID: lineupID, from: index, by: 1) }
            Button("Move to Top") { model.moveEntry(lineupID: lineupID, from: index, by: -1000) }
            Button("Move to Bottom") { model.moveEntry(lineupID: lineupID, from: index, by: 1000) }
            Divider()
            Button("Insert Silence After") { model.addBlock(.silence(), to: lineupID, after: index) }
            Menu("Insert Transition After") {
                ForEach(TransitionStyle.allCases) { t in Button(t.rawValue) { model.addBlock(.transition(t), to: lineupID, after: index) } }
            }
            Divider()
            Button("Remove from Set", role: .destructive) {
                if let li = model.lineupIndex(lineupID), index < model.lineups[li].entries.count {
                    model.lineups[li].entries.remove(at: index)
                }
            }
        }
    }
}

// MARK: - Lights (fixtures)

struct LightsView: View {
    @EnvironmentObject var model: AppModel
    @State private var showAdvanced: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    PageHeader(title: "My Lights", subtitle: "Pick your light model. Addresses are filled in for you.")
                    Spacer()
                    Menu {
                        ForEach(FixtureProfile.all) { p in
                            Button(p.name) { model.addFixture(profile: p) }
                        }
                    } label: { Label("Add Light", systemImage: "plus") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .controlSize(.large)
                }
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How your lights work together").font(.headline)
                        Picker("", selection: $model.rigMode) {
                            ForEach(RigMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text(model.rigMode.explanation).font(.callout).foregroundColor(.secondary)
                        Text("Lights are treated left to right in the order listed below. Daisy-chained bars: give each its own address (shown on each card) so the app can control them separately; if both are set to the same address they will always do exactly the same thing.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                ForEach(model.fixtures) { fx in
                    FixtureCard(fixtureID: fx.id, showAdvanced: $showAdvanced)
                }
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Testing").font(.headline)
                        HStack {
                            ForEach([TestMode.white, .rainbow]) { m in
                                Button(m.rawValue) { model.stop(); model.testMode = m }
                            }
                            Button("Test Off") { model.testMode = .off }
                        }
                        Text("Use these to check that every light responds. Starting a song turns testing off.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .padding(24)
        }
    }
}

struct FixtureCard: View {
    @EnvironmentObject var model: AppModel
    let fixtureID: UUID
    @Binding var showAdvanced: UUID?

    var body: some View {
        let b = model.fixtureBinding(fixtureID)
        let fx = b.wrappedValue
        let conflicts = model.addressConflicts(for: fx)
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "light.beacon.max").font(.title2).foregroundColor(.pink)
                    TextField("Name", text: b.name).font(.title3.bold()).textFieldStyle(.plain).frame(width: 200)
                    Spacer()
                    Button {
                        model.stop()
                        model.identifyFixtureID = fx.id
                        model.testMode = model.testMode == .identify ? .off : .identify
                    } label: { Label("Identify", systemImage: "flashlight.on.fill") }
                    .help("Flashes just this light so you can find it")
                    Button(role: .destructive) {
                        model.fixtures.removeAll { $0.id == fx.id }
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                }
                HStack(spacing: 16) {
                    Picker("Model", selection: Binding(get: { fx.profileName }, set: { name in
                        b.wrappedValue.profileName = name
                        if let p = FixtureProfile.named(name) { b.wrappedValue.layout = p.layout }
                    })) {
                        ForEach(FixtureProfile.all) { p in Text(p.name).tag(p.name) }
                        if fx.profile == nil { Text("Custom").tag(fx.profileName) }
                    }
                    .frame(width: 420)
                    Stepper("Start address: \(fx.address)", value: b.address, in: 1...512)
                    Picker("Output", selection: Binding(get: { fx.outputKey ?? DMXEngine.mainKey },
                                                        set: { model.assignOutput(fixtureID: fx.id, key: $0) })) {
                        ForEach(model.outputChoices, id: \.key) { c in Text(c.name).tag(c.key) }
                    }
                    .frame(width: 260)
                    .help("Which wireless DMX box this light is plugged into")
                    Text("Uses \(fx.address)–\(fx.lastAddress) · \(fx.channelCount) ch · \(fx.headCount) head\(fx.headCount == 1 ? "" : "s")")
                        .foregroundColor(.secondary)
                }
                if let tip = fx.profile?.setupTip, !tip.isEmpty {
                    HStack(alignment: .top) {
                        Image(systemName: "info.circle")
                        Text(tip.replacingOccurrences(of: "the start address shown here", with: "address \(String(format: "%03d", fx.address))"))
                    }
                    .font(.callout).foregroundColor(.secondary)
                }
                BehaviorEditor(fixtureID: fx.id)
                HStack(spacing: 6) {
                    Image(systemName: "display")
                    Text("The light's display should read ").foregroundColor(.secondary) + Text(fx.displayCode).bold().monospacedDigit()
                }
                .font(.callout)
                if let src = conflicts.first(where: { $0.address == fx.address && $0.layout == fx.layout }),
                   model.fixtures.firstIndex(where: { $0.id == src.id }) ?? 0 < model.fixtures.firstIndex(where: { $0.id == fx.id }) ?? 0 {
                    Label("Same address as \(src.name) (\(fx.displayCode)). Chained lights on the same address always do the same thing, so this one mirrors \(src.name).",
                          systemImage: "link")
                        .foregroundColor(.green)
                } else if conflicts.contains(where: { !($0.address == fx.address && $0.layout == fx.layout) }) {
                    Label("Overlaps with \(conflicts.map(\.name).joined(separator: ", ")). Change the start address.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                }
                if fx.lastAddress > 512 {
                    Label("Goes past channel 512. Lower the start address.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                }
                DisclosureGroup("Advanced: channel layout", isExpanded: Binding(
                    get: { showAdvanced == fx.id }, set: { showAdvanced = $0 ? fx.id : nil })) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Channel layout", text: Binding(get: { fx.layout }, set: { v in
                            b.wrappedValue.layout = v
                            b.wrappedValue.profileName = FixtureProfile.all.first { $0.layout == v }?.name ?? "Custom"
                        }))
                        .font(.system(.body, design: .monospaced))
                        Text("Letters per channel, in order: D dimmer · R G B W A UV colors (add a number for each head, like R1 G1 B1 W1) · S strobe · P/T pan/tilt · PF/TF fine · SPD speed · a plain number holds that channel at a fixed value.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

// MARK: - Wireless DMX (Bluetooth-style)

struct WirelessView: View {
    @EnvironmentObject var model: AppModel
    @State private var manualIP = ""
    @State private var showUSB = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Wireless DMX",
                           subtitle: "Finds wireless DMX boxes (like your PKnight) on your Wi-Fi, like pairing a Bluetooth speaker.")

                Card {
                    HStack {
                        Circle().fill(model.connected ? Color.green : Color.gray).frame(width: 12, height: 12)
                        Text(model.connected ? "Connected" : "Not connected").font(.headline)
                        Text(model.statusMessage).foregroundColor(.secondary).lineLimit(1)
                        Spacer()
                        if model.connected {
                            Button("Disconnect") { model.disconnect() }
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Devices").font(.headline)
                            if model.searchingNodes { ProgressView().controlSize(.small) }
                            Spacer()
                            Toggle("Keep scanning", isOn: $model.output.autoScan)
                            Button {
                                model.findNodes()
                            } label: { Label("Scan Now", systemImage: "antenna.radiowaves.left.and.right") }
                        }
                        if model.discoveredNodes.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(model.searchingNodes ? "Looking for devices…" : "No wireless DMX devices found yet.")
                                Text("• PKnight WiFi-DMX EasyNode (factory setting): on your Mac's Wi-Fi menu, join the network named \"PKNIGHT.WIFI+…\" (default password: PKNIGHT.WIFI). It will then appear here.\n• If you set the PKnight to join your router instead, your MacBook must be on that same Wi-Fi.\n• For a wired PKnight, plug it into the same router your Mac uses.")
                                    .font(.callout).foregroundColor(.secondary)
                            }
                        }
                        ForEach(model.discoveredNodes) { node in
                            HStack(spacing: 12) {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .font(.title2)
                                    .foregroundColor(model.isOnline(node) ? .green : .gray)
                                VStack(alignment: .leading) {
                                    HStack {
                                        Text(node.name).font(.headline)
                                        if model.output.rememberedDevice?.id == node.id {
                                            Text("Remembered").font(.caption).padding(.horizontal, 6)
                                                .background(Capsule().fill(Color.pink.opacity(0.3)))
                                        }
                                    }
                                    Text("\(node.ip)\(node.longName.isEmpty || node.longName == node.name ? "" : " · " + node.longName) · \(model.isOnline(node) ? "online" : "offline")")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if node.ip.hasPrefix("192.168.4.") {
                                    Button("PKnight Settings") { NSWorkspace.shared.open(URL(string: "http://\(node.ip)")!) }
                                        .help("Opens the PKnight's own setup page")
                                }
                                if model.isCurrentDevice(node) {
                                    Label("Connected", systemImage: "checkmark.circle.fill").foregroundColor(.green)
                                    Button("Forget") { model.forgetDevice() }
                                } else {
                                    Button("Connect") { model.useNode(node) }.disabled(!model.isOnline(node))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Test your lights").font(.headline)
                            Spacer()
                            Text(model.connected ? "Sending \(model.packetsPerSecond) frames/sec" : "Not sending")
                                .font(.caption).monospacedDigit().foregroundColor(model.connected && model.packetsPerSecond > 0 ? .green : .orange)
                        }
                        HStack {
                            Button { model.stop(); model.activePresetID = nil; model.testMode = .white } label: { Label("All White", systemImage: "sun.max.fill") }
                            Button { model.stop(); model.activePresetID = nil; model.testMode = .rainbow } label: { Label("Rainbow", systemImage: "paintpalette.fill") }
                            Button { model.testMode = .off } label: { Label("Stop Test", systemImage: "stop.fill") }
                        }
                        Toggle("Send on universes 0 and 1 (works with any PKnight setting)", isOn: Binding(
                            get: { model.output.universeAuto ?? true }, set: { model.output.universeAuto = $0; model.connect(quiet: true) }))
                        Toggle("Also send sACN (the other protocol the PKnight understands)", isOn: Binding(
                            get: { model.output.alsoSendSACN ?? true }, set: { model.output.alsoSendSACN = $0; model.connect(quiet: true) }))
                        Text("If the lights don't respond:").font(.subheadline.bold()).padding(.top, 4)
                        Text("""
                        1. Look at the PKnight's channel light. Blinking quickly means DMX is coming out (PKnight manual). If it's not blinking, the Mac isn't reaching it: make sure the Mac's Wi-Fi is on the PKNIGHT.WIFI network and the PKnight shows as Connected above.
                        2. If it IS blinking quickly but the lights do nothing: check the DMX cable (PKnight → Bar 1 DMX IN, Bar 1 DMX OUT → Bar 2 DMX IN) and that each bar's display reads A.001 (38-channel DMX mode), not Auto or Sound mode.
                        3. Close Photon or any other lighting app; two apps sending at once fight each other.
                        """)
                        .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Can't find it? Enter it manually").font(.headline)
                        HStack {
                            TextField("IP address shown on the PKnight screen (e.g. 192.168.1.50)", text: $manualIP)
                                .frame(width: 360)
                            Stepper("Universe \(model.output.artNetUniverse)", value: $model.output.artNetUniverse, in: 0...32767)
                            Button("Connect") {
                                model.output.kind = .artNet
                                model.output.artNetIP = manualIP.trimmingCharacters(in: .whitespaces)
                                model.connect()
                            }
                            .disabled(manualIP.isEmpty)
                        }
                        Text("With \"Send on universes 0 and 1\" on, the universe here only matters for other setups.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Timing").font(.headline)
                        HStack {
                            Text("Light delay correction")
                            Slider(value: $model.globalLatencyMs, in: -200...400, step: 10).frame(width: 260)
                            Text("\(Int(model.globalLatencyMs)) ms").monospacedDigit()
                        }
                        Text("If every song's lights land a little after the beat (common with Bluetooth speakers or busy Wi-Fi), slide this right until they hit together.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                DisclosureGroup("USB DMX interfaces (not needed for PKnight)", isExpanded: $showUSB) {
                    HStack {
                        Picker("Type", selection: $model.output.kind) {
                            ForEach(OutputKind.allCases) { Text($0.rawValue).tag($0) }
                        }.frame(width: 340)
                        Picker("Port", selection: $model.output.serialPath) {
                            Text("Choose…").tag("")
                            ForEach(SerialPort.availablePorts(), id: \.self) { Text($0).tag($0) }
                        }.frame(width: 300)
                        Button("Connect") { model.connect() }
                    }
                    .padding(.top, 6)
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Idle look

struct IdleView: View {
    @EnvironmentObject var model: AppModel
    @State private var previewing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Idle Look",
                           subtitle: "What the lights do when there's no music: before you press Play, between songs, and during silent parts.")
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Mode", selection: $model.idle.mode) {
                            ForEach(IdleMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        if model.idle.mode == .solid || model.idle.mode == .breathe {
                            ColorPicker("Color", selection: Binding(
                                get: { model.idle.color.color },
                                set: { c in
                                    if let ns = NSColor(c).usingColorSpace(.deviceRGB) {
                                        model.idle.color = RGB(r: Double(ns.redComponent), g: Double(ns.greenComponent), b: Double(ns.blueComponent))
                                    }
                                }), supportsOpacity: false)
                            HStack {
                                ForEach(["Red Velvet", "Purple Haze", "Ocean", "Warm White"], id: \.self) { name in
                                    Button {
                                        model.idle.color = Palette.named(name).color(0)
                                    } label: {
                                        Circle().fill(Palette.named(name).color(0).color).frame(width: 22, height: 22)
                                    }
                                    .buttonStyle(.plain)
                                    .help(name)
                                }
                            }
                        }
                        if model.idle.mode == .colorFade {
                            Picker("Colors", selection: $model.idle.palette) {
                                ForEach(Palette.all) { Text($0.id).tag($0.id) }
                            }.frame(width: 300)
                        }
                        if model.idle.mode != .off {
                            HStack {
                                Text("Brightness")
                                Slider(value: $model.idle.brightness, in: 0.05...1).frame(width: 260)
                                Text("\(Int(model.idle.brightness * 100))%").monospacedDigit()
                            }
                            HStack {
                                Text("Beam position")
                                Slider(value: $model.idle.tilt, in: 0...1).frame(width: 260)
                            }
                        }
                    }
                }
                Text("The lights fade into this look about half a second into any silence, and snap back right as the music returns.")
                    .font(.callout).foregroundColor(.secondary)
                StagePreview()
            }
            .padding(24)
        }
    }
}

// MARK: - Transport bar (always visible)

struct TransportBar: View {
    @EnvironmentObject var model: AppModel

    var nowPlaying: String {
        if let b = model.activeBlock { return b.entry.blockLabel }
        if model.inGap { return "Next song starting…" }
        if let id = model.playingSongID, let s = model.song(id) { return s.displayName }
        return "Nothing playing · idle look on"
    }

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Button { model.previousInLineup() } label: { Image(systemName: "backward.fill") }
                    .disabled(model.playingLineupID == nil)
                Button { model.togglePlay() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").frame(width: 24)
                }
                .help("Play / Pause (Space)")
                Button { model.stop() } label: { Image(systemName: "stop.fill") }
                Button { model.nextInLineup() } label: { Image(systemName: "forward.fill") }
                    .disabled(model.playingLineupID == nil)
            }
            .buttonStyle(.borderless)
            .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(nowPlaying).font(.headline).lineLimit(1)
                if let id = model.playingSongID, let a = model.song(id)?.analysis {
                    LiveReader(model.live) { Text("\(formatTime(model.currentTime)) / \(formatTime(a.duration))").font(.caption).monospacedDigit().foregroundColor(.secondary) }
                } else if let lid = model.playingLineupID, let l = model.lineups.first(where: { $0.id == lid }) {
                    Text(l.name).font(.caption).foregroundColor(.secondary)
                }
            }
            .frame(width: 260, alignment: .leading)

            Spacer()

            HStack(spacing: 6) {
                Circle().fill(model.connected ? Color.green : Color.red).frame(width: 8, height: 8)
                Text(model.connected ? "Lights connected" : "Lights not connected").font(.caption).foregroundColor(.secondary)
            }

            HStack {
                Image(systemName: "sun.max")
                Slider(value: $model.master, in: 0...1).frame(width: 140)
            }
            .help("Master brightness")

            HoldButton(title: "FLASH", color: .white, isHeld: $model.flashHeld).help("Hold for full white (or hold F)")
            HoldButton(title: "STROBE", color: .yellow, isHeld: $model.strobeHeld).help("Hold to strobe everything (or hold S)")

            Toggle(isOn: $model.blackout) {
                Text("BLACKOUT").font(.caption.bold())
            }
            .toggleStyle(.button)
            .tint(.red)
            .help("⌘B")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.35))
    }
}

// MARK: - Sequence / Stationary editor

struct BehaviorEditor: View {
    @EnvironmentObject var model: AppModel
    let fixtureID: UUID

    var body: some View {
        let b = model.fixtureBinding(fixtureID)
        let fx = b.wrappedValue
        let look = fx.stationaryLook
        let setLook: (StationaryLook) -> Void = { b.wrappedValue.stationary = $0 }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("This light is", selection: Binding(get: { fx.effectiveBehavior }, set: { b.wrappedValue.behavior = $0 })) {
                    ForEach(LightBehavior.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
                Text(fx.effectiveBehavior.explanation).font(.caption).foregroundColor(.secondary)
            }
            if fx.effectiveBehavior == .stationary {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Brightness").frame(width: 80, alignment: .leading)
                        Slider(value: Binding(get: { look.brightness }, set: { var l = look; l.brightness = $0; setLook(l) }), in: 0...1)
                            .frame(width: 260)
                        Text("\(Int(look.brightness * 100))%").monospacedDigit()
                    }
                    HStack {
                        Text("Color").frame(width: 80, alignment: .leading)
                        if let wheel = fx.colorWheel {
                            ForEach(0..<wheel.slots.count, id: \.self) { i in
                                let slot = wheel.slots[i]
                                let selected = wheel.nearest(look.color).value == slot.value
                                Button {
                                    var l = look; l.color = slot.color; setLook(l)
                                } label: {
                                    Circle().fill(slot.color.color).frame(width: 24, height: 24)
                                        .overlay(Circle().stroke(selected ? Color.white : Color.clear, lineWidth: 3))
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            ColorPicker("", selection: Binding(get: { look.color.color }, set: { c in
                                if let ns = NSColor(c).usingColorSpace(.deviceRGB) {
                                    var l = look
                                    l.color = RGB(r: Double(ns.redComponent), g: Double(ns.greenComponent), b: Double(ns.blueComponent))
                                    setLook(l)
                                }
                            }), supportsOpacity: false).labelsHidden()
                        }
                    }
                    if fx.hasStrobeChannel {
                        HStack {
                            Text("Strobe").frame(width: 80, alignment: .leading)
                            Slider(value: Binding(get: { look.strobe }, set: { var l = look; l.strobe = $0; setLook(l) }), in: 0...1)
                                .frame(width: 260)
                            Text(look.strobe < 0.02 ? "Off" : "\(Int(look.strobe * 100))%").monospacedDigit()
                        }
                    }
                    if fx.isMover {
                        HStack {
                            Text("Position").frame(width: 80, alignment: .leading)
                            Slider(value: Binding(get: { look.tilt }, set: { var l = look; l.tilt = $0; setLook(l) }), in: 0...1)
                                .frame(width: 260)
                        }
                    }
                    Toggle("Stay on before the show and between songs", isOn: Binding(get: { look.onWhenIdle }, set: { var l = look; l.onWhenIdle = $0; setLook(l) }))
                    if fx.colorWheel != nil {
                        Text("Focus, focal length and iris are set with the knobs on the light itself.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 4)
            }
        }
    }
}

/// A button that is "on" only while pressed.
struct HoldButton: View {
    let title: String
    let color: Color
    @Binding var isHeld: Bool

    var body: some View {
        Text(title)
            .font(.caption.bold())
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(isHeld ? color.opacity(0.9) : Color.white.opacity(0.1)))
            .foregroundColor(isHeld ? .black : .primary)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isHeld { isHeld = true } }
                .onEnded { _ in isHeld = false })
    }
}

// MARK: - Problems

struct ProblemsView: View {
    @ObservedObject var errors = ErrorCenter.shared
    @State private var expanded: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    PageHeader(title: "Problems", subtitle: "Anything that didn't work. Report a problem and it goes straight to the DMX Studio GitHub so it can be fixed.")
                    Spacer()
                    if !errors.problems.isEmpty {
                        Button("Clear All") { errors.problems.removeAll() }
                    }
                }
                if errors.problems.isEmpty {
                    Card { Label("Everything's working. No problems so far.", systemImage: "checkmark.seal.fill").foregroundColor(.green) }
                }
                ForEach(errors.problems) { p in
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(p.area).font(.headline)
                                    Text(p.message)
                                    Text(p.date, style: .time).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if p.reported {
                                    Label("Reported", systemImage: "checkmark").foregroundColor(.green)
                                }
                                Button(p.reported ? "Report Again" : "Report Problem") { errors.sendReport(p) }
                            }
                            if !p.details.isEmpty {
                                DisclosureGroup("Technical details", isExpanded: Binding(
                                    get: { expanded == p.id }, set: { expanded = $0 ? p.id : nil })) {
                                    ScrollView {
                                        Text(p.details).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .frame(maxHeight: 200)
                                }
                            }
                        }
                    }
                }
                Text("Report Problem opens a pre-filled issue on GitHub (you just click Submit) and copies the full report to your clipboard.")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(24)
        }
    }
}


/// Drops onto a set list: audio files get imported; songs dragged from the library get added.
func handleSongDrop(_ providers: [NSItemProvider], model: AppModel, lineupID: UUID) {
    let fileType = UTType.fileURL.identifier
    let files = providers.filter { $0.hasItemConformingToTypeIdentifier(fileType) }
    if !files.isEmpty { loadDroppedURLs(files) { urls in model.importSongs(urls, into: lineupID) } }
    for p in providers where !p.hasItemConformingToTypeIdentifier(fileType) && p.canLoadObject(ofClass: NSString.self) {
        _ = p.loadObject(ofClass: NSString.self) { obj, _ in
            guard let str = obj as? String else { return }
            if str.hasPrefix("block:") {
                let parts = str.split(separator: ":").map(String.init)
                let e: LineupEntry = parts.count > 2 && parts[1] == "transition"
                    ? .transition(TransitionStyle(rawValue: parts[2]) ?? .colorWash) : .silence()
                DispatchQueue.main.async { model.addBlock(e, to: lineupID) }
                return
            }
            let ids = str.split(separator: "\n").compactMap { UUID(uuidString: String($0)) }
            DispatchQueue.main.async {
                for id in ids { if let song = model.song(id) { model.addToLineup(lineupID, songID: id, showID: song.activeShow?.id) } }
            }
        }
    }
}

/// The song library beside a set list: click + (or double-click, or drag) to add songs to the set.
struct SetListLibraryPanel: View {
    @EnvironmentObject var model: AppModel
    let lineupID: UUID
    @State private var search = ""

    var body: some View {
        let inSet = Set(model.lineups.first { $0.id == lineupID }?.entries.map(\.songID) ?? [])
        let list = model.songs.filter { search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search) }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Song Library").font(.headline)
                Spacer()
                Button("Add All") {
                    for s in list where !inSet.contains(s.id) { model.addToLineup(lineupID, songID: s.id, showID: s.activeShow?.id) }
                }
                .disabled(list.allSatisfy { inSet.contains($0.id) })
                .help("Add every song shown here that isn't in the set yet")
            }
            BlockPalette(lineupID: lineupID)
            Divider()
            TextField("Search songs or artists", text: $search).textFieldStyle(.roundedBorder)
            if model.songs.isEmpty {
                Text("No songs yet. Import them on the Songs tab, or drag files into the set.")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(list) { s in
                        HStack(spacing: 8) {
                            Image(systemName: "music.note").foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.title).lineLimit(1)
                                Text(s.artistName + (s.analysis.map { " · \(Int($0.bpm.rounded())) BPM" } ?? ""))
                                    .font(.caption).foregroundColor(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if inSet.contains(s.id) {
                                Image(systemName: "checkmark").foregroundColor(.secondary).help("Already in this set (you can add it again)")
                            }
                            Button { model.addToLineup(lineupID, songID: s.id, showID: s.activeShow?.id) } label: {
                                Image(systemName: "plus.circle.fill").font(.system(size: 16)).foregroundColor(.pink)
                            }
                            .buttonStyle(.borderless)
                            .help("Add to the end of the set")
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { model.addToLineup(lineupID, songID: s.id, showID: s.activeShow?.id) }
                        .onDrag { NSItemProvider(object: s.id.uuidString as NSString) }
                    }
                }
                .listStyle(.inset)
            }
            Text("Click +, double-click, or drag a song into the set.").font(.caption).foregroundColor(.secondary)
        }
        .padding(14)
        .frame(width: 290)
    }
}


/// Blocks you can drop between songs: silence and built-in transitions. Click to add at the end, or drag into the set.
struct BlockPalette: View {
    @EnvironmentObject var model: AppModel
    let lineupID: UUID
    private let cols = [GridItem(.adaptive(minimum: 120), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Blocks").font(.headline)
            LazyVGrid(columns: cols, alignment: .leading, spacing: 6) {
                chip("Silence", icon: "speaker.slash.fill", help: "Quiet pause with the idle look") { .silence() }
                    .onDrag { NSItemProvider(object: "block:silence" as NSString) }
                ForEach(TransitionStyle.allCases) { t in
                    chip(t.rawValue, icon: t.icon, help: t.blurb) { .transition(t) }
                        .onDrag { NSItemProvider(object: "block:transition:\(t.rawValue)" as NSString) }
                }
            }
            Text("Click to add at the end, or drag into the set, then move it between songs.")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    private func chip(_ title: String, icon: String, help: String, make: @escaping () -> LineupEntry) -> some View {
        Button { model.addBlock(make(), to: lineupID) } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10))
                Text(title).font(.caption).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// A silence or transition block in a set list.
struct BlockRow: View {
    @EnvironmentObject var model: AppModel
    let lineupID: UUID
    let index: Int
    let entry: LineupEntry

    var body: some View {
        let isNow = model.playingLineupID == lineupID && model.playingEntryIndex == index
        let isSilence = entry.block == .silence
        HStack(spacing: 12) {
            Text("").frame(width: 24)
            Image(systemName: isSilence ? "speaker.slash.fill" : (entry.transition ?? .colorWash).icon)
                .foregroundColor(isNow ? .pink : .purple)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(isSilence ? "Silence" : "Transition").font(.headline)
                Text(isSilence ? ((entry.transition == .blackout) ? "Lights dark" : "Idle look") : (entry.transition ?? .colorWash).blurb)
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if isSilence {
                Picker("Lights", selection: Binding(get: { entry.transition == .blackout ? TransitionStyle.blackout : .idle },
                                                    set: { v in model.updateEntry(lineupID, entry.id) { $0.transition = v } })) {
                    Text("Idle look").tag(TransitionStyle.idle)
                    Text("Dark").tag(TransitionStyle.blackout)
                }
                .labelsHidden().frame(width: 110)
            } else {
                Picker("Transition", selection: Binding(get: { entry.transition ?? .colorWash }, set: { v in
                    model.updateEntry(lineupID, entry.id) { $0.transition = v; if v.usesPalette && $0.palette == nil { $0.palette = v.defaultPalette } }
                })) {
                    ForEach(TransitionStyle.allCases) { t in Text(t.rawValue).tag(t) }
                }
                .labelsHidden().frame(width: 160)
                if (entry.transition ?? .colorWash).usesPalette {
                    Picker("Colors", selection: Binding(get: { entry.palette ?? "Neon" },
                                                        set: { v in model.updateEntry(lineupID, entry.id) { $0.palette = v } })) {
                        ForEach(Palette.all) { Text($0.id).tag($0.id) }
                    }
                    .labelsHidden().frame(width: 120)
                }
                Toggle("Fade music", isOn: Binding(get: { entry.fadeMusic ?? false },
                                                   set: { v in model.updateEntry(lineupID, entry.id) { $0.fadeMusic = v } }))
                    .help("Fade the song before out during this transition, and the next song in")
            }
            Stepper("\(Int(entry.blockSeconds)) s", value: Binding(get: { entry.blockSeconds },
                                                                set: { v in model.updateEntry(lineupID, entry.id) { $0.seconds = v } }),
                    in: 1...60, step: 1)
                .frame(width: 90)
            VStack(spacing: 2) {
                Button { model.moveEntry(lineupID: lineupID, from: index, by: -1) } label: { Image(systemName: "chevron.up") }
                    .disabled(index == 0)
                Button { model.moveEntry(lineupID: lineupID, from: index, by: 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(index >= (model.lineups.first { $0.id == lineupID }?.entries.count ?? 1) - 1)
            }
            .buttonStyle(.borderless)
            Button { model.removeEntry(lineupID: lineupID, entryID: entry.id) } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.borderless).help("Remove this block")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(isNow ? 0.25 : 0.10)))
        .contextMenu {
            Button("Move Up") { model.moveEntry(lineupID: lineupID, from: index, by: -1) }
            Button("Move Down") { model.moveEntry(lineupID: lineupID, from: index, by: 1) }
            Divider()
            Button("Remove Block", role: .destructive) { model.removeEntry(lineupID: lineupID, entryID: entry.id) }
        }
    }
}
