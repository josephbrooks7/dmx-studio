import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct DMXStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

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
            }
            CommandMenu("Playback") {
                Button("Play / Pause  (Space)") { model.togglePlay() }
                Button("Stop") { model.stop() }.keyboardShortcut(".", modifiers: .command)
                Button("Next Song") { model.nextInLineup() }.keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Previous Song") { model.previousInLineup() }.keyboardShortcut(.leftArrow, modifiers: .command)
                Divider()
                Button(model.blackout ? "Release Blackout" : "Blackout") { model.blackout.toggle() }
                    .keyboardShortcut("b", modifiers: .command)
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var errors = ErrorCenter.shared

    var body: some View {
        ZStack {
            if model.showingStart {
                SessionsScreen().transition(.opacity)
            } else {
                MainShell().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.showingStart)
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
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).lineLimit(1)
                if let a = song.artist, !a.isEmpty {
                    Text(a).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                if let p = model.learning[song.id] {
                    ProgressView(value: p).controlSize(.small)
                } else if let a = song.analysis {
                    Text("\(Int(a.bpm.rounded())) BPM · \(song.shows.count) show\(song.shows.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Not learned yet").font(.caption).foregroundStyle(.orange)
                }
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
