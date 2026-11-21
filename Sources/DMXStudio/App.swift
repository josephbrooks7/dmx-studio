import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

@main
struct DMXStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Not @StateObject: that makes the whole scene (and the menu bar) rebuild on every change in the
    // app — the beat, the play position — which closed any menu you had open. Views observe the model
    // through the environment instead.
    @State private var model: AppModel

    init() {
        // Test hook: `DMXStudio --analyze song.wav` prints what Learn finds, then exits.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--analyze"), i + 1 < args.count {
            Self.runAnalyzeAndExit(path: args[i + 1])
        }
        // Helper modes: risky work runs in a separate process so a failure can't crash the app
        // Test hook: export a session with one song to a .dmxsession file, import it back, check it matches.
        if let i = args.firstIndex(of: "--test-package"), i + 1 < args.count {
            let audio = URL(fileURLWithPath: args[i + 1])
            var song = Song(title: "Package Test", path: audio.path, artist: "Red Velvet Test")
            song.shows = [LightShow(name: "Test", style: .club, variation: 1, sections: [])]
            var session = Session(name: "Package Test", fixtures: Session.standardRig(), lineups: [Lineup(name: "Set")])
            session.lineups[0].entries = [LineupEntry(songID: song.id, showID: nil)]
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("pkg-test.dmxsession")
            do {
                try LibraryFiles.exportSession(session, songs: [song], to: dest)
                let (s2, songs2) = try LibraryFiles.importSession(from: dest)
                let ok = s2.id == session.id && s2.fixtures.count == 3 && s2.lineups.first?.entries.first?.songID == song.id
                    && songs2.count == 1 && songs2[0].shows.count == 1 && FileManager.default.fileExists(atPath: songs2[0].path)
                    && songs2[0].path.contains("DMX Studio/Songs")
                print("package size=\((try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? -1) imported audio=\(songs2.first?.path ?? "-") ok=\(ok)")
                exit(ok ? 0 : 1)
            } catch {
                print("ERROR: \(error)"); exit(2)
            }
        }
        // Test hook: a library with an odd number in one song and one damaged song still saves and loads.
        if args.contains("--test-library") {
            var good = Song(title: "Keeps", path: "/tmp/a.wav", artist: "Test")
            var a = SongAnalysis(duration: 10, bpm: .nan, beats: [0, 0.5], downbeatOffset: 0, frameRate: 1,
                                 energy: [Float.nan, 0.5], bass: [0.1], mid: [0.1], high: [0.1],
                                 kicks: [], snares: [], hats: [], detectedSections: [], silences: nil)
            a.beatBase = 0
            good.analysis = a
            let lib = Library(songs: [good, Song(title: "Second", path: "/tmp/b.wav")], sessions: [])
            do {
                var data = try Library.encoder.encode(lib)
                // damage the second song
                var text = String(decoding: data, as: UTF8.self)
                text = text.replacingOccurrences(of: "\"title\":\"Second\"", with: "\"title\":42")
                data = Data(text.utf8)
                let back = try Library.decoder.decode(Library.self, from: data)
                let ok = back.songs.count == 1 && back.songs[0].title == "Keeps" && back.songs[0].analysis?.bpm.isNaN == true
                print("library songs=\(back.songs.map(\.title)) ok=\(ok)")
                exit(ok ? 0 : 1)
            } catch { print("ERROR: \(error)"); exit(2) }
        }
        // Test hook: transcribe a vocal file with the bundled Whisper + a given model, then read its meaning
        if let i = args.firstIndex(of: "--test-lyrics"), i + 2 < args.count {
            WhisperEngine.overrideModel = URL(fileURLWithPath: args[i + 2])
            var result: Result<[LyricWord], Error>?
            WhisperEngine.transcribe(vocals: URL(fileURLWithPath: args[i + 1]), phrases: [], model: .base, progress: { _ in }) { result = $0 }
            while result == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
            switch result! {
            case .success(let words):
                print("words=" + words.map { String(format: "%@@%.2f(%.2f)", $0.text, $0.start, $0.confidence) }.joined(separator: " "))
                var ly = LyricsLearner.build(words: words, phrases: [], source: "test")
                LyricsInterpreter.interpret(&ly)
                for (l, ins) in zip(ly.lines, ly.insights ?? []) {
                    print("line=\(l.text) | emotions=\(ins.emotions.joined(separator: "+")) score=\(String(format: "%.2f", ins.emotionScore)) imagery=\(ins.imagery.joined(separator: "+")) delivery=\(ins.delivery)")
                }
                let a = SongAnalysis(duration: 10, bpm: 120, beats: [], downbeatOffset: 0, frameRate: 43, energy: [], bass: [], mid: [], high: [],
                                     kicks: [], snares: [], hats: [], detectedSections: [])
                for c in LyricLighting.cues(ly, analysis: a) { print("cue=\(c.kind):\(c.label) @\(String(format: "%.2f", c.start)) — \(c.reason)") }
                exit(words.isEmpty ? 1 : 0)
            case .failure(let e):
                print("ERROR: \(e)"); exit(2)
            }
        }
        // Test hook: listen to a song, then line up pasted lyrics with what was heard (like Paste in the app)
        if let i = args.firstIndex(of: "--test-paste"), i + 3 < args.count {
            WhisperEngine.overrideModel = URL(fileURLWithPath: args[i + 2])
            let text = (try? String(contentsOfFile: args[i + 3])) ?? ""
            let url = URL(fileURLWithPath: args[i + 1])
            let duration = (try? AVAudioFile(forReading: url)).map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0
            var result: Result<[LyricWord], Error>?
            WhisperEngine.transcribe(vocals: url, phrases: [], model: .base, progress: { _ in }) { result = $0 }
            while result == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
            guard case .success(let heard) = result! else { print("ERROR: \(result!)"); exit(2) }
            print("heard=" + heard.map { String(format: "%@@%.2f", $0.text, $0.start) }.joined(separator: " "))
            let ly = LyricsLearner.align(text: text, heard: heard, phrases: [], duration: duration)
            for l in ly.lines { print(String(format: "LINE %.2f %.2f ", l.start, l.end) + l.text) }
            for lb in ly.sectionLabels ?? [] { print("LABEL \(lb.line) \(lb.name)") }
            exit(0)
        }
        if args.contains("--scan-artnet") {
            CrashGuard.install(writeToStderr: true)
            CrashGuard.breadcrumb("Scanning for wireless DMX devices")
            let nodes = ArtNetDiscovery.discover(timeout: 1.5)
            FileHandle.standardOutput.write((try? JSONEncoder().encode(nodes)) ?? Data("[]".utf8))
            exit(0)
        }
        if let i = args.firstIndex(of: "--learn"), i + 2 < args.count {
            CrashGuard.install(writeToStderr: true)
            CrashGuard.breadcrumb("Learning \(URL(fileURLWithPath: args[i + 1]).lastPathComponent)")
            do {
                // optional: where to save the separated parts, and the song's detection settings (JSON)
                let stems = i + 3 < args.count && !args[i + 3].isEmpty ? URL(fileURLWithPath: args[i + 3]) : nil
                let settings = i + 4 < args.count
                    ? ((try? Data(contentsOf: URL(fileURLWithPath: args[i + 4]))).flatMap { try? JSONDecoder().decode(DetectionSettings.self, from: $0) } ?? DetectionSettings())
                    : DetectionSettings()
                let hq = i + 5 < args.count && args[i + 5] == "hq"
                let a = try AudioAnalyzer.analyze(url: URL(fileURLWithPath: args[i + 1]), settings: settings, stemsDir: stems, highQuality: hq) { p in
                    print("progress=\(p)"); fflush(stdout)
                }
                try Library.encoder.encode(a).write(to: URL(fileURLWithPath: args[i + 2]))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data(error.localizedDescription.utf8))
                exit(3)
            }
        }
        CrashGuard.install()
        NSApplication.shared.setActivationPolicy(.regular)
        // made last: the test modes above exit before the app (and its audio, sessions) starts
        _model = State(initialValue: AppModel())
    }

    static func runAnalyzeAndExit(path: String) -> Never {
        let url = URL(fileURLWithPath: path)
        do {
            let meta = SongMetadata.read(url)
            let args = CommandLine.arguments
            let stems = args.firstIndex(of: "--stems").flatMap { $0 + 1 < args.count ? URL(fileURLWithPath: args[$0 + 1]) : nil }
            let hqModel = args.firstIndex(of: "--hq-model").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
            if let hqModel { HQSplitter.overrideModel = URL(fileURLWithPath: hqModel) }
            let a = try AudioAnalyzer.analyze(url: url, stemsDir: stems, highQuality: hqModel != nil) { _ in }
            let show = ShowGenerator.generateShaped(a, style: a.suggestedStyle, variation: 1, design: nil)
            let g = a.groove
            print(String(format: "groove=%@ confidence=%.2f feltBPM=%.1f fourOnFloor=%.2f", g.feel.rawValue, g.confidence, a.feltBPM, a.fourOnTheFloor))
            print("genres=\(a.genreSummary)")
            print("accents=" + (a.accents ?? []).map { "\($0.kind.rawValue)@\(String(format: "%.2f", $0.start))" }.joined(separator: ","))
            print("title=\(meta.title) artist=\(meta.artist ?? "-")")
            print(String(format: "duration=%.2f bpm=%.2f beats=%d downbeat=%d kicks=%d snares=%d hats=%d",
                         a.duration, a.bpm, a.beats.count, a.downbeatOffset, a.kicks.count, a.snares.count, a.hats.count))
            print("snareTimes=" + a.snares.map { String(format: "%.3f", $0) }.joined(separator: ","))
            print("kickTimes=" + a.kicks.map { String(format: "%.3f", $0) }.joined(separator: ","))
            print("hatTimes=" + a.hats.map { String(format: "%.3f", $0) }.joined(separator: ","))
            print("vocalPhrases=" + (a.vocalPhrases ?? []).map { String(format: "%.2f-%.2f", $0.start, $0.end) }.joined(separator: ","))
            print("stems=\(a.stemsFolder ?? "-")")
            print("firstBeats=" + a.beats.prefix(6).map { String(format: "%.3f", $0) }.joined(separator: ","))
            print("silences=" + (a.silences ?? []).map { String(format: "%.2f-%.2f", $0.start, $0.end) }.joined(separator: ","))
            print(String(format: "musicStart=%.2f musicEnd=%.2f", a.musicStart, a.musicEnd))
            for d in a.detectedSections {
                print(String(format: "section %@ %.1f-%.1f %@ energy=%.2f", d.name, d.start, d.end, d.level.rawValue, d.energy))
            }
            print("suggested=\(a.suggestedStyle.rawValue) showSections=\(show.count)")
            // Render a few frames to make sure the show engine runs
            let fx = [Fixture(name: "A", address: 1, profileName: FixtureProfile.shehdsBeam38.name, layout: FixtureProfile.shehdsBeam38.layout),
                      Fixture(name: "B", address: 39, profileName: FixtureProfile.shehdsBeam38.name, layout: FixtureProfile.shehdsBeam38.layout)]
            let r = ShowRenderer(analysis: a, sections: show, fixtures: fx)
            var lit = 0
            for k in 0..<200 {
                let t = a.duration * Double(k) / 200
                let frame = DMXMapper.frame(fixtures: fx, rendered: r.renderWithIdle(at: t), master: 1, blackout: false, time: t)
                if frame.contains(where: { $0 > 0 }) { lit += 1 }
            }
            print("framesWithLight=\(lit)/200")
            exit(0)
        } catch {
            print("ERROR: \(error.localizedDescription)")
            exit(2)
        }
    }

    var body: some Scene {
        WindowGroup("DMX Studio") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1180, minHeight: 760)
                .preferredColorScheme(.dark)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import Session…") { model.importSessionWithPanel() }.keyboardShortcut("o", modifiers: .command)
                Button("Export Session…") { model.exportSessionWithPanel() }.keyboardShortcut("e", modifiers: .command)
                Divider()
                Button("Show Files in Finder") { model.showLibraryFolder() }
                Button("Lyrics Library…") { model.showLyricsLibrary = true }.keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { model.undo() }.keyboardShortcut("z", modifiers: .command)
                Button("Redo") { model.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updater.shared.checkNow() }
            }
            CommandGroup(after: .toolbar) {
                Button("Toggle Full Screen") { model.toggleFullScreen() }.keyboardShortcut("f", modifiers: [.command, .control])
            }
            CommandMenu("Playback") {
                Button("Play / Pause  (Space)") { model.togglePlay() }
                Button("Stop") { model.stop() }.keyboardShortcut(".", modifiers: .command)
                Button("Next Song") { model.nextInLineup() }.keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Previous Song") { model.previousInLineup() }.keyboardShortcut(.leftArrow, modifiers: .command)
                Divider()
                Button("Blackout On / Off") { model.blackout.toggle() }
                    .keyboardShortcut("b", modifiers: .command)
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var errors = ErrorCenter.shared
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        ZStack {
            if model.showingStart {
                SessionsScreen().transition(.opacity)
            } else {
                MainShell().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.showingStart)
        .sheet(item: Binding(get: { model.lyricsPrompt.first.map(PromptID.init) }, set: { _ in })) { p in
            LyricsPromptSheet(songID: p.id).environmentObject(model).interactiveDismissDisabled()
        }
        .sheet(isPresented: Binding(get: { model.showLyricsLibrary }, set: { model.showLyricsLibrary = $0 })) {
            LyricsLibraryView().environmentObject(model)
        }
        .sheet(isPresented: $updater.showing) { UpdateSheet() }
        .onAppear { updater.checkQuietly() }

        .onAppear {
            // the window can go full screen (green button, View menu, ⌃⌘F)
            DispatchQueue.main.async { NSApp.windows.forEach { $0.collectionBehavior.insert(.fullScreenPrimary) } }
        }
        .alert(errors.current.map { "Something didn't work: \($0.area)" } ?? "",
               isPresented: Binding(get: { errors.current != nil }, set: { if !$0 { errors.current = nil } })) {
            Button("Report Problem") {
                if let p = errors.current { errors.sendReport(p) }
                errors.current = nil
            }
            Button("OK", role: .cancel) { errors.current = nil }
        } message: {
            Text((errors.current?.message ?? "") + "\n\nThe app is still running. You can report this so it gets fixed.")
        }
        .onAppear {
            if let r = CrashGuard.takePendingReport() {
                ErrorCenter.shared.report(area: "Crash", message: "DMX Studio closed unexpectedly last time.", details: r)
            }
        }
    }
}

