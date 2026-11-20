import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct DMXStudioApp: App {
    @StateObject private var model = AppModel()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("DMX Studio") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1100, minHeight: 720)
                .preferredColorScheme(.dark)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.saveNow()
                    model.disconnect()
                }
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

enum SidebarItem: Hashable {
    case song(UUID)
    case lineup(UUID)
    case lights
    case wireless
    case idle
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection: SidebarItem? = .wireless
    @State private var importing = false
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                List(selection: $selection) {
                    Section("Setup") {
                        Label {
                            HStack {
                                Text("Wireless DMX")
                                Spacer()
                                Circle().fill(model.connected ? Color.green : Color.gray).frame(width: 8, height: 8)
                            }
                        } icon: { Image(systemName: "wifi") }
                        .tag(SidebarItem.wireless)
                        Label("My Lights", systemImage: "light.beacon.max").tag(SidebarItem.lights)
                        Label("Idle Look", systemImage: "moon.stars").tag(SidebarItem.idle)
                    }
                    Section("Set Lists") {
                        ForEach(model.lineups) { l in
                            Label {
                                HStack {
                                    Text(l.name)
                                    Spacer()
                                    if model.playingLineupID == l.id {
                                        Image(systemName: "speaker.wave.2.fill").foregroundStyle(.pink)
                                    }
                                    Text("\(l.entries.count)").foregroundStyle(.secondary).font(.caption)
                                }
                            } icon: { Image(systemName: "list.number") }
                            .tag(SidebarItem.lineup(l.id))
                            .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                                loadDroppedURLs(providers) { urls in model.importSongs(urls, into: l.id) }
                                return true
                            }
                            .contextMenu {
                                Button("Delete Set List", role: .destructive) {
                                    model.lineups.removeAll { $0.id == l.id }
                                }
                            }
                        }
                        Button {
                            selection = .lineup(model.newLineup())
                        } label: { Label("New Set List", systemImage: "plus") }
                        .buttonStyle(.borderless)
                    }
                    Section("Songs") {
                        ForEach(model.songs) { s in
                            SongRow(song: s).tag(SidebarItem.song(s.id))
                                .contextMenu {
                                    Button("Learn Again") { model.learn(s.id) }
                                    Menu("Add to Set List") {
                                        ForEach(model.lineups) { l in
                                            Button(l.name) { model.addToLineup(l.id, songID: s.id, showID: s.activeShow?.id) }
                                        }
                                    }
                                    if let a = s.artist, !a.isEmpty {
                                        Button("Create Set List for \(a)") { selection = .lineup(model.createSetList(forArtist: a)) }
                                    }
                                    Divider()
                                    Button("Remove Song", role: .destructive) { model.removeSong(s.id) }
                                }
                        }
                        Button { importing = true } label: { Label("Add Songs…", systemImage: "plus") }
                            .buttonStyle(.borderless)
                        Text("Or drag WAV / MP3 files or a folder here")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
                    loadDroppedURLs(providers) { urls in
                        let ids = model.importSongs(urls)
                        if let last = ids.last { selection = .song(last) }
                    }
                    return true
                }
                .overlay(dropTargeted ? RoundedRectangle(cornerRadius: 8).stroke(Color.pink, lineWidth: 3).padding(4) : nil)
                .listStyle(.sidebar)
                .frame(width: 260)
                Divider()
                Group {
                    switch selection {
                    case .song(let id): SongView(songID: id).id(id)
                    case .lineup(let id): LineupView(lineupID: id).id(id)
                    case .lights: LightsView()
                    case .idle: IdleView()
                    case .wireless, .none: WirelessView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            TransportBar()
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .mp3, .wav, .folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                let ids = model.importSongs(urls)
                if let last = ids.last { selection = .song(last) }
            }
        }
        .onChange(of: selection) { sel in
            if case .song(let id) = sel { model.selectedSongID = id }
        }
        .alert("Heads up", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("OK") { model.alert = nil }
        } message: {
            Text(model.alert ?? "")
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
