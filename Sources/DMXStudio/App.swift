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
                let a = try AudioAnalyzer.analyze(url: URL(fileURLWithPath: args[i + 1])) { p in
                    print("progress=\(p)"); fflush(stdout)
                }
                try JSONEncoder().encode(a).write(to: URL(fileURLWithPath: args[i + 2]))
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
            let a = try AudioAnalyzer.analyze(url: url) { _ in }
            let show = ShowGenerator.generate(a, style: a.suggestedStyle, variation: 1)
            print("title=\(meta.title) artist=\(meta.artist ?? "-")")
            print(String(format: "duration=%.2f bpm=%.2f beats=%d downbeat=%d kicks=%d snares=%d hats=%d",
                         a.duration, a.bpm, a.beats.count, a.downbeatOffset, a.kicks.count, a.snares.count, a.hats.count))
            print("snareTimes=" + a.snares.map { String(format: "%.3f", $0) }.joined(separator: ","))
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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Safety net: if anything below gets stuck, leave anyway after 3 seconds.
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { exit(0) }
        AppModel.current?.prepareToQuit()
        return .terminateNow
    }
}