struct SongRow: View {
    @EnvironmentObject var model: AppModel
    let song: Song

    var body: some View {
        HStack {
            Image(systemName: model.playingSongID == song.id ? "speaker.wave.2.fill" : "music.note")
                .foregroundStyle(model.playingSongID == song.id ? Color.pink : Color.secondary)
                .frame(width: 18)
                // drag the note onto a set list (dragging on the name picks several songs instead)
                .onDrag { NSItemProvider(object: song.id.uuidString as NSString) }
                .help("Drag onto a set list")
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).lineLimit(1)
                if let a = song.artist, !a.isEmpty {
                    Text(a).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                if model.learningLyricsFirst(song.id) && model.learning[song.id] == nil {
                    // Learn step 1 of 2: lyrics first, then the music
                    ProgressView(value: model.lyricsProgress[song.id] ?? 0).controlSize(.small)
                    Ticking { "Learning · lyrics first (1 of 2) · " + model.lyricsCountdown(song.id) }
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                } else if let p = model.learning[song.id] {
                    ProgressView(value: p).controlSize(.small)
                    Ticking { model.learnCountdown(song.id) }.font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                } else if let a = song.analysis {
                    Text("\(Int(a.bpm.rounded())) BPM · \(song.shows.count) show\(song.shows.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.hqProgress[song.id] != nil {
                        Ticking { model.hqCountdown(song.id) }.font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                } else {
                    Text("Not learned yet").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        // small ✕ in the top-right corner while hovering
        .overlay(alignment: .topTrailing) {
            if model.hoveredSongID == song.id {
                Button { model.requestRemove(model.pickedSongs.contains(song.id) && model.pickedSongs.count > 1 ? Array(model.pickedSongs) : [song.id]) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(width: 14, height: 14).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -3)
                .help("Remove from the library")
            }
        }
    }
}

func formatTime(_ t: Double) -> String {
    let s = max(0, Int(t))
    return String(format: "%d:%02d", s / 60, s % 60)
}

/// Reads file URLs out of a drag-and-drop.
func loadDroppedURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    var urls: [URL] = []
    let lock = NSLock()
    let group = DispatchGroup()
    for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        group.enter()
        p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var u: URL?
            if let d = item as? Data { u = URL(dataRepresentation: d, relativeTo: nil) }
            else if let url = item as? URL { u = url }
            if let u { lock.lock(); urls.append(u); lock.unlock() }
            group.leave()
        }
    }
    group.notify(queue: .main) { completion(urls) }
}


/// Closing the window quits the app (music and lights stop), and quitting never hangs.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Double-clicking a .dmxsession file opens it here.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.pathExtension.lowercased() == LibraryFiles.sessionExtension {
            if let m = AppModel.current { m.importSessionFile(url) }
            else { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { AppModel.current?.importSessionFile(url) } }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Safety net: if anything below gets stuck, leave anyway after 3 seconds.
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { exit(0) }
        AppModel.current?.prepareToQuit()
        return .terminateNow
    }
}


/// Identifies the new song whose lyrics prompt is showing
struct PromptID: Identifiable { let id: UUID }
