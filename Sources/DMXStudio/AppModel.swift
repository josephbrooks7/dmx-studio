import Foundation
import AVFoundation
import SwiftUI
import AppKit
import MediaPlayer
import Network

struct Library: Codable {
    var fixtures: [Fixture] = []
    var songs: [Song] = []
    var lineups: [Lineup] = []
    var output = OutputSettings()
    var idle = IdleLook()
    var globalLatencyMs: Double = 0
    var rigMode: RigMode? = nil
    var sessions: [Session]? = nil
    var lastSessionID: UUID? = nil
    var chainedBarsFix: Bool? = nil   // one-time: Beam Bar 2 moved to A.001 to match the real rig

    init(fixtures: [Fixture] = [], songs: [Song] = [], lineups: [Lineup] = [], output: OutputSettings = OutputSettings(),
         idle: IdleLook = IdleLook(), globalLatencyMs: Double = 0, rigMode: RigMode? = nil, sessions: [Session]? = nil,
         lastSessionID: UUID? = nil, chainedBarsFix: Bool? = nil) {
        self.fixtures = fixtures; self.songs = songs; self.lineups = lineups; self.output = output; self.idle = idle
        self.globalLatencyMs = globalLatencyMs; self.rigMode = rigMode; self.sessions = sessions
        self.lastSessionID = lastSessionID; self.chainedBarsFix = chainedBarsFix
    }

    /// Forgiving: one damaged song or session is skipped instead of losing the whole library.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fixtures = (try? c.decodeIfPresent([Lossy<Fixture>].self, forKey: .fixtures))?.compactMap(\.value) ?? []
        songs = (try? c.decodeIfPresent([Lossy<Song>].self, forKey: .songs))?.compactMap(\.value) ?? []
        lineups = (try? c.decodeIfPresent([Lossy<Lineup>].self, forKey: .lineups))?.compactMap(\.value) ?? []
        output = (try? c.decodeIfPresent(OutputSettings.self, forKey: .output)) ?? OutputSettings()
        idle = (try? c.decodeIfPresent(IdleLook.self, forKey: .idle)) ?? IdleLook()
        globalLatencyMs = (try? c.decodeIfPresent(Double.self, forKey: .globalLatencyMs)) ?? 0
        rigMode = try? c.decodeIfPresent(RigMode.self, forKey: .rigMode)
        sessions = (try? c.decodeIfPresent([Lossy<Session>].self, forKey: .sessions))?.compactMap(\.value)
        lastSessionID = try? c.decodeIfPresent(UUID.self, forKey: .lastSessionID)
        chainedBarsFix = try? c.decodeIfPresent(Bool.self, forKey: .chainedBarsFix)
    }

    /// JSON that never refuses a value (an odd number in one song can't block saving everything).
    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return e
    }
    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return d
    }
}

/// Decodes a value, or nil if that one item is damaged.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

enum TestMode: String, CaseIterable, Identifiable {
    case off = "Off"
    case white = "All White"
    case rainbow = "Rainbow Check"
    case identify = "Identify Fixture"
    case beamTest = "Beam Test"     // one light (and its linked twins): every beam a different color
    case tiltTest = "Tilt Test"     // all moving lights swing end to end, white
    var id: String { rawValue }
}

final class AppModel: ObservableObject {
    // Saved
    @Published var fixtures: [Fixture] = [] { didSet { scheduleSave(); rememberDevices() } }
    /// Devices you've set up, kept across sessions (Device Library)
    @Published var deviceLibrary: [Fixture] = DeviceLibrary.load()
    @Published var showDeviceLibrary = false
    @Published var showHueSetup = false
    @Published var showVideoExport = false

    /// Mount every beam bar the same way (floor / upright on truss legs / hanging) to compare setups
    func stageScenario(_ m: StageMount) {
        for k in stage.items.indices {
            guard let fid = stage.items[k].fixtureID, let fx = fixtures.first(where: { $0.id == fid }), fx.headCount > 1 else { continue }
            switch m {
            case .upright: stage.items[k].upright = true; stage.items[k].hanging = false; stage.items[k].y = 1.2
            case .hanging: stage.items[k].upright = nil; stage.items[k].hanging = true; stage.items[k].y = 3.3
            default: stage.items[k].upright = nil; stage.items[k].hanging = false; stage.items[k].y = 0.6
            }
            syncMount(stage.items[k].id)
        }
    }

    /// A light's 3D mounting also sets how the flat previews draw it
    func syncMount(_ itemID: UUID) {
        guard let item = stage.items.first(where: { $0.id == itemID }), let fid = item.fixtureID,
              let i = fixtures.firstIndex(where: { $0.id == fid }) else { return }
        fixtures[i].stageMount = item.upright == true ? .upright : (item.hanging ? .hanging : .floor)
    }
    @Published var songs: [Song] = [] { didSet { scheduleSave(); recordShowUndo(oldValue) } }

    // MARK: Undo / redo for light show edits (⌘Z / ⇧⌘Z)

    private struct ShowUndo { let songID: UUID; let shows: [LightShow] }
    private var undoStack: [ShowUndo] = [], redoStack: [ShowUndo] = []
    private var undoing = false
    private var lastUndoPush = Date.distantPast
    private var lastUndoSong: UUID?

