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
    var rigMode: RigMode? = nil
    var sessions: [Session]? = nil
    var lastSessionID: UUID? = nil
    var chainedBarsFix: Bool? = nil   // one-time: Beam Bar 2 moved to A.001 to match the real rig
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
    @Published var rigMode: RigMode = .together { didSet { scheduleSave() } }
    @Published var presets: [LookPreset] = LookPreset.defaults { didSet { scheduleSave() } }
    @Published var sessions: [Session] = [] { didSet { scheduleSave() } }
    @Published var currentSessionID: UUID?
    @Published var showingStart = true           // the black Sessions screen

    // Live looks and beat tracking
    @Published var activePresetID: UUID?
    private var presetStart: Double = 0
    @Published var beatSource: BeatSource = .manual { didSet { beatSourceChanged(oldValue) } }
    @Published var displayBPM: Double = 120
    var beatOn: Bool { get { live.beatOn } set { live.beatOn = newValue } }   // pulses on each beat (for the BPM light)
    var micLevel: Double { get { live.micLevel } set { live.micLevel = newValue } }
    @Published var audioInputs: [AudioInputDevice] = []
    @Published var autoLighting = false { didSet { if autoLighting && beatSource != .mic { beatSource = .mic } } }  // pick looks from what it hears
    private var autoEnergy = 0.0
    private var windowShowing = true
    private var scanTicks = 0
    var wirelessPageOpen = false
    private var lastAutoChange: Double = 0      // when Auto Lighting last switched looks
    private var clock = BeatClock()
    private var tapTimes: [Double] = []
    private let mic = MicBeatTracker()
    @Published var manual: [UUID: ManualControl] = [:]   // hands-on control per light
    @Published var outputEnabled = true          // off = simulate only, real lights stay dark
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
    @Published var isPlaying = false
    var currentTime: Double { get { live.currentTime } set { if live.currentTime != newValue { live.currentTime = newValue } } }
    @Published var learning: [UUID: Double] = [:]
    var preview: [RenderedFixture] { get { live.preview } set { live.preview = newValue } }
    /// Fast-changing state (light preview, playhead, beat light, mic level) lives in its own object, so only
    /// the small views that show it redraw 20-40 times a second, not every screen of the app.
    let live = LiveState()
    @Published var master: Double = 1
    @Published var blackout = false
    @Published var flashHeld = false     // hold: everything full white
    @Published var strobeHeld = false    // hold: everything strobes
    @Published var testMode: TestMode = .off
    @Published var identifyFixtureID: UUID?
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
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] e in
            guard let self else { return e }
            let mods = e.modifierFlags.intersection([.command, .option, .control])
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
        guard let data = try? Data(contentsOf: Self.storeURL),
              let lib = try? JSONDecoder().decode(Library.self, from: data) else {
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
        if !presets.contains(where: { $0.effect == .soundLevel }), let fs = LookPreset.essentials.last { presets.append(fs) }
        // One time per session: add the themed looks (Fairy, EDM, Dubstep, Techno, Disco, Pop, Psychedelic…)
        let packKey = "presetPack.themes1.\(s.id.uuidString)"
        if !UserDefaults.standard.bool(forKey: packKey) {
            let have = Set(presets.map(\.name))
            presets += LookPreset.themePack.filter { !have.contains($0.name) }
            UserDefaults.standard.set(true, forKey: packKey)
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

    /// Presets grouped by theme, in a fixed order (custom groups after the built-in ones).
    var presetGroups: [(name: String, presets: [LookPreset])] {
        var order = LookPreset.groupOrder
        for p in presets { let g = p.group ?? "Essentials"; if !order.contains(g) { order.append(g) } }
        return order.compactMap { g in
            let list = presets.filter { ($0.group ?? "Essentials") == g }
            return list.isEmpty ? nil : (g, list)
        }
    }

    func togglePreset(_ id: UUID) {
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

    /// Quitting: stop music, listening and timers, darken the lights, and save, quickly and in order.
    func prepareToQuit() {
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

    func saveNow(sync: Bool = false) {
        captureCurrentSession()
        let lib = Library(fixtures: fixtures, songs: songs, lineups: lineups, output: output,
                          idle: idle, globalLatencyMs: globalLatencyMs, rigMode: rigMode,
                          sessions: sessions, lastSessionID: currentSessionID, chainedBarsFix: true)
        let write = {
            if let data = try? JSONEncoder().encode(lib) {
                try? data.write(to: Self.storeURL, options: .atomic)
            }
        }
        if sync { write() } else { DispatchQueue.global(qos: .utility).async(execute: write) }
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
        fixtures.append(Fixture(name: "\(base) \(count + 1)", address: min(nextFreeAddress, 512),
                                profileName: profile.name, layout: profile.layout))
    }

    func addressConflicts(for fx: Fixture) -> [Fixture] {
        fixtures.filter { $0.id != fx.id && $0.address <= fx.lastAddress && fx.address <= $0.lastAddress }
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
            let song = Song(title: meta.title, path: url.path, artist: meta.artist)
            songs.append(song)
            ids.append(song.id)
            learn(song.id)
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
    func learn(_ id: UUID) {
        guard let i = index(of: id), learning[id] == nil else { return }
        let url = songs[i].url
        let title = songs[i].title
        learning[id] = 0.05
        guard FileManager.default.fileExists(atPath: url.path) else {
            learning[id] = nil
            ErrorCenter.shared.report(area: "Learn", message: "Couldn't find the file for \"\(title)\". It may have been moved or deleted.", details: url.path)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("learn-\(id.uuidString).json")
            // Learn in a separate helper process: a bad file can't crash the app
            let r = Helper.run(["--learn", url.path, out.path], timeout: 600)
            let analysis = (try? Data(contentsOf: out)).flatMap { try? JSONDecoder().decode(SongAnalysis.self, from: $0) }
            try? FileManager.default.removeItem(at: out)
            DispatchQueue.main.async {
                self.learning[id] = nil
                guard let analysis, r.status == 0 else {
                    let msg = r.crashed
                        ? "Learning \"\(title)\" stopped unexpectedly. The app is fine; please report this so it can be fixed."
                        : "Couldn't learn \"\(title)\": \(r.stderr.isEmpty ? "the file couldn't be read" : r.stderr)"
                    ErrorCenter.shared.report(area: "Learn", message: msg, details: "file: \(url.lastPathComponent)\nexit \(r.status)\n\(r.stderr)")
                    return
                }
                guard let i = self.index(of: id) else { return }
                self.songs[i].analysis = analysis
                if self.songs[i].shows.isEmpty { self.createShow(for: id) }
            }
        }
    }

    /// Builds a new light show from what was learned, using the song's genre (or the one passed in).
    func createShow(for id: UUID, style: ShowStyle? = nil) {
        guard let i = index(of: id), let a = songs[i].analysis else { return }
        let st = style ?? songs[i].effectiveGenre
        let variation = (songs[i].shows.filter { $0.style == st }.map(\.variation).max() ?? 0) + 1
        let name = variation == 1 ? "\(st.rawValue)" : "\(st.rawValue) #\(variation)"
        // Build for the lights that are switched on in this session right now
        let onLights = fixtures.filter { $0.isOn }
        var sections = ShowGenerator.generate(a, style: st, variation: variation)
        ShowGenerator.fit(&sections, to: onLights.filter { $0.effectiveBehavior == .sequence })
        let show = LightShow(name: name, style: st, variation: variation, sections: sections,
                             fixtureIDs: onLights.isEmpty ? nil : onLights.map(\.id))
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
    func playLineup(_ id: UUID, from entry: Int = 0) {
        guard let li = lineupIndex(id), lineups[li].entries.indices.contains(entry) else { stop(); return }
        let e = lineups[li].entries[entry]
        guard song(e.songID) != nil else { playLineup(id, from: entry + 1); return }
        // Skip the silent lead-in baked into the file (keep a hair of it so the first hit isn't clipped)
        var start = 0.0
        if lineups[li].skipDeadAir ?? true, let a = song(e.songID)?.analysis {
            start = max(0, a.musicStart - 0.15)
        }
        play(e.songID, show: e.showID, from: start, keepLineup: true)
        playingLineupID = id
        playingEntryIndex = entry
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
        CrashGuard.breadcrumb("Playing \(songs[i].title)")
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
            let idleFrame = idle.render(fixtures: fixtures, time: now)  // all lights, same order as `fixtures`
            var showFrame: [RenderedFixture]? = nil

            if let id = playingSongID, let i = index(of: id), let p = player {
                currentTime = p.currentTime
                if isPlaying && !p.isPlaying {
                    songFinished()
                    return
                }
                // In a set list, move on as soon as the music ends instead of playing out silent tails
                if isPlaying, let lid = playingLineupID, let li = lineupIndex(lid), lineups[li].skipDeadAir ?? true,
                   let a = songs[i].analysis, a.musicEnd < a.duration - 0.5, p.currentTime > a.musicEnd + 0.3 {
                    songFinished()
                    return
                }
                let showID = playingShowID ?? songs[i].activeShow?.id
                if let a = songs[i].analysis, let show = songs[i].shows.first(where: { $0.id == showID }) ?? songs[i].activeShow {
                    t = p.currentTime + (songs[i].syncOffsetMs + globalLatencyMs) / 1000
                    // Only the lights linked to this show run it; the rest stay on the idle look
                    let linked = fixtures.indices.filter { show.includes(fixtures[$0]) && fixtures[$0].isOn && fixtures[$0].effectiveBehavior == .sequence && copySource(of: $0) == nil }
                    var r = ShowRenderer(analysis: a, sections: show.sections, fixtures: linked.map { fixtures[$0] })
                    r.idle = idle
                    r.rig = rigMode
                    let part = r.renderWithIdle(at: t)
                    var full = idleFrame
                    for (j, fi) in linked.enumerated() where j < part.count { full[fi] = part[j] }
                    showFrame = full
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
                }
                let la = clock.liveAnalysis(now: now, onsets: onsets, level: level, useOnsetsAsKicks: beatSource == .mic)
                let linked = fixtures.indices.filter { fixtures[$0].isOn && fixtures[$0].effectiveBehavior == .sequence && copySource(of: $0) == nil }
                var r = ShowRenderer(analysis: la, sections: [preset.asSection(start: presetStart)], fixtures: linked.map { fixtures[$0] })
                r.rig = rigMode
                let part = r.render(at: now)
                var full = idleFrame
                for (j, fi) in linked.enumerated() where j < part.count { full[fi] = part[j] }
                showFrame = full
                t = now
            }

            // Smoothly ramp between show and idle when a song starts, pauses or stops
            let target: Double = (showFrame != nil && (isPlaying || activePresetID != nil)) ? 0 : 1
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
            let showRunning = playingSongID != nil || inGap
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
        let keys = Set(fixtures.map { $0.outputKey ?? DMXEngine.mainKey })
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

/// Fast-changing values the UI shows. Separate from AppModel so updating them doesn't redraw every screen.
final class LiveState: ObservableObject {
    @Published var preview: [RenderedFixture] = []
    @Published var currentTime: Double = 0
    @Published var beatOn = false
    @Published var micLevel: Double = 0
}

/// Redraws only its contents when the live values change.
struct LiveReader<Content: View>: View {
    @ObservedObject var live: LiveState
    let content: () -> Content
    init(_ live: LiveState, @ViewBuilder content: @escaping () -> Content) { self.live = live; self.content = content }
    var body: some View { content() }
}
