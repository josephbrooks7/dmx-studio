import SwiftUI
import CoreMIDI

// MIDI: play Live Control pads from any MIDI controller (Learn MIDI), and follow MIDI Clock from
// DJ software or a DAW (rekordbox, Serato, Traktor, VirtualDJ, Ableton…) for tempo and beat.

/// One key, pad or knob on a controller
struct MIDIBinding: Codable, Hashable {
    var isCC: Bool
    var channel: UInt8
    var number: UInt8
    var label: String { (isCC ? "CC " : "Note ") + "\(number)" + (channel > 0 ? " · ch \(channel + 1)" : "") }
}

/// Listens to every connected MIDI device
final class MIDIInput {
    static let shared = MIDIInput()
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var started = false
    /// (status, data1, data2, time in Date().timeIntervalSinceReferenceDate)
    var onMessage: ((UInt8, UInt8, UInt8, Double) -> Void)?
    var onDevicesChanged: (([String]) -> Void)?

    private let timebase: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1e9
    }()

    func start() {
        guard !started else { return }
        started = true
        MIDIClientCreateWithBlock("DMX Studio" as CFString, &client) { [weak self] note in
            if note.pointee.messageID == .msgSetupChanged { DispatchQueue.main.async { self?.connectAll() } }
        }
        MIDIInputPortCreateWithBlock(client, "DMX Studio In" as CFString, &port) { [weak self] list, _ in
            self?.read(list)
        }
        connectAll()
    }

    private func connectAll() {
        var names: [String] = []
        for i in 0..<MIDIGetNumberOfSources() {
            let src = MIDIGetSource(i)
            MIDIPortConnectSource(port, src, nil)     // connecting twice is harmless
            var name: Unmanaged<CFString>?
            if MIDIObjectGetStringProperty(src, kMIDIPropertyDisplayName, &name) == noErr, let n = name?.takeRetainedValue() {
                names.append(n as String)
            }
        }
        onDevicesChanged?(names)
    }

    private func read(_ list: UnsafePointer<MIDIPacketList>) {
        let nowHost = mach_absolute_time()
        let nowDate = Date().timeIntervalSinceReferenceDate
        var packet = list.pointee.packet
        for _ in 0..<list.pointee.numPackets {
            let ts = packet.timeStamp
            let when = ts == 0 || ts > nowHost ? nowDate : nowDate - Double(nowHost - ts) * timebase
            let bytes = withUnsafeBytes(of: packet.data) { Array($0.prefix(Int(packet.length))) }
            var i = 0
            var running: UInt8 = 0
            while i < bytes.count {
                let b = bytes[i]
                if b >= 0xF8 { onMessage?(b, 0, 0, when); i += 1; continue }       // clock, start, stop…
                if b >= 0xF0 { i += 1; continue }                                   // system messages: skip
                var status = running, d1: UInt8 = 0, d2: UInt8 = 0
                if b & 0x80 != 0 { status = b; running = b; i += 1 }
                guard status != 0, i < bytes.count else { break }
                d1 = bytes[i]; i += 1
                let kind = status & 0xF0
                if kind != 0xC0 && kind != 0xD0 { guard i < bytes.count else { break }; d2 = bytes[i]; i += 1 }
                onMessage?(status, d1, d2, when)
            }
            packet = MIDIPacketNext(&packet).pointee
        }
    }
}

/// Works out tempo and beat from MIDI Clock (24 ticks per beat)
struct MIDIClockFollower {
    private var ticks: [Double] = []
    private var tickCount = 0
    var bpm: Double?
    var beatTime: Double?
    var running = false

    mutating func start() { tickCount = 0; ticks = []; running = true }
    mutating func stop() { running = false }

    /// Returns true on a tick that starts a beat
    mutating func tick(_ t: Double) -> Bool {
        if let last = ticks.last, t - last > 0.5 { ticks = [] }          // clock paused: start over
        ticks.append(t)
        if ticks.count > 49 { ticks.removeFirst() }
        if ticks.count >= 13 {
            let per = (ticks.last! - ticks.first!) / Double(ticks.count - 1)
            if per > 0 { bpm = min(250, max(40, 60 / (per * 24))) }
        }
        defer { tickCount += 1 }
        if tickCount % 24 == 0 { beatTime = t; return true }
        return false
    }
}

extension AppModel {
    static let midiBindingsKey = "midiBindings"

    func startMIDI() {
        let midi = MIDIInput.shared
        midi.onDevicesChanged = { [weak self] names in self?.midiDevices = names }
        midi.onMessage = { [weak self] s, d1, d2, t in
            DispatchQueue.main.async { self?.handleMIDI(s, d1, d2, at: t) }
        }
        midi.start()
        if let data = UserDefaults.standard.data(forKey: Self.midiBindingsKey),
           let saved = try? JSONDecoder().decode([String: MIDIBinding].self, from: data) {
            midiBindings = saved
        }
    }

    func saveMIDIBindings() {
        if let data = try? JSONEncoder().encode(midiBindings) { UserDefaults.standard.set(data, forKey: Self.midiBindingsKey) }
    }

    func midiBinding(for target: String) -> MIDIBinding? { midiBindings[target] }

