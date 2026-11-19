import Foundation
import AVFoundation
import SwiftUI
import AppKit

struct Library: Codable {
    var fixtures: [Fixture] = []
    var songs: [Song] = []
    var lineups: [Lineup] = []
    var output = OutputSettings()
    var idle = IdleLook()
    var globalLatencyMs: Double = 0
}

enum TestMode: String, CaseIterable, Identifiable {
    case off = "Off"
    case white = "All White"
    case rainbow = "Rainbow Check"
    case identify = "Identify Fixture"
    var id: String { rawValue }
}

final class AppModel: ObservableObject {
    // Saved
    @Published var fixtures: [Fixture] = [] { didSet { scheduleSave() } }
    @Published var songs: [Song] = [] { didSet { scheduleSave() } }
    @Published var output = OutputSettings() { didSet { scheduleSave() } }
    @Published var lineups: [Lineup] = [] { didSet { scheduleSave() } }
    @Published var idle = IdleLook() { didSet { scheduleSave() } }
    @Published var globalLatencyMs: Double = 0 { didSet { scheduleSave() } }

    // Live
    @Published var selectedSongID: UUID?
    @Published var playingSongID: UUID?
    @Published var playingShowID: UUID?
    @Published var playingLineupID: UUID?
    @Published var playingEntryIndex: Int?
    @Published var inGap = false          // waiting between lineup songs
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var learning: [UUID: Double] = [:]
    @Published var preview: [RenderedFixture] = []
    @Published var master: Double = 1
    @Published var blackout = false
    @Published var testMode: TestMode = .off
    @Published var identifyFixtureID: UUID?
    @Published var connected = false
    @Published var statusMessage = "Not connected"
    @Published var discoveredNodes: [ArtNetNode] = []   // everything seen this session
    @Published var searchingNodes = false
    @Published var lastScan: Date?
    @Published var alert: String?

    let engine = DMXEngine()
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var saveWork: DispatchWorkItem?
    private var loading = true
    private var tickCount = 0
    private var gapWork: DispatchWorkItem?
    private var scanTimer: Timer?
    private var keyMonitor: Any?
    private var idleBlend: Double = 1     // 1 = fully idle look; ramps for smooth starts/stops