    /// Keeps the shows as they were before each change (a drag counts as one change)
    private func recordShowUndo(_ old: [Song]) {
        guard !undoing, !loading else { return }
        let before = Dictionary(old.map { ($0.id, $0.shows) }, uniquingKeysWith: { a, _ in a })
        for s in songs {
            guard let prev = before[s.id], prev != s.shows else { continue }
            // changes within half a second on the same song (dragging an edge) are one step
            if lastUndoSong == s.id && Date().timeIntervalSince(lastUndoPush) < 0.5 { lastUndoPush = Date(); continue }
            undoStack.append(ShowUndo(songID: s.id, shows: prev))
            if undoStack.count > 200 { undoStack.removeFirst() }
            redoStack.removeAll()
            lastUndoPush = Date(); lastUndoSong = s.id
        }
    }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func undo() {
        if NSApp.keyWindow?.firstResponder is NSText { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil); return }
        guard let u = undoStack.popLast(), let i = index(of: u.songID) else { return }
        redoStack.append(ShowUndo(songID: u.songID, shows: songs[i].shows))
        undoing = true; songs[i].shows = u.shows; undoing = false
        lastUndoSong = nil
    }
    func redo() {
        if NSApp.keyWindow?.firstResponder is NSText { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil); return }
        guard let r = redoStack.popLast(), let i = index(of: r.songID) else { return }
        undoStack.append(ShowUndo(songID: r.songID, shows: songs[i].shows))
        undoing = true; songs[i].shows = r.shows; undoing = false
        lastUndoSong = nil
    }
    @Published var output = OutputSettings() { didSet { scheduleSave() } }
    @Published var lineups: [Lineup] = [] { didSet { scheduleSave() } }
    @Published var idle = IdleLook() { didSet { scheduleSave() } }
    @Published var globalLatencyMs: Double = 0 { didSet { scheduleSave() } }
    @Published var rigMode: RigMode = .together { didSet { scheduleSave() } }
    @Published var presets: [LookPreset] = LookPreset.defaults { didSet { scheduleSave() } }
    @Published var sessions: [Session] = [] { didSet { scheduleSave() } }
    @Published var currentSessionID: UUID?
    @Published var showingStart = true           // the black Sessions screen

    // Live looks and beat tracking
    @Published var activePresetID: UUID?
    private var presetStart: Double = 0
    @Published var beatSource: BeatSource = .manual { didSet { beatSourceChanged(oldValue) } }
    // MIDI (see Midi.swift)
    @Published var midiDevices: [String] = []
    @Published var midiBindings: [String: MIDIBinding] = [:]
    @Published var midiLearnTarget: String?
    @Published var lastMIDI: String?
    var midiClockSeen: Date?
    var midiClock = MIDIClockFollower()
    var midiIgnoreRelease: MIDIBinding?
    @Published var displayBPM: Double = 120
    var beatOn: Bool { get { live.beatOn } set { live.beatOn = newValue } }   // pulses on each beat (for the BPM light)
    var micLevel: Double { get { live.micLevel } set { live.micLevel = newValue } }
    @Published var audioInputs: [AudioInputDevice] = []
    @Published var autoLighting = false { didSet { if autoLighting && beatSource != .mic { beatSource = .mic } } }  // pick looks from what it hears
    private var autoEnergy = 0.0
    private var windowShowing = true
    private var scanTicks = 0
    var wirelessPageOpen = false
    var songsPageOpen = false
    private var lastAutoChange: Double = 0      // when Auto Lighting last switched looks
    var clock = BeatClock()
    private var tapTimes: [Double] = []
    private let mic = MicBeatTracker()
    @Published var manual: [UUID: ManualControl] = [:]   // hands-on control per light
    // starts in Preview every time: press GO LIVE to control the lights (the build's signal test starts live)
    @Published var outputEnabled = ProcessInfo.processInfo.environment["DMX_TEST_ARTNET_IP"] != nil
    @Published var packetsPerSecond = 0
    private var lastPacketCount = 0
    @Published var haze: Double = 0.6            // beam visibility in the Stage simulation
    @Published var stage = StageLayout() { didSet { scheduleSave() } }
    @Published var selectedStageItem: UUID?
    @Published var stageEditing = false
    /// Full-quality 3D (glow, smoothing, 60 fps). Off by default on Intel Macs: their graphics chips can
    /// restart the whole Mac under heavy 3D load, so the Stage view runs light there.
    @Published var stageHighQuality: Bool = UserDefaults.standard.object(forKey: "stageHighQuality") as? Bool ?? AppModel.isAppleSilicon {
        didSet { UserDefaults.standard.set(stageHighQuality, forKey: "stageHighQuality") }
    }
    static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
    @Published var stageCameraRequest: (name: String, id: UUID)? = nil

    // Live
    @Published var selectedSongID: UUID?
    @Published var playingSongID: UUID?
    @Published var playingShowID: UUID?
    @Published var playingLineupID: UUID?
    @Published var playingEntryIndex: Int?
    @Published var inGap = false          // waiting between lineup songs
    @Published var activeBlock: ActiveBlock?   // a silence or transition block in a set list is running
    @Published var cuedEntry: Int? {            // cued set: this entry is ready and waits for Space / →
        didSet { if cuedEntry != nil && oldValue == nil { cueStart = Date().timeIntervalSinceReferenceDate } }
    }
    private var cueStart: Double = 0
    private var fadingPlayer: AVAudioPlayer?   // the song fading out under a transition
    private var blockEndWork: DispatchWorkItem? // ends a transition that blends into the next song
    @Published var pauseTime: Double?           // set while paused: the moment the lights froze
    /// Master volume for all songs (0…1), remembered between launches.
    /// How much flashing the shows may use. Fast strobes are opt-in (photosensitivity safety).
    enum FlashLimit: String, CaseIterable, Identifiable {
        case none = "No Flashing", gentle = "Gentle", full = "Full Strobes"
        var id: String { rawValue }
        var hz: Double { switch self { case .none: return 0; case .gentle: return 3; case .full: return 25 } }
        var blurb: String {
            switch self {
            case .none: return "No flashing or strobing at all. Big moments swell to white instead."
            case .gentle: return "Blinder hits and strobes up to 3 flashes a second (safe for most audiences)."
            case .full: return "Fast strobes and stutters (16ths, 32nds). Can affect people with photosensitive epilepsy: warn your audience."
            }
        }
    }
    static func savedFlashLimit() -> FlashLimit {
        let f = FlashLimit(rawValue: UserDefaults.standard.string(forKey: "flashLimit") ?? "") ?? .gentle
        ShowRenderer.maxFlashHz = f.hz
        return f
    }
    @Published var flashLimit: FlashLimit = AppModel.savedFlashLimit() {
        didSet { UserDefaults.standard.set(flashLimit.rawValue, forKey: "flashLimit"); ShowRenderer.maxFlashHz = flashLimit.hz }
    }

    @Published var musicVolume: Double = UserDefaults.standard.object(forKey: "musicVolume") as? Double ?? 1 {
        didSet {
            UserDefaults.standard.set(musicVolume, forKey: "musicVolume")
            // with stems playing the main player is silent and the stems carry the sound
            if stemPlayers.isEmpty { player?.volume = Float(musicVolume) }
            else if let id = stemPlayersSong { for (name, sp) in stemPlayers { sp.volume = Float(musicVolume * stemGain(id, name)) } }
        }
    }
    /// Mute / unmute the music (the speaker icon): remembers the volume to go back to.
    func toggleMute() {
        if musicVolume > 0 {
            UserDefaults.standard.set(musicVolume, forKey: "volumeBeforeMute")
            musicVolume = 0
        } else {
            musicVolume = max(0.2, UserDefaults.standard.object(forKey: "volumeBeforeMute") as? Double ?? 1)
        }
    }
    private var pausedPresetElapsed: Double?
    private var lastSongBPM: Double = 120
    @Published var isPlaying = false { didSet { if isPlaying != oldValue { updateNowPlayingInfo() } } }
    var currentTime: Double {
        get { live.currentTime }
        set {
            if live.currentTime != newValue { live.currentTime = newValue }
            // big lists (lyrics) follow a slower clock: 4 updates a second instead of 40
            if abs(coarse.time - newValue) >= 0.25 { coarse.time = newValue }
        }
    }
    let coarse = CoarseClock()
    @Published var learning: [UUID: Double] = [:]
    var preview: [RenderedFixture] { get { live.preview } set { live.preview = newValue } }
    /// Fast-changing state (light preview, playhead, beat light, mic level) lives in its own object, so only
    /// the small views that show it redraw 20-40 times a second, not every screen of the app.
    let live = LiveState()
    @Published var master: Double = 1
    @Published var blackout = false
    @Published var flashHeld = false     // hold: everything full white
    @Published var strobeHeld = false    // hold: everything strobes
    @Published var blinderHeld = false   // full white; fades out after release
    @Published var paparazziHeld = false // camera-flash pops on random heads
    private var blinderLevel = 0.0
    private var lastLoud = 0.0
    private var breakBlend = 0.0
    /// Live with the mic / computer audio: pause effects when the music drops out (a break), resume on its return
    var musicBreak: Bool {
        get { UserDefaults.standard.object(forKey: "musicBreak") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "musicBreak"); objectWillChange.send() }
    }
    @Published var testMode: TestMode = .off
    @Published var identifyFixtureID: UUID?
    /// Opens the step-by-step light setup walkthrough (nil = closed; empty = all lights)
    @Published var setupWizardFor: [UUID]? = nil

    func beamTest(_ id: UUID?) {
        if let id { identifyFixtureID = id; testMode = .beamTest } else { testMode = .off }
    }
    @Published var connected = false
    @Published var statusMessage = "Not connected"
    @Published var discoveredNodes: [ArtNetNode] = []   // everything seen this session
    @Published var searchingNodes = false
    @Published var lastScan: Date?
    private var scanFailures = 0
    /// Setting this shows a friendly error with a Report button (it never crashes the app).
    var alert: String? {
        get { nil }
        set { if let m = newValue { ErrorCenter.shared.report(area: "DMX Studio", message: m) } }
    }

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
        AppModel.current = self
        load()
        setupMediaKeys()
        startMIDI()
        engine.onError = { [weak self] msg in
            self?.statusMessage = "Output error: \(msg)"
        }
        timer = Timer(timeInterval: 1.0 / 40.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        if output.autoConnect { connect(quiet: true) }
        syncExtraOutputs()

        // Demo/screenshot hooks used by the automated build checks
        let env = ProcessInfo.processInfo.environment
        if let ip = env["DMX_TEST_ARTNET_IP"] {
            output.kind = .artNet; output.artNetIP = ip; output.autoScan = false
            output.rememberedDevice = ArtNetNode(ip: ip, name: "Test receiver")
            connect(quiet: true)
        }
        if let path = env["DMX_DEMO_SONG"] { importSongs([URL(fileURLWithPath: path)]) }
        if env["DMX_DEMO_OPEN"] != nil, let first = sessions.first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.openSession(first.id)
                if env["DMX_DEMO_PRESET"] != nil, let p = self.presets.first { self.togglePreset(p.id) }
                if env["DMX_DEMO_SET"] != nil, let song = self.songs.first, !self.lineups.isEmpty {
                    let lid = self.lineups[0].id
                    self.lineups[0].entries = []
                    self.addToLineup(lid, songID: song.id, showID: nil)
                    self.addBlock(.transition(.buildUp), to: lid)
                    self.addToLineup(lid, songID: song.id, showID: nil)
                    self.addBlock(.silence(4), to: lid)
                    self.addBlock(.transition(.colorWash), to: lid)
                    self.addToLineup(lid, songID: song.id, showID: nil)
                }
            }
        }
        if env["DMX_TEST_LIVE_STRESS"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.startLiveStress() }
        }
        // Bluetooth-style background scanning for wireless DMX devices
        // Each scan runs a helper process, so: every 8 s on the Wireless page or while not connected,
        // otherwise once a minute (just to notice new devices).
        scanTimer = Timer(timeInterval: 8, repeats: true) { [weak self] _ in
            guard let self, self.output.autoScan else { return }
            self.scanTicks += 1
            guard self.wirelessPageOpen || !self.connected || self.scanTicks % 8 == 0 else { return }
            self.findNodes()
        }
        RunLoop.main.add(scanTimer!, forMode: .common)
        findNodes()

        // Space bar = play/pause, except while typing in a text field
        // Space = play/pause, hold F = flash, hold S = strobe (not while typing)
        // Double-click a song in the library: play it (the list's own selection handling swallows
        // SwiftUI double-tap gestures on macOS 12, so watch the clicks directly)
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] e in
            guard let self, e.clickCount == 2, self.songListHovered else { return e }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let id = self.hoveredSongID ?? self.selectedSongID, self.song(id) != nil {
                    self.selectedSongID = id
                    self.selectedEntry = nil
                    self.play(id, from: self.songStart(id))
                }
            }
            return e
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] e in
            guard let self else { return e }
            let mods = e.modifierFlags.intersection([.command, .option, .control])
            if e.keyCode == 53, e.type == .keyDown, NSApp.keyWindow?.firstResponder is NSText {
                NSApp.keyWindow?.makeFirstResponder(nil)   // Esc leaves the text box; Space plays again
                return nil
            }
            guard mods.isEmpty, !(NSApp.keyWindow?.firstResponder is NSText) else { return e }
            let down = e.type == .keyDown
            switch e.keyCode {
            case 49:
                if down && !e.isARepeat { self.togglePlay() }
                return nil
            case 3:  // F
                if self.flashHeld != down { self.flashHeld = down }
                return nil
            case 1:  // S
                if self.strobeHeld != down { self.strobeHeld = down }
                return nil
            case 124: // → = start the cued song, or the next one
                if down && !e.isARepeat { self.nextInLineup() }
                return nil
            case 123: // ← = back to the start of the song (twice: the song before)
                if down && !e.isARepeat { self.previousInLineup() }
                return nil
            case 125, 126: // ↓ / ↑ = pick the song to play next (in the set list or the library)
                if down { self.moveSelection(e.keyCode == 125 ? 1 : -1) }
                return nil
            case 51, 117: // Delete / ⌦: a selected timeline block is emptied; otherwise the picked library songs (asks first)
                if let ts = self.timelineSelection, self.songsScreenShowing {
                    if down && !e.isARepeat { self.emptySection(songID: ts.song, sectionID: ts.section) }
                    return nil
                }
                // only songs that are picked (after clicking off to deselect, Delete does nothing)
                guard self.songsScreenShowing, !self.pickedSongs.isEmpty else { return e }
                if down && !e.isARepeat { self.requestRemove(Array(self.pickedSongs)) }
                return nil
            case 47: // . = cut the selected block (or the playing one at the playhead) and leave a slot
                guard self.timelineSelection != nil || self.playingSongID != nil else { return e }
                if down && !e.isARepeat { self.splitKey() }
                return nil
            case 17: // T = tap tempo
                if down && !e.isARepeat { self.tapTempo() }
                return nil
            default:
                return e
            }
        }
    }

    // MARK: - Persistence

    private func load() {
        defer { loading = false }
        let fileThere = FileManager.default.fileExists(atPath: Self.storeURL.path)
        guard let data = try? Data(contentsOf: Self.storeURL),
              let lib = try? Library.decoder.decode(Library.self, from: data) else {
            if fileThere {
                // Never start over silently: keep the unreadable file, and rebuild from Documents/DMX Studio
                let backup = Self.storeURL.deletingLastPathComponent()
                    .appendingPathComponent("library-unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.copyItem(at: Self.storeURL, to: backup)
                let rec = LibraryFiles.recover()
                if !rec.sessions.isEmpty || !rec.songs.isEmpty {
                    songs = rec.songs
                    sessions = rec.sessions.isEmpty
                        ? [Session(name: "My First Session", fixtures: Session.standardRig(), lineups: [Lineup(name: "My Set List")])]
                        : rec.sessions
                    output.kind = .artNet
                    if let s = sessions.first { apply(s) }
                    selectedSongID = songs.first?.id
                    DispatchQueue.main.async {
                        ErrorCenter.shared.report(area: "Library", message: "Your library file couldn't be read, so DMX Studio restored \(rec.songs.count) songs and \(rec.sessions.count) sessions from Documents › DMX Studio. The old file was kept as \(backup.lastPathComponent).")
                    }
                    return
                }
            }
            // First launch: one session with your rig (two SHEHDS bars + followspot)
            output.kind = .artNet
            let first = Session(name: "My First Session", fixtures: Session.standardRig(), lineups: [Lineup(name: "My Set List")])
            sessions = [first]
            apply(first)
            return
        }
        songs = lib.songs
        output = lib.output
        globalLatencyMs = lib.globalLatencyMs
        if let saved = lib.sessions, !saved.isEmpty {
            sessions = saved
        } else {
            // First time with sessions: turn the existing setup into the first session
            sessions = [Session(name: "My First Session", fixtures: lib.fixtures.isEmpty ? Session.standardRig() : lib.fixtures,
                                lineups: lib.lineups.isEmpty ? [Lineup(name: "My Set List")] : lib.lineups,
                                presets: nil, idle: lib.idle, rigMode: lib.rigMode)]
        }
        // One-time fix: the old default put Beam Bar 2 at 39, but the real bars are chained on A.001
        if lib.chainedBarsFix == nil {
            for si in sessions.indices {
                let f = sessions[si].fixtures
                if f.contains(where: { $0.name == "Beam Bar 1" && $0.address == 1 && $0.profileName == FixtureProfile.shehdsBeam38.name }),
                   let j = f.firstIndex(where: { $0.name == "Beam Bar 2" && $0.address == 39 && $0.profileName == FixtureProfile.shehdsBeam38.name }) {
                    sessions[si].fixtures[j].address = 1
                }
            }
        }
        // Load the last session's lights so the idle look runs while you're on the Sessions screen
        let last = sessions.first { $0.id == lib.lastSessionID } ?? sessions.sorted { $0.modified > $1.modified }.first
        if let last { apply(last) }
        selectedSongID = songs.first?.id
        adoptExistingSongs()
        // One time: remake learned shows so 38CH bars use their beams separately
        if !UserDefaults.standard.bool(forKey: "showsRebuilt.perBeam6") {
            UserDefaults.standard.set(true, forKey: "showsRebuilt.perBeam6")
            DispatchQueue.main.async { self.rebuildShowsForCurrentLights() }
        }
        // Songs that were still learning when the app closed: finish learning them now
        let unlearned = songs.filter { $0.analysis == nil && FileManager.default.fileExists(atPath: $0.path) }.map(\.id)
        if !unlearned.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { for id in unlearned { self.learn(id) } }
        }
        // White accents are worked out from what was learned: refresh them with the latest rules
        for i in songs.indices where songs[i].analysis != nil { songs[i].analysis!.accents = AccentFinder.find(songs[i].analysis!) }
        // One time: relearn every song with the new song-structure detection (verse / pre-chorus /
        // chorus / bridge…) and the better vocal detection, then rebuild its shows
        if !UserDefaults.standard.bool(forKey: "relearn.structure1") {
            UserDefaults.standard.set(true, forKey: "relearn.structure1")
            let all = songs.filter { $0.analysis != nil && FileManager.default.fileExists(atPath: $0.path) }.map(\.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { for id in all { self.learn(id, rebuildShows: true) } }
        }
        // (no automatic splitting at launch: stems are only made when you ask in the Stems tab)
    }

    private func scheduleSave() {
        guard !loading else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    // MARK: - Sessions

    private func apply(_ s: Session) {
        currentSessionID = s.id
        fixtures = s.fixtures
        lineups = s.lineups.isEmpty ? [Lineup(name: "My Set List")] : s.lineups
        presets = s.presets ?? LookPreset.defaults
        trimSongLooks()
        if !presets.contains(where: { $0.effect == .soundLevel }), let fs = LookPreset.essentials.last { presets.append(fs) }
        // One time per session: add the themed looks (Fairy, EDM, Dubstep, Techno, Disco, Pop, Psychedelic…)
        for i in presets.indices where presets[i].mode == nil {
            if let d = (LookPreset.beamPack + LookPreset.barPack).first(where: { $0.name == presets[i].name }) { presets[i].mode = d.mode }
        }
        for (pack, list) in [("themes1", LookPreset.themePack), ("beams4", LookPreset.beamPack), ("bars9ch1", LookPreset.barPack),
                             ("strobes1", LookPreset.strobePack), ("colorfx1", LookPreset.colorFXPack),
                             ("movefx1", LookPreset.moveFXPack), ("beamfx1", LookPreset.beamFXPack),
                             ("risestrobe1", LookPreset.moveFXPack.filter { $0.effect == .riseStrobe })] {
            let packKey = "presetPack.\(pack).\(s.id.uuidString)"
            if !UserDefaults.standard.bool(forKey: packKey) {
                let have = Set(presets.map(\.name))
                presets += list.filter { !have.contains($0.name) }
                UserDefaults.standard.set(true, forKey: packKey)
            }
        }
        idle = s.idle
        rigMode = s.rigMode ?? .together
        stage = s.stage ?? StageLayout.starter(for: s.fixtures)
        manual = [:]
        activePresetID = nil
    }

    /// Copies what's on screen back into the current session.
    private func captureCurrentSession() {
        guard let id = currentSessionID, let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        let s = sessions[i]
        // Only write (and bump "edited") when something actually changed — avoids endless re-saving
        guard s.fixtures != fixtures || s.lineups != lineups || (s.presets ?? LookPreset.defaults) != presets
                || s.idle != idle || (s.rigMode ?? .together) != rigMode || s.stage != stage else { return }
        var updated = s
        updated.fixtures = fixtures; updated.lineups = lineups; updated.presets = presets
        updated.idle = idle; updated.rigMode = rigMode; updated.stage = stage
        updated.modified = Date()
        if !loading { sessions[i] = updated }
    }

    func openSession(_ id: UUID) {
        captureCurrentSession()
        guard let s = sessions.first(where: { $0.id == id }) else { return }
        if playingSongID != nil { stop() }
        apply(s)
        showingStart = false
        saveNow()
    }

    @discardableResult
    func newSession(name: String? = nil) -> UUID {
        captureCurrentSession()
        let n = name ?? "Session \(sessions.count + 1)"
        let s = Session(name: n, fixtures: Session.standardRig(), lineups: [Lineup(name: "My Set List")])
        sessions.append(s)
        openSession(s.id)
        // first time in a new session: walk through setting the real lights to match
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.setupWizardFor = [] }
        return s.id
    }

    func duplicateSession(_ id: UUID) {
        captureCurrentSession()
        guard var s = sessions.first(where: { $0.id == id }) else { return }
        s.id = UUID(); s.name += " copy"; s.created = Date(); s.modified = Date()
        sessions.append(s)
    }

    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if sessions.isEmpty {
            sessions = [Session(name: "My First Session", fixtures: Session.standardRig(), lineups: [Lineup(name: "My Set List")])]
        }
        if currentSessionID == id, let first = sessions.first { apply(first) }
    }

    func renameSession(_ id: UUID, to name: String) {
        if let i = sessions.firstIndex(where: { $0.id == id }) { sessions[i].name = name }
    }

    func showSessions() {
        captureCurrentSession()
        showingStart = true
        saveNow()
    }

    var currentSessionName: String { sessions.first { $0.id == currentSessionID }?.name ?? "Session" }

    // MARK: - Lights sharing an address (daisy-chained copies)

    /// Index of the light this one copies (same address + same model), or nil if it's independent.
    func copySource(of i: Int) -> Int? {
        guard i < fixtures.count else { return nil }
        let f = fixtures[i]
        return fixtures.indices.first { $0 < i && fixtures[$0].address == f.address && fixtures[$0].layout == f.layout && fixtures[$0].outputKey == f.outputKey }
    }

    // MARK: - Automated live-mode stress test (CI): does what a busy user does, fast

    private var stressTesting = false
    private var stressTimer: Timer?

    private func startLiveStress() {
        stressTesting = true
        beatSource = .mic
        autoLighting = true
        var step = 0
        let t = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            guard let self else { return }
            step += 1
            let now = Date().timeIntervalSinceReferenceDate
            let kick = step % 23 == 0                       // ~130 BPM at 50 Hz
            let loud = Float(0.2 + 0.8 * abs(sin(Double(step) / 400)))
            self.mic.injectTest(low: kick ? 0.5 * loud : 0.001, full: loud * (kick ? 1 : 0.4), at: now)
            CrashGuard.breadcrumb("Stress step \(step)")
            switch Int.random(in: 0..<60) {
            case 0: if let p = self.presets.randomElement() { self.togglePreset(p.id) }
            case 1: self.autoLighting.toggle()
            case 2: self.tapTempo(); self.beatSource = .mic
            case 3: self.flashHeld.toggle()
            case 4: self.strobeHeld.toggle()
            case 5: self.rigMode = RigMode.allCases.randomElement() ?? .together
            case 6: if let f = self.fixtures.randomElement() { self.setLightOn(f.id, Bool.random()) }
            case 7: if self.fixtures.count >= 2 {
                        let a = self.fixtures[0].id, b = self.fixtures[1].id
                        if self.isLinked(self.fixtures[0], self.fixtures[1]) { self.unlink(a, b) } else { self.link(a, b) }
                        self.linkNotice = nil
                    }
            case 8: if let f = self.fixtures.randomElement() {
                        self.setManual(f.id) { $0.dimmer = Bool.random() ? Double.random(in: 0...1) : nil; $0.color = Bool.random() ? RGB(h: Double.random(in: 0...1), s: 1, v: 1) : nil; $0.strobe = Bool.random() ? Double.random(in: 0...1) : nil }
                    }
            case 9: self.nudgeBPM(Bool.random() ? 1 : -1); self.beatSource = .mic
            case 10: self.master = Double.random(in: 0...1)
            case 11: self.blackout = Int.random(in: 0..<4) == 0
            case 12: self.manual = [:]
            case 13: self.activePresetID = nil
            default: break
            }
            if step % 1500 == 0 { print("stress: \(step) steps, preset \(self.activePresetID.flatMap { id in self.presets.first { $0.id == id }?.name } ?? "none"), bpm \(Int(self.clock.bpm))"); fflush(stdout) }
        }
        RunLoop.main.add(t, forMode: .common)
        stressTimer = t
    }

    // MARK: - Turning single lights on and off

    /// Linked lights (same address, chained with a DMX cable) turn on and off together.
    func setLightOn(_ id: UUID, _ on: Bool) {
        let ids = Set([id] + sharesAddress(id).map(\.id))
        for i in fixtures.indices where ids.contains(fixtures[i].id) { fixtures[i].off = on ? nil : true }
    }

    // MARK: - SHEHDS bar mode (must match the light's display: d.xxx = 38 ch, A.xxx = 10 ch)

    /// Switches a SHEHDS bar (and the bars linked to it) between 38-channel (each beam) and 10-channel mode.
    /// Tilt speed channel value for a bar and the bars linked to it.
    func setMoveLead(_ id: UUID, _ ms: Double) {
        let ids = Set([id] + sharesAddress(id).map(\.id))
        for i in fixtures.indices where ids.contains(fixtures[i].id) { fixtures[i].moveLeadMs = ms }
    }

    func setTiltSpeed(_ id: UUID, _ v: Double) {
        let ids = Set([id] + sharesAddress(id).map(\.id))
        for i in fixtures.indices where ids.contains(fixtures[i].id) { fixtures[i].tiltSpeed = v }
    }

    func setShehdsMode(_ id: UUID, perBeam: Bool) {
        let p = perBeam ? FixtureProfile.shehdsBeam38 : FixtureProfile.shehdsBeam9
        let ids = Set([id] + sharesAddress(id).map(\.id))
        for i in fixtures.indices where ids.contains(fixtures[i].id) && fixtures[i].isShehdsBar {
            fixtures[i].profileName = p.name
            fixtures[i].layout = p.layout
        }
        // the shows are built for what the lights can do, so remake them for the new mode
        rebuildShowsForCurrentLights()
    }

    // MARK: - Linking chained lights

    @Published var linkNotice: String?

    /// Two lights of the same model on the same device can be linked (mirrored on one address).
    func canLink(_ a: Fixture, _ b: Fixture) -> Bool { a.layout == b.layout && a.outputKey == b.outputKey }
    func isLinked(_ a: Fixture, _ b: Fixture) -> Bool { canLink(a, b) && a.address == b.address }

    func link(_ aID: UUID, _ bID: UUID) {
        guard let a = fixtures.first(where: { $0.id == aID }), let j = fixtures.firstIndex(where: { $0.id == bID }) else { return }
        fixtures[j].address = a.address
        fixtures[j].off = a.off
        linkNotice = "\(fixtures[j].name) is linked to \(a.name). They now mirror each other on \(a.displayCode).\n\nOn the real light, set \(fixtures[j].name) to \(a.displayCode) too (MENU → address → UP/DOWN → ENTER)."
    }

    func unlink(_ aID: UUID, _ bID: UUID) {
        guard let a = fixtures.first(where: { $0.id == aID }), let j = fixtures.firstIndex(where: { $0.id == bID }) else { return }
        let size = max(fixtures[j].channelCount, 1)
        func free(_ start: Int) -> Bool {
            let end = start + size - 1
            guard start >= 1, end <= 512 else { return false }
            return !fixtures.indices.contains { k in k != j && fixtures[k].address <= end && fixtures[k].lastAddress >= start }
        }
        var addr = a.lastAddress + 1
        if !free(addr) { addr = (fixtures.indices.filter { $0 != j }.map { fixtures[$0].lastAddress }.max() ?? 0) + 1 }
        guard free(addr) else {
            ErrorCenter.shared.report(area: "Lights", message: "There's no room left in the 512 channels to give \(fixtures[j].name) its own address.")
            return
        }
        fixtures[j].address = addr
        let code = fixtures[j].displayCode
        linkNotice = "\(fixtures[j].name) is unlinked and now has its own address: \(code).\n\nOn the real light, set \(fixtures[j].name) to \(code) (MENU → address → UP/DOWN → ENTER). Until you do, it keeps copying \(a.name)."
    }
    var anyLightOff: Bool { fixtures.contains { !$0.isOn } }
    func turnAllLightsOn() { for i in fixtures.indices { fixtures[i].off = nil } }

    /// Other lights on the same address as this one (they physically receive the same signal).
    func sharesAddress(_ id: UUID) -> [Fixture] {
        guard let f = fixtures.first(where: { $0.id == id }) else { return [] }
        return fixtures.filter { $0.id != id && $0.address == f.address && $0.layout == f.layout && $0.outputKey == f.outputKey }
    }

    // MARK: - 3D venue

    /// Every light in the session gets a place in the venue.
    func ensureStageItems() {
        var items = stage.items.filter { item in item.fixtureID == nil || fixtures.contains { $0.id == item.fixtureID } }
        for fx in fixtures where !items.contains(where: { $0.fixtureID == fx.id }) {
            let n = items.filter { $0.fixtureID != nil }.count
            items.append(StageItem(fixtureID: fx.id, x: Double(n % 5) * 1.0 - 2, z: -1.5 + Double(n / 5) * 0.8, y: 0.6))
        }
        if items != stage.items { stage.items = items }
    }

    func addProp(_ kind: PropKind) {
        var item = StageItem(prop: kind, x: 0, z: 1.5)
        switch kind {
        case .truss: item.size = 3; item.y = 3
        case .trussTower: item.size = 3.5
        case .lightStand: item.size = 2.2
        case .micStand, .performer: item.z = 0
        default: break
        }
        stage.items.append(item)
        selectedStageItem = item.id
    }

    func addStageLight(_ profile: FixtureProfile) {
        addFixture(profile: profile)
        ensureStageItems()
        if let fx = fixtures.last, let i = stage.items.firstIndex(where: { $0.fixtureID == fx.id }) {
            stage.items[i].x = 0; stage.items[i].z = 0.5; stage.items[i].y = 0.6
            selectedStageItem = stage.items[i].id
        }
    }

    func updateStageItem(_ id: UUID, _ change: (inout StageItem) -> Void) {
        guard let i = stage.items.firstIndex(where: { $0.id == id }) else { return }
        change(&stage.items[i])
    }

    func deleteStageItem(_ id: UUID) {
        guard let item = stage.items.first(where: { $0.id == id }) else { return }
        if let fid = item.fixtureID {
            fixtures.removeAll { $0.id == fid }    // removing a light from the venue removes it from the session
        }
        stage.items.removeAll { $0.id == id }
        selectedStageItem = nil
    }

    // MARK: - Live looks & beat

    /// Channel modes in use by SHEHDS bars that are on ("38CH", "9CH").
    var activeModes: Set<String> { Set(fixtures.filter { $0.isOn && $0.isShehdsBar }.map(\.modeLabel)) }

    /// Presets grouped by theme, in a fixed order. Looks made for a channel mode only show when a light is in
    /// that mode (38CH looks need separate beams; 9CH looks are for whole bars).
    var presetGroups: [(name: String, presets: [LookPreset])] {
        let modes = activeModes
        let usable = presets.filter { p in
            guard let m = p.mode else { return true }
            return modes.isEmpty ? m == "38CH" : modes.contains(m)
        }
        var order = LookPreset.groupOrder
        for p in usable { let g = p.group ?? "Essentials"; if !order.contains(g) { order.append(g) } }
        return order.compactMap { g in
            let list = usable.filter { ($0.group ?? "Essentials") == g }
            return list.isEmpty ? nil : (g, list)
        }
    }

    /// The lights a new show is programmed for, in words (also stored on the show).
    var rigDescription: String {
        fixtures.filter { $0.isOn && $0.effectiveBehavior == .sequence }.map { "\($0.name) · \($0.modeLabel)" }.joined(separator: ", ")
    }

    /// Remakes one song's shows for the lights and channel modes in use now.
    func rebuildShows(for songID: UUID) {
        guard let i = index(of: songID), let a = songs[i].analysis else { return }
        let onLights = fixtures.filter { $0.isOn }
        for j in songs[i].shows.indices {
            var secs = ShowGenerator.generateShaped(a, peak: songs[i].peakGenre ?? a.suggestedPeakStyle, style: songs[i].shows[j].style, variation: songs[i].shows[j].variation, design: songs[i].shows[j].design)
            if useLibraryInShows { ShowGenerator.enrich(&secs, a, presets: presets, variation: songs[i].shows[j].variation, lyrics: songs[i].lyrics) } else { ShowGenerator.learnedRules(&secs, a, variation: songs[i].shows[j].variation, lyrics: songs[i].lyrics) }
            ShowGenerator.fit(&secs, to: onLights.filter { $0.effectiveBehavior == .sequence })
            songs[i].shows[j].sections = secs
            songs[i].shows[j].fixtureIDs = onLights.isEmpty ? nil : onLights.map(\.id)
            songs[i].shows[j].builtFor = rigDescription
        }
    }

    /// Strobe / blinder pads: on only while held, then whatever was running before comes back
    private var heldPresetID: UUID?
    private var presetBeforeHold: UUID?
    // MARK: Record to show: holding a pad while a song plays writes that look into its show
    @Published var recordToShow = false
    @Published var recordNote: String?
    private var recStart: (preset: UUID, song: UUID, t: Double)?
    /// Where the playing song's show is right now (same timing the lights use)
    var showTimeNow: Double? {
        guard let id = playingSongID, let i = index(of: id) else { return nil }
        return currentTime + (songs[i].syncOffsetMs + globalLatencyMs) / 1000
    }

    /// Put a look into a song's show from `a` to `b` (seconds), replacing what was there. Undo with ⌘Z.
    func writeLook(_ p: LookPreset, songID: UUID, from a0: Double, to b0: Double) {
        guard let i = index(of: songID), let si = songs[i].activeShowIndex else { return }
        // land on the beat when it's close (a human press is a little early or late)
        func snap(_ t: Double) -> Double {
            guard let beats = songs[i].analysis?.beats, let n = beats.min(by: { abs($0 - t) < abs($1 - t) }), abs(n - t) < 0.12 else { return t }
            return n
        }
        var a = snap(a0), b = snap(b0)
        guard b - a >= 0.25 else { return }
        var secs = songs[i].shows[si].sections
        guard let template = secs.first(where: { $0.start <= a && a < $0.end }) ?? secs.first(where: { $0.start < b && b <= $0.end }) else { return }
        var out: [ShowSection] = []
        for s in secs {
            if s.end <= a || s.start >= b { out.append(s); continue }
            if s.start < a {
                if a - s.start >= 0.2 { var left = s; left.end = a; out.append(left) } else { a = s.start }
            }
            if s.end > b {
                if s.end - b >= 0.2 { var right = s; right.id = UUID(); right.start = b; right.accentStrobe = false; out.append(right) } else { b = s.end }
            }
        }
        var n = template
        n.id = UUID(); n.start = a; n.end = b
        n.name = p.name
        n.effect = p.effect; n.palette = p.palette; n.movement = p.movement; n.rate = p.rate; n.intensity = p.intensity
        n.colorShift = nil; n.empty = nil; n.transition = nil; n.accentStrobe = false
        out.append(n)
        secs = out.sorted { $0.start < $1.start }
        songs[i].shows[si].sections = secs
        recordNote = "Wrote \(p.name) into \(songs[i].title) at \(formatTime(a))–\(formatTime(b)) · ⌘Z to undo"
    }

    func holdPreset(_ id: UUID) {
        if recordToShow, let song = playingSongID, let t = showTimeNow { recStart = (id, song, t) }
        if pauseTime != nil && playingSongID == nil && activeBlock == nil { resumeFromPause() }
        if heldPresetID == nil { presetBeforeHold = activePresetID }
        heldPresetID = id
        activePresetID = id
        presetStart = Date().timeIntervalSinceReferenceDate
        testMode = .off
    }
    func releasePreset(_ id: UUID) {
        guard heldPresetID == id else { return }
        if let r = recStart, r.preset == id, playingSongID == r.song, let t = showTimeNow, t > r.t,
           let p = presets.first(where: { $0.id == id }) {
            writeLook(p, songID: r.song, from: r.t, to: t)
        }
        recStart = nil
        heldPresetID = nil
        activePresetID = presetBeforeHold
        presetBeforeHold = nil
    }

    /// Show page: play a look through once (one 4-bar cycle at the current tempo), then back to the show.
    /// Tapping it again stops it early.
    private var previewToken = UUID()
    func previewPresetOnce(_ id: UUID) {
        if activePresetID == id { activePresetID = nil; return }
        togglePreset(id)
        let token = UUID(); previewToken = token
        let secs = min(12, max(4, 16 * 60 / max(clock.bpm, 40)))
        DispatchQueue.main.asyncAfter(deadline: .now() + secs) { [weak self] in
            guard let self, self.previewToken == token, self.activePresetID == id else { return }
            self.activePresetID = nil
        }
    }

    func togglePreset(_ id: UUID) {
        if pauseTime != nil && playingSongID == nil && activeBlock == nil { resumeFromPause() }
        if activePresetID == id { activePresetID = nil; return }
        activePresetID = id
        if presets.first(where: { $0.id == id })?.effect == .soundLevel && beatSource != .mic { beatSource = .mic }
        presetStart = Date().timeIntervalSinceReferenceDate
        testMode = .off
    }

    func tapTempo() {
        let now = Date().timeIntervalSinceReferenceDate
        if let last = tapTimes.last, now - last > 2.5 { tapTimes.removeAll() }
        tapTimes.append(now)
        if tapTimes.count > 8 { tapTimes.removeFirst() }
        if tapTimes.count >= 2 {
            let gaps = zip(tapTimes.dropFirst(), tapTimes).map { $0 - $1 }.sorted()
            clock.bpm = min(200, max(50, 60 / gaps[gaps.count / 2]))
        }
        clock.anchor = now
        displayBPM = clock.bpm
        if beatSource == .mic { beatSource = .manual }
    }

    func nudgeBPM(_ d: Double) {
        clock.bpm = min(200, max(50, (clock.bpm + d).rounded()))
        displayBPM = clock.bpm
    }

    private func beatSourceChanged(_ old: BeatSource) {
        guard beatSource != old else { return }
        if stressTesting { return }   // automated test feeds the tracker itself
        if beatSource == .mic {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    guard granted else {
                        ErrorCenter.shared.report(area: "Microphone", message: "DMX Studio isn't allowed to use the microphone. Turn it on in System Preferences → Security & Privacy → Privacy → Microphone.")
                        self.beatSource = .manual
                        return
                    }
                    self.refreshAudioInputs()
                    let dev = self.audioInputs.first { $0.name == self.output.audioInputName }?.id
                    do { try self.mic.start(device: dev) } catch {
                        ErrorCenter.shared.report(area: "Microphone", message: "Couldn't start listening: \(error.localizedDescription)", details: "\(error)")
                        self.beatSource = .manual
                    }
                }
            }
        } else {
            mic.stop()
            micLevel = 0
        }
    }

    func refreshAudioInputs() { audioInputs = AudioInputs.list() }

    /// Switch what the beat tracker listens to (restarts listening if it's on).
    func selectAudioInput(_ name: String?) {
        output.audioInputName = name
        guard beatSource == .mic else { return }
        let dev = audioInputs.first { $0.name == name }?.id
        do { try mic.start(device: dev) } catch {
            ErrorCenter.shared.report(area: "Audio input", message: "Couldn't listen to \(name ?? "that input"): \(error.localizedDescription)")
        }
    }

    /// Auto Lighting: choose looks from how energetic the audio is, changing every 16 beats.
    private func runAutoLighting(now: Double) {
        guard autoLighting, beatSource == .mic, playingSongID == nil else { return }
        let lvl = mic.snapshot().level
        autoEnergy = autoEnergy * 0.995 + lvl * 0.005        // slow average (~6 s)
        // Change looks every 16 beats (the mic re-anchors the beat clock on every kick, so count time, not beat numbers)
        let sixteenBeats = 16 * clock.period
        guard activePresetID == nil || now - lastAutoChange >= sixteenBeats || now < lastAutoChange else { return }
        lastAutoChange = now
        let pools: [[String]] = [["Ocean Drift", "Slow Burn", "Color Fades", "Follows Sound"],
                                 ["Beat Colors", "Red Velvet", "Cyan · Pink", "Follows Sound"],
                                 ["Club Chase", "Kick Hits", "Rainbow Flow", "Blue · Orange", "Beat Colors"]]
        let tier = autoEnergy < 0.25 ? 0 : (autoEnergy < 0.5 ? 1 : 2)
        var choices = presets.filter { pools[tier].contains($0.name) && $0.id != activePresetID }
        if choices.isEmpty { choices = presets.filter { $0.id != activePresetID } }
        guard let pick = choices.randomElement() else { return }
        activePresetID = pick.id
        presetStart = now
    }

    func setManual(_ id: UUID, _ change: (inout ManualControl) -> Void) {
        var m = manual[id] ?? ManualControl()
        change(&m)
        manual[id] = m.isEmpty ? nil : m
    }

    static weak var current: AppModel?

    /// The keyboard's play/pause and next/previous keys (and the Touch Bar) control DMX Studio,
    /// so pausing the sound always pauses the lights too.
    func setupMediaKeys() {
        let c = MPRemoteCommandCenter.shared()
        c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.togglePlay(); return .success }
        c.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !self.isPlaying { self.togglePlay() }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.isPlaying { self.pause() }
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in self?.nextInLineup(); return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in self?.previousInLineup(); return .success }
    }

    /// Tells macOS what's playing (so the media keys and Touch Bar point here).
    func updateNowPlayingInfo() {
        let info = MPNowPlayingInfoCenter.default()
        guard let id = playingSongID, let song = song(id) else {
            info.nowPlayingInfo = nil
            info.playbackState = .stopped
            return
        }
        info.nowPlayingInfo = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artistName,
            MPMediaItemPropertyPlaybackDuration: player?.duration ?? 0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player?.currentTime ?? 0,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        info.playbackState = isPlaying ? .playing : .paused
    }

    // MARK: - Library folder, export & import

    /// Songs imported before the library folder existed get copied into it (in the background).
    func adoptExistingSongs() {
        let list = songs.map { ($0.id, $0.url) }
        DispatchQueue.global(qos: .utility).async {
            var moved: [UUID: String] = [:]
            for (id, url) in list {
                let kept = LibraryFiles.adopt(audio: url)
                if kept.path != url.path { moved[id] = kept.path }
            }
            guard !moved.isEmpty else { return }
            DispatchQueue.main.async {
                for i in self.songs.indices { if let p = moved[self.songs[i].id] { self.songs[i].path = p } }
            }
        }
    }

    func showLibraryFolder() {
        saveNow()
        _ = LibraryFiles.folder("Sessions")
        NSWorkspace.shared.activateFileViewerSelecting([LibraryFiles.root])
    }

    /// Asks where to save, then writes the session (with its songs) as one .dmxsession file.
    func exportSessionWithPanel(_ id: UUID? = nil) {
        saveNow()
        guard let s = sessions.first(where: { $0.id == (id ?? currentSessionID) }) else { return }
        let panel = NSSavePanel()
        panel.title = "Export Session"
        panel.message = "Saves the lights, presets, set lists, stage and songs of \"\(s.name)\" as one file you can open on another computer."
        panel.nameFieldStringValue = LibraryFiles.safeName(s.name) + "." + LibraryFiles.sessionExtension
        panel.allowedFileTypes = [LibraryFiles.sessionExtension]
        panel.directoryURL = LibraryFiles.folder("Exports")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let all = songs
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try LibraryFiles.exportSession(s, songs: all, to: url)
                DispatchQueue.main.async {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } catch {
                DispatchQueue.main.async {
                    ErrorCenter.shared.report(area: "Export", message: "Couldn't export \(s.name): \(error.localizedDescription)", details: "\(error)")
                }
            }
        }
    }

    func importSessionWithPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import Session"
        panel.allowedFileTypes = [LibraryFiles.sessionExtension]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { importSessionFile(url) }
    }

    /// Opens a .dmxsession file: adds its songs (audio + learned shows) and the session, then opens it.
    func importSessionFile(_ url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let (session, newSongs) = try LibraryFiles.importSession(from: url)
                DispatchQueue.main.async {
                    for song in newSongs {
                        if let i = self.songs.firstIndex(where: { $0.id == song.id }) {
                            if !FileManager.default.fileExists(atPath: self.songs[i].path), !song.path.isEmpty { self.songs[i].path = song.path }
                            // bring over shows we don't have yet
                            for show in song.shows where !self.songs[i].shows.contains(where: { $0.id == show.id }) { self.songs[i].shows.append(show) }
                            if self.songs[i].analysis == nil { self.songs[i].analysis = song.analysis }
                        } else {
                            self.songs.append(song)
                        }
                    }
                    var s = session
                    if self.sessions.contains(where: { $0.id == s.id }) {
                        s.id = UUID()
                        s.name += " (imported)"
                    }
                    s.modified = Date()
                    self.sessions.insert(s, at: 0)
                    self.openSession(s.id)
                    self.saveNow()
                }
            } catch {
                DispatchQueue.main.async {
                    ErrorCenter.shared.report(area: "Import", message: "Couldn't open \(url.lastPathComponent): \(error.localizedDescription)", details: "\(error)")
                }
            }
        }
    }

    /// Quitting: stop music, listening and timers, darken the lights, and save, quickly and in order.
    func prepareToQuit() {
        // save first: if stopping the audio below gets stuck, nothing is lost
        saveWork?.cancel()
        saveNow(sync: true)
        timer?.invalidate(); timer = nil
        scanTimer?.invalidate(); scanTimer = nil
        stressTimer?.invalidate(); stressTimer = nil
        gapWork?.cancel()
        player?.stop(); player = nil
        mic.stop()
        engine.shutdown()
        saveWork?.cancel()
        saveNow(sync: true)
    }

    private var mirrorWork: DispatchWorkItem?
    func saveNow(sync: Bool = false) {
        captureCurrentSession()
        let lib = Library(fixtures: fixtures, songs: songs, lineups: lineups, output: output,
                          idle: idle, globalLatencyMs: globalLatencyMs, rigMode: rigMode,
                          sessions: sessions, lastSessionID: currentSessionID, chainedBarsFix: true)
        // Also keep readable files in Documents/DMX Studio (sessions, your presets, set lists, songs)
        let allSessions = sessions, allSongs = songs
        var seenSets = Set<UUID>(), sets: [Lineup] = []
        for l in allSessions.flatMap(\.lineups) where seenSets.insert(l.id).inserted { sets.append(l) }
        var seenPresets = Set<UUID>(), mine: [LookPreset] = []
        for p in allSessions.flatMap({ $0.presets ?? [] }) where !p.isBuiltIn && seenPresets.insert(p.id).inserted { mine.append(p) }
        let write = {
            do {
                let data = try Library.encoder.encode(lib)
                try data.write(to: Self.storeURL, options: .atomic)
            } catch {
                DispatchQueue.main.async {
                    ErrorCenter.shared.report(area: "Saving", message: "Your latest changes couldn't be saved: \(error.localizedDescription)", details: "\(error)")
                }
            }
            if sync { LibraryFiles.mirror(sessions: allSessions, songs: allSongs, userPresets: mine, lineups: sets) }
        }
        if sync { write() } else { DispatchQueue.global(qos: .utility).async(execute: write) }
        // the readable copies in Documents re-encode every song: at most every 15 s, not after every change
        if !sync {
            mirrorWork?.cancel()
            let m = DispatchWorkItem {
                DispatchQueue.global(qos: .background).async {
                    LibraryFiles.mirror(sessions: allSessions, songs: allSongs, userPresets: mine, lineups: sets)
                }
            }
            mirrorWork = m
            DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: m)
        }
    }

    // MARK: - Output

    func connect(quiet: Bool = false) {
        CrashGuard.breadcrumb("Connecting to DMX output")
        do {
            if output.kind != .artNet && output.serialPath.isEmpty {
                throw DMXError.openFailed("choose a USB port first")
            }
            try engine.connect(output)
            connected = true
            switch output.kind {
            case .artNet:
                let u = output.sendUniverses.map(String.init).joined(separator: " + ")
                statusMessage = "Sending to \(output.artNetIP) · Art-Net universe \(u)\((output.alsoSendSACN ?? true) ? " + sACN 1" : "")"
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
        let manual = lastScan == nil ? false : true
        DispatchQueue.global(qos: .utility).async {
            // Scan in a separate helper process: if anything goes wrong, the app keeps running
            let r = Helper.run(["--scan-artnet"], timeout: 8)
            var nodes: [ArtNetNode] = []
            var problem: (String, String)? = nil
            if r.crashed || r.status != 0 {
                problem = ("The Wi-Fi scan for DMX devices stopped unexpectedly. Your lights and shows are fine; you can still connect by typing the PKnight's IP (192.168.4.1 on its own hotspot).",
                           "exit \(r.status)\n\(r.stderr)")
            } else if let decoded = try? JSONDecoder().decode([ArtNetNode].self, from: r.stdout) {
                nodes = decoded
            } else {
                problem = ("The Wi-Fi scan returned something unreadable.", String(decoding: r.stdout.prefix(500), as: UTF8.self) + "\n" + r.stderr)
            }
            DispatchQueue.main.async {
                if let problem {
                    self.searchingNodes = false
                    self.lastScan = Date()
                    self.scanFailures += 1
                    // Don't nag every 8 s: show once, then just log quietly
                    ErrorCenter.shared.report(area: "Wi-Fi scan", message: problem.0, details: problem.1,
                                              show: self.scanFailures == 1 || manual)
                    if self.scanFailures >= 3 { self.output.autoScan = false }
                    return
                }
                self.scanFailures = 0
                self.mergeScan(nodes)
            }
        }
    }

    private func mergeScan(_ nodes: [ArtNetNode]) {
        searchingNodes = false
        if var extras = output.extraDevices {
            var changed = false
            for (i, e) in extras.enumerated() {
                if let m = nodes.first(where: { $0.id == e.id }), m.ip != e.ip { extras[i] = m; changed = true }
            }
            if changed { output.extraDevices = extras; syncExtraOutputs() }
        }
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

    /// Every device a light can be wired to: the main one plus extra wireless boxes.
    var outputChoices: [(key: String, name: String)] {
        var out: [(key: String, name: String)] = [(key: DMXEngine.mainKey, name: "Main device" + (output.rememberedDevice.map { " (\($0.name))" } ?? ""))]
        var seen = Set<String>()
        for n in (output.extraDevices ?? []) + discoveredNodes
        where n.ip != output.artNetIP && !seen.contains(n.id) {
            seen.insert(n.id)
            out.append((key: n.id, name: "\(n.name) · \(n.ip)"))
        }
        return out
    }

    func assignOutput(fixtureID: UUID, key: String) {
        guard let i = fixtures.firstIndex(where: { $0.id == fixtureID }) else { return }
        fixtures[i].outputKey = key == DMXEngine.mainKey ? nil : key
        if key != DMXEngine.mainKey, let node = discoveredNodes.first(where: { $0.id == key }) ?? output.extraDevices?.first(where: { $0.id == key }) {
            var extras = output.extraDevices ?? []
            extras.removeAll { $0.id == node.id }
            extras.append(node)
            output.extraDevices = extras
        }
        syncExtraOutputs()
    }

    func syncExtraOutputs() {
        let used = Set(fixtures.compactMap { $0.outputKey })
        let devices = (output.extraDevices ?? []).filter { used.contains($0.id) }.map { (key: $0.id, ip: $0.ip) }
        engine.setExtraDevices(devices)
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
        let fx = Fixture(name: "\(base) \(count + 1)", address: min(nextFreeAddress, 512),
                         profileName: profile.name, layout: profile.layout)
        fixtures.append(fx)
        setupWizardFor = [fx.id]     // walk through setting the new light
    }

    func addressConflicts(for fx: Fixture) -> [Fixture] {
        fixtures.filter { $0.id != fx.id && $0.outputKey == fx.outputKey && fx.outputKey?.hasPrefix("hue:") != true
                          && $0.address <= fx.lastAddress && fx.address <= $0.lastAddress }
    }

    // MARK: - Songs

    /// Adds audio files (WAV, MP3, …) to the library, named from their tags. Folders are searched too.
    /// Returns the song ids in order (existing songs are reused, not duplicated).
    @discardableResult
    func importSongs(_ urls: [URL], into lineupID: UUID? = nil) -> [UUID] {
        var files: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
                while let f = e?.nextObject() as? URL { if SongMetadata.isAudio(f) { files.append(f) } }
            } else if SongMetadata.isAudio(url) {
                files.append(url)
            }
        }
        files.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        var ids: [UUID] = []
        for url in files {
            if let existing = songs.first(where: { $0.path == url.path }) { ids.append(existing.id); continue }
            let meta = SongMetadata.read(url)
            // Keep a copy in Documents/DMX Studio/Songs so the library (and exported sessions) never lose the audio
            let kept = LibraryFiles.adopt(audio: url)
            if let existing = songs.first(where: { $0.path == kept.path }) { ids.append(existing.id); continue }
            let song = Song(title: meta.title, path: kept.path, artist: meta.artist)
            songs.append(song)
            ids.append(song.id)
            lyricsPrompt.append(song.id)       // ask: paste the lyrics, or transcribe them from the audio
            if ProcessInfo.processInfo.environment["DMX_DEMO_SONG"] != nil { answerLyricsPrompt(song.id, .transcribe) }
        }
        if let first = ids.last { selectedSongID = first }

        if let lineupID, let li = lineupIndex(lineupID) {
            let wasEmpty = lineups[li].entries.isEmpty
            for id in ids { lineups[li].entries.append(LineupEntry(songID: id, showID: nil)) }
            // A fresh set list gets named after the artist
            if wasEmpty && isDefaultName(lineups[li].name), let a = mainArtist(of: ids) {
                lineups[li].name = uniqueSetListName(a)
            }
        }
        if files.isEmpty && !urls.isEmpty {
            alert = "Those files aren't audio DMX Studio can play. Use WAV, MP3, AIFF or M4A."
        }
        return ids
    }

    private func isDefaultName(_ n: String) -> Bool {
        n.hasPrefix("Set List") || n.hasPrefix("Lineup") || n == "My Lineup" || n == "My Set List" || n.isEmpty
    }

    func mainArtist(of ids: [UUID]) -> String? {
        let names = ids.compactMap { song($0)?.artist }.filter { !$0.isEmpty }
        let counts = Dictionary(grouping: names, by: { $0 }).mapValues { $0.count }
        return counts.max { $0.value < $1.value }?.key
    }

    func uniqueSetListName(_ base: String) -> String {
        var name = base, n = 2
        while lineups.contains(where: { $0.name == name }) { name = "\(base) \(n)"; n += 1 }
        return name
    }

    var artists: [String] {
        Array(Set(songs.compactMap { $0.artist }.filter { !$0.isEmpty })).sorted()
    }

    /// New set list containing every song by an artist, named after them.
    @discardableResult
    func createSetList(forArtist artist: String) -> UUID {
        let l = Lineup(name: uniqueSetListName(artist),
                       entries: songs.filter { $0.artist == artist }.map { LineupEntry(songID: $0.id, showID: nil) })
        lineups.append(l)
        return l.id
    }

    func index(of id: UUID?) -> Int? {
        guard let id else { return nil }
        return songs.firstIndex { $0.id == id }
    }

    /// Listens to the song and learns its structure. Creates a first show automatically.
    // MARK: - Stems: listen to the separated parts (Solo / Mute / volume per part)

    struct StemChannel: Equatable { var volume: Double = 1; var solo = false; var mute = false }
    @Published var stemMixes: [UUID: [String: StemChannel]] = [:]
    private var stemPlayers: [String: AVAudioPlayer] = [:]
    private var stemPlayersSong: UUID?

    func stemChannel(_ songID: UUID, _ name: String) -> Binding<StemChannel> {
        Binding(get: { self.stemMixes[songID]?[name] ?? StemChannel() },
                set: { self.stemMixes[songID, default: [:]][name] = $0 })
    }

    func stemGain(_ songID: UUID, _ name: String) -> Double {
        let mix = stemMixes[songID] ?? [:]
        let c = mix[name] ?? StemChannel()
        if c.mute { return 0 }
        if mix.values.contains(where: { $0.solo }) && !c.solo { return 0 }
        return c.volume
    }

    private func stopStems() {
        for p in stemPlayers.values { p.stop() }
        stemPlayers = [:]
        stemPlayersSong = nil
    }

    /// While a part is soloed, muted or turned down, the four parts play in step with the song
    /// (the song keeps running silently as the clock) instead of the original file.
    private func syncStems(_ i: Int, _ p: AVAudioPlayer) {
        let id = songs[i].id
        let mix = stemMixes[id] ?? [:]
        let active = mix.values.contains { $0.solo || $0.mute || $0.volume < 0.999 }
        guard active, let folder = songs[i].analysis?.stemsFolder else {
            if !stemPlayers.isEmpty { stopStems(); p.volume = Float(musicVolume) }
            return
        }
        if stemPlayersSong != id {
            stopStems()
            for name in StemStyle.all.map(\.name) {
                let u = URL(fileURLWithPath: folder).appendingPathComponent("\(name).m4a")
                if let sp = try? makePlayer(u) { sp.prepareToPlay(); stemPlayers[name] = sp }
            }
            stemPlayersSong = id
            if stemPlayers.isEmpty { return }
        }
        p.volume = 0
        for (name, sp) in stemPlayers {
            sp.volume = Float(musicVolume * stemGain(id, name))
            if p.isPlaying {
                if !sp.isPlaying { sp.currentTime = p.currentTime; sp.play() }
                else if abs(sp.currentTime - p.currentTime) > 0.06 { sp.currentTime = p.currentTime }
            } else if sp.isPlaying { sp.pause() }
        }
    }

    /// Where a song's separated parts (vocals / drums / bass / other) are saved.
    func stemsFolder(for song: Song) -> URL {
        LibraryFiles.folder("Songs/Stems")
            .appendingPathComponent("\(LibraryFiles.safeName(song.title)) \(song.id.uuidString.prefix(8))", isDirectory: true)
    }

    /// One song learns at a time (splitting into stems uses a lot of the computer).
    private let learnQueue = DispatchQueue(label: "learn", qos: .userInitiated)

    // MARK: Stop
    private var procs: [String: Process] = [:]
    private var stopped: Set<String> = []
    private var lyricsCurrent: UUID?
    func stopLearn(_ id: UUID) {
        stopped.insert("learn-\(id)")
        procs["learn-\(id)"]?.terminate()
        learning[id] = nil; learnStarted[id] = nil
    }
    func stopHQ(_ id: UUID) {
        stopped.insert("hq-\(id)")
        procs["hq-\(id)"]?.terminate()
        hqProgress[id] = nil; hqStarted[id] = nil
    }
    func stopLyrics(_ id: UUID) {
        let wasWaiting = lyricsCurrent != id
        lyricsQueue.removeAll { $0 == id }
        waitingForNetwork.removeAll { $0 == id }
        if lyricsCurrent == id { stopped.insert("lyrics-\(id)"); WhisperEngine.running?.terminate(); vocalSplitProc?.terminate() }
        lyricsProgress[id] = nil; lyricsStatus[id] = nil
        if wasWaiting { lyricsDone(id) }     // stopped before it started: go on to the music
    }

    // High Quality split runs after the quick learn, in the background (the show is usable meanwhile)
    @Published var hqProgress: [UUID: Double] = [:]
    @Published var hqStarted: [UUID: Date] = [:]
    private let hqQueue = DispatchQueue(label: "hq-split", qos: .utility)
    var wantsHQ: Bool { (UserDefaults.standard.object(forKey: "hqStems") as? Bool ?? true) && HQSplitter.isInstalled }
    func hqCountdown(_ id: UUID) -> String {
        guard let p = hqProgress[id] else { return "" }
        if hqStarted[id] == nil { return "High Quality split waiting" }
        return "High Quality split · \(Int(p * 100))% · " + AppModel.eta(started: hqStarted[id], progress: p)
    }

    /// Splits with the AI models and updates the parts, sung phrases and lyrics. Keeps the shows.
    func upgradeToHQ(_ id: UUID) {
        guard let i = index(of: id), hqProgress[id] == nil, HQSplitter.isInstalled else { return }
        let url = songs[i].url, title = songs[i].title
        let stems = stemsFolder(for: songs[i])
        let settings = songs[i].detection ?? DetectionSettings()
        hqProgress[id] = 0.01
        hqQueue.async {
            // one heavy job at a time: wait while lyrics are being listened to
            while DispatchQueue.main.sync(execute: { self.lyricsBusy }) { Thread.sleep(forTimeInterval: 1) }
            DispatchQueue.main.async { if self.hqProgress[id] != nil { self.hqProgress[id] = 0.02; self.hqStarted[id] = Date() } }
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("hq-\(id.uuidString).json")
            let settingsFile = FileManager.default.temporaryDirectory.appendingPathComponent("hq-\(id.uuidString)-settings.json")
            try? JSONEncoder().encode(settings).write(to: settingsFile)
            let r = Helper.run(["--learn", url.path, out.path, stems.path, settingsFile.path, "hq"], timeout: 7200, progress: { p in
                DispatchQueue.main.async { if self.hqProgress[id] != nil { self.hqProgress[id] = max(0.02, min(0.99, p)) } }
            }, onStart: { proc in DispatchQueue.main.async { self.procs["hq-\(id)"] = proc } })
            let analysis = (try? Data(contentsOf: out)).flatMap { try? Library.decoder.decode(SongAnalysis.self, from: $0) }
            try? FileManager.default.removeItem(at: out)
            try? FileManager.default.removeItem(at: settingsFile)
            DispatchQueue.main.async {
                self.hqProgress[id] = nil
                self.hqStarted[id] = nil
                self.procs["hq-\(id)"] = nil
                if self.stopped.remove("hq-\(id)") != nil { return }
                guard let analysis, r.status == 0, let i = self.index(of: id) else {
                    ErrorCenter.shared.report(area: "Stems", message: "The High Quality split of \"\(title)\" didn't finish; it keeps the quick split.",
                                              details: "exit \(r.status)\n\(r.stderr)")
                    return
                }
                self.songs[i].analysis = analysis
                self.refreshLyricLighting(id)
            }
        }
    }

    /// Songs whose music is learned right after their lyrics
    private var musicAfterLyrics: [UUID: Bool] = [:]     // id → rebuildShows
    private var splitOnLearn: Set<UUID> = []

    /// Learn: 1) listen for the lyrics (straight from the song, no stems), 2) learn the music.
    /// No stems are made unless `split` (the Split buttons in the Stems tab).
    /// Deep Learn: lyrics first, then split into stems (High Quality when it's installed) and learn the music from them.
    func deepLearn(_ id: UUID) { learn(id, rebuildShows: true, split: true, deep: true) }
    private var deepOnLearn: Set<UUID> = []

    func learn(_ id: UUID, rebuildShows: Bool = false, split: Bool = false, deep: Bool = false) {
        guard let i = index(of: id), learning[id] == nil, musicAfterLyrics[id] == nil else { return }
        if split { splitOnLearn.insert(id) }
        if deep { deepOnLearn.insert(id) }
        let needsLyrics = songs[i].lyrics == nil && WhisperEngine.isAvailable && (!split || deep)
        if needsLyrics, musicAfterLyrics[id] == nil, FileManager.default.fileExists(atPath: songs[i].path) {
            musicAfterLyrics[id] = rebuildShows
            learnLyrics(id)
            return
        }
        learnMusic(id, rebuildShows: rebuildShows)
    }

    // MARK: New songs: lyrics first (pasted or transcribed), then learning

    enum LyricsChoice { case paste(String), transcribe, skip }
    /// New songs waiting for you to say how to get their lyrics (shown one at a time)
    @Published var lyricsPrompt: [UUID] = []
    @Published var showLyricsLibrary = false
    private var pendingPaste: [UUID: String] = [:]

    func answerLyricsPrompt(_ id: UUID, _ choice: LyricsChoice) {
        lyricsPrompt.removeAll { $0 == id }
        switch choice {
        case .transcribe:
            learn(id)                                   // lyrics from the audio, then the music
        case .paste(let text):
            if let s = song(id) { LyricsLibrary.save(title: s.title, text: text) }
            pendingPaste[id] = text                     // the music first, then the words are placed on it
            learnMusic(id, rebuildShows: false)
        case .skip:
            learnMusic(id, rebuildShows: false)
        }
    }
    /// Same answer for every song still waiting
    func answerAllLyricsPrompts(_ choice: LyricsChoice) {
        for id in lyricsPrompt { answerLyricsPrompt(id, choice) }
    }

    /// The Lyrics panel is open (closed at every launch; lyrics also show on the timeline only while it's open)
    @Published var lyricsOpen = false

    /// Learn is on step 1 (lyrics) for this song
    func learningLyricsFirst(_ id: UUID) -> Bool { musicAfterLyrics[id] != nil }

    /// After a song's lyrics are done (or stopped): learn its music next.
    private func lyricsDone(_ id: UUID) {
        if let rebuild = musicAfterLyrics.removeValue(forKey: id) { learnMusic(id, rebuildShows: rebuild) }
    }

    private func learnMusic(_ id: UUID, rebuildShows: Bool) {
        guard let i = index(of: id), learning[id] == nil else { return }
        let deep = deepOnLearn.remove(id) != nil
        let split = splitOnLearn.remove(id) != nil || deep
        let mode = deep && HQSplitter.isInstalled ? "hq" : "fast"
        let url = songs[i].url
        let title = songs[i].title
        let stems = stemsFolder(for: songs[i])
        let keepStems = songs[i].analysis?.stemsFolder.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
        let settings = songs[i].detection ?? DetectionSettings()
        learning[id] = 0.02
        guard FileManager.default.fileExists(atPath: url.path) else {
            learning[id] = nil
            ErrorCenter.shared.report(area: "Learn", message: "Couldn't find the file for \"\(title)\". It may have been moved or deleted.", details: url.path)
            return
        }
        // Lyrics and the High Quality split only run when you ask (Listen / Split in their tabs): they're
        // heavy, and running them on their own alongside learning overloaded an older Mac
        learnQueue.async {
            DispatchQueue.main.async { if self.learning[id] != nil { self.learning[id] = 0.05; self.learnStarted[id] = Date() } }
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("learn-\(id.uuidString).json")
            let settingsFile = FileManager.default.temporaryDirectory.appendingPathComponent("learn-\(id.uuidString)-settings.json")
            try? JSONEncoder().encode(settings).write(to: settingsFile)
            // Learn in a separate helper process: a bad file can't crash the app.
            // It splits the song into stems first, then learns from those parts.
            // quick learn first (seconds): the show is ready to play; the High Quality split follows in the background
            if self.stopped.contains("learn-\(id)") { DispatchQueue.main.async { self.stopped.remove("learn-\(id)") }; return }
            let r = Helper.run(["--learn", url.path, out.path, split ? stems.path : "", settingsFile.path, mode], timeout: mode == "hq" ? 7200 : 1800, progress: { p in
                DispatchQueue.main.async { if self.learning[id] != nil { self.learning[id] = max(0.05, min(0.99, p)) } }
            }, onStart: { proc in DispatchQueue.main.async { self.procs["learn-\(id)"] = proc } })
            let analysis = (try? Data(contentsOf: out)).flatMap { try? Library.decoder.decode(SongAnalysis.self, from: $0) }
            try? FileManager.default.removeItem(at: out)
            try? FileManager.default.removeItem(at: settingsFile)
            DispatchQueue.main.async {
                self.learning[id] = nil
                self.learnStarted[id] = nil
                self.procs["learn-\(id)"] = nil
                if self.stopped.remove("learn-\(id)") != nil { return }
                guard let analysis, r.status == 0 else {
                    let msg = r.crashed
                        ? "Learning \"\(title)\" stopped unexpectedly. The app is fine; please report this so it can be fixed."
                        : "Couldn't learn \"\(title)\": \(r.stderr.isEmpty ? "the file couldn't be read" : r.stderr)"
                    ErrorCenter.shared.report(area: "Learn", message: msg, details: "file: \(url.lastPathComponent)\nexit \(r.status)\n\(r.stderr)")
                    return
                }
                guard let i = self.index(of: id) else { return }
                var learned = analysis
                // learning without splitting keeps the parts you split before
                if !split, learned.stemsFolder == nil, let keepStems { learned.stemsFolder = keepStems }
                self.songs[i].analysis = learned
                if self.songs[i].shows.isEmpty { self.createShow(for: id) }
                else if rebuildShows { self.rebuildShows(for: id) }
                self.makeLooks(from: id)
                // lyrics were started with learning; now that the song is known, make their lighting cues
                if let text = self.pendingPaste.removeValue(forKey: id) {
                    self.pasteLyrics(id, text: text)    // your lyrics, placed on the song (then timed by listening)
                } else if self.songs[i].lyrics != nil {
                    self.refreshLyricLighting(id)
                    self.fillLyricGaps(id)          // now that it knows where the singing is
                }
            }
        }
    }

    /// New looks made from a learned song: what its show does in each kind of part (drop, chorus,
    /// verse, intro…), with that song's colors, beam effect, movement and speed. They go in their own
    /// group named after the song, next to the built-in presets; making them again replaces them.
    @discardableResult
    func makeLooks(from songID: UUID) -> Int {
        guard let i = index(of: songID), let show = songs[i].activeShow else { return 0 }
        let title = songs[i].title
        let group = "From Songs: \(title)"
        var made: [LookPreset] = []
        // skip looks you already have (in any group), so songs don't add near-copies
        var seen = Set(presets.filter { $0.group != group }.map { "\($0.effect)|\($0.palette)|\($0.movement)|\($0.rate)" })
        let secs = show.sections.filter { $0.effect != .blackout && $0.end - $0.start >= 4 }
        let icons: [EnergyLevel: String] = [.drop: "bolt.fill", .high: "flame.fill", .medium: "waveform", .low: "moon.stars.fill"]
        let has38 = activeModes.contains("38CH")
        outer: for lvl in [EnergyLevel.drop, .high, .medium, .low] {
            for sec in secs where sec.level == lvl {
                let key = "\(sec.effect)|\(sec.palette)|\(sec.movement)|\(sec.rate)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                let part = sec.name.components(separatedBy: CharacterSet.decimalDigits).joined()
                    .trimmingCharacters(in: .whitespaces)
                var name = "\(title) · \(part.isEmpty ? lvl.rawValue : part)"
                if made.contains(where: { $0.name == name }) { name += " \(made.count + 1)" }
                made.append(LookPreset(name: name, effect: sec.effect, palette: sec.palette, movement: sec.movement,
                                       rate: sec.rate, intensity: max(0.6, sec.intensity), icon: icons[lvl] ?? "music.note",
                                       group: group, mode: sec.effect.perBeam && has38 ? "38CH" : nil))
                if made.count >= Self.looksPerSong { break outer }
            }
        }
        presets.removeAll { $0.group == group }
        guard !made.isEmpty else { return 0 }
        presets += made
        trimSongLooks(keep: group)
        return made.count
    }

    /// At most `maxSongGroups` automatic "From Songs" groups (oldest go first) with `looksPerSong` looks each
    func trimSongLooks(keep: String? = nil) {
        var songGroups: [String] = []
        for p in presets { if let g = p.group, g.hasPrefix("From Songs: "), !songGroups.contains(g) { songGroups.append(g) } }
        var list = presets
        while songGroups.count > Self.maxSongGroups, let oldest = songGroups.first(where: { $0 != keep }) {
            list.removeAll { $0.group == oldest }
            songGroups.removeAll { $0 == oldest }
        }
        var counts: [String: Int] = [:]
        list = list.filter { p in
            guard let g = p.group, g.hasPrefix("From Songs: ") else { return true }
            counts[g, default: 0] += 1
            return counts[g]! <= Self.looksPerSong
        }
        if list != presets { presets = list }
    }
    static let looksPerSong = 4
    static let maxSongGroups = 10

    // MARK: - Lyrics

    @Published var lyricsProgress: [UUID: Double] = [:]
    private var lyricsQueue: [UUID] = []
    private var lyricsBusy = false

    /// Learns the words from the song's separated vocals (one song at a time).
    func learnLyrics(_ id: UUID) {
        guard lyricsProgress[id] == nil else { return }
        lyricsProgress[id] = 0
        lyricsQueue.append(id)
        nextLyrics()
    }

    @Published var lyricsStatus: [UUID: String] = [:]
    /// Lyrics listen to the vocal part instead of the whole song (setting)
    var lyricsFromVocalPart: Bool {
        get { UserDefaults.standard.bool(forKey: "lyricsFromVocalPart") }
        set { UserDefaults.standard.set(newValue, forKey: "lyricsFromVocalPart"); objectWillChange.send() }
    }
    private var lyricsRetryOnVocals: Set<UUID> = []
    /// Separate the vocal before listening for lyrics (setting, on by default). In tests the words heard
    /// went from 51% to 63% right on a synth-heavy song, and the chorus was found.
    var lyricsSeparateVocal: Bool {
        get { UserDefaults.standard.object(forKey: "lyricsSeparateVocal") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "lyricsSeparateVocal"); objectWillChange.send() }
    }
    private var vocalSplitProc: Process?
    /// Where the vocal separated for listening is kept (just vocals.m4a per song)
    static var lyricVocalsDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DMX Studio/Lyric Vocals", isDirectory: true)
    }
    static func lyricVocal(_ id: UUID) -> URL { lyricVocalsDir.appendingPathComponent("\(id.uuidString)/vocals.m4a") }
    // when each job really started (for the countdown)
    @Published var learnStarted: [UUID: Date] = [:]
    var lyricsStarted: [UUID: Date] = [:]

    /// "about 3:20 left", from how fast the progress has been moving so far
    static func eta(started: Date?, progress p: Double) -> String {
        guard let s = started, p > 0.03 else { return "estimating time…" }
        let el = Date().timeIntervalSince(s)
        guard el > 4 else { return "estimating time…" }
        let left = max(0, el / p * (1 - p))
        if left < 60 { return "about \(max(1, Int(left.rounded()))) s left" }
        return String(format: "about %d:%02d left", Int(left) / 60, Int(left) % 60)
    }
    func learnCountdown(_ id: UUID) -> String {
        guard let p = learning[id] else { return "" }
        if learnStarted[id] == nil {
            let waiting = learning.keys.filter { learnStarted[$0] == nil }.count
            return waiting > 1 ? "waiting (\(waiting) songs in line)" : "waiting to start"
        }
        let queued = learning.count - 1
        return "\(Int(p * 100))% · " + AppModel.eta(started: learnStarted[id], progress: p) + (queued > 0 ? " · \(queued) more in line" : "")
    }
    func lyricsCountdown(_ id: UUID) -> String {
        guard let p = lyricsProgress[id] else { return "" }
        if lyricsCurrent != id {
            // not its turn yet: one heavy job at a time
            let ahead = (lyricsQueue.firstIndex(of: id) ?? 0) + (lyricsCurrent != nil ? 1 : 0) + learning.count
            return ahead > 0 ? "waiting · \(ahead) ahead in line" : "starting…"
        }
        return "\(Int(p * 100))% · " + AppModel.eta(started: lyricsStarted[id], progress: p)
    }
    var songListHovered = false
    var hoveredSongID: UUID?
    private var mouseMonitor: Any?
    /// Songs waiting for an internet connection to download the lyrics model (once)
    private var waitingForNetwork: [UUID] = []
    private var netMonitor: NWPathMonitor?
    @Published var online = true

    private func watchNetwork() {
        guard netMonitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }
                self.online = path.status == .satisfied
                if self.online && !self.waitingForNetwork.isEmpty {
                    let ids = self.waitingForNetwork
                    self.waitingForNetwork = []
                    for id in ids { self.lyricsStatus[id] = nil; self.learnLyrics(id) }
                }
            }
        }
        m.start(queue: DispatchQueue(label: "net"))
        netMonitor = m
    }

    static func isOffline(_ e: Error) -> Bool {
        let ns = e as NSError
        return ns.domain == NSURLErrorDomain && [-1009, -1020, -1004, -1003, -1001, -1005, -1018].contains(ns.code)
    }

    private func waitForNetwork(_ id: UUID) {
        watchNetwork()
        lyricsBusy = false
        lyricsProgress[id] = nil
        if !waitingForNetwork.contains(id) { waitingForNetwork.append(id) }
        lyricsStatus[id] = "Waiting for internet to get the lyrics model (once) — or use a model file"
        lyricsDone(id)          // don't hold up learning the music
        nextLyrics()
    }

    /// Use a Whisper model file you already have (e.g. downloaded on another network).
    func installWhisperModel(from url: URL) {
        let dest = WhisperEngine.modelURL(WhisperEngine.chosen)
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            let ids = waitingForNetwork
            waitingForNetwork = []
            for id in ids { lyricsStatus[id] = nil; learnLyrics(id) }
        } catch {
            ErrorCenter.shared.report(area: "Lyrics", message: "Couldn't use that model file: \(error.localizedDescription)", details: "\(error)")
        }
    }

    private func nextLyrics() {
        guard !lyricsBusy, !lyricsQueue.isEmpty else { return }
        // one heavy job at a time: wait for a High Quality split or learning to finish first
        if hqProgress.values.contains(where: { $0 > 0.015 }) || !learning.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.nextLyrics() }
            return
        }
        let id = lyricsQueue.removeFirst()
        guard let i = index(of: id) else {
            lyricsProgress[id] = nil; nextLyrics(); return
        }
        let a = songs[i].analysis
        // Listen to the whole song (fast, no splitting needed) — or the separated vocal part when chosen,
        // or when the whole song gave hardly any words
        let folder = a?.stemsFolder ?? ""
        let vocalPart = URL(fileURLWithPath: folder).appendingPathComponent("vocals.m4a")
        // only the High Quality vocals help (the quick split's vocal part made lyrics worse in tests);
        // the High Quality split is the one that also writes backing.m4a
        let haveVocalPart = !folder.isEmpty && FileManager.default.fileExists(atPath: vocalPart.path)
            && FileManager.default.fileExists(atPath: URL(fileURLWithPath: folder).appendingPathComponent("backing.m4a").path)
        // the High Quality vocal part is the cleanest: use it whenever the song has one
        let useVocalPart = haveVocalPart && (lyricsFromVocalPart || lyricsSeparateVocal || lyricsRetryOnVocals.contains(id))
        lyricsRetryOnVocals.remove(id)
        // No vocal part yet: separate just the vocal first (one AI model, in a helper process so it can't
        // take the app down), then listen to that instead of the whole mix
        let sepVocal = AppModel.lyricVocal(id)
        let voxInstalled = FileManager.default.fileExists(atPath: HQSplitter.voxURL.appendingPathComponent("coremldata.bin").path)
        // your own lyrics only need timing, not words: listen to the whole song (fast), no separating
        let lyricsGiven = songs[i].lyrics?.pastedText != nil || pendingPaste[id] != nil
        if !useVocalPart, !lyricsGiven, lyricsSeparateVocal, voxInstalled, WhisperEngine.isAvailable, lyricsSkipSeparation.remove(id) == nil,
           !FileManager.default.fileExists(atPath: sepVocal.path) {
            separateVocalForLyrics(id, url: songs[i].url)
            return
        }
        let useSeparated = !useVocalPart && !lyricsGiven && FileManager.default.fileExists(atPath: sepVocal.path)
        let vocals = useVocalPart ? vocalPart : (useSeparated ? sepVocal : songs[i].url)
        let title = songs[i].title
        let phrases = a?.vocalPhrases ?? []
        lyricsBusy = true
        lyricsCurrent = id
        func finish(_ result: Result<[LyricWord], Error>, engine: String) {
            lyricsBusy = false
            lyricsCurrent = nil
            if stopped.remove("lyrics-\(id)") != nil { lyricsProgress[id] = nil; lyricsStatus[id] = nil; lyricsDone(id); nextLyrics(); return }
            lyricsProgress[id] = nil
            lyricsStatus[id] = nil
            switch result {
            case .success(let words):
                if let i = index(of: id), songs[i].lyrics?.source == "Pasted", let text = songs[i].lyrics?.pastedText,
                   let a = songs[i].analysis {
                    // you pasted the words: listening was only to find where each word is sung
                    let mode = songs[i].lyrics?.mode
                    let spans = a.vocalShare > 0.15 ? (a.vocalPhrases ?? []) : sungParts(a)
                    songs[i].lyrics = LyricsLearner.align(text: text, heard: words, phrases: spans, duration: a.duration)
                    songs[i].lyrics?.engine = "Pasted · timed by listening"
                    songs[i].lyrics?.mode = mode
                    refreshLyricLighting(id)
                    applyLyricStructure(id)          // "Verse 1", "Chorus"… in your lyrics mark the song's parts
                } else if let i = index(of: id), !["Pasted", "Edited"].contains(songs[i].lyrics?.source ?? "") {
                    var ly = LyricsLearner.build(words: words, phrases: phrases, source: "Heard from the vocals")
                    ly.engine = engine
                    ly.mode = songs[i].lyrics?.mode
                    songs[i].lyrics = ly
                    refreshLyricLighting(id)
                    gapFilled.remove(id)
                    if songs[i].analysis != nil { DispatchQueue.main.async { self.fillLyricGaps(id) } }
                }
            case .failure(let e):
                ErrorCenter.shared.report(area: "Lyrics", message: "Couldn't learn the lyrics of \"\(title)\": \(e.localizedDescription)", details: "\(e)")
                if (e as? LyricsError) == .notAllowed { lyricsQueue.forEach { lyricsProgress[$0] = nil }; lyricsQueue = [] }
            }
            lyricsDone(id); nextLyrics()
        }
        let progress: (Double) -> Void = { p in
            guard self.lyricsProgress[id] != nil else { return }
            // a new pass (or the model download) starts the clock again
            if p <= 0.01 || self.lyricsStarted[id] == nil || p + 0.05 < (self.lyricsProgress[id] ?? 0) { self.lyricsStarted[id] = Date() }
            self.lyricsProgress[id] = p
        }
        // Whisper (built in, on this Mac) when it's available; Apple's speech recognizer otherwise
        if WhisperEngine.isAvailable {
            let size = WhisperEngine.chosen
            let run = {
                self.lyricsStatus[id] = useVocalPart || useSeparated ? "Listening to the vocal…" : "Listening to the song…"
                WhisperEngine.transcribe(vocals: vocals, phrases: useVocalPart ? phrases : [], model: size, progress: progress) { r in
                    // Hardly any lead vocal (backing / performance track)? Listen again for the
                    // background vocals: turned up, whole vocal part, a bit less strict
                    if case .success(let lead) = r, WhisperEngine.looksPoor(lead), !useVocalPart, haveVocalPart {
                        // the whole song gave hardly any words: try the separated vocal part
                        self.lyricsRetryOnVocals.insert(id)
                        self.lyricsBusy = false
                        self.lyricsProgress[id] = nil
                        self.learnLyrics(id)
                    } else if case .success(let lead) = r, WhisperEngine.looksPoor(lead), useVocalPart {
                        self.lyricsStatus[id] = "No lead vocal — listening for background vocals…"
                        self.lyricsProgress[id] = 0
                        // the vocal part plus "other" (where the AI split can put vocal chops, choirs, stacked backing vocals)
                        // every part that can hold singing (never bass or drums)
                        let extra = ["backing", "other", "guitar", "piano"]
                            .map { URL(fileURLWithPath: folder).appendingPathComponent("\($0).m4a") }
                            .filter { FileManager.default.fileExists(atPath: $0.path) }
                        WhisperEngine.transcribe(vocals: vocals, extra: extra,
                                                 phrases: phrases, model: size, background: true, progress: progress) { r2 in
                            if case .success(let bg) = r2, bg.count > lead.count, !WhisperEngine.looksPoor(bg) { finish(.success(bg), engine: "Whisper \(size.rawValue) · background vocals") }
                            else { finish(r, engine: "Whisper \(size.rawValue)" + (WhisperEngine.looksPoor(lead) ? " · unsure, please check" : "")) }
                        }
                    } else {
                        var unsure = false
                        if case .success(let w) = r { unsure = WhisperEngine.looksPoor(w) }
                        finish(r, engine: "Whisper \(size.rawValue)" + (unsure ? " · unsure, please check" : ""))
                    }
                }
            }
            if WhisperEngine.isInstalled(size) { run() }
            else {
                watchNetwork()
                if !online { waitForNetwork(id); return }
                lyricsStatus[id] = "Getting the lyrics model (once)…"
                FileDownloader.fetch(size.url, to: WhisperEngine.modelURL(size), progress: progress) { err in
                    if let err, AppModel.isOffline(err) { self.waitForNetwork(id) }
                    else if let err { finish(.failure(err), engine: "") }
                    else { self.lyricsProgress[id] = 0; run() }
                }
            }
        } else {
            lyricsStatus[id] = "Listening (Apple speech)…"
            LyricsLearner.transcribe(vocals: vocals, phrases: phrases, duration: a?.duration ?? 600, progress: progress) { r in
                finish(r, engine: "Apple speech")
            }
        }
    }

    /// Step 1 of listening for lyrics: pull the vocal out of the mix, then go on to listening
    private func separateVocalForLyrics(_ id: UUID, url: URL) {
        lyricsBusy = true
        lyricsCurrent = id
        lyricsStatus[id] = "Separating the vocal (step 1 of 2)…"
        lyricsProgress[id] = 0
        lyricsStarted[id] = Date()
        let folder = AppModel.lyricVocal(id).deletingLastPathComponent()
        let work = folder.deletingLastPathComponent().appendingPathComponent("\(id.uuidString)-working")
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.createDirectory(at: work.deletingLastPathComponent(), withIntermediateDirectories: true)
            let r = Helper.run(["--vocals", url.path, work.path], timeout: 3600, progress: { p in
                DispatchQueue.main.async { if self.lyricsProgress[id] != nil { self.lyricsProgress[id] = max(0.01, min(0.99, p)) } }
            }, onStart: { proc in DispatchQueue.main.async { self.vocalSplitProc = proc } })
            // keep only the vocal (the other parts aren't needed for lyrics)
            let fm = FileManager.default
            let ok = r.status == 0 && fm.fileExists(atPath: work.appendingPathComponent("vocals.m4a").path)
            if ok {
                try? fm.removeItem(at: folder)
                try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
                try? fm.moveItem(at: work.appendingPathComponent("vocals.m4a"), to: AppModel.lyricVocal(id))
            }
            try? fm.removeItem(at: work)
            DispatchQueue.main.async {
                self.vocalSplitProc = nil
                self.lyricsBusy = false
                self.lyricsCurrent = nil
                if self.stopped.remove("lyrics-\(id)") != nil {
                    self.lyricsProgress[id] = nil; self.lyricsStatus[id] = nil; self.lyricsDone(id); self.nextLyrics(); return
                }
                if !ok {
                    // couldn't separate: listen to the whole song instead (and don't try separating it again now)
                    self.lyricsSkipSeparation.insert(id)
                    NSLog("Vocal separation for lyrics failed (exit %d): %@", r.status, String(r.stderr.suffix(300)))
                }
                self.lyricsStatus[id] = "Listening to the vocal (step 2 of 2)…"
                self.lyricsProgress[id] = 0
                self.lyricsQueue.insert(id, at: 0)
                self.nextLyrics()
            }
        }
    }
    private var lyricsSkipSeparation: Set<UUID> = []

    /// Official lyrics pasted in: placed on the sung parts and analyzed for topic and mood.
    /// A first line that's just the song's title isn't sung: leave it out
    static func withoutTitleLine(_ text: String, title: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        if let k = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           LyricsLibrary.key(lines[k]) == LyricsLibrary.key(title), !LyricsLibrary.key(title).isEmpty {
            lines.remove(at: k)
        }
        return lines.joined(separator: "\n")
    }

    func pasteLyrics(_ id: UUID, text rawText: String) {
        let text = index(of: id).map { AppModel.withoutTitleLine(rawText, title: songs[$0].title) } ?? rawText
        if let i = index(of: id) { LyricsLibrary.save(title: songs[i].title, text: text) }   // keep them in the Lyrics Library
        guard let i = index(of: id), let a = songs[i].analysis else { return }
        let heard = ["Pasted", "Edited"].contains(songs[i].lyrics?.source ?? "") ? [] : (songs[i].lyrics?.words ?? [])
        // Tracks made to be sung over have little lead vocal: place the words on the sung parts of the
        // song structure (verses, pre-choruses, choruses, bridge) instead
        let spans = a.vocalShare > 0.15 ? (a.vocalPhrases ?? []) : sungParts(a)
        let mode = songs[i].lyrics?.mode
        songs[i].lyrics = LyricsLearner.align(text: text, heard: heard, phrases: spans, duration: a.duration)
        songs[i].lyrics?.engine = "Pasted"
        songs[i].lyrics?.mode = mode
        refreshLyricLighting(id)
        applyLyricStructure(id)
        // listen once more to find where each pasted line is really sung
        if WhisperEngine.isAvailable, lyricsProgress[id] == nil { learnLyrics(id) }
    }

    private func sungParts(_ a: SongAnalysis) -> [TimeSpan] {
        a.detectedSections.filter { d in ["Verse", "Pre-Chorus", "Chorus", "Post-Chorus", "Bridge"].contains { d.name.hasPrefix($0) } }
            .map { TimeSpan(start: $0.start, end: $0.end) }
    }


    /// Fix a line by hand (words and/or timing). Your corrections are kept when the song is relearned.
    func editLyricLine(_ id: UUID, lineID: UUID, text: String? = nil, shift: Double = 0, start: Double? = nil, end: Double? = nil) {
        defer { saveLyricsToLibrary(id) }     // your corrections go in the Lyrics Library too
        guard let i = index(of: id), var ly = songs[i].lyrics, let li = ly.lines.firstIndex(where: { $0.id == lineID }) else { return }
        var line = ly.lines[li]
        let oldStart = line.start, oldEnd = line.end
        line.start = max(0, (start ?? line.start) + shift)
        line.end = max(line.start + 0.2, (end ?? line.end) + shift)
        if let text, text != line.text { line.text = text }
        line.confidence = 1
        // words in this line: re-spread over the (new) line
        ly.words.removeAll { $0.start >= oldStart - 0.01 && $0.end <= oldEnd + 0.01 }
        let ws = line.text.split(separator: " ").map(String.init)
        let step = (line.end - line.start) / Double(max(ws.count, 1))
        for (k, w) in ws.enumerated() {
            ly.words.append(LyricWord(text: w, start: line.start + Double(k) * step, end: line.start + Double(k + 1) * step, confidence: 1))
        }
        ly.words.sort { $0.start < $1.start }
        ly.lines[li] = line
        ly.lines.sort { $0.start < $1.start }
        ly.source = "Edited"
        songs[i].lyrics = ly
        refreshLyricLighting(id)
    }

    /// Adds a lyric line (e.g. at the playhead); starts lyrics from scratch if there are none.
    func addLyricLine(_ id: UUID, at t: Double, text: String = "New line") -> UUID? {
        defer { saveLyricsToLibrary(id) }     // your corrections go in the Lyrics Library too
        guard let i = index(of: id) else { return nil }
        var ly = songs[i].lyrics ?? Lyrics(lines: [], words: [], source: "Edited")
        let line = LyricLine(text: text, start: max(0, t), end: max(0, t) + 2.5, confidence: 1)
        ly.lines.append(line)
        ly.lines.sort { $0.start < $1.start }
        let ws = text.split(separator: " ").map(String.init)
        for (k, w) in ws.enumerated() {
            let step = 2.5 / Double(max(ws.count, 1))
            ly.words.append(LyricWord(text: w, start: line.start + Double(k) * step, end: line.start + Double(k + 1) * step, confidence: 1))
        }
        ly.words.sort { $0.start < $1.start }
        ly.source = "Edited"
        songs[i].lyrics = ly
        refreshLyricLighting(id)
        return line.id
    }

    func deleteLyricLine(_ id: UUID, lineID: UUID) {
        defer { saveLyricsToLibrary(id) }     // your corrections go in the Lyrics Library too
        guard let i = index(of: id), var ly = songs[i].lyrics, let li = ly.lines.firstIndex(where: { $0.id == lineID }) else { return }
        let l = ly.lines[li]
        ly.words.removeAll { $0.start >= l.start - 0.01 && $0.end <= l.end + 0.01 }
        ly.lines.remove(at: li)
        ly.source = "Edited"
        songs[i].lyrics = ly
        refreshLyricLighting(id)
    }

    func setLyricMode(_ id: UUID, _ m: LyricLightingMode) {
        guard let i = index(of: id), songs[i].lyrics != nil else { return }
        songs[i].lyrics?.mode = m
        refreshLyricLighting(id, regenerate: false)
    }

    func setCueAccepted(_ id: UUID, cueID: UUID, _ v: Bool?) {
        guard let i = index(of: id), let ci = songs[i].lyrics?.cues?.firstIndex(where: { $0.id == cueID }) else { return }
        songs[i].lyrics?.cues?[ci].accepted = v
        refreshLyricLighting(id, regenerate: false)
    }

    /// Re-reads the lyrics (emotion, imagery, delivery) and remakes the lighting cues from them.
    /// Your accept / reject choices are kept for cues that are still there.
    // MARK: Missed parts: listen again only where someone sings but no words were heard

    private var gapFilled: Set<UUID> = []

    /// Sung stretches (from learning the music) with no heard words in them
    func missedSungSpans(_ id: UUID) -> [TimeSpan] {
        guard let i = index(of: id), let ly = songs[i].lyrics, let ph = songs[i].analysis?.vocalPhrases else { return [] }
        var merged: [TimeSpan] = []
        for p in ph.sorted(by: { $0.start < $1.start }) {
            if let l = merged.last, p.start - l.end < 1.5 { merged[merged.count - 1].end = max(l.end, p.end) } else { merged.append(p) }
        }
        var out: [TimeSpan] = []
        for p in merged where p.end - p.start >= 3 {
            // the parts of it with no words within 1.5 s
            var cur = p.start
            for w in ly.words.sorted(by: { $0.start < $1.start }) where w.end > p.start && w.start < p.end {
                if w.start - cur >= 3 { out.append(TimeSpan(start: max(0, cur - 0.5), end: w.start + 0.3)) }
                cur = max(cur, w.end)
            }
            if p.end - cur >= 3 { out.append(TimeSpan(start: max(0, cur - 0.5), end: p.end + 0.5)) }
        }
        return out
    }

    /// Whisper sometimes skips ahead and misses a whole verse: listen again just to those parts and add what it hears
    func fillLyricGaps(_ id: UUID) {
        guard WhisperEngine.isAvailable, !gapFilled.contains(id), let i = index(of: id),
              songs[i].lyrics?.source == "Heard from the vocals" else { return }
        let gaps = missedSungSpans(id)
        guard gaps.reduce(0, { $0 + $1.end - $1.start }) >= 3 else { return }
        // one heavy job at a time
        if lyricsBusy || !learning.isEmpty || hqProgress.values.contains(where: { $0 > 0.015 }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.fillLyricGaps(id) }
            return
        }
        gapFilled.insert(id)
        let url = FileManager.default.fileExists(atPath: AppModel.lyricVocal(id).path) ? AppModel.lyricVocal(id) : songs[i].url
        lyricsBusy = true
        lyricsCurrent = id
        lyricsProgress[id] = 0
        lyricsStarted[id] = Date()
        lyricsStatus[id] = "Listening again where words were missed…"
        WhisperEngine.transcribe(vocals: url, phrases: gaps, model: WhisperEngine.chosen, onlyPhrases: true, progress: { p in
            if self.lyricsProgress[id] != nil { self.lyricsProgress[id] = p }
        }) { r in
            self.lyricsBusy = false
            self.lyricsCurrent = nil
            self.lyricsProgress[id] = nil
            self.lyricsStatus[id] = nil
            if self.stopped.remove("lyrics-\(id)") != nil { self.nextLyrics(); return }
            if case .success(let found) = r, !found.isEmpty, let i = self.index(of: id), var ly = self.songs[i].lyrics,
               ly.source == "Heard from the vocals" {
                let fresh = found.filter { w in gaps.contains { w.start >= $0.start - 0.3 && w.start <= $0.end } }
                let words = (ly.words + fresh).sorted { $0.start < $1.start }
                var rebuilt = LyricsLearner.build(words: words, phrases: self.songs[i].analysis?.vocalPhrases ?? [], source: "Heard from the vocals")
                rebuilt.engine = (ly.engine ?? "Whisper") + " · missed parts listened again"
                rebuilt.mode = ly.mode
                ly = rebuilt
                self.songs[i].lyrics = ly
                self.refreshLyricLighting(id)
            }
            self.nextLyrics()
        }
    }

    /// The lyrics as heard, with timing and how sure it was, as a report (opens a pre-filled report and
    /// copies the whole thing to the clipboard) so wrong words can be compared with the real lyrics
    func sendLyricsReport(_ id: UUID) {
        guard let i = index(of: id), let ly = songs[i].lyrics else { return }
        let s = songs[i]
        func t(_ x: Double) -> String { String(format: "%d:%04.1f", Int(x) / 60, x.truncatingRemainder(dividingBy: 60)) }
        var d = """
        Song: \(s.title)\(s.artist.map { " — " + $0 } ?? "")
        Length: \(s.analysis.map { t($0.duration) } ?? "?")  ·  BPM: \(s.analysis.map { String(Int($0.bpm.rounded())) } ?? "?")
        Heard by: \(ly.engine ?? ly.source)  ·  model: \(WhisperEngine.chosen.label)  ·  language: \(WhisperEngine.language.rawValue)
        Listened to: \(lyricsSeparateVocal ? "separated vocal" : "whole song")  ·  stems: \(s.analysis?.stemsFolder == nil ? "none" : "yes")
        Lines: \(ly.lines.count)  ·  words: \(ly.words.count)  ·  sung parts found: \(s.analysis?.vocalPhrases?.count ?? 0)

        LINES (start–end  sure%  [who]  text)

        """
        for l in ly.lines {
            d += "\(t(l.start))–\(t(l.end))  \(Int((l.confidence * 100).rounded()))%  [\(l.vocalist ?? "Lead")]  \(l.text)\n"
        }
        // stretches of the song with singing but no words (missed parts)
        if let ph = s.analysis?.vocalPhrases, !ph.isEmpty {
            let missed = ph.filter { p in !ly.lines.contains { $0.start < p.end && $0.end > p.start } && p.end - p.start >= 2 }
            if !missed.isEmpty {
                d += "\nSINGING WITH NO WORDS HEARD\n" + missed.map { "\(t($0.start))–\(t($0.end))" }.joined(separator: ", ") + "\n"
            }
        }
        d += "\nWORDS (time word sure%)\n" + ly.words.map { "\(t($0.start)) \($0.text) \(Int(($0.confidence * 100).rounded()))" }.joined(separator: "\n")
        ErrorCenter.shared.sendReport(AppProblem(area: "Lyrics report", message: "Lyrics heard for \"\(s.title)\"", details: d))
    }

    /// Section names written in your lyrics ("Verse 1", "Chorus"…) become the song's structure: each section starts
    /// where its first line is sung (on the bar), and the light shows are rebuilt for it.
    func applyLyricStructure(_ id: UUID) {
        guard let i = index(of: id), let ly = songs[i].lyrics, let labels = ly.sectionLabels, labels.count >= 2,
              var a = songs[i].analysis, !ly.lines.isEmpty else { return }
        var bars: [Double] = []
        var b = a.downbeatOffset
        while b < a.beats.count { bars.append(a.beats[b]); b += 4 }
        func snap(_ t: Double) -> Double {
            guard let n = bars.min(by: { abs($0 - t) < abs($1 - t) }), abs(n - t) < 1.5 else { return t }
            return n
        }
        var marks: [(name: String, t: Double, drop: Bool)] = []
        for l in labels {
            let raw: Double
            if l.instrumental == true {
                // no singing in it: starts where the singing before it ends (the intro starts with the music)
                raw = l.line == 0 ? a.musicStart : ly.lines[min(l.line, ly.lines.count) - 1].end + 0.2
            } else {
                guard l.line < ly.lines.count else { continue }
                raw = ly.lines[l.line].start - 0.3
            }
            let t = snap(max(a.musicStart, raw))
            if let last = marks.last, t - last.t < 2 { marks[marks.count - 1].name = l.name; marks[marks.count - 1].drop = l.drop == true; continue }
            if let last = marks.last, t < last.t { continue }
            marks.append((l.name, t, l.drop == true))
        }
        guard marks.count >= 2 else { return }
        // number repeated parts: Chorus → Chorus 1, Chorus 2 (written numbers are kept)
        var counts: [String: Int] = [:]
        let named: [(String, Double, Bool)] = marks.map { m in
            let base = m.name.split(separator: " ").first.map(String.init) ?? m.name
            if m.name != base { return (m.name, m.t, m.drop) }
            if ["Intro", "Outro", "Instrumental", "Interlude"].contains(base) { return (base, m.t, m.drop) }
            counts[base, default: 0] += 1
            return ("\(base) \(counts[base]!)", m.t, m.drop)
        }
        let old = a.detectedSections
        func section(_ name: String, _ s: Double, _ e: Double, drop: Bool = false) -> DetectedSection {
            // loudness from the sections it overlaps
            var w = 0.0, en = 0.0, levelTime: [EnergyLevel: Double] = [:]
            for o in old {
                let ov = min(e, o.end) - max(s, o.start)
                guard ov > 0 else { continue }
                w += ov; en += o.energy * ov; levelTime[o.level, default: 0] += ov
            }
            let level = drop ? .drop : (levelTime.max { $0.value < $1.value }?.key ?? .medium)
            return DetectedSection(start: s, end: e, energy: w > 0 ? en / w : 0.5, level: level, name: name)
        }
        var secs: [DetectedSection] = []
        if named[0].1 - a.musicStart > 3 && !named[0].0.hasPrefix("Intro") { secs.append(section("Intro", a.musicStart, named[0].1)) }
        let lastSung = ly.lines.last?.end ?? a.musicEnd
        for (k, m) in named.enumerated() {
            var end = k + 1 < named.count ? named[k + 1].1 : a.musicEnd
            // music carries on well after the last line: that's an outro
            if k + 1 == named.count && a.musicEnd - lastSung > 8 && !m.0.hasPrefix("Outro") { end = snap(lastSung + 0.5) }
            if end - m.1 >= 1 { secs.append(section(m.0, m.1, end, drop: m.2)) }
        }
        if let last = secs.last, a.musicEnd - last.end > 2 { secs.append(section("Outro", last.end, a.musicEnd)) }
        secs = fillMissingParts(secs, lyrics: ly, heard: old, bars: bars, section: section)
        a.detectedSections = secs
        songs[i].analysis = a
        rebuildShows(for: id)
    }

    /// Lyric sheets often leave parts out (a repeated chorus not written again, "(repeat)", an instrumental
    /// post-chorus), so a labelled part can run on over the next one. Where a part is longer than that kind of
    /// part ever is, or the singing in it stops well before it ends, the missing part is taken from what Learn
    /// heard in the music. A pre-chorus is always followed by a chorus.
    private func fillMissingParts(_ secs: [DetectedSection], lyrics ly: Lyrics, heard: [DetectedSection], bars: [Double],
                                  section: (String, Double, Double, Bool) -> DetectedSection) -> [DetectedSection] {
        guard bars.count > 4 else { return secs }
        let gaps = zip(bars.dropFirst(), bars).map { $0 - $1 }.sorted()
        let bar = gaps[gaps.count / 2]
        func role(_ n: String) -> String {
            for r in ["Pre-Chorus", "Post-Chorus"] where n.hasPrefix(r) { return r }
            return n.split(separator: " ").first.map(String.init) ?? n
        }
        let maxBars: [String: Double] = ["Pre-Chorus": 8, "Post-Chorus": 8, "Build": 16, "Intro": 16,
                                         "Chorus": 16, "Verse": 16, "Bridge": 16, "Drop": 32, "Breakdown": 32]
        func snap(_ t: Double) -> Double { bars.min { abs($0 - t) < abs($1 - t) } ?? t }
        func heardRole(at t: Double) -> String? {
            heard.first { $0.start <= t + 0.5 && $0.end > t + 0.5 }.map { role($0.name) }
        }
        var out: [DetectedSection] = []
        var queue = secs
        var guardN = 0
        while !queue.isEmpty && guardN < 200 {
            guardN += 1
            let s = queue.removeFirst()
            let r = role(s.name)
            let len = (s.end - s.start) / bar
            var cut: Double? = nil
            var nextName: String? = nil
            // 1. the singing in this part stops well before it ends: the rest is another part
            let sungInside = ly.lines.filter { $0.start >= s.start - 0.5 && $0.start < s.end }
            if !["Intro", "Outro", "Instrumental", "Interlude", "Breakdown"].contains(r),
               let lastLine = sungInside.last, s.end - lastLine.end > 4 * bar {
                let c = snap(lastLine.end + 0.3)
                if c - s.start >= 2 * bar && s.end - c >= 2 * bar {
                    cut = c
                    nextName = r == "Chorus" ? "Post-Chorus" : (heardRole(at: c) ?? "Instrumental")
                }
            }
            // 2. too long for this kind of part: split where the music changes (or after the longest it can be)
            if cut == nil, let mx = maxBars[r], len > mx + 2 {
                let inner = heard.map(\.start).filter { $0 > s.start + 2 * bar && $0 < s.end - 2 * bar }
                let c = inner.min { abs($0 - (s.start + mx * bar)) < abs($1 - (s.start + mx * bar)) }
                    .flatMap { abs($0 - s.start) <= (mx + 2) * bar ? $0 : nil } ?? snap(s.start + mx * bar)
                cut = c
                nextName = heardRole(at: c)
            }
            guard let c = cut, c > s.start + bar, c < s.end - bar else { out.append(s); continue }
            // what comes next: a pre-chorus always leads into the chorus; never the same part twice in a row
            var n = nextName ?? r
            if r == "Pre-Chorus" { n = "Chorus" }
            if n == r { n = r == "Chorus" ? "Post-Chorus" : r == "Verse" ? "Pre-Chorus" : "Instrumental" }
            if n == "Silence" { n = "Instrumental" }
            out.append(section(s.name, s.start, c, s.level == .drop))
            queue.insert(section(n, c, s.end, false), at: 0)
        }
        // number them again in order (Chorus 1, Chorus 2…), since parts were added
        var counts: [String: Int] = [:]
        let totals = Dictionary(grouping: out, by: { role($0.name) }).mapValues(\.count)
        return out.map { d in
            var d = d
            let r = role(d.name)
            guard !["Intro", "Outro", "Instrumental", "Interlude", "Silence"].contains(r) else { d.name = r; return d }
            counts[r, default: 0] += 1
            let suffix = d.name.contains("·") ? " ·" + (d.name.components(separatedBy: "·").last ?? "") : ""
            d.name = ((totals[r] ?? 0) > 1 || ["Verse", "Chorus", "Pre-Chorus"].contains(r) ? "\(r) \(counts[r]!)" : r) + suffix
            return d
        }
    }

    /// Corrected lyrics are kept in the Lyrics Library (by song title)
    func saveLyricsToLibrary(_ id: UUID) {
        guard let s = song(id), let ly = s.lyrics, ["Pasted", "Edited"].contains(ly.source), !ly.lines.isEmpty else { return }
        LyricsLibrary.save(title: s.title, text: ly.lines.map(\.text).joined(separator: "\n"))
    }

    /// Throw away this song's lyrics (and the lighting cues made from them), e.g. when they were heard wrong
    func clearLyrics(_ id: UUID) {
        stopLyrics(id)
        guard let i = index(of: id) else { return }
        songs[i].lyrics = nil
        songs[i].analysis?.lyricCues = nil
    }

    func refreshLyricLighting(_ id: UUID, regenerate: Bool = true) {
        guard let i = index(of: id), var ly = songs[i].lyrics, let a = songs[i].analysis else { return }
        if regenerate {
            var level: [Float]? = nil
            if let folder = a.stemsFolder, let v = try? AudioAnalyzer.loadMono(url: URL(fileURLWithPath: folder).appendingPathComponent("vocals.m4a")) {
                level = v
            }
            LyricsInterpreter.interpret(&ly, vocalLevel: level, levelRate: AudioAnalyzer.sampleRate)
            let old = ly.cues ?? []
            var fresh = LyricLighting.cues(ly, analysis: a)
            for k in fresh.indices {
                if let o = old.first(where: { $0.kind == fresh[k].kind && $0.label == fresh[k].label && abs($0.start - fresh[k].start) < 0.5 }) {
                    fresh[k].accepted = o.accepted
                    fresh[k].id = o.id
                }
            }
            ly.cues = fresh
            songs[i].lyrics = ly
        }
        let cues = ly.cues ?? []
        let used: [LyricCue]
        switch ly.mode ?? .automatic {
        case .automatic: used = cues.filter { $0.accepted != false && $0.confidence >= 0.4 }
        case .assisted: used = cues.filter { $0.accepted == true }
        case .manual: used = []
        }
        songs[i].analysis?.lyricCues = used
    }

    /// Colors the active show to fit what the lyrics are about (drops keep their genre colors).
    func applyLyricColors(_ id: UUID) {
        guard let i = index(of: id), let pal = LyricsLearner.palette(for: songs[i].lyrics?.themes ?? []),
              let j = songs[i].activeShowIndex else { return }
        for k in songs[i].shows[j].sections.indices where songs[i].shows[j].sections[k].level != .drop {
            songs[i].shows[j].sections[k].palette = pal
        }
    }

    /// Changes the lighting mode(s) of a show and re-programs it.
    func setDesign(songID: UUID, showID: UUID, _ blend: DesignBlend) {
        guard let i = index(of: songID), let j = songs[i].shows.firstIndex(where: { $0.id == showID }),
              let a = songs[i].analysis else { return }
        songs[i].shows[j].design = blend.isAutomatic ? nil : blend
        let onLights = fixtures.filter { $0.isOn }
        var secs = ShowGenerator.generateShaped(a, peak: songs[i].peakGenre ?? a.suggestedPeakStyle, style: songs[i].shows[j].style, variation: songs[i].shows[j].variation,
                                                design: songs[i].shows[j].design)
        if useLibraryInShows { ShowGenerator.enrich(&secs, a, presets: presets, variation: songs[i].shows[j].variation, lyrics: songs[i].lyrics) } else { ShowGenerator.learnedRules(&secs, a, variation: songs[i].shows[j].variation, lyrics: songs[i].lyrics) }
        ShowGenerator.fit(&secs, to: onLights.filter { $0.effectiveBehavior == .sequence })
        songs[i].shows[j].sections = secs
        songs[i].shows[j].builtFor = rigDescription
    }

    /// Builds a new light show from what was learned, using the song's genre (or the one passed in).
    func createShow(for id: UUID, style: ShowStyle? = nil, design: DesignBlend? = nil) {
        guard let i = index(of: id), let a = songs[i].analysis else { return }
        let st = style ?? songs[i].effectiveGenre
        let variation = (songs[i].shows.filter { $0.style == st }.map(\.variation).max() ?? 0) + 1
        let name = variation == 1 ? "\(st.rawValue)" : "\(st.rawValue) #\(variation)"
        // Build for the lights that are switched on in this session right now, fitted to what those
        // models can do (moving heads or not, tilt-only, separate beams, color mixing vs a color wheel)
        let onLights = fixtures.filter { $0.isOn }
        let blend = design ?? songs[i].activeShow?.design
        var sections = ShowGenerator.generateShaped(a, peak: songs[i].peakGenre ?? a.suggestedPeakStyle, style: st, variation: variation, design: blend)
        if useLibraryInShows { ShowGenerator.enrich(&sections, a, presets: presets, variation: variation, lyrics: songs[i].lyrics) } else { ShowGenerator.learnedRules(&sections, a, variation: variation, lyrics: songs[i].lyrics) }
        ShowGenerator.fit(&sections, to: onLights.filter { $0.effectiveBehavior == .sequence })
        var show = LightShow(name: name, style: st, variation: variation, sections: sections,
                             fixtureIDs: onLights.isEmpty ? nil : onLights.map(\.id))
        show.builtFor = rigDescription
        show.design = blend
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

    // MARK: Music output (headphone / line-out jack, speakers, USB interface)

    /// The output the music plays through (nil = whatever macOS uses)
    var audioOutputUID: String? {
        get { UserDefaults.standard.string(forKey: "audioOutputUID") }
        set {
            UserDefaults.standard.set(newValue, forKey: "audioOutputUID")
            objectWillChange.send()
            // move what's playing now
            let uid = playableOutput()
            player?.currentDevice = uid
            fadingPlayer?.currentDevice = uid
            for p in stemPlayers.values { p.currentDevice = uid }
        }
    }
    /// The chosen output if it's connected, else the system output (unplugged interface: keep playing)
    func playableOutput() -> String? {
        guard let uid = audioOutputUID else { return nil }
        return AudioOutputs.exists(uid) ? uid : nil
    }
    func makePlayer(_ url: URL) throws -> AVAudioPlayer {
        let p = try AVAudioPlayer(contentsOf: url)
        p.currentDevice = playableOutput()
        return p
    }
    private var testPlayer: AVAudioPlayer?
    func playStereoTest() {
        guard let u = AudioOutputs.stereoTestFile(), let p = try? makePlayer(u) else { return }
        testPlayer = p
        p.play()
    }

    /// Full screen for the whole app (View menu, ⌃⌘F, or the button at the top right)
    func toggleFullScreen() {
        guard let w = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
        w.collectionBehavior.insert(.fullScreenPrimary)
        w.toggleFullScreen(nil)
    }

    /// The block selected on a song's timeline (Delete empties it)
    @Published var timelineSelection: TimelineSel?
    struct TimelineSel: Equatable { let song: UUID; let section: UUID }

    /// Remove a block's look but keep its place: an empty slot of the same length to fill with another look
    func emptySection(songID: UUID, sectionID: UUID) {
        guard let i = index(of: songID), let si = songs[i].activeShowIndex,
              let k = songs[i].shows[si].sections.firstIndex(where: { $0.id == sectionID }) else { return }
        songs[i].shows[si].sections[k].empty = true
    }

    /// Show building uses transitions, the effects library and the new block controls (setting, on by default)
    var useLibraryInShows: Bool {
        get { UserDefaults.standard.object(forKey: "useLibraryInShows") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "useLibraryInShows"); objectWillChange.send() }
    }

    /// Songs picked in the library (click, ⇧/⌘-click or drag to pick several)
    @Published var pickedSongs: Set<UUID> = []
    var songsScreenShowing = false
    /// Songs waiting for "Remove?" to be confirmed
    @Published var removeRequest: [UUID]? = nil
    func requestRemove(_ ids: [UUID]) { if !ids.isEmpty { removeRequest = ids } }
    func removeSongs(_ ids: [UUID]) {
        for id in ids { removeSong(id) }
        pickedSongs.subtract(ids)
    }

    func removeSong(_ id: UUID) {
        if playingSongID == id { stop() }
        songs.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: AppModel.lyricVocal(id).deletingLastPathComponent())
        for i in lineups.indices { lineups[i].entries.removeAll { $0.songID == id } }
        if selectedSongID == id { selectedSongID = songs.first?.id }
    }

    /// Splits a section in two at the bar nearest its middle, so you can give each half its own look.
    func splitSection(songID: UUID, sectionID: UUID) {
        guard let i = index(of: songID), let si = songs[i].activeShowIndex, let a = songs[i].analysis,
              let k = songs[i].shows[si].sections.firstIndex(where: { $0.id == sectionID }) else { return }
        let sec = songs[i].shows[si].sections[k]
        let mid = (sec.start + sec.end) / 2
        var bars: [Double] = []
        var b = a.downbeatOffset
        while b < a.beats.count { bars.append(a.beats[b]); b += 4 }
        let cut = bars.filter { $0 > sec.start + 1 && $0 < sec.end - 1 }.min { abs($0 - mid) < abs($1 - mid) } ?? mid
        var first = sec, second = sec
        first.end = cut
        second.id = UUID(); second.start = cut; second.name = sec.name + " (b)"
        second.accentStrobe = false
        second.colorShift = (sec.colorShift ?? 0) + 1
        songs[i].shows[si].sections[k] = first
        songs[i].shows[si].sections.insert(second, at: k + 1)
    }

    /// The playhead on the shown song's timeline when it isn't playing (set by clicking the timeline)
    var timelinePlayhead: Double?

    /// "." : cut a block and leave a short empty slot (half a bar) for a transition. With a block selected:
    /// at the playhead if it's inside that block, else in the block's middle (on the beat). While playing with
    /// nothing selected: the block under the playhead. Later blocks keep their times.
    func splitKey() {
        if let ts = timelineSelection, let i = index(of: ts.song), let si = songs[i].activeShowIndex,
           let sec = songs[i].shows[si].sections.first(where: { $0.id == ts.section }), let a = songs[i].analysis {
            let head: Double? = playingSongID == ts.song
                ? currentTime + (songs[i].syncOffsetMs + globalLatencyMs) / 1000 : timelinePlayhead
            var t: Double
            if let h = head, h > sec.start + 0.3, h < sec.end - 0.2 { t = h }
            else {
                // the middle of the block, on the nearest bar (or beat)
                let mid = (sec.start + sec.end) / 2
                var bars: [Double] = []
                var b = a.downbeatOffset
                while b < a.beats.count { bars.append(a.beats[b]); b += 4 }
                t = bars.filter { $0 > sec.start + 0.3 && $0 < sec.end - 0.3 }.min { abs($0 - mid) < abs($1 - mid) }
                    ?? a.beats.filter { $0 > sec.start + 0.3 && $0 < sec.end - 0.3 }.min { abs($0 - mid) < abs($1 - mid) } ?? mid
            }
            cutWithSlot(songID: ts.song, at: t)
        } else if let id = playingSongID, let i = index(of: id) {
            cutWithSlot(songID: id, at: currentTime + (songs[i].syncOffsetMs + globalLatencyMs) / 1000)
        }
    }

    /// Scissors: cut a block exactly at a time (no slot)
    func cutAt(songID: UUID, sectionID: UUID, time t: Double) {
        guard let i = index(of: songID), let si = songs[i].activeShowIndex,
              let k = songs[i].shows[si].sections.firstIndex(where: { $0.id == sectionID }) else { return }
        let sec = songs[i].shows[si].sections[k]
        guard t - sec.start >= 0.2, sec.end - t >= 0.2 else { return }
        var left = sec, right = sec
        left.end = t
        right.id = UUID(); right.start = t; right.accentStrobe = false
        songs[i].shows[si].sections.replaceSubrange(k...k, with: [left, right])
    }

    func cutWithSlot(songID: UUID, at raw: Double) {
        guard let i = index(of: songID), let si = songs[i].activeShowIndex, let a = songs[i].analysis else { return }
        let t = a.beats.min(by: { abs($0 - raw) < abs($1 - raw) }).flatMap { abs($0 - raw) < 0.3 ? $0 : nil } ?? raw
        guard let k = songs[i].shows[si].sections.firstIndex(where: { $0.start < t && t < $0.end }) else { return }
        let sec = songs[i].shows[si].sections[k]
        guard t - sec.start >= 0.25 else { return }               // right at the start: nothing to cut
        let beat = 60 / max(a.bpm, 40)
        let gap = min(2 * beat, sec.end - t)                       // half a bar (less near the block's end)
        guard gap >= 0.2 else { return }
        var left = sec, slot = sec, right = sec
        left.end = t
        slot.id = UUID(); slot.start = t; slot.end = t + gap
        slot.empty = true; slot.transition = nil; slot.accentStrobe = false; slot.name = "Transition"
        right.id = UUID(); right.start = t + gap; right.accentStrobe = false
        var parts = [left, slot]
        if right.end - right.start >= 0.2 { parts.append(right) } else { parts[1].end = sec.end }
        songs[i].shows[si].sections.replaceSubrange(k...k, with: parts)
        timelineSelection = TimelineSel(song: songID, section: slot.id)
        lastSplitNote = "Cut \(sec.name) at \(formatTime(t)) — empty slot for a transition"
    }

    /// Fill a block (usually an empty slot) with a transition: the hit on top of the look before it
    func setTransition(_ kind: HitKind, songID: UUID, sectionID: UUID) {
        guard let i = index(of: songID), let si = songs[i].activeShowIndex,
              let k = songs[i].shows[si].sections.firstIndex(where: { $0.id == sectionID }) else { return }
        var s = songs[i].shows[si].sections[k]
        // carry the look from the block before (so the hit plays over it, then the next block takes over)
        if let prev = songs[i].shows[si].sections[..<k].last(where: { $0.empty != true && $0.transition == nil }) {
            s.effect = prev.effect; s.palette = prev.palette; s.movement = prev.movement; s.rate = prev.rate
            s.intensity = prev.intensity; s.colorShift = prev.colorShift
        }
        s.transition = kind
        s.empty = nil
        s.accentStrobe = false
        s.name = kind.rawValue
        songs[i].shows[si].sections[k] = s
    }
    @Published var lastSplitNote: String?

    /// Put a transition hit on the playing / shown song at a time
    func addHit(_ kind: HitKind, songID: UUID, at time: Double) {
        guard let i = index(of: songID), let si = songs[i].activeShowIndex, let a = songs[i].analysis else { return }
        let t = a.beats.min(by: { abs($0 - time) < abs($1 - time) }).flatMap { abs($0 - time) < 0.3 ? $0 : nil } ?? time
        var hits = songs[i].shows[si].hits ?? []
        hits.removeAll { abs($0.time - t) < 0.05 && $0.kind == kind }
        hits.append(ShowHit(time: t, kind: kind, beats: kind.beats))
        songs[i].shows[si].hits = hits.sorted { $0.time < $1.time }
    }
    func removeHit(songID: UUID, hitID: UUID) {
        guard let i = index(of: songID), let si = songs[i].activeShowIndex else { return }
        songs[i].shows[si].hits?.removeAll { $0.id == hitID }
    }
    func setHitLength(songID: UUID, hitID: UUID, beats: Double) {
        guard let i = index(of: songID), let si = songs[i].activeShowIndex,
              let h = songs[i].shows[si].hits?.firstIndex(where: { $0.id == hitID }) else { return }
        songs[i].shows[si].hits?[h].beats = beats
    }

    /// Joins a section with the one after it.
    func mergeWithNext(songID: UUID, sectionID: UUID) {
        guard let i = index(of: songID), let si = songs[i].activeShowIndex,
              let k = songs[i].shows[si].sections.firstIndex(where: { $0.id == sectionID }),
              k + 1 < songs[i].shows[si].sections.count else { return }
        songs[i].shows[si].sections[k].end = songs[i].shows[si].sections[k + 1].end
        songs[i].shows[si].sections.remove(at: k + 1)
    }

    // MARK: - Lineups

    func lineupIndex(_ id: UUID?) -> Int? {
        guard let id else { return nil }
        return lineups.firstIndex { $0.id == id }
    }

    /// Adds a silence or transition block (at the end, or right after `after`).
    func addBlock(_ e: LineupEntry, to lineupID: UUID, after index: Int? = nil) {
        guard let li = lineupIndex(lineupID) else { return }
        if let index, index + 1 <= lineups[li].entries.count {
            lineups[li].entries.insert(e, at: index + 1)
            if playingLineupID == lineupID, let p = playingEntryIndex, p > index { playingEntryIndex = p + 1 }
        } else {
            lineups[li].entries.append(e)
        }
    }

    // MARK: - Set timing

    /// How long one set-list entry plays (songs: from where the music starts to where it ends, if skipping dead air).
    func entryDuration(_ e: LineupEntry, in l: Lineup) -> Double {
        if e.isBlock { return e.blockSeconds }
        guard let a = song(e.songID)?.analysis else { return 0 }
        return (l.skipDeadAir ?? true) ? max(1, a.musicEnd - max(0, a.musicStart - 0.15)) : a.duration
    }

    /// Gap after entry i (the idle look between two songs in a continuous set).
    func gapAfter(_ i: Int, in l: Lineup) -> Double {
        guard i + 1 < l.entries.count, l.mode == .continuous else { return 0 }
        let e = l.entries[i], n = l.entries[i + 1]
        return (e.isBlock || n.isBlock || (n.waitForCue ?? false)) ? 0 : l.gapSeconds
    }

    /// A transition between two songs in a continuous set blends over both: auto-sync places it over the
    /// first song's outro and the second song's intro (on the beat); otherwise it's split around the change.
    func crossTiming(_ i: Int, in l: Lineup) -> CrossTiming? {
        guard l.mode == .continuous, i > 0, i + 1 < l.entries.count else { return nil }
        let e = l.entries[i], pe = l.entries[i - 1], ne = l.entries[i + 1]
        guard e.block == .transition, e.fadeMusic ?? false, !(e.waitForCue ?? false),
              !pe.isBlock, !ne.isBlock, !(ne.waitForCue ?? false),
              let a = song(pe.songID)?.analysis else { return nil }
        let b = song(ne.songID)?.analysis
        func bar(_ x: SongAnalysis?) -> Double { 4 * 60 / max(60, x?.bpm ?? 120) }
        if e.autoFit ?? false {
            // over the outro: from where the outro starts (or the last two bars) to where the music ends
            var lead = a.detectedSections.last(where: { $0.name.hasPrefix("Outro") && $0.start < a.musicEnd })
                .map { a.musicEnd - $0.start } ?? 2 * bar(a)
            lead = min(16, max(bar(a), lead))
            // over the intro: from where the next song's music starts to where its intro ends (or two bars)
            var leadIn = 2 * bar(b)
            if let b, let intro = b.detectedSections.first(where: { $0.name.hasPrefix("Intro") && $0.end > b.musicStart }) {
                leadIn = intro.end - b.musicStart
            }
            leadIn = min(16, max(bar(b), leadIn))
            return CrossTiming(seconds: lead + leadIn, lead: lead, leadIn: leadIn)
        }
        let beat = 60 / max(60, a.bpm)
        let lead = min(max(beat, (e.blockSeconds / 2 / beat).rounded() * beat), max(0.5, e.blockSeconds - 0.5))
        return CrossTiming(seconds: e.blockSeconds, lead: lead, leadIn: e.blockSeconds - lead)
    }

    /// A block's actual length (auto-synced transitions size themselves).
    func blockLength(_ i: Int, in l: Lineup) -> Double {
        guard l.entries.indices.contains(i) else { return 0 }
        return crossTiming(i, in: l)?.seconds ?? l.entries[i].blockSeconds
    }

    /// When each entry starts, and the whole set's running time (cued waits not counted).
    func setTimeline(_ l: Lineup) -> (starts: [Double], total: Double) {
        var t = 0.0, starts: [Double] = [], end = 0.0
        for (i, e) in l.entries.enumerated() {
            if let ct = crossTiming(i, in: l) {
                // starts over the outro of the song before; the next song begins `lead` later
                let s = max(starts.last ?? 0, t - ct.lead)
                starts.append(s)
                end = max(end, s + ct.seconds)
                t = s + ct.lead
                continue
            }
            starts.append(t)
            t += (e.isBlock ? blockLength(i, in: l) : entryDuration(e, in: l)) + gapAfter(i, in: l)
            end = max(end, t)
        }
        return (starts, max(t, end))
    }

    /// Remakes every learned show for the lights switched on now (same style and variation, so set lists keep their links).
    func rebuildShowsForCurrentLights() {
        let onLights = fixtures.filter { $0.isOn }
        let seq = onLights.filter { $0.effectiveBehavior == .sequence }
        for i in songs.indices {
            guard let a = songs[i].analysis else { continue }
            for j in songs[i].shows.indices {
                var secs = ShowGenerator.generateShaped(a, peak: songs[i].peakGenre ?? a.suggestedPeakStyle, style: songs[i].shows[j].style, variation: songs[i].shows[j].variation, design: songs[i].shows[j].design)
                if useLibraryInShows { ShowGenerator.enrich(&secs, a, presets: presets, variation: songs[i].shows[j].variation, lyrics: songs[i].lyrics) } else { ShowGenerator.learnedRules(&secs, a, variation: songs[i].shows[j].variation, lyrics: songs[i].lyrics) }
                ShowGenerator.fit(&secs, to: seq)
                songs[i].shows[j].sections = secs
                songs[i].shows[j].fixtureIDs = onLights.isEmpty ? nil : onLights.map(\.id)
                songs[i].shows[j].builtFor = rigDescription
            }
        }
    }

    func removeEntry(lineupID: UUID, entryID: UUID) {
        guard let li = lineupIndex(lineupID), let i = lineups[li].entries.firstIndex(where: { $0.id == entryID }) else { return }
        lineups[li].entries.remove(at: i)
        if playingLineupID == lineupID, let p = playingEntryIndex, p > i { playingEntryIndex = p - 1 }
    }

    func updateEntry(_ lineupID: UUID, _ entryID: UUID, _ change: (inout LineupEntry) -> Void) {
        guard let li = lineupIndex(lineupID), let i = lineups[li].entries.firstIndex(where: { $0.id == entryID }) else { return }
        change(&lineups[li].entries[i])
    }

    func addToLineup(_ lineupID: UUID, songID: UUID, showID: UUID?) {
        guard let li = lineupIndex(lineupID) else { return }
        lineups[li].entries.append(LineupEntry(songID: songID, showID: showID))
    }

    func newLineup() -> UUID {
        let l = Lineup(name: "Set List \(lineups.count + 1)")
        lineups.append(l)
        return l.id
    }

    func song(_ id: UUID) -> Song? { songs.first { $0.id == id } }

    /// Plays a whole lineup from the given entry: music + lights, then the next song automatically.
    func playLineup(_ id: UUID, from entry: Int = 0, keepBlock: Bool = false, fadeIn fadeInOverride: Double? = nil) {
        guard let li = lineupIndex(id), lineups[li].entries.indices.contains(entry) else { stop(); return }
        let e = lineups[li].entries[entry]
        cuedEntry = nil
        if e.isBlock { startBlock(e, lineup: id, index: entry); return }
        guard song(e.songID) != nil else { playLineup(id, from: entry + 1); return }
        // Coming out of a transition that fades the music: bring this song in gently
        var fadeIn = fadeInOverride ?? 0
        if fadeInOverride == nil, entry > 0, let prev = Optional(lineups[li].entries[entry - 1]), prev.block == .transition, prev.fadeMusic ?? false {
            fadeIn = min(2.5, prev.blockSeconds)
        }
        // Skip the silent lead-in baked into the file (keep a hair of it so the first hit isn't clipped)
        var start = 0.0
        if lineups[li].skipDeadAir ?? true, let a = song(e.songID)?.analysis {
            start = max(0, a.musicStart - 0.15)
        }
        play(e.songID, show: e.showID, from: start, keepLineup: true, fadeIn: fadeIn, keepBlock: keepBlock)
        playingLineupID = id
        playingEntryIndex = entry
    }

    // MARK: - Set list blocks (silence & transitions)

    /// Moves a set on to entry `index`: starts it, or (cued set / "wait for cue") holds it ready for Space or →.
    private func advance(_ lineup: UUID, to index: Int) {
        guard let li = lineupIndex(lineup), index < lineups[li].entries.count else {
            playingLineupID = nil; playingEntryIndex = nil; cuedEntry = nil; isPlaying = false
            return
        }
        let next = lineups[li].entries[index]
        if lineups[li].mode == .cued || (next.waitForCue ?? false) {
            player?.stop(); player = nil
            playingSongID = nil; playingShowID = nil; currentTime = 0
            activeBlock = nil; inGap = false
            playingLineupID = lineup
            playingEntryIndex = index
            cuedEntry = index
            isPlaying = false
            return
        }
        playLineup(lineup, from: index)
    }

    /// Starts the cued entry (Space / →). Returns false if nothing is cued.
    @discardableResult
    func goCued() -> Bool {
        guard let lid = playingLineupID, let idx = cuedEntry else { return false }
        cuedEntry = nil
        playLineup(lid, from: idx)
        return true
    }

    var cuedLabel: String? {
        guard let idx = cuedEntry, let lid = playingLineupID, let li = lineupIndex(lid), idx < lineups[li].entries.count else { return nil }
        let e = lineups[li].entries[idx]
        return e.isBlock ? e.blockLabel : (song(e.songID)?.displayName ?? "Next song")
    }

    /// Runs a silence or transition block, then moves on to the next entry.
    /// `keepPlayer`: the song before keeps playing and fades out underneath (a music transition).
    private func startBlock(_ e: LineupEntry, lineup: UUID, index: Int, keepPlayer: Bool = false, cross: CrossTiming? = nil) {
        gapWork?.cancel(); gapWork = nil; inGap = false
        blockEndWork?.cancel(); blockEndWork = nil
        fadingPlayer?.stop(); fadingPlayer = nil
        let length = cross?.seconds ?? (lineupIndex(lineup).map { blockLength(index, in: lineups[$0]) } ?? e.blockSeconds)
        if keepPlayer, let p = player {
            // the song before fades out under the transition (over its outro)
            p.setVolume(0, fadeDuration: max(0.5, cross?.lead ?? length))
            fadingPlayer = p
        } else {
            player?.stop()
        }
        player = nil
        playingSongID = nil
        playingShowID = nil
        currentTime = 0
        playingLineupID = lineup
        playingEntryIndex = index
        isPlaying = true
        activeBlock = ActiveBlock(entry: e, start: Date().timeIntervalSinceReferenceDate, bpm: lastSongBPM, length: length)
        if let cross {
            // the next song comes in under the transition (its intro), the transition's lights finish on top
            let startNext = DispatchWorkItem { [weak self] in
                guard let self, let li = self.lineupIndex(lineup), index + 1 < self.lineups[li].entries.count else { return }
                self.playLineup(lineup, from: index + 1, keepBlock: true, fadeIn: min(2, cross.leadIn))
            }
            gapWork = startNext
            DispatchQueue.main.asyncAfter(deadline: .now() + cross.lead, execute: startNext)
            let end = DispatchWorkItem { [weak self] in
                self?.fadingPlayer?.stop(); self?.fadingPlayer = nil
                self?.activeBlock = nil
            }
            blockEndWork = end
            DispatchQueue.main.asyncAfter(deadline: .now() + length, execute: end)
        } else {
            scheduleBlockEnd(after: length, lineup: lineup, index: index)
        }
    }

    private func scheduleBlockEnd(after seconds: Double, lineup: UUID, index: Int) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.fadingPlayer?.stop(); self.fadingPlayer = nil
            self.activeBlock = nil
            if let li = self.lineupIndex(lineup), index + 1 < self.lineups[li].entries.count {
                self.advance(lineup, to: index + 1)
            } else {
                self.stop()
            }
        }
        gapWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.1, seconds), execute: work)
    }

    /// Lights while a cued song waits: idle look, dark, or one of your presets running on the beat.
    private func renderWaitLook(_ choice: String?, now: Double, idleFrame: [RenderedFixture]) -> [RenderedFixture] {
        let c = choice ?? "idle"
        if c == "idle" { return idleFrame }
        if c == "dark" { return fixtures.map { RenderedFixture(heads: Array(repeating: .off, count: $0.headCount)) } }
        guard let preset = presets.first(where: { $0.name == c }) else { return idleFrame }
        let linked = fixtures.indices.filter { fixtures[$0].isOn && fixtures[$0].effectiveBehavior == .sequence && copySource(of: $0) == nil }
        var bc = BeatClock(); bc.bpm = lastSongBPM; bc.anchor = cueStart
        let la = bc.liveAnalysis(now: now, onsets: [], level: 0.7, useOnsetsAsKicks: false)
        var r = ShowRenderer(analysis: la, sections: [preset.asSection(start: cueStart)], fixtures: linked.map { fixtures[$0] })
        r.rig = rigMode
        let part = r.render(at: now)
        var full = idleFrame
        for (j, fi) in linked.enumerated() where j < part.count { full[fi] = part[j] }
        return full
    }

    /// Lights for a running block.
    private func renderBlock(_ b: ActiveBlock, now: Double, idleFrame: [RenderedFixture]) -> [RenderedFixture] {
        let e = b.entry
        let dur = max(0.5, b.length)
        let p = max(0, min(1, (now - b.start) / dur))
        let dark = fixtures.map { RenderedFixture(heads: Array(repeating: .off, count: $0.headCount)) }
        func white(_ k: Double, strobe: Double = 0) -> [RenderedFixture] {
            fixtures.map { var r = RenderedFixture(heads: Array(repeating: FixtureState(intensity: k, color: .white), count: $0.headCount)); r.strobe = strobe; return r }
        }
        func scaled(_ f: [RenderedFixture], _ k: Double) -> [RenderedFixture] {
            f.map { var r = $0; for h in r.heads.indices { r.heads[h].intensity *= k }; return r }
        }
        func look(_ effect: LightEffect, rate: Double, movement: MoveEffect) -> [RenderedFixture] {
            let linked = fixtures.indices.filter { fixtures[$0].isOn && fixtures[$0].effectiveBehavior == .sequence && copySource(of: $0) == nil }
            var c = BeatClock(); c.bpm = b.bpm; c.anchor = b.start
            let la = c.liveAnalysis(now: now, onsets: [], level: 0.8, useOnsetsAsKicks: false)
            let look = LookPreset(name: "Transition", effect: effect, palette: e.palette ?? "Neon", movement: movement, rate: rate)
            var r = ShowRenderer(analysis: la, sections: [look.asSection(start: b.start)], fixtures: linked.map { fixtures[$0] })
            r.rig = rigMode
            let part = r.render(at: now)
            var full = dark
            for (j, fi) in linked.enumerated() where j < part.count { full[fi] = part[j] }
            return full
        }
        let style = e.transition ?? .idle
        if e.block == .silence { return style == .blackout ? dark : idleFrame }
        switch style {
        case .idle: return idleFrame
        case .blackout: return p < 0.15 ? scaled(idleFrame, 1 - p / 0.15) : dark
        case .colorWash: return look(.breathe, rate: 0.5, movement: .sweep)
        case .sweep: return look(.chase, rate: 1, movement: .sweep)
        case .buildUp:
            if p > 0.93 { return white(1) }
            return scaled(look(.chase, rate: p < 0.5 ? 1 : (p < 0.8 ? 2 : 4), movement: .fan), 0.35 + 0.65 * p)
        case .strobeHit:
            let strobe: Double = ShowRenderer.maxFlashHz >= 10 ? 1 : 0   // the light's strobe only with fast strobes on
            return p < 0.45 ? white(1, strobe: strobe) : scaled(white(1), max(0, 1 - (p - 0.45) / 0.2))
        case .whiteFlash: return white(sin(.pi * p))
        case .rainbow: return look(.rainbow, rate: 1, movement: .fullRotate)
        }
    }

    /// Moves a set-list entry up (negative) or down (positive); big numbers go to the top/bottom.
    func moveEntry(lineupID: UUID, from index: Int, by delta: Int) {
        guard let li = lineupIndex(lineupID), lineups[li].entries.indices.contains(index) else { return }
        let target = max(0, min(lineups[li].entries.count - 1, index + delta))
        guard target != index else { return }
        let e = lineups[li].entries.remove(at: index)
        lineups[li].entries.insert(e, at: target)
        // Keep "now playing" pointing at the same song
        if playingLineupID == lineupID, let p = playingEntryIndex {
            if p == index { playingEntryIndex = target }
            else if index < p && target >= p { playingEntryIndex = p - 1 }
            else if index > p && target <= p { playingEntryIndex = p + 1 }
        }
    }

    /// ⏭ / →: start the cued song, else the next one in the set, else the next song in the library.
    /// ↑ / ↓: moves the selection in the set list (if a set-list row is selected) or in the song library.
    func moveSelection(_ d: Int) {
        if let sel = selectedEntry, let li = lineupIndex(sel.lineup), li < lineups.count {
            let n = lineups[li].entries.count
            guard n > 0 else { return }
            let ni = min(max(sel.index + d, 0), n - 1)
            selectedEntry = (sel.lineup, ni)
            if lineups[li].entries[ni].block == nil { selectedSongID = lineups[li].entries[ni].songID }
            return
        }
        guard !songs.isEmpty else { return }
        let i = selectedSongID.flatMap { id in songs.firstIndex { $0.id == id } } ?? -1
        selectedSongID = songs[min(max(i + d, 0), songs.count - 1)].id
    }

    func nextInLineup() {
        // A song you picked (click or ↑/↓) plays next, instead of the next one in order
        if let sel = selectedEntry, let lid = playingLineupID, sel.lineup == lid, sel.index != playingEntryIndex {
            cancelGap()
            selectedEntry = nil
            playLineup(lid, from: sel.index)
            return
        }
        if playingLineupID == nil, isPlaying, let sel = selectedSongID, sel != playingSongID, song(sel) != nil {
            play(sel, from: songStart(sel))
            return
        }
        if goCued() { return }
        if let lid = playingLineupID, let idx = playingEntryIndex {
            cancelGap()
            playLineup(lid, from: idx + 1)
            return
        }
        guard !songs.isEmpty else { return }
        let cur = playingSongID ?? selectedSongID
        let i = cur.flatMap { id in songs.firstIndex { $0.id == id } } ?? -1
        let next = songs[(i + 1) % songs.count]
        selectedSongID = next.id
        play(next.id, from: songStart(next.id))
    }

    /// ⏮ / ←: back to the beginning of this song; pressed again right away, the song before.
    func previousInLineup() {
        let into = (player?.currentTime ?? 0) - (playingSongID.map(songStart) ?? 0)
        if let id = playingSongID, player != nil, into > 3 {
            player?.currentTime = songStart(id)
            currentTime = player?.currentTime ?? 0
            return
        }
        if let lid = playingLineupID, let idx = playingEntryIndex {
            cancelGap()
            playLineup(lid, from: max(0, idx - 1))
            return
        }
        guard !songs.isEmpty else { return }
        let cur = playingSongID ?? selectedSongID
        let i = cur.flatMap { id in songs.firstIndex { $0.id == id } } ?? 0
        let prev = songs[(i - 1 + songs.count) % songs.count]
        selectedSongID = prev.id
        play(prev.id, from: songStart(prev.id))
    }

    /// Where a song's music actually starts (skipping silence at the top).
    func songStart(_ id: UUID) -> Double {
        songs.first { $0.id == id }?.analysis.map { max(0, $0.musicStart - 0.15) } ?? 0
    }

    private func cancelGap() { gapWork?.cancel(); gapWork = nil; inGap = false }

    // MARK: - Transport (music + lights start together)

    func play(_ id: UUID, show: UUID? = nil, from start: Double? = nil, keepLineup: Bool = false, fadeIn: Double = 0, keepBlock: Bool = false) {
        guard let i = index(of: id) else { return }
        CrashGuard.breadcrumb("Playing \(songs[i].title)")
        cancelGap()
        if !keepBlock {
            activePresetID = nil      // playing a song: its own light show takes over from any live look
            activeBlock = nil
            blockEndWork?.cancel(); blockEndWork = nil
            fadingPlayer?.stop(); fadingPlayer = nil
        }
        if let bpm = songs[i].analysis?.bpm { lastSongBPM = bpm }
        if !keepLineup { playingLineupID = nil; playingEntryIndex = nil }
        if playingSongID != id || player == nil {
            player?.stop()
            do {
                let p = try makePlayer(songs[i].url)
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
        resumeFromPause()
        if fadeIn > 0 { player?.volume = 0 }
        player?.play()
        if fadeIn > 0 { player?.setVolume(Float(musicVolume), fadeDuration: fadeIn) } else { player?.volume = Float(musicVolume) }
        isPlaying = true
    }

    func togglePlay() {
        if isPlaying { pause(); return }
        if pauseTime != nil, playingSongID == nil, activeBlock == nil, activePresetID != nil { resumeFromPause(); return }
        if goCued() { return }
        if var b = activeBlock, let remaining = b.pausedRemaining, let lid = playingLineupID, let idx = playingEntryIndex {
            // resume a paused block where it left off
            b.start = Date().timeIntervalSinceReferenceDate - (b.length - remaining)
            b.pausedRemaining = nil
            activeBlock = b
            resumeFromPause()
            fadingPlayer?.play()
            isPlaying = true
            scheduleBlockEnd(after: remaining, lineup: lid, index: idx)
            return
        }
        // On the Songs page, Space plays the song you have selected (music + its light show)
        if songsPageOpen, let sel = selectedSongID, sel != playingSongID {
            let start = songs.first { $0.id == sel }?.analysis.map { max(0, $0.musicStart - 0.15) } ?? 0
            play(sel, from: start)
            return
        }
        if let id = playingSongID, player != nil { play(id, show: playingShowID, keepLineup: playingLineupID != nil); return }
        if let id = selectedSongID { play(id, from: 0) }
    }

    func pause() {
        finishCrossfade()
        // the next song already came in under a transition: let the transition finish now
        if activeBlock != nil, playingSongID != nil {
            blockEndWork?.cancel(); blockEndWork = nil
            fadingPlayer?.stop(); fadingPlayer = nil
            activeBlock = nil
        }
        if pauseTime == nil, isPlaying || activePresetID != nil || activeBlock != nil {
            pauseTime = Date().timeIntervalSinceReferenceDate
            pausedPresetElapsed = activePresetID != nil ? pauseTime! - presetStart : nil
        }
        player?.pause()
        if var b = activeBlock, b.pausedRemaining == nil {
            gapWork?.cancel(); gapWork = nil
            b.pausedRemaining = max(0.1, b.length - (Date().timeIntervalSinceReferenceDate - b.start))
            blockEndWork?.cancel(); blockEndWork = nil
            activeBlock = b
            fadingPlayer?.pause()
        }
        isPlaying = false
    }

    /// Un-freezes the lights; a live look carries on from where it was.
    private func resumeFromPause() {
        guard pauseTime != nil else { return }
        if let e = pausedPresetElapsed { presetStart = Date().timeIntervalSinceReferenceDate - e }
        pauseTime = nil
        pausedPresetElapsed = nil
        resumedAt = Date().timeIntervalSinceReferenceDate
    }
    private var resumedAt: Double?
    private var smoothPan: [Double] = [], smoothTilt: [Double] = []

    // MARK: - Fade to another song (second play button)

    /// The song fading out while another fades in: (song, show, when the fade started, how long).
    private var crossFrom: (song: UUID, show: UUID?, start: Double, length: Double)?
    private var crossWork: DispatchWorkItem?
    @Published var crossfadeSeconds: Double = UserDefaults.standard.object(forKey: "crossfadeSeconds") as? Double ?? 6 {
        didSet { UserDefaults.standard.set(crossfadeSeconds, forKey: "crossfadeSeconds") }
    }
    var isCrossfading: Bool { crossFrom != nil }
    /// A song picked in a set list (single click): Fade to plays it and the set carries on from there.
    @Published var selectedEntry: (lineup: UUID, index: Int)?

    /// Fades from the song that's playing into `id`: music and lights blend over `crossfadeSeconds`.
    func fadeTo(_ id: UUID) {
        guard isPlaying, let cur = playingSongID, cur != id, let p = player else {
            selectedSongID = id
            play(id, from: songStart(id))
            return
        }
        finishCrossfade()
        let len = max(1, crossfadeSeconds)
        p.setVolume(0, fadeDuration: len)
        fadingPlayer = p
        player = nil
        crossFrom = (cur, playingShowID, Date().timeIntervalSinceReferenceDate, len)
        let entry = selectedEntry.flatMap { se -> (UUID, Int)? in
            guard let li = lineupIndex(se.lineup), se.index < lineups[li].entries.count,
                  lineups[li].entries[se.index].songID == id else { return nil }
            return (se.lineup, se.index)
        }
        selectedSongID = id
        if let (lid, idx) = entry, let li = lineupIndex(lid) {
            // continue the set from the song faded into
            play(id, show: lineups[li].entries[idx].showID, from: songStart(id), keepLineup: true, fadeIn: min(len, 4), keepBlock: true)
            playingLineupID = lid; playingEntryIndex = idx
        } else {
            playingLineupID = nil; playingEntryIndex = nil
            play(id, from: songStart(id), fadeIn: min(len, 4), keepBlock: true)
        }
        let w = DispatchWorkItem { [weak self] in self?.finishCrossfade() }
        crossWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + len, execute: w)
    }

    private func finishCrossfade() {
        crossWork?.cancel(); crossWork = nil
        if crossFrom != nil { fadingPlayer?.stop(); fadingPlayer = nil }
        crossFrom = nil
    }

    /// One song's show at a moment in that song (for blending two songs during a fade).
    func songFrame(_ songID: UUID, show showID: UUID?, at time: Double, idleFrame: [RenderedFixture]) -> [RenderedFixture]? {
        guard let i = index(of: songID), let a = songs[i].analysis,
              let show = songs[i].shows.first(where: { $0.id == showID }) ?? songs[i].activeShow else { return nil }
        let linked = fixtures.indices.filter { show.includes(fixtures[$0]) && fixtures[$0].isOn && fixtures[$0].effectiveBehavior == .sequence && copySource(of: $0) == nil }
        var r = ShowRenderer(analysis: a, sections: show.sections, fixtures: linked.map { fixtures[$0] })
        r.hits = show.hits ?? []
        r.idle = idle
        r.rig = rigMode
        let part = r.renderWithIdle(at: time + (songs[i].syncOffsetMs + globalLatencyMs) / 1000)
        var full = idleFrame
        for (j, fi) in linked.enumerated() where j < part.count { full[fi] = part[j] }
        return full
    }
    /// How bright the lights stay while paused (same colors, dimmed).
    static let pausedLevel = 0.25

    func stop() {
        finishCrossfade()
        resumeFromPause()
        cancelGap()
        activeBlock = nil
        blockEndWork?.cancel(); blockEndWork = nil
        cuedEntry = nil
        fadingPlayer?.stop(); fadingPlayer = nil
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
        // Cued set (or a song marked "wait for cue"): hold the next one ready for Space / →
        let nextEntry = lineups[li].entries[idx + 1]
        if lineups[li].mode == .cued || (nextEntry.waitForCue ?? false) { advance(lineup, to: idx + 1); return }
        // A block next in line replaces the gap
        if nextEntry.isBlock { playLineup(lineup, from: idx + 1); return }
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
        // Paused: the lights freeze exactly where they are (same frame every tick) until play
        let now = pauseTime ?? Date().timeIntervalSinceReferenceDate
        var rendered: [RenderedFixture]
        var t: Double = now

        if testMode != .off {
            rendered = testFrame(now)
        } else {
            let idleFrame = idle.render(fixtures: fixtures, time: now)  // all lights, same order as `fixtures`
            var showFrame: [RenderedFixture]? = nil

            if player == nil, !stemPlayers.isEmpty { stopStems() }
            if let id = playingSongID, let i = index(of: id), let p = player {
                currentTime = p.currentTime
                syncStems(i, p)
                if isPlaying && !p.isPlaying {
                    // Stopped before the end = the sound was paused from outside (media key, headphones
                    // unplugged, another app): pause the lights too instead of skipping ahead.
                    if p.currentTime > 0.05 && p.currentTime < p.duration - 0.5 {
                        pause()
                    } else {
                        songFinished()
                        return
                    }
                }
                // In a set list, move on as soon as the music ends instead of playing out silent tails
                if isPlaying, let lid = playingLineupID, let li = lineupIndex(lid), lineups[li].skipDeadAir ?? true,
                   let a = songs[i].analysis, a.musicEnd < a.duration - 0.5, p.currentTime > a.musicEnd + 0.3 {
                    songFinished()
                    return
                }
                // A transition that fades the music starts while this song is still ending
                if isPlaying, let lid = playingLineupID, let li = lineupIndex(lid), let idx = playingEntryIndex,
                   idx + 1 < lineups[li].entries.count {
                    let nx = lineups[li].entries[idx + 1]
                    if let ct = crossTiming(idx + 1, in: lineups[li]) {
                        let a = songs[i].analysis
                        let end = a?.musicEnd ?? p.duration
                        // start right on a beat over the outro
                        var at = end - ct.lead
                        if let beats = a?.beats, let near = beats.min(by: { abs($0 - at) < abs($1 - at) }), abs(near - at) < 0.6 { at = near }
                        if p.currentTime >= at {
                            startBlock(nx, lineup: lid, index: idx + 1, keepPlayer: true, cross: ct)
                            return
                        }
                    }
                }
                let showID = playingShowID ?? songs[i].activeShow?.id
                if let a = songs[i].analysis, let show = songs[i].shows.first(where: { $0.id == showID }) ?? songs[i].activeShow {
                    t = p.currentTime + (songs[i].syncOffsetMs + globalLatencyMs) / 1000
                    // Only the lights linked to this show run it; the rest stay on the idle look
                    let linked = fixtures.indices.filter { show.includes(fixtures[$0]) && fixtures[$0].isOn && fixtures[$0].effectiveBehavior == .sequence && copySource(of: $0) == nil }
                    var r = ShowRenderer(analysis: a, sections: show.sections, fixtures: linked.map { fixtures[$0] })
                    r.hits = show.hits ?? []
                    r.idle = idle
                    r.rig = rigMode
                    let part = r.renderWithIdle(at: t)
                    var full = idleFrame
                    for (j, fi) in linked.enumerated() where j < part.count { full[fi] = part[j] }
                    showFrame = full
                }
                // Fading from another song: blend that song's lights into this one's
                if let cf = crossFrom, let fp = fadingPlayer,
                   let old = songFrame(cf.song, show: cf.show, at: fp.currentTime, idleFrame: idleFrame) {
                    let k = min(1, max(0, (Date().timeIntervalSinceReferenceDate - cf.start) / cf.length))
                    showFrame = blendRendered(old, showFrame ?? idleFrame, k)
                }
            }

            runAutoLighting(now: now)
            // Live look (tapped preset): runs on the beat clock, and overrides a playing song's show
            if let pid = activePresetID, let preset = presets.first(where: { $0.id == pid }) {
                var onsets: [Double] = []
                var level = 0.7
                if beatSource == .mic {
                    let snap = mic.snapshot()
                    clock.bpm = snap.bpm; clock.anchor = snap.anchor
                    onsets = snap.onsets; level = max(0.3, snap.level)
                    if snap.level > 0.08 { lastLoud = now }
                }
                let la = clock.liveAnalysis(now: now, onsets: onsets, level: level, useOnsetsAsKicks: beatSource == .mic)
                let linked = fixtures.indices.filter { fixtures[$0].isOn && fixtures[$0].effectiveBehavior == .sequence && copySource(of: $0) == nil }
                var r = ShowRenderer(analysis: la, sections: [preset.asSection(start: presetStart)], fixtures: linked.map { fixtures[$0] })
                r.rig = rigMode
                let part = r.render(at: now)
                var full = idleFrame
                for (j, fi) in linked.enumerated() where j < part.count { full[fi] = part[j] }
                // Music Break: the music dropped out → ease to the idle look until it comes back
                let quiet = beatSource == .mic && musicBreak && now - lastLoud > 1.2
                breakBlend = quiet ? min(1, breakBlend + 1.0 / 20) : max(0, breakBlend - 1.0 / 4)
                showFrame = breakBlend > 0.001 ? blendRendered(full, idleFrame, breakBlend) : full
                t = now
            }

            // Cued set waiting for Space / →: the set's "while waiting" look
            if cuedEntry != nil, activePresetID == nil, let lid = playingLineupID, let li = lineupIndex(lid) {
                showFrame = renderWaitLook(lineups[li].waitLook, now: now, idleFrame: idleFrame)
                t = now
            }

            // Set list block (silence / transition) between songs
            // A transition takes over the lights for its length, easing in from the song's own
            // programming and easing back into it at the end (no hard cuts).
            if let b = activeBlock, activePresetID == nil {
                let blockFrame = renderBlock(b, now: now, idleFrame: idleFrame)
                let elapsed = b.pausedRemaining.map { b.length - $0 } ?? (now - b.start)
                let edge = min(1.0, max(0.2, b.length * 0.18))
                let k = max(0, min(1, elapsed / edge, (b.length - elapsed) / edge))
                let underneath = showFrame ?? idleFrame
                showFrame = blendRendered(underneath, blockFrame, k)
                t = now
            }

            // Smoothly ramp between show and idle when a song starts, pauses or stops
            let target: Double = (showFrame != nil && (isPlaying || activePresetID != nil || cuedEntry != nil || pauseTime != nil)) ? 0 : 1
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

        // Stationary lights (like the spotlight) hold their own settings
        if testMode == .off {
            let showRunning = playingSongID != nil || inGap || activeBlock != nil || cuedEntry != nil
            for (i, fx) in fixtures.enumerated() where i < rendered.count && fx.effectiveBehavior == .stationary {
                let look = fx.stationaryLook
                rendered[i] = (showRunning || look.onWhenIdle) ? look.render(fx)
                    : RenderedFixture(heads: Array(repeating: .off, count: fx.headCount))
            }
        }

        // Hands-on control from the light's control panel
        if testMode == .off {
            for (i, fx) in fixtures.enumerated() where i < rendered.count {
                guard let m = manual[fx.id] else { continue }
                for h in rendered[i].heads.indices {
                    if let c = m.color {
                        rendered[i].heads[h].color = c
                        if m.dimmer == nil { rendered[i].heads[h].intensity = max(rendered[i].heads[h].intensity, 1) }
                    }
                    if let d = m.dimmer { rendered[i].heads[h].intensity = d }
                }
                if let s = m.strobe { rendered[i].strobe = s }
                if let p = m.pan { rendered[i].pan = p }
                if let tl = m.tilt { rendered[i].tilt = tl }
            }
        }

        // Chained lights on the same address physically do the same thing: mirror them
        for i in rendered.indices { if let src = copySource(of: i), src < rendered.count { rendered[i] = rendered[src] } }

        // Beat light + BPM readout
        if beatSource == .mic && activePresetID == nil {
            let snap = mic.snapshot(); clock.bpm = snap.bpm; clock.anchor = snap.anchor
        }
        if tickCount % 40 == 0 {
            let c = engine.mainPacketsSent
            let pps = max(0, c - lastPacketCount)
            lastPacketCount = c
            if pps != packetsPerSecond { packetsPerSecond = pps }
        }
        if tickCount % 4 == 0 {
            let bpmNow: Double
            if let id = playingSongID, let a = song(id)?.analysis, activePresetID == nil { bpmNow = a.bpm } else { bpmNow = clock.bpm }
            if abs(bpmNow - displayBPM) > 0.4 { displayBPM = bpmNow }
            if beatSource == .mic { let l = mic.snapshot().level; if abs(l - micLevel) > 0.05 { micLevel = l } }
        }
        let phase = clock.beatNumber(at: now) - floor(clock.beatNumber(at: now))
        let on = phase < 0.18
        if on != beatOn { beatOn = on }

        // Smooth movement: heads glide to where the show wants them instead of snapping (no jerky moves)
        if testMode == .off {
            if smoothPan.count != rendered.count { smoothPan = rendered.map(\.pan); smoothTilt = rendered.map(\.tilt) }
            let a = 1 - exp(-(1.0 / 40.0) / 0.07)   // light smoothing: moves are already eased and beat-timed
            for i in rendered.indices {
                smoothPan[i] += (rendered[i].pan - smoothPan[i]) * a
                smoothTilt[i] += (rendered[i].tilt - smoothTilt[i]) * a
                rendered[i].pan = smoothPan[i]; rendered[i].tilt = smoothTilt[i]
            }
        }

        // Paused: hold the same colors, dimmed, no strobing (eases down; eases back up on play)
        let wall = Date().timeIntervalSinceReferenceDate
        var dimK = 1.0
        if let pt = pauseTime { dimK = 1 - (1 - Self.pausedLevel) * min(1, (wall - pt) / 0.6) }
        else if let r = resumedAt, wall - r < 0.4 { dimK = Self.pausedLevel + (1 - Self.pausedLevel) * ((wall - r) / 0.4) }
        if dimK < 1 {
            for i in rendered.indices {
                for h in rendered[i].heads.indices { rendered[i].heads[h].intensity *= dimK }
                if pauseTime != nil { rendered[i].strobe = 0 }
            }
        }

        // Blinder: full white while held, then fades out (about a second)
        blinderLevel = blinderHeld ? 1 : blinderLevel * 0.93
        if blinderLevel > 0.01 {
            for i in rendered.indices { for h in rendered[i].heads.indices {
                rendered[i].heads[h].color = rendered[i].heads[h].color.mix(.white, blinderLevel)
                rendered[i].heads[h].intensity = max(rendered[i].heads[h].intensity, blinderLevel)
            } }
        }
        // Paparazzi: random heads pop like camera flashes (no faster than the flash limit allows)
        if paparazziHeld && ShowRenderer.maxFlashHz > 0 {
            let step = Int(now * min(8, ShowRenderer.maxFlashHz * 2))
            var n = 0
            for i in rendered.indices { for h in rendered[i].heads.indices {
                var x = UInt64(truncatingIfNeeded: (n &* 2246822519) ^ (step &* 3266489917))
                x ^= x >> 15; x = x &* 0xBF58476D1CE4E5B9; x ^= x >> 31
                if x % 5 == 0 { rendered[i].heads[h].color = .white; rendered[i].heads[h].intensity = 1 }
                n += 1
            } }
        }

        // Live hold buttons override everything
        if flashHeld || strobeHeld {
            for i in rendered.indices {
                for h in rendered[i].heads.indices {
                    rendered[i].heads[h].intensity = 1
                    if flashHeld { rendered[i].heads[h].color = .white }
                }
                if strobeHeld { rendered[i].strobe = 1 }
            }
        }

        // Lights switched off: dark on screen. On the wire, lights sharing one address get the
        // same signal, so that address only goes dark when every light on it is off.
        func dark(_ r: RenderedFixture) -> RenderedFixture {
            var d = r; for h in d.heads.indices { d.heads[h].intensity = 0 }; d.strobe = 0; return d
        }
        var wire = rendered
        var isCopy = [Bool](repeating: false, count: fixtures.count)
        for i in fixtures.indices where i < rendered.count {
            if copySource(of: i) != nil { isCopy[i] = true; continue }
            let group = fixtures.indices.filter { $0 == i || copySource(of: $0) == i }
            if !group.contains(where: { fixtures[$0].isOn }) { wire[i] = dark(rendered[i]) }
        }
        for i in fixtures.indices where i < rendered.count && !fixtures[i].isOn { rendered[i] = dark(rendered[i]) }

        // One DMX frame per output device
        var frames: [String: [UInt8]] = [:]
        // Hue lights go over Wi-Fi to the Hue Bridge, not DMX
        sendHue(wire)
        let keys = Set(fixtures.map { $0.outputKey ?? DMXEngine.mainKey }).filter { !$0.hasPrefix("hue:") }
        for key in keys {
            let idx = fixtures.indices.filter { (fixtures[$0].outputKey ?? DMXEngine.mainKey) == key && $0 < wire.count && !isCopy[$0] }
            frames[key] = DMXMapper.frame(fixtures: idx.map { fixtures[$0] }, rendered: idx.map { wire[$0] },
                                          master: master, blackout: blackout, time: t)
        }
        if !outputEnabled {
            // Simulation only: keep the real lights dark, but keep everything running on screen
            for k in frames.keys { frames[k] = [UInt8](repeating: 0, count: 512) }
        }
        engine.setFrames(frames)

        tickCount += 1
        // Nothing on screen to update while the window is hidden or minimized: keep sending DMX, skip the UI
        if tickCount % 20 == 0 { windowShowing = NSApp.windows.contains { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) } }
        if windowShowing && tickCount % 2 == 0 && rendered != preview { preview = rendered }
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
                case .tiltTest:
                    heads.append(FixtureState(intensity: 1, color: .white))
                case .beamTest:
                    // red, orange, yellow, green, cyan, blue, purple, pink across the beams; a colour wheel steps through its colours
                    let target = identifyFixtureID.map { id in id == fx.id || sharesAddress(id).contains { $0.id == fx.id } } ?? false
                    let h = Double(heads.count) / Double(max(1, fx.headCount))
                    let col = fx.headCount > 1 ? RGB(h: h * 0.9, s: 1, v: 1)
                                               : [RGB.white, RGB(h: 0, s: 1, v: 1), RGB(h: 0.33, s: 1, v: 1), RGB(h: 0.66, s: 1, v: 1)][Int(t) % 4]
                    heads.append(FixtureState(intensity: target ? 1 : 0, color: col))
                case .off:
                    heads.append(.off)
                }
                p += 1
            }
            var rf = RenderedFixture(heads: heads)
            if testMode == .rainbow { rf.tilt = 0.5 + 0.3 * sin(t) }
            if testMode == .tiltTest { rf.tilt = Int(t / 1.5) % 2 == 0 ? 0.02 : 0.98; rf.pan = rf.tilt }
            return rf
        }
    }
}