    func forgetMIDI(_ target: String) { midiBindings[target] = nil; saveMIDIBindings() }

    private func handleMIDI(_ status: UInt8, _ d1: UInt8, _ d2: UInt8, at t: Double) {
        // MIDI Clock
        switch status {
        case 0xF8:
            let first = midiClockSeen.map { Date().timeIntervalSince($0) > 2 } ?? true
            midiClockSeen = Date()
            if first { objectWillChange.send() }      // update "Following MIDI Clock" without redrawing on every tick
            guard beatSource == .midiClock else { return }
            if midiClock.tick(t), let bpm = midiClock.bpm, let bt = midiClock.beatTime {
                clock.bpm = bpm; clock.anchor = bt
                displayBPM = bpm
            }
            return
        case 0xFA: midiClock.start(); return               // start: next tick is beat 1
        case 0xFB: midiClock.running = true; return
        case 0xFC: midiClock.stop(); return
        default: break
        }
        let kind = status & 0xF0, ch = status & 0x0F
        guard kind == 0x90 || kind == 0x80 || kind == 0xB0 else { return }
        let isCC = kind == 0xB0
        let pressed = isCC ? d2 >= 64 : (kind == 0x90 && d2 > 0)
        let binding = MIDIBinding(isCC: isCC, channel: ch, number: d1)
        lastMIDI = binding.label + (isCC ? " = \(d2)" : (pressed ? " on" : " off"))

        // Learn MIDI: the next key / pad / knob is bound to the chosen control
        if let target = midiLearnTarget {
            guard isCC || pressed else { return }
            for (k, v) in midiBindings where v == binding { midiBindings[k] = nil }
            midiBindings[target] = binding
            midiLearnTarget = nil
            saveMIDIBindings()
            midiIgnoreRelease = binding      // the release of the learning press shouldn't trigger it
            return
        }
        if let ignore = midiIgnoreRelease, ignore == binding, !pressed { midiIgnoreRelease = nil; return }

        for (target, b) in midiBindings where b == binding {
            if target == "master" && isCC { master = Double(d2) / 127; continue }
            switch target {
            case "flash": flashHeld = pressed
            case "strobe": strobeHeld = pressed
            case "blackout": blackout = pressed
            case "tap": if pressed { tapTempo() }
            default:
                guard target.hasPrefix("preset:"), let id = UUID(uuidString: String(target.dropFirst(7))) else { continue }
                let mode = HitRelease(rawValue: UserDefaults.standard.string(forKey: "hitRelease") ?? "") ?? .hold
                if pressed {
                    if mode == .toggle && activePresetID == id { releasePreset(id) } else { holdPreset(id) }
                } else if mode == .hold {
                    releasePreset(id)
                } else if let s = mode.seconds {
                    DispatchQueue.main.asyncAfter(deadline: .now() + s) { self.releasePreset(id) }
                }
            }
        }
    }
}

/// Right-click menu items for any control that can be played from MIDI
struct MIDILearnMenu: View {
    @EnvironmentObject var model: AppModel
    let target: String
    var body: some View {
        Button(model.midiLearnTarget == target ? "Waiting for MIDI… (click to cancel)" : "Learn MIDI") {
            model.midiLearnTarget = model.midiLearnTarget == target ? nil : target
        }
        if let b = model.midiBinding(for: target) {
            Button("Forget MIDI (\(b.label))") { model.forgetMIDI(target) }
        }
    }
}

/// Small tag on a control showing its MIDI key, or that it's waiting to learn one
struct MIDITag: View {
    @EnvironmentObject var model: AppModel
    let target: String
    var body: some View {
        if model.midiLearnTarget == target {
            Text("PRESS A KEY").font(.system(size: 8, weight: .heavy))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Capsule().fill(Color.orange)).foregroundColor(.black)
        } else if let b = model.midiBinding(for: target) {
            Text(b.label).font(.system(size: 8, weight: .bold))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(0.55))).foregroundColor(.white.opacity(0.85))
        }
    }
}

/// MIDI status for the Live Control page
struct MIDIStatusBar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "pianokeys").foregroundColor(model.midiDevices.isEmpty ? .secondary : Theme.lightOn)
            Text(model.midiDevices.isEmpty ? "No MIDI devices" : "MIDI: " + model.midiDevices.joined(separator: ", "))
                .lineLimit(1)
            if let last = model.lastMIDI { Text("· last: " + last).foregroundColor(Theme.subtle).monospacedDigit() }
            if model.midiLearnTarget != nil {
                Text("· Press a key, pad or knob on your controller…").foregroundColor(.orange)
                Button("Cancel") { model.midiLearnTarget = nil }.buttonStyle(PillButtonStyle())
            }
            Spacer()
            if model.beatSource == .midiClock {
                Text(model.midiClockSeen.map { Date().timeIntervalSince($0) < 2 } == true ? "Following MIDI Clock" : "Waiting for MIDI Clock…")
                    .foregroundColor(model.midiClockSeen.map { Date().timeIntervalSince($0) < 2 } == true ? Theme.lightOn : .orange)
            }
        }
        .font(.caption)
    }
}