    private static var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DMX Studio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }

    init() {
        load()
        engine.onError = { [weak self] msg in
            self?.statusMessage = "Output error: \(msg)"
        }
        timer = Timer(timeInterval: 1.0 / 40.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        if output.autoConnect { connect(quiet: true) }
        // Bluetooth-style background scanning for wireless DMX devices
        scanTimer = Timer(timeInterval: 8, repeats: true) { [weak self] _ in
            guard let self, self.output.autoScan else { return }
            self.findNodes()
        }
        RunLoop.main.add(scanTimer!, forMode: .common)
        findNodes()

        // Space bar = play/pause, except while typing in a text field
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            let mods = e.modifierFlags.intersection([.command, .option, .control])
            if e.keyCode == 49 && mods.isEmpty && !(NSApp.keyWindow?.firstResponder is NSText) {
                self.togglePlay()
                return nil
            }
            return e
        }
    }

    // MARK: - Persistence

    private func load() {
        defer { loading = false }
        guard let data = try? Data(contentsOf: Self.storeURL),
              let lib = try? JSONDecoder().decode(Library.self, from: data) else {
            // First launch: start with your SHEHDS beam bar already added.
            fixtures = [Fixture(name: "Beam Bar 1", address: 1,
                                profileName: FixtureProfile.shehdsBeam38.name,
                                layout: FixtureProfile.shehdsBeam38.layout)]
            output.kind = .artNet
            lineups = [Lineup(name: "My Lineup")]
            return
        }
        fixtures = lib.fixtures
        songs = lib.songs
        lineups = lib.lineups.isEmpty ? [Lineup(name: "My Lineup")] : lib.lineups
        output = lib.output
        idle = lib.idle
        globalLatencyMs = lib.globalLatencyMs
        selectedSongID = songs.first?.id
    }

    private func scheduleSave() {
        guard !loading else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    func saveNow() {
        let lib = Library(fixtures: fixtures, songs: songs, lineups: lineups, output: output,
                          idle: idle, globalLatencyMs: globalLatencyMs)
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(lib) {
                try? data.write(to: Self.storeURL, options: .atomic)
            }
        }
    }

    // MARK: - Output

    func connect(quiet: Bool = false) {
        do {
            if output.kind != .artNet && output.serialPath.isEmpty {
                throw DMXError.openFailed("choose a USB port first")
            }
            try engine.connect(output)
            connected = true
            switch output.kind {
            case .artNet: statusMessage = "Sending Art-Net to \(output.artNetIP), universe \(output.artNetUniverse)"
            default: statusMessage = "Connected to \(output.serialPath)"
            }
        } catch {
            connected = false
            statusMessage = error.localizedDescription
            if !quiet { alert = error.localizedDescription }
        }
    }

    func disconnect() {
        engine.disconnect()
        connected = false
        statusMessage = "Not connected"
    }

    /// Scans the Wi-Fi/network for Art-Net devices (PKnight and others).
    func findNodes() {
        guard !searchingNodes else { return }
        searchingNodes = true
        DispatchQueue.global(qos: .utility).async {
            let nodes = ArtNetDiscovery.discover(timeout: 1.5)
            DispatchQueue.main.async { self.mergeScan(nodes) }
        }
    }

    private func mergeScan(_ nodes: [ArtNetNode]) {
        searchingNodes = false
        lastScan = Date()
        for n in nodes {
            if let i = discoveredNodes.firstIndex(where: { $0.id == n.id }) { discoveredNodes[i] = n }
            else { discoveredNodes.append(n) }
        }
        discoveredNodes.sort { $0.name < $1.name }

        // Reconnect to the remembered device, following it if its IP changed
        if let saved = output.rememberedDevice,
           let match = nodes.first(where: { (!saved.mac.isEmpty && $0.mac == saved.mac) || $0.ip == saved.ip }) {
            if match.ip != output.artNetIP || !connected {
                output.artNetIP = match.ip
                output.rememberedDevice = match
                if output.kind == .artNet { connect(quiet: true) }
            }
        } else if output.rememberedDevice == nil && nodes.count == 1 && output.kind == .artNet && !connected {
            // First time with exactly one device around: pair with it automatically
            useNode(nodes[0])
        }
    }

    func isOnline(_ node: ArtNetNode) -> Bool {
        Date().timeIntervalSince(node.lastSeen) < 25
    }

    func isCurrentDevice(_ node: ArtNetNode) -> Bool {
        connected && output.kind == .artNet && output.artNetIP == node.ip
    }

    func useNode(_ node: ArtNetNode) {
        output.kind = .artNet
        output.artNetIP = node.ip
        output.rememberedDevice = node
        connect()
    }

    func forgetDevice() {
        output.rememberedDevice = nil
        disconnect()
    }

    // MARK: - Fixtures

    var nextFreeAddress: Int {
        (fixtures.map { $0.lastAddress }.max() ?? 0) + 1
    }

    func addFixture(profile: FixtureProfile) {
        let count = fixtures.filter { $0.profileName == profile.name }.count
        let base = profile.name.hasPrefix("SHEHDS") ? "Beam Bar" : (profile.name.contains("Followspot") ? "Followspot" : "Light")
        fixtures.append(Fixture(name: "\(base) \(count + 1)", address: min(nextFreeAddress, 512),
                                profileName: profile.name, layout: profile.layout))
    }

    func addressConflicts(for fx: Fixture) -> [Fixture] {
        fixtures.filter { $0.id != fx.id && $0.address <= fx.lastAddress && fx.address <= $0.lastAddress }
    }

    // MARK: - Songs

    func importSongs(_ urls: [URL]) {
        for url in urls {
            let title = url.deletingPathExtension().lastPathComponent
            let song = Song(title: title, path: url.path)
            songs.append(song)
            selectedSongID = song.id
            learn(song.id)
        }
    }

    func index(of id: UUID?) -> Int? {
        guard let id else { return nil }
        return songs.firstIndex { $0.id == id }
    }

    /// Listens to the song and learns its structure. Creates a first show automatically.
    func learn(_ id: UUID) {
        guard let i = index(of: id), learning[id] == nil else { return }
        let url = songs[i].url
        learning[id] = 0
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let analysis = try AudioAnalyzer.analyze(url: url) { p in
                    DispatchQueue.main.async { if self.learning[id] != nil { self.learning[id] = p } }
                }
                DispatchQueue.main.async {
                    self.learning[id] = nil
                    guard let i = self.index(of: id) else { return }
                    self.songs[i].analysis = analysis
                    if self.songs[i].shows.isEmpty { self.createShow(for: id) }
                }
            } catch {
                DispatchQueue.main.async {
                    self.learning[id] = nil
                    self.alert = "Couldn't learn \"\(url.lastPathComponent)\": \(error.localizedDescription)"
                }
            }
        }
    }

    /// Builds a new light show from what was learned, using the song's genre (or the one passed in).
    func createShow(for id: UUID, style: ShowStyle? = nil) {
        guard let i = index(of: id), let a = songs[i].analysis else { return }
        let st = style ?? songs[i].effectiveGenre
        let variation = (songs[i].shows.filter { $0.style == st }.map(\.variation).max() ?? 0) + 1
        let name = variation == 1 ? "\(st.rawValue)" : "\(st.rawValue) #\(variation)"
        let show = LightShow(name: name, style: st, variation: variation,
                             sections: ShowGenerator.generate(a, style: st, variation: variation))
        songs[i].shows.append(show)
        songs[i].activeShowID = show.id
    }

    func deleteShow(songID: UUID, showID: UUID) {
        guard let i = index(of: songID) else { return }
        songs[i].shows.removeAll { $0.id == showID }
        if songs[i].activeShowID == showID { songs[i].activeShowID = songs[i].shows.first?.id }
    }

    func duplicateShow(songID: UUID, showID: UUID) {
        guard let i = index(of: songID), var s = songs[i].shows.first(where: { $0.id == showID }) else { return }
        s.id = UUID()
        s.name += " copy"
        s.sections = s.sections.map { var x = $0; x.id = UUID(); return x }
        songs[i].shows.append(s)
        songs[i].activeShowID = s.id
    }

    func removeSong(_ id: UUID) {
        if playingSongID == id { stop() }
        songs.removeAll { $0.id == id }
        for i in lineups.indices { lineups[i].entries.removeAll { $0.songID == id } }
        if selectedSongID == id { selectedSongID = songs.first?.id }
    }

    // MARK: - Lineups

    func lineupIndex(_ id: UUID?) -> Int? {
        guard let id else { return nil }
        return lineups.firstIndex { $0.id == id }
    }

    func addToLineup(_ lineupID: UUID, songID: UUID, showID: UUID?) {
        guard let li = lineupIndex(lineupID) else { return }
        lineups[li].entries.append(LineupEntry(songID: songID, showID: showID))
    }

    func newLineup() -> UUID {
        let l = Lineup(name: "Lineup \(lineups.count + 1)")
        lineups.append(l)
        return l.id
    }

    func song(_ id: UUID) -> Song? { songs.first { $0.id == id } }

    /// Plays a whole lineup from the given entry: music + lights, then the next song automatically.
    func playLineup(_ id: UUID, from entry: Int = 0) {
        guard let li = lineupIndex(id), lineups[li].entries.indices.contains(entry) else { stop(); return }
        let e = lineups[li].entries[entry]
        guard song(e.songID) != nil else { playLineup(id, from: entry + 1); return }
        play(e.songID, show: e.showID, from: 0, keepLineup: true)
        playingLineupID = id
        playingEntryIndex = entry
    }

    func nextInLineup() {
        guard let lid = playingLineupID, let idx = playingEntryIndex else { return }
        cancelGap()
        playLineup(lid, from: idx + 1)
    }

    func previousInLineup() {
        guard let lid = playingLineupID, let idx = playingEntryIndex else { return }
        cancelGap()
        playLineup(lid, from: max(0, idx - 1))
    }

    private func cancelGap() { gapWork?.cancel(); gapWork = nil; inGap = false }

    // MARK: - Transport (music + lights start together)

    func play(_ id: UUID, show: UUID? = nil, from start: Double? = nil, keepLineup: Bool = false) {
        guard let i = index(of: id) else { return }
        cancelGap()
        if !keepLineup { playingLineupID = nil; playingEntryIndex = nil }
        if playingSongID != id || player == nil {
            player?.stop()
            do {
                let p = try AVAudioPlayer(contentsOf: songs[i].url)
                p.prepareToPlay()
                player = p
            } catch {
                alert = "Couldn't play \(songs[i].title): \(error.localizedDescription)"
                return
            }
            playingSongID = id
        }
        playingShowID = show ?? songs[i].activeShow?.id
        if let start { player?.currentTime = start }
        testMode = .off
        player?.play()
        isPlaying = true
    }

    func togglePlay() {
        if isPlaying { pause(); return }
        if let id = playingSongID, player != nil { play(id, show: playingShowID, keepLineup: playingLineupID != nil); return }
        if let id = selectedSongID { play(id, from: 0) }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        cancelGap()
        player?.stop()
        player = nil
        isPlaying = false
        playingSongID = nil
        playingShowID = nil
        playingLineupID = nil
        playingEntryIndex = nil
        currentTime = 0
    }

    func seek(to t: Double) {
        guard let p = player else { return }
        p.currentTime = max(0, min(t, p.duration))
        currentTime = p.currentTime
    }

    private func songFinished() {
        player?.stop()
        player = nil
        isPlaying = false
        let lineup = playingLineupID, idx = playingEntryIndex
        playingSongID = nil
        playingShowID = nil
        currentTime = 0
        guard let lineup, let idx, let li = lineupIndex(lineup) else { playingLineupID = nil; playingEntryIndex = nil; return }
        if idx + 1 >= lineups[li].entries.count {
            playingLineupID = nil; playingEntryIndex = nil
            return
        }
        // Idle look during the gap, then the next song
        inGap = true
        playingEntryIndex = idx + 1
        let work = DispatchWorkItem { [weak self] in
            self?.inGap = false
            self?.playLineup(lineup, from: idx + 1)
        }
        gapWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + lineups[li].gapSeconds, execute: work)
    }

    // MARK: - Frame loop (40 Hz)

    private func tick() {
        let now = Date().timeIntervalSinceReferenceDate
        var rendered: [RenderedFixture]
        var t: Double = now

        if testMode != .off {
            rendered = testFrame(now)
        } else {
            let idleFrame = idle.render(fixtures: fixtures, time: now)
            var showFrame: [RenderedFixture]? = nil

            if let id = playingSongID, let i = index(of: id), let p = player {
                currentTime = p.currentTime
                if isPlaying && !p.isPlaying {
                    songFinished()
                    return
                }
                let showID = playingShowID ?? songs[i].activeShow?.id
                if let a = songs[i].analysis, let show = songs[i].shows.first(where: { $0.id == showID }) ?? songs[i].activeShow {
                    t = p.currentTime + (songs[i].syncOffsetMs + globalLatencyMs) / 1000
                    var r = ShowRenderer(analysis: a, sections: show.sections, fixtures: fixtures)
                    r.idle = idle
                    showFrame = r.renderWithIdle(at: t)
                }
            }

            // Smoothly ramp between show and idle when a song starts, pauses or stops
            let target: Double = (showFrame != nil && isPlaying) ? 0 : 1
            let step = 1.0 / (40 * 0.8)   // ~0.8 s fade
            if idleBlend < target { idleBlend = min(target, idleBlend + step) }
            if idleBlend > target { idleBlend = max(target, idleBlend - step * 4) } // come in fast on play
            if let showFrame {
                rendered = blendRendered(showFrame, idleFrame, idleBlend)
            } else {
                rendered = idleFrame
                idleBlend = 1
            }
        }

        let frame = DMXMapper.frame(fixtures: fixtures, rendered: rendered, master: master, blackout: blackout, time: t)
        engine.setFrame(frame)

        tickCount += 1
        if tickCount % 2 == 0 && rendered != preview { preview = rendered }
    }

    private func testFrame(_ t: Double) -> [RenderedFixture] {
        var p = 0
        let total = max(1, fixtures.reduce(0) { $0 + $1.headCount })
        return fixtures.map { fx in
            var heads: [FixtureState] = []
            for _ in 0..<fx.headCount {
                switch testMode {
                case .white:
                    heads.append(FixtureState(intensity: 1, color: .white))
                case .rainbow:
                    heads.append(FixtureState(intensity: 1, color: RGB(h: t * 0.2 + Double(p) / Double(total), s: 1, v: 1)))
                case .identify:
                    let on = fx.id == identifyFixtureID && Int(t * 3) % 2 == 0
                    heads.append(FixtureState(intensity: on ? 1 : 0, color: .white))
                case .off:
                    heads.append(.off)
                }
                p += 1
            }
            var rf = RenderedFixture(heads: heads)
            if testMode == .rainbow { rf.tilt = 0.5 + 0.3 * sin(t) }
            return rf
        }
    }
}