/// Fast-changing values the UI shows. Separate from AppModel so updating them doesn't redraw every screen.
final class LiveState: ObservableObject {
    @Published var preview: [RenderedFixture] = []
    @Published var currentTime: Double = 0
    @Published var beatOn = false
    @Published var micLevel: Double = 0
}

/// The play position at 4 updates a second, for big views (the lyrics list) that don't need 40.
final class CoarseClock: ObservableObject {
    @Published var time: Double = 0
}
struct CoarseReader<Content: View>: View {
    @ObservedObject var clock: CoarseClock
    let content: () -> Content
    init(_ clock: CoarseClock, @ViewBuilder content: @escaping () -> Content) { self.clock = clock; self.content = content }
    var body: some View { content() }
}

/// Redraws only its contents when the live values change.
struct LiveReader<Content: View>: View {
    @ObservedObject var live: LiveState
    let content: () -> Content
    init(_ live: LiveState, @ViewBuilder content: @escaping () -> Content) { self.live = live; self.content = content }
    var body: some View { content() }
}

/// A silence or transition block that's running in a set list.
struct ActiveBlock {
    var entry: LineupEntry
    var start: Double
    var bpm: Double
    var length: Double
    var pausedRemaining: Double? = nil
}

/// How a transition blends two songs: it starts `lead` seconds before the first song's music ends
/// (over its outro), and the next song comes in after `lead`, under the rest of the transition (its intro).
struct CrossTiming {
    var seconds: Double
    var lead: Double
    var leadIn: Double
}
