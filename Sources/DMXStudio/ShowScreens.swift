import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Look & feel

enum Theme {
    static let accent = Color(red: 0.95, green: 0.16, blue: 0.36)        // Red Velvet
    static let accent2 = Color(red: 0.55, green: 0.25, blue: 1.0)
    static let bg = Color(red: 0.035, green: 0.035, blue: 0.045)
    static let panel = Color.white.opacity(0.055)
    static let panelBorder = Color.white.opacity(0.08)
    static let subtle = Color.white.opacity(0.55)
    // Each kind of highlight gets its own color, so they don't all read as the same burgundy:
    static let selection = Color(red: 0.22, green: 0.47, blue: 0.98)     // selected rows (blue, like Finder)
    static let lightOn = Color(red: 0.12, green: 0.74, blue: 0.64)       // lights included in a show (teal)
    static let tag = Color.white.opacity(0.13)                           // plain info tags
}

/// A chip that's switched on: a tinted fill with a bright edge in its own color
struct OnChip: ViewModifier {
    let color: Color
    let on: Bool
    func body(content: Content) -> some View {
        content
            .background(Capsule().fill(on ? color.opacity(0.28) : Color.white.opacity(0.06)))
            .overlay(Capsule().stroke(on ? color : Color.white.opacity(0.10), lineWidth: on ? 1.5 : 1))
            .foregroundColor(on ? .white : .secondary)
    }
}
extension View {
    func onChip(_ color: Color, _ on: Bool) -> some View { modifier(OnChip(color: color, on: on)) }
}

struct Panel<Content: View>: View {
    var padding: CGFloat = 16
    let content: Content
    init(padding: CGFloat = 16, @ViewBuilder _ content: () -> Content) { self.padding = padding; self.content = content() }
    var body: some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.panelBorder))
    }
}

struct PillButtonStyle: ButtonStyle {
    var active = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(active ? Theme.accent : Color.white.opacity(configuration.isPressed ? 0.18 : 0.09)))
            .foregroundColor(.white)
    }
}

// MARK: - Sessions (the black start screen)

struct SessionsScreen: View {
    @EnvironmentObject var model: AppModel
    @State private var renaming: UUID?
    @State private var renameText = ""

    private let cols = [GridItem(.adaptive(minimum: 230, maximum: 280), spacing: 22)]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [Theme.accent.opacity(0.18), .clear], center: .top, startRadius: 10, endRadius: 600)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("DMX Studio").font(.system(size: 38, weight: .heavy, design: .rounded))
                            Text("Red Velvet Studios").font(.system(size: 14, weight: .medium)).foregroundColor(Theme.accent)
                        }
                        Spacer()
                        UpdateBadge()
                        HStack(spacing: 6) {
                            Circle().fill(model.connected ? Color.green : Color.gray).frame(width: 8, height: 8)
                            Text(model.connected ? "Lights connected" : "Lights not connected")
                                .font(.caption).foregroundColor(Theme.subtle)
                        }
                    }
                    HStack {
                        Text("Your Sessions").font(.system(size: 20, weight: .bold))
                        Spacer()
                        Button { model.importSessionWithPanel() } label: { Label("Import Session…", systemImage: "square.and.arrow.down") }
                            .buttonStyle(PillButtonStyle())
                            .help("Open a .dmxsession file exported from DMX Studio on any computer")
                        Button { model.showLibraryFolder() } label: { Label("Show Files", systemImage: "folder") }
                            .buttonStyle(PillButtonStyle())
                            .help("Your sessions, presets, set lists and songs are saved in Documents › DMX Studio")
                    }
                    LazyVGrid(columns: cols, alignment: .leading, spacing: 22) {
                        Button { model.newSession() } label: {
                            VStack(spacing: 14) {
                                Image(systemName: "plus").font(.system(size: 34, weight: .light))
                                Text("New Session").font(.headline)
                                Text("Starts with your two beam bars and followspot").font(.caption).foregroundColor(Theme.subtle)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, minHeight: 210)
                            .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 6])).foregroundColor(Color.white.opacity(0.25)))
                        }
                        .buttonStyle(.plain)

                        ForEach(model.sessions.sorted { $0.modified > $1.modified }) { s in
                            SessionCard(session: s)
                                .onTapGesture { model.openSession(s.id) }
                                .contextMenu {
                                    Button("Open") { model.openSession(s.id) }
                                    Button("Rename…") { renaming = s.id; renameText = s.name }
                                    Button("Duplicate") { model.duplicateSession(s.id) }
                                    Button("Export…") { model.exportSessionWithPanel(s.id) }
                                    Divider()
                                    Button("Delete", role: .destructive) { model.deleteSession(s.id) }
                                }
                        }
                    }
                    if let rid = renaming {
                        HStack {
                            TextField("Session name", text: $renameText).textFieldStyle(.roundedBorder).frame(width: 300)
                            Button("Save") { model.renameSession(rid, to: renameText); renaming = nil }
                            Button("Cancel") { renaming = nil }
                        }
                    }
                    Text("Tip: right-click a session to rename, duplicate or delete it. Your song library is shared by every session.")
                        .font(.caption).foregroundColor(Theme.subtle)
                }
                .padding(40)
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct SessionCard: View {
    @EnvironmentObject var model: AppModel
    let session: Session
    @State private var hover = false

    var body: some View {
        let pal = Palette.named((session.presets ?? LookPreset.defaults).first?.palette ?? "Red Velvet")
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                LinearGradient(colors: [Color.black, Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
                HStack(spacing: 14) {
                    ForEach(Array(session.fixtures.prefix(4).enumerated()), id: \.offset) { i, _ in
                        RingShape(segments: 6, gap: 0.05)
                            .stroke(pal.color(i).color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                            .frame(width: 44, height: 44)
                            .shadow(color: pal.color(i).color.opacity(0.6), radius: 8)
                    }
                }
            }
            .frame(height: 130)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.name).font(.headline).lineLimit(1)
                Text("Edited \(session.modified, style: .date)").font(.caption).foregroundColor(Theme.subtle)
                Text("\(session.fixtures.count) lights · \(session.lineups.count) set list\(session.lineups.count == 1 ? "" : "s")")
                    .font(.caption).foregroundColor(Theme.subtle)
            }
            .padding(14)
        }
        .background(Color(white: 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(hover ? Theme.accent : (session.id == model.currentSessionID ? Color.white.opacity(0.3) : Theme.panelBorder), lineWidth: hover ? 2 : 1))
        .scaleEffect(hover ? 1.02 : 1)
        .animation(.easeOut(duration: 0.15), value: hover)
        .onHover { hover = $0 }
        .contentShape(Rectangle())
    }
}

// MARK: - Main shell with tabs

enum MainTab: String, CaseIterable, Identifiable {
    case show = "Show", stage = "Stage", live = "Live", songs = "Songs", sets = "Set Lists", setup = "Setup"
    var id: String { rawValue }
    /// What the tab is called on screen
    var title: String { self == .live ? "Live Control" : rawValue }
    var icon: String {
        switch self {
        case .show: return "lightbulb.fill"
        case .stage: return "theatermasks.fill"
        case .live: return "square.grid.3x3.fill"
        case .songs: return "music.note.list"
        case .sets: return "list.number"
        case .setup: return "gearshape.fill"
        }
    }
}

struct MainShell: View {
    @EnvironmentObject var model: AppModel
    @State private var tab: MainTab = MainTab(rawValue: ProcessInfo.processInfo.environment["DMX_DEMO_TAB"] ?? "") ?? .show

    var body: some View {
        shell
            .sheet(isPresented: Binding(get: { model.setupWizardFor != nil }, set: { if !$0 { model.setupWizardFor = nil } })) {
                LightSetupWizard(only: model.setupWizardFor ?? []).environmentObject(model)
            }
    }

    private var shell: some View {
        VStack(spacing: 0) {
            TopBar()
            Divider().opacity(0.4)
            Group {
                switch tab {
                case .show: ShowScreen()
                case .stage: StageScreen()
                case .live: LiveScreen()
                case .songs: SongsScreen()
                        .onAppear {
                            model.songsPageOpen = true
                            // don't let the search box grab the keyboard, so Space plays
                            DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
                        }
                        .onDisappear { model.songsPageOpen = false }
                case .sets: SetListsScreen()
                case .setup: SetupScreen()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // a small window showing what the lights are doing, on every page but Stage
            .overlay(alignment: .bottomTrailing) {
                if tab != .stage { MiniOutputPreview { tab = .stage }.padding(14) }
            }
            BottomBar(tab: $tab)
        }
        .background(Theme.bg)
    }
}

struct TopBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            Button { model.showSessions() } label: { Label("Sessions", systemImage: "square.grid.2x2") }
                .buttonStyle(PillButtonStyle())
            Text(model.currentSessionName).font(.system(size: 20, weight: .bold)).lineLimit(1)
            Spacer()
            NowPlayingCard()
            Spacer()
            UpdateBadge()
            RealLightsSwitch()
            HStack(spacing: 6) {
                Circle().fill(model.connected ? Color.green : Color.red).frame(width: 8, height: 8)
                Text(model.connected ? (model.output.rememberedDevice?.name ?? "Lights connected") : "Not connected")
                    .font(.caption).foregroundColor(Theme.subtle).lineLimit(1)
            }
            Button { model.toggleFullScreen() } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundColor(Theme.subtle)
            .help("Full screen (⌃⌘F) — press again or Esc to leave")
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
    }
}

struct NowPlayingCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let song = model.playingSongID.flatMap { model.song($0) }
        HStack(spacing: 12) {
            let canSkip = !model.songs.isEmpty
            Button { model.previousInLineup() } label: { Image(systemName: "backward.fill").frame(width: 24, height: 24).contentShape(Rectangle()) }
                .buttonStyle(.plain).disabled(!canSkip).opacity(canSkip ? 1 : 0.3)
                .help("Back to the start of the song (←). Click again for the song before.")
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.accent))
            }
            .buttonStyle(.plain)
            Button { model.nextInLineup() } label: { Image(systemName: "forward.fill").frame(width: 24, height: 24).contentShape(Rectangle()) }
                .buttonStyle(.plain).disabled(!canSkip).opacity(canSkip ? 1 : 0.3)
                .help("Next song (→)")
            FadeToButton()
            VStack(alignment: .leading, spacing: 3) {
                Text(model.cuedLabel.map { "Ready: \($0) · Space / →" } ?? model.activeBlock.map { $0.entry.blockLabel } ?? (model.inGap ? "Next song starting…" : (song?.displayName ?? "Nothing playing")))
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if let a = song?.analysis {
                    LiveReader(model.live) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(Theme.accent).frame(width: g.size.width * CGFloat(min(1, model.currentTime / max(a.duration, 1))))
                        }
                    }
                    .frame(height: 4)
                    }
                    LiveReader(model.live) {
                    Text("\(formatTime(model.currentTime)) / \(formatTime(a.duration))").font(.caption2).monospacedDigit().foregroundColor(Theme.subtle)
                    }
                } else if model.activePresetID != nil {
                    HStack(spacing: 6) {
                        Text("Live look on the lights").font(.caption2).foregroundColor(Theme.subtle)
                        Button { model.activePresetID = nil } label: {
                            Text("Stop").font(.system(size: 10, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(Color.white.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                        .help("Stop the live look (lights go back to the idle look)")
                    }
                } else {
                    Text("Standby look on the lights").font(.caption2).foregroundColor(Theme.subtle)
                }
            }
            .frame(width: 260, alignment: .leading)
            VolumeControl()
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Capsule().fill(Theme.panel))
        .overlay(Capsule().stroke(Theme.panelBorder))
    }
}

struct BottomBar: View {
    @EnvironmentObject var model: AppModel
    @Binding var tab: MainTab

    var usedChannels: Int { model.fixtures.reduce(0) { $0 + $1.channelCount } }

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "cellularbars")
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(usedChannels)").font(.system(size: 15, weight: .bold)).monospacedDigit()
                    Text("of 512 channels").font(.system(size: 9)).foregroundColor(Theme.subtle)
                }
            }
            .frame(width: 160, alignment: .leading)
            Spacer()
            HStack(spacing: 4) {
                ForEach(MainTab.allCases) { t in
                    Button { tab = t } label: {
                        VStack(spacing: 3) {
                            Image(systemName: t.icon).font(.system(size: 15))
                            Text(t.title).font(.system(size: 11, weight: .medium))
                        }
                        .frame(width: 78, height: 44)
                        .foregroundColor(tab == t ? Theme.accent : Theme.subtle)
                        .background(RoundedRectangle(cornerRadius: 10).fill(tab == t ? Theme.accent.opacity(0.12) : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            BeatPill().frame(width: 160, alignment: .trailing)
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .background(Color.black.opacity(0.55))
    }
}

// MARK: - Beat tracker (BPM pill + popover)

struct BeatPill: View {
    @EnvironmentObject var model: AppModel
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                LiveReader(model.live) { Circle().fill(model.beatOn ? Theme.accent : Color.white.opacity(0.15)).frame(width: 10, height: 10) }
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(model.displayBPM.rounded()))").font(.system(size: 20, weight: .bold)).monospacedDigit()
                    Text(model.playingSongID != nil && model.activePresetID == nil ? "BPM · song" :
                            (model.beatSource == .mic ? "BPM · mic" : "BPM · tap"))
                        .font(.system(size: 9)).foregroundColor(Theme.subtle)
                }
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .top) { BeatPopover().environmentObject(model) }
    }
}

struct BeatPopover: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Beat Tracker").font(.headline)
            Text("Learned songs always use their own beats. This sets the beat for live looks and music the app hasn't learned.")
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker("", selection: $model.beatSource) {
                ForEach(BeatSource.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            if model.beatSource == .mic {
                AudioSourcePicker()
            }
            HStack(spacing: 12) {
                Button { model.nudgeBPM(-1) } label: { Image(systemName: "minus") }
                Button { model.tapTempo() } label: {
                    VStack(spacing: 2) {
                        Text("\(Int(model.displayBPM.rounded())) BPM").font(.system(size: 22, weight: .bold)).monospacedDigit()
                        Text("Tap to sync").font(.caption2).foregroundColor(.secondary)
                    }
                    .frame(width: 130, height: 56)
                    .background(LiveReader(model.live) { RoundedRectangle(cornerRadius: 12).fill(model.beatOn ? Theme.accent.opacity(0.5) : Color.white.opacity(0.08)) })
                }
                .buttonStyle(.plain)
                Button { model.nudgeBPM(1) } label: { Image(systemName: "plus") }
            }
            Text("Tip: press T to tap the beat").font(.caption2).foregroundColor(.secondary)
        }
        .padding(18)
        .frame(width: 340)
    }
}

/// Choose what to listen to: built-in mic (voice/room), a USB mic, or computer audio via BlackHole.
struct AudioSourcePicker: View {
    @EnvironmentObject var model: AppModel
    @State private var showHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Listen to", selection: Binding(get: { model.output.audioInputName ?? "" },
                                                   set: { model.selectAudioInput($0.isEmpty ? nil : $0) })) {
                Text("Default input (built-in mic)").tag("")
                ForEach(model.audioInputs) { d in
                    Text(d.isLoopback ? "\(d.name) · computer audio" : d.name).tag(d.name)
                }
            }
            HStack {
                Image(systemName: "waveform")
                LiveReader(model.live) { ProgressView(value: model.micLevel).frame(width: 180) }
            }
            Toggle("Auto Lighting (picks looks from the music's energy)", isOn: $model.autoLighting)
            Button(showHelp ? "Hide computer-audio setup" : "How to light up music playing on this Mac") { showHelp.toggle() }
                .buttonStyle(.link).font(.caption)
            if showHelp {
                Text("""
                macOS Monterey doesn't let apps hear the computer's sound directly. Use the free BlackHole driver:
                1. Install BlackHole 2ch (free), then open Audio MIDI Setup.
                2. Click + → Create Multi-Output Device; tick your speakers AND BlackHole 2ch.
                3. In System Preferences → Sound → Output, choose that Multi-Output Device.
                4. Here, pick "BlackHole 2ch · computer audio".
                Now Spotify, YouTube or anything else drives the lights while you still hear it.
                """)
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { model.refreshAudioInputs() }
    }
}

// MARK: - Show screen (Photon-inspired)

struct ShowScreen: View {
    @EnvironmentObject var model: AppModel
    @State private var controlling: UUID?
    @State private var editingPreset: UUID?

    private let cols = [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 12)]

    var body: some View {
        content
            .alert("Lights", isPresented: Binding(get: { model.linkNotice != nil }, set: { if !$0 { model.linkNotice = nil } })) {
                Button("OK") { model.linkNotice = nil }
            } message: { Text(model.linkNotice ?? "") }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 16) {
            MasterColumn()
            VStack(alignment: .leading, spacing: 16) {
                // Stage: your lights as live rings
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Stage").font(.system(size: 17, weight: .bold))
                            Text("Tap a light to control it by hand").font(.caption).foregroundColor(Theme.subtle)
                            Spacer()
                            if model.anyLightOff {
                                Button("Turn all on") { model.turnAllLightsOn() }.buttonStyle(PillButtonStyle())
                            }
                            if !model.manual.isEmpty {
                                Button("Release all") { model.manual = [:] }.buttonStyle(PillButtonStyle())
                            }
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 26) {
                                ForEach(Array(model.fixtures.enumerated()), id: \.element.id) { i, fx in
                                  HStack(spacing: 26) {
                                    if i > 0, model.canLink(model.fixtures[i - 1], fx) {
                                        LinkToggle(prev: model.fixtures[i - 1], next: fx)
                                    }
                                    LiveReader(model.live) { FixtureRing(fixture: fx, rendered: i < model.preview.count ? model.preview[i] : nil,
                                                manual: model.manual[fx.id] != nil,
                                                onPower: { model.setLightOn(fx.id, !fx.isOn) }) }
                                        .onTapGesture { controlling = fx.id }
                                        .popover(isPresented: Binding(get: { controlling == fx.id }, set: { if !$0 { controlling = nil } }),
                                                 arrowEdge: .bottom) {
                                            FixtureControlPanel(fixtureID: fx.id).environmentObject(model)
                                        }
                                  }
                                }
                            }
                            .padding(.vertical, 16).padding(.horizontal, 12)   // room for the glow and hover zoom
                        }
                    }
                }

                // Presets & sequences
                Panel {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if let song = model.selectedSongID.flatMap({ model.song($0) }), !song.shows.isEmpty {
                                HStack {
                                    Text("Sequences · \(song.title)").font(.system(size: 17, weight: .bold)).lineLimit(1)
                                    Text("Plays the song with its light show").font(.caption).foregroundColor(Theme.subtle)
                                }
                                LazyVGrid(columns: cols, alignment: .leading, spacing: 12) {
                                    ForEach(song.shows) { show in
                                        SequenceTile(song: song, show: show)
                                    }
                                }
                            }
                            HStack {
                                Text("Presets").font(.system(size: 17, weight: .bold))
                                Text("Tap to run on the beat · tap again to stop").font(.caption).foregroundColor(Theme.subtle)
                                Spacer()
                                Button {
                                    let p = LookPreset(name: "New Look", effect: .pulse, palette: "Red Velvet", movement: .sweep)
                                    model.presets.append(p)
                                    editingPreset = p.id
                                } label: { Label("New Preset", systemImage: "plus") }
                                .buttonStyle(PillButtonStyle())
                            }
                            ForEach(model.presetGroups, id: \.name) { group in
                            if model.presetGroups.count > 1 {
                                Text(group.name).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.subtle).padding(.top, 4)
                            }
                            LazyVGrid(columns: cols, alignment: .leading, spacing: 12) {
                                ForEach(group.presets) { p in
                                    PresetTile(preset: p, active: model.activePresetID == p.id)
                                        .onTapGesture { model.togglePreset(p.id) }
                                        .contextMenu {
                                            Button("Edit…") { editingPreset = p.id }
                                            Button("Duplicate") {
                                                var c = p; c.id = UUID(); c.name += " copy"; model.presets.append(c)
                                            }
                                            Divider()
                                            Button("Delete", role: .destructive) {
                                                if model.activePresetID == p.id { model.activePresetID = nil }
                                                model.presets.removeAll { $0.id == p.id }
                                            }
                                        }
                                        .popover(isPresented: Binding(get: { editingPreset == p.id }, set: { if !$0 { editingPreset = nil } })) {
                                            PresetEditor(presetID: p.id).environmentObject(model)
                                        }
                                }
                            }
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
    }
}

struct MasterColumn: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Panel(padding: 12) {
            VStack(spacing: 12) {
                Text("Master").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.subtle)
                VerticalFader(value: $model.master)
                    .frame(width: 64)
                Text("\(Int(model.master * 100))%").font(.caption).monospacedDigit()
                HoldPad(title: "FLASH", icon: "sun.max.fill", color: .white, isHeld: $model.flashHeld)
                HoldPad(title: "STROBE", icon: "bolt.fill", color: .yellow, isHeld: $model.strobeHeld)
                Button { model.blackout.toggle() } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "lightbulb.slash.fill")
                        Text("BLACKOUT").font(.system(size: 9, weight: .bold))
                    }
                    .frame(width: 64, height: 50)
                    .background(RoundedRectangle(cornerRadius: 12).fill(model.blackout ? Color.red : Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 92)
    }
}

struct VerticalFader: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08))
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.95), Color.white.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                    .frame(height: max(8, g.size.height * CGFloat(value)))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                value = Double(min(1, max(0, 1 - v.location.y / g.size.height)))
            })
        }
    }
}

/// A glowing rubber pad, lit from inside (like a hardware lighting controller's pads)
struct GlowPadBackground: View {
    var color: Color
    var lit: Bool = true
    var corner: CGFloat = 14
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color(white: 0.11))
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(RadialGradient(colors: [Color.white.opacity(lit ? 0.9 : 0.25), color.opacity(lit ? 0.95 : 0.45), color.opacity(lit ? 0.75 : 0.28)],
                                     center: .center, startRadius: 0, endRadius: 70))
                .padding(3)
            // soft top highlight like a rubber pad
            RoundedRectangle(cornerRadius: corner - 2, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center))
                .padding(3)
        }
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(Color.black.opacity(0.6), lineWidth: 1))
        .shadow(color: color.opacity(lit ? 0.6 : 0.15), radius: lit ? 12 : 4)
    }
}

/// A dark hardware key with a colored label (STROBE, BLINDER, BLACKOUT…)
struct HardwareKeyBackground: View {
    var held: Bool = false
    var accent: Color = .white
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: held ? 0.32 : 0.22), Color(white: held ? 0.2 : 0.12)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.black.opacity(0.8), lineWidth: 1.5)
            RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1).padding(1.5)
        }
        .shadow(color: held ? accent.opacity(0.7) : .black.opacity(0.5), radius: held ? 10 : 2, y: held ? 0 : 1)
    }
}

struct HoldPad: View {
    let title: String
    let icon: String
    let color: Color
    @Binding var isHeld: Bool

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
            Text(title).font(.system(size: 9, weight: .bold))
        }
        .frame(width: 64, height: 50)
        .background(HardwareKeyBackground(held: isHeld, accent: color))
        .foregroundColor(isHeld ? color : color.opacity(0.85))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !isHeld { isHeld = true } }
            .onEnded { _ in isHeld = false })
    }
}

// MARK: - Light rings

/// A ring split into segments (one per head), drawn as an open arc like Photon's zones.
struct RingShape: Shape {
    var segments: Int
    var gap: Double = 0.03
    var index: Int? = nil   // draw only this segment
    var inset: CGFloat = 0  // pull the ring in so a thick stroke stays inside the frame

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = max(1, min(rect.width, rect.height) / 2 - inset)
        let startA = 125.0, sweep = 290.0                         // open at the bottom
        let n = max(segments, 1)
        let each = sweep / Double(n)
        for i in 0..<n where index == nil || index == i {
            let a0 = startA + Double(i) * each + each * gap / 2
            let a1 = startA + Double(i + 1) * each - each * gap / 2
            p.addArc(center: c, radius: r, startAngle: .degrees(a0), endAngle: .degrees(a1), clockwise: false)
            if index == nil { p.move(to: CGPoint(x: c.x + r * CGFloat(cos((a1 + each * gap) * .pi / 180)),
                                                  y: c.y + r * CGFloat(sin((a1 + each * gap) * .pi / 180)))) }
        }
        return p
    }
}

/// The chain-link button between two lights of the same model: linked = they mirror on one address.
struct LinkToggle: View {
    @EnvironmentObject var model: AppModel
    let prev: Fixture
    let next: Fixture

    var body: some View {
        let linked = model.isLinked(prev, next)
        Button {
            if linked { model.unlink(prev.id, next.id) } else { model.link(prev.id, next.id) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.system(size: 15, weight: .bold))
                    .overlay(linked ? nil : Rectangle().frame(width: 2, height: 22).rotationEffect(.degrees(45)))
                    .foregroundColor(linked ? .white : Theme.subtle)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(linked ? Theme.accent : Color.white.opacity(0.1)))
                    .overlay(Circle().stroke(Color.white.opacity(linked ? 0 : 0.2), lineWidth: 1))
                Text(linked ? "Linked" : "Unlinked").font(.system(size: 9, weight: .semibold)).foregroundColor(Theme.subtle)
            }
        }
        .buttonStyle(.plain)
        .padding(.bottom, 30)
        .help(linked ? "\(prev.name) and \(next.name) are chained on one address and mirror each other. Click to unlink."
                     : "Click to link: \(next.name) mirrors \(prev.name) on the same address (daisy-chained).")
    }
}

struct FixtureRing: View {
    let fixture: Fixture
    let rendered: RenderedFixture?
    let manual: Bool
    var onPower: (() -> Void)? = nil
    @State private var hover = false

    var body: some View {
        let heads = rendered?.heads ?? Array(repeating: FixtureState.off, count: fixture.headCount)
        VStack(spacing: 8) {
            ZStack {
                ForEach(0..<max(1, heads.count), id: \.self) { h in
                    let st = h < heads.count ? heads[h] : .off
                    let lit = max(0.12, st.intensity)
                    RingShape(segments: max(1, heads.count), gap: heads.count > 1 ? 0.12 : 0, index: h, inset: 10)
                        .stroke(st.color.color.opacity(lit), style: StrokeStyle(lineWidth: 18, lineCap: heads.count > 1 ? .butt : .round))
                        .shadow(color: st.color.color.opacity(st.intensity * 0.8), radius: 10 * st.intensity)
                }
                VStack(spacing: 2) {
                    Text(fixture.name).font(.system(size: 13, weight: .bold)).lineLimit(1)
                    Text(fixture.effectiveBehavior == .stationary ? "Stationary" : "Sequence")
                        .font(.system(size: 9)).foregroundColor(Theme.subtle)
                    if !fixture.isOn {
                        Text("OFF").font(.system(size: 8, weight: .heavy)).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.gray.opacity(0.6)))
                    } else if manual {
                        Text("MANUAL").font(.system(size: 8, weight: .heavy)).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Theme.accent))
                    }
                }
                .frame(width: 90)
            }
            .frame(width: 140, height: 140)
            .opacity(fixture.isOn ? 1 : 0.45)
            .scaleEffect(hover ? 1.04 : 1)
            .animation(.easeOut(duration: 0.12), value: hover)
            .overlay(alignment: .topTrailing) {
                if let onPower {
                    Button(action: onPower) {
                        Image(systemName: "power").font(.system(size: 12, weight: .bold))
                            .foregroundColor(fixture.isOn ? .white : Theme.subtle)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(fixture.isOn ? Theme.accent : Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .help(fixture.isOn ? "Turn this light off" : "Turn this light on")
                }
            }
            HStack(spacing: 4) {
                Image(systemName: "lightbulb").font(.system(size: 9))
                Text("\(fixture.modeLabel) · \(fixture.headCount == 1 ? "1 light" : "\(fixture.headCount) beams") · ch \(fixture.address)")
                    .font(.system(size: 10))
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .foregroundColor(Theme.subtle)
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

// MARK: - Light control panel (tap a ring)

struct FixtureControlPanel: View {
    @EnvironmentObject var model: AppModel
    let fixtureID: UUID

    private let swatches: [RGB] = [RGB(hex: 0xFF0000), RGB(hex: 0xFF6A00), RGB(hex: 0xFFD000), RGB(hex: 0x00FF40),
                                   RGB(hex: 0x00E0FF), RGB(hex: 0x0040FF), RGB(hex: 0x8000FF), RGB(hex: 0xFF00C8), .white]

    var body: some View {
        let fx = model.fixtures.first { $0.id == fixtureID }
        let m = model.manual[fixtureID] ?? ManualControl()
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(fx?.name ?? "Light").font(.title3.bold())
                Spacer()
                Toggle(isOn: Binding(get: { fx?.isOn ?? true }, set: { model.setLightOn(fixtureID, $0) })) {
                    Text(fx?.isOn ?? true ? "On" : "Off").font(.callout.bold())
                }
                .toggleStyle(.switch)
                Button("Follow show") { model.manual[fixtureID] = nil }
                    .buttonStyle(PillButtonStyle(active: model.manual[fixtureID] == nil))
            }
            if let fx, fx.isShehdsBar {
                ShehdsModePicker(fixture: fx)
            }
            let twins = model.sharesAddress(fixtureID)
            if !twins.isEmpty {
                Label("Linked with \(twins.map(\.name).joined(separator: ", ")) on \(fx?.displayCode ?? ""): they mirror each other and turn on and off together. Use the link button between them to unlink.", systemImage: "link")
                    .font(.caption2).foregroundColor(Theme.subtle).fixedSize(horizontal: false, vertical: true)
            }
            if let wheel = fx?.colorWheel {
                Text("Color wheel").font(.caption).foregroundColor(.secondary)
                HStack(spacing: 8) {
                    ForEach(0..<wheel.slots.count, id: \.self) { i in
                        swatch(wheel.slots[i].color, selected: m.color.map { wheel.nearest($0).value == wheel.slots[i].value } ?? false)
                    }
                }
            } else {
                Text("Color").font(.caption).foregroundColor(.secondary)
                HStack(spacing: 8) {
                    ForEach(0..<swatches.count, id: \.self) { i in
                        swatch(swatches[i], selected: m.color == swatches[i])
                    }
                    ColorPicker("", selection: Binding(get: { (m.color ?? .white).color }, set: { c in
                        if let ns = NSColor(c).usingColorSpace(.deviceRGB) {
                            model.setManual(fixtureID) { $0.color = RGB(r: Double(ns.redComponent), g: Double(ns.greenComponent), b: Double(ns.blueComponent)) }
                        }
                    }), supportsOpacity: false).labelsHidden()
                }
            }
            sliderRow("Dimmer", icon: "sun.max", value: m.dimmer, default: 1) { v in model.setManual(fixtureID) { $0.dimmer = v } }
            if fx?.hasStrobeChannel == true || true {
                sliderRow("Strobe", icon: "bolt", value: m.strobe, default: 0) { v in model.setManual(fixtureID) { $0.strobe = v } }
            }
            if fx?.isMover == true {
                sliderRow("Tilt / position", icon: "arrow.up.and.down", value: m.tilt, default: 0.5) { v in model.setManual(fixtureID) { $0.tilt = v } }
                if fx?.channels.contains(.role(.pan, head: 0)) == true {
                    sliderRow("Pan", icon: "arrow.left.and.right", value: m.pan, default: 0.5) { v in model.setManual(fixtureID) { $0.pan = v } }
                }
            }
            if fx?.colorWheel != nil {
                Text("Focus and iris are the knobs on the light itself.").font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(18)
        .frame(width: 380)
    }

    private func swatch(_ c: RGB, selected: Bool) -> some View {
        Button { model.setManual(fixtureID) { $0.color = c } } label: {
            Circle().fill(c.color).frame(width: 26, height: 26)
                .overlay(Circle().stroke(selected ? Color.white : Color.white.opacity(0.15), lineWidth: selected ? 3 : 1))
        }
        .buttonStyle(.plain)
    }

    private func sliderRow(_ label: String, icon: String, value: Double?, default d: Double, set: @escaping (Double?) -> Void) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 18)
            Text(label).frame(width: 100, alignment: .leading)
            Slider(value: Binding(get: { value ?? d }, set: { set($0) }), in: 0...1)
            Button { set(nil) } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.borderless).help("Back to the show").opacity(value == nil ? 0.3 : 1)
        }
    }
}

// MARK: - Tiles

struct PresetTile: View {
    let preset: LookPreset
    let active: Bool
    @State private var hover = false

    var body: some View {
        let pal = Palette.named(preset.palette)
        HStack(spacing: 12) {
            ZStack {
                GlowPadBackground(color: pal.color(0).color, lit: active || hover, corner: 10)
                Image(systemName: preset.icon).font(.system(size: 17, weight: .bold))
                    .foregroundColor(active || hover ? .black.opacity(0.75) : .white)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 5) {
                Text(preset.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                HStack(spacing: 2) {
                    ForEach(0..<min(4, pal.colors.count), id: \.self) { i in
                        Capsule().fill(pal.color(i).color).frame(width: 10, height: 4)
                    }
                }
                HStack(spacing: 5) {
                    Image(systemName: "sun.max")
                    Image(systemName: "drop.fill")
                    if preset.isBeatDriven { Image(systemName: "metronome") }
                    if preset.usesMovement { Image(systemName: "arrow.up.and.down") }
                    if preset.usesStrobe { Image(systemName: "bolt.fill") }
                }
                .font(.system(size: 9)).foregroundColor(Theme.subtle)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(active ? Theme.accent.opacity(0.28) : Color.white.opacity(hover ? 0.1 : 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(active ? Theme.accent : Theme.panelBorder, lineWidth: active ? 2 : 1))
        .shadow(color: active ? Theme.accent.opacity(0.5) : .clear, radius: 10)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

struct SequenceTile: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    let show: LightShow

    var body: some View {
        let playing = model.playingSongID == song.id && model.isPlaying && (model.playingShowID ?? song.activeShow?.id) == show.id
        let pal = Palette.named(show.sections.first { $0.name != "Silence" }?.palette ?? "Red Velvet")
        Button {
            if playing { model.pause() } else {
                model.songBinding(song.id).wrappedValue.activeShowID = show.id
                model.activePresetID = nil
                model.play(song.id, show: show.id, from: model.playingSongID == song.id ? nil : 0)
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Theme.accent)
                    Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 16, weight: .bold))
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text(show.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 2) {
                        ForEach(0..<min(4, pal.colors.count), id: \.self) { i in
                            Capsule().fill(pal.color(i).color).frame(width: 10, height: 4)
                        }
                    }
                    Text("\(show.sections.filter { $0.name != "Silence" }.count) steps").font(.system(size: 9)).foregroundColor(Theme.subtle)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(playing ? Theme.accent.opacity(0.28) : Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(playing ? Theme.accent : Theme.panelBorder))
        }
        .buttonStyle(.plain)
    }
}

struct PresetEditor: View {
    @EnvironmentObject var model: AppModel
    let presetID: UUID

    var body: some View {
        if let i = model.presets.firstIndex(where: { $0.id == presetID }) {
            let b = $model.presets[i]
            Form {
                TextField("Name", text: b.name)
                Picker("Effect", selection: b.effect) { ForEach(LightEffect.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Colors", selection: b.palette) { ForEach(Palette.all) { Text($0.id).tag($0.id) } }
                Picker("Movement", selection: b.movement) { ForEach(MoveEffect.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Speed", selection: b.rate) {
                    Text("½ speed").tag(0.5); Text("Normal").tag(1.0); Text("2× speed").tag(2.0)
                }
                HStack { Text("Brightness"); Slider(value: b.intensity, in: 0.1...1) }
            }
            .padding(18)
            .frame(width: 340)
        }
    }
}

// MARK: - Live screen (big pads)

struct LiveScreen: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("hitRelease") private var hitRelease = HitRelease.hold.rawValue
    private let cols = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 14)]

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            MasterColumn()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Live Control").font(.system(size: 22, weight: .heavy))
                        Text("Hold a pad to play it over the show; let go and the programmed show comes back. Release (below) can make pads stay on or last 1–10 s instead.")
                            .font(.caption).foregroundColor(Theme.subtle)
                        Spacer()
                        Button { model.tapTempo() } label: {
                            HStack {
                                LiveReader(model.live) { Circle().fill(model.beatOn ? Theme.accent : Color.white.opacity(0.2)).frame(width: 10, height: 10) }
                                Text("TAP  \(Int(model.displayBPM.rounded())) BPM").monospacedDigit()
                            }
                        }
                        .buttonStyle(PillButtonStyle())
                        Toggle("Listen", isOn: Binding(get: { model.beatSource == .mic }, set: { model.beatSource = $0 ? .mic : .manual }))
                            .toggleStyle(.switch)
                            .help("Follow the beat from the microphone or computer audio")
                    }
                    if model.beatSource == .mic {
                        Panel { AudioSourcePicker() }
                        Toggle("Music Break: pause effects when the music drops out", isOn: Binding(get: { model.musicBreak }, set: { model.musicBreak = $0 }))
                            .toggleStyle(.switch)
                            .help("When it hears a break (no music for about a second), the lights ease to the idle look and come back with the music")
                    }
                    ForEach(model.presetGroups, id: \.name) { group in
                        Text(group.name == "Essentials" ? "Looks" : group.name).font(.headline).foregroundColor(Theme.subtle)
                        LazyVGrid(columns: cols, spacing: 14) {
                            ForEach(group.presets) { p in
                                let colors = Palette.named(p.palette).colors.prefix(3).map { $0.color }
                                // every pad runs only while held (or as the Release setting says),
                                // then the programmed show comes back
                                LiveMomentPad(title: p.name, icon: p.icon, colors: colors, presetID: p.id)
                            }
                        }
                    }
                    HStack {
                        Text("Hits").font(.headline).foregroundColor(Theme.subtle)
                        Spacer()
                        Text("Release").font(.caption).foregroundColor(Theme.subtle)
                        Picker("", selection: $hitRelease) {
                            ForEach(HitRelease.allCases) { Text($0.rawValue).tag($0.rawValue) }
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 280)
                        .help("Hold: on while pressed · Toggle: press on, press off · 1 / 5 / 10 s: on for that long")
                    }
                    LazyVGrid(columns: cols, spacing: 14) {
                        LiveHoldPad(title: "Flash", icon: "sun.max.fill", color: .white, isHeld: $model.flashHeld)
                        LiveHoldPad(title: "Strobe", icon: "bolt.fill", color: .yellow, isHeld: $model.strobeHeld)
                        LiveHoldPad(title: "Blinder", icon: "sun.max.circle.fill", color: Color(red: 1, green: 0.95, blue: 0.8), isHeld: $model.blinderHeld)
                        LiveHoldPad(title: "Paparazzi", icon: "camera.fill", color: .cyan, isHeld: $model.paparazziHeld)
                        LiveHoldPad(title: "Blackout", icon: "lightbulb.slash.fill", color: .red, isHeld: $model.blackout)
                        LivePad(title: "Stop Look", icon: "stop.fill", colors: [Color.gray, Color.black], active: false) { model.activePresetID = nil }
                    }
                }
                .padding(.trailing, 4)
            }
        }
        .padding(16)
    }
}

struct LivePad: View {
    let title: String
    let icon: String
    let colors: [Color]
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 26, weight: .bold))
                Text(title).font(.system(size: 13, weight: .bold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 110)
            .foregroundColor(active ? .black.opacity(0.8) : .white)
            .background(GlowPadBackground(color: colors.first ?? .white, lit: active, corner: 18))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(active ? Color.white : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

/// A pad that runs its look only while it's held down (Release setting: Hold / Toggle / 1–10 s)
struct LiveMomentPad: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let icon: String
    let colors: [Color]
    let presetID: UUID
    @AppStorage("hitRelease") private var release = HitRelease.hold.rawValue
    @State private var pressed = false

    var body: some View {
        let active = model.activePresetID == presetID
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 26, weight: .bold))
            Text(title).font(.system(size: 13, weight: .bold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .foregroundColor(active ? .black.opacity(0.8) : .white)
        .background(GlowPadBackground(color: colors.first ?? .white, lit: active, corner: 18))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(active ? Color.white : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .help("Hold to run it; let go and the show comes back")
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !pressed else { return }
                pressed = true
                let mode = HitRelease(rawValue: release) ?? .hold
                if mode == .toggle && active { model.releasePreset(presetID) } else { model.holdPreset(presetID) }
            }
            .onEnded { _ in
                pressed = false
                let mode = HitRelease(rawValue: release) ?? .hold
                if mode == .hold { model.releasePreset(presetID) }
                else if let s = mode.seconds {
                    DispatchQueue.main.asyncAfter(deadline: .now() + s) { model.releasePreset(presetID) }
                }
            })
    }
}

/// How the hit keys let go (like a hardware controller's release modes)
enum HitRelease: String, CaseIterable, Identifiable {
    case hold = "Hold", toggle = "Toggle", one = "1 s", five = "5 s", ten = "10 s"
    var id: String { rawValue }
    var seconds: Double? { switch self { case .one: return 1; case .five: return 5; case .ten: return 10; default: return nil } }
}

struct LiveHoldPad: View {
    let title: String
    let icon: String
    let color: Color
    @Binding var isHeld: Bool
    @AppStorage("hitRelease") private var release = HitRelease.hold.rawValue
    @State private var pressed = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 26, weight: .bold))
            Text((HitRelease(rawValue: release) ?? .hold) == .hold ? "Hold · \(title)" : title).font(.system(size: 13, weight: .bold))
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .background(HardwareKeyBackground(held: isHeld, accent: color))
        .foregroundColor(isHeld ? color : color.opacity(0.85))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !pressed else { return }
                pressed = true
                switch HitRelease(rawValue: release) ?? .hold {
                case .hold: isHeld = true
                case .toggle: isHeld.toggle()
                default: isHeld = true
                }
            }
            .onEnded { _ in
                pressed = false
                let mode = HitRelease(rawValue: release) ?? .hold
                if mode == .hold { isHeld = false }
                else if let s = mode.seconds {
                    DispatchQueue.main.asyncAfter(deadline: .now() + s) { isHeld = false }
                }
            })
    }
}

// MARK: - Songs, Set Lists, Setup (existing pages in a two-pane layout)

struct SongsScreen: View {
    @EnvironmentObject var model: AppModel
    @State private var importing = false
    @State private var dropTargeted = false
    @State private var search = ""

    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var anchor: UUID?             // the last song clicked (⇧-click selects from here)
    @State private var dragBase: Set<UUID>? = nil // picked songs when a ⌘-drag started

    private var filteredSongs: [Song] {
        model.songs.filter { search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search) }
    }
    private func row(at p: CGPoint) -> UUID? {
        rowFrames.first { $0.value.minY - 1 <= p.y && p.y <= $0.value.maxY + 1 }?.key
            ?? (p.y < (rowFrames.values.map(\.minY).min() ?? 0) ? filteredSongs.first?.id : nil)
            ?? (p.y > (rowFrames.values.map(\.maxY).max() ?? 0) ? filteredSongs.last(where: { rowFrames[$0.id] != nil })?.id : nil)
    }
    private func range(_ a: UUID, _ b: UUID) -> Set<UUID> {
        let ids = filteredSongs.map(\.id)
        guard let i = ids.firstIndex(of: a), let j = ids.firstIndex(of: b) else { return [b] }
        return Set(ids[min(i, j)...max(i, j)])
    }
    private func pickDrag(from start: CGPoint, to now: CGPoint, moved: Bool) {
        guard moved, let a = row(at: start), let b = row(at: now) else { return }
        let cmd = NSEvent.modifierFlags.contains(.command)
        if dragBase == nil { dragBase = cmd ? model.pickedSongs : [] }
        model.pickedSongs = (dragBase ?? []).union(range(a, b))
        anchor = a
    }
    private func pickEnd(at p: CGPoint, moved: Bool) {
        defer { dragBase = nil }
        if moved { return }
        model.timelineSelection = nil          // Delete now means the songs again
        // a click on empty space (not on a song) deselects
        guard let id = rowFrames.first(where: { $0.value.minY - 1 <= p.y && p.y <= $0.value.maxY + 1 })?.key else {
            if !NSEvent.modifierFlags.contains(.command) && !NSEvent.modifierFlags.contains(.shift) { model.pickedSongs = [] }
            return
        }
        let mods = NSEvent.modifierFlags
        if mods.contains(.shift), let a = anchor ?? model.selectedSongID {
            model.pickedSongs = mods.contains(.command) ? model.pickedSongs.union(range(a, id)) : range(a, id)
        } else if mods.contains(.command) {
            if model.pickedSongs.contains(id) { model.pickedSongs.remove(id) } else { model.pickedSongs.insert(id) }
            anchor = id
        } else {
            model.pickedSongs = [id]
            model.selectedSongID = id
            model.selectedEntry = nil
            anchor = id
        }
    }

    private var removeTitle: String {
        let ids = model.removeRequest ?? []
        if ids.count == 1, let s = model.song(ids[0]) { return "Remove \"\(s.title)\"?" }
        return "Remove \(ids.count) songs?"
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Song Library").font(.system(size: 17, weight: .bold))
                    Spacer()
                    Menu {
                        Button("Rebuild Light Shows for the Lights That Are On") { model.rebuildShowsForCurrentLights() }
                    } label: { Image(systemName: "wand.and.rays") }
                        .menuStyle(.borderlessButton).fixedSize()
                        .help("Remake every song's learned shows for the lights switched on now (hand edits to a show's sections are replaced)")
                    Button { importing = true } label: { Image(systemName: "plus") }.buttonStyle(PillButtonStyle())
                }
                TextField("Search songs or artists", text: $search).textFieldStyle(.roundedBorder)
                GeometryReader { listGeo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredSongs) { s in
                            SongRow(song: s)
                                .padding(.vertical, 5).padding(.horizontal, 8)
                                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(model.pickedSongs.contains(s.id) ? Theme.selection.opacity(model.selectedSongID == s.id && model.pickedSongs.count > 1 ? 0.55 : 0.42)
                                          : (model.hoveredSongID == s.id ? Color.white.opacity(0.05) : Color.clear)))
                                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(model.pickedSongs.contains(s.id) ? Theme.selection : Color.clear, lineWidth: 1))
                                .contentShape(Rectangle())
                                .background(GeometryReader { g in
                                    Color.clear.preference(key: SongRowFrames.self, value: [s.id: g.frame(in: .named("songList"))])
                                })
                                .onHover { inside in
                                    if inside { model.hoveredSongID = s.id } else if model.hoveredSongID == s.id { model.hoveredSongID = nil }
                                }
                                .contextMenu {
                                    Button("Learn Again") { model.learn(s.id) }
                                    Button("Deep Learn (with stems)") { model.deepLearn(s.id) }
                                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([s.url]) }
                                    if let f = s.analysis?.stemsFolder, FileManager.default.fileExists(atPath: f) {
                                        Button("Show Stems in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f)]) }
                                    }
                                    Menu("Add to Set List") {
                                        ForEach(model.lineups) { l in
                                            Button(l.name) { model.addToLineup(l.id, songID: s.id, showID: s.activeShow?.id) }
                                        }
                                    }
                                    if let a = s.artist, !a.isEmpty {
                                        Button("Create Set List for \(a)") { model.createSetList(forArtist: a) }
                                    }
                                    Divider()
                                    if model.pickedSongs.contains(s.id) && model.pickedSongs.count > 1 {
                                        Button("Remove \(model.pickedSongs.count) Songs…", role: .destructive) { model.requestRemove(Array(model.pickedSongs)) }
                                    } else {
                                        Button("Remove Song…", role: .destructive) { model.requestRemove([s.id]) }
                                    }
                                }
                        }
                    }
                    .padding(4)
                    Spacer(minLength: 0)
                    }
                    // the empty space below the songs counts too: start a drag there, or click it to deselect
                    .frame(minHeight: listGeo.size.height, alignment: .top)
                    .contentShape(Rectangle())
                    .coordinateSpace(name: "songList")
                    .onPreferenceChange(SongRowFrames.self) { rowFrames = $0 }
                    // click / ⇧-click / ⌘-click / click-and-drag to pick songs
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("songList"))
                        .onChanged { v in pickDrag(from: v.startLocation, to: v.location, moved: abs(v.translation.height) > 4) }
                        .onEnded { v in pickEnd(at: v.startLocation, moved: abs(v.translation.height) > 4) })
                }
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))

                .onChange(of: model.pickedSongs) { picked in
                    // one song picked: open it; several: keep showing the last one opened
                    if picked.count == 1, let id = picked.first, model.selectedSongID != id { model.selectedSongID = id; model.selectedEntry = nil }
                }
                .onChange(of: model.selectedSongID) { id in
                    if let id, !model.pickedSongs.contains(id) { model.pickedSongs = [id] }
                }
                .onAppear { if model.pickedSongs.isEmpty, let id = model.selectedSongID { model.pickedSongs = [id] } }
                .confirmationDialog(removeTitle, isPresented: Binding(get: { model.removeRequest != nil }, set: { if !$0 { model.removeRequest = nil } })) {
                    Button(model.removeRequest?.count ?? 0 > 1 ? "Remove \(model.removeRequest?.count ?? 0) Songs" : "Remove Song", role: .destructive) {
                        if let ids = model.removeRequest { model.removeSongs(ids) }
                        model.removeRequest = nil
                    }
                } message: {
                    Text("Removes them from the library and from your set lists, with their light shows. The audio files stay in your DMX Studio folder.")
                }
                .onHover { model.songListHovered = $0 }
                Text("Drag WAV / MP3 / M4A / AIFF / FLAC files or a folder here").font(.caption).foregroundColor(Theme.subtle)
            }
            .padding(14)
            .frame(width: 300)
            .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
                loadDroppedURLs(providers) { urls in model.importSongs(urls) }
                return true
            }
            .overlay(dropTargeted ? RoundedRectangle(cornerRadius: 12).stroke(Theme.accent, lineWidth: 3).padding(6) : nil)
            .onAppear { model.songsScreenShowing = true }
            .onDisappear { model.songsScreenShowing = false }
            Divider()
            if let id = model.selectedSongID, model.song(id) != nil {
                SongView(songID: id).id(id)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "music.note").font(.system(size: 44)).foregroundColor(Theme.accent)
                    Text("Add songs to get started").font(.title3.bold())
                    Text("Drag WAV or MP3 files onto the library. Each one is learned automatically and gets a light show.")
                        .foregroundColor(Theme.subtle).multilineTextAlignment(.center).frame(width: 360)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .mp3, .wav, .mpeg4Audio, .aiff, UTType(filenameExtension: "m4a") ?? .audio, UTType(filenameExtension: "flac") ?? .audio, .folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.importSongs(urls) }
        }
    }
}

/// Where each song row is in the library list (for drag-to-pick)
struct SongRowFrames: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue()) { $1 } }
}

struct SetListsScreen: View {
    @EnvironmentObject var model: AppModel
    @State private var selected: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Set Lists").font(.system(size: 17, weight: .bold))
                    Spacer()
                    Button { selected = model.newLineup() } label: { Image(systemName: "plus") }.buttonStyle(PillButtonStyle())
                }
                List(selection: $selected) {
                    ForEach(model.lineups) { l in
                        HStack {
                            Image(systemName: model.playingLineupID == l.id ? "speaker.wave.2.fill" : "list.number")
                                .foregroundColor(model.playingLineupID == l.id ? Theme.accent : Theme.subtle)
                            Text(l.name)
                            Spacer()
                            Text(l.entries.isEmpty ? "0" : formatTime(model.setTimeline(l).total)).font(.caption).monospacedDigit().foregroundColor(Theme.subtle)
                        }
                        .tag(Optional(l.id))
                        .onDrop(of: [UTType.fileURL, UTType.plainText], isTargeted: nil) { providers in
                            handleSongDrop(providers, model: model, lineupID: l.id)
                            return true
                        }
                        .contextMenu {
                            Button("Delete Set List", role: .destructive) { model.lineups.removeAll { $0.id == l.id } }
                        }
                    }
                }
                .listStyle(.inset)
            }
            .padding(14)
            .frame(width: 280)
            Divider()
            if let id = selected ?? model.lineups.first?.id {
                LineupView(lineupID: id).id(id)
            } else {
                Text("Create a set list with +").foregroundColor(Theme.subtle).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

enum SetupPage: String, CaseIterable, Identifiable {
    case wireless = "Wireless DMX", lights = "My Lights", idle = "Idle Look", problems = "Problems"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .wireless: return "wifi"
        case .lights: return "lightbulb"
        case .idle: return "moon.stars"
        case .problems: return "exclamationmark.triangle"
        }
    }
}

struct SetupScreen: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var errors = ErrorCenter.shared
    @State private var page: SetupPage? = .wireless

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $page) {
                ForEach(SetupPage.allCases) { p in
                    HStack {
                        Label(p.rawValue, systemImage: p.icon)
                        Spacer()
                        if p == .wireless { Circle().fill(model.connected ? Color.green : Color.gray).frame(width: 8, height: 8) }
                        if p == .problems && !errors.problems.isEmpty {
                            Text("\(errors.problems.count)").font(.caption).foregroundColor(.orange)
                        }
                    }
                    .tag(Optional(p))
                }
            }
            .listStyle(.sidebar)
            .frame(width: 220)
            Divider()
            Group {
                switch page ?? .wireless {
                case .wireless: WirelessView()
                        .onAppear { model.wirelessPageOpen = true }
                        .onDisappear { model.wirelessPageOpen = false }
                case .lights: LightsView()
                case .idle: IdleView()
                case .problems: ProblemsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}


/// Master music volume: click the speaker to mute / unmute.
struct VolumeControl: View {
    @EnvironmentObject var model: AppModel
    @State private var beforeMute: Double = 1

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if model.musicVolume > 0 { beforeMute = model.musicVolume; model.musicVolume = 0 }
                else { model.musicVolume = max(0.2, beforeMute) }
            } label: {
                Image(systemName: icon).frame(width: 18)
            }
            .buttonStyle(.plain)
            .help(model.musicVolume > 0 ? "Mute the music" : "Unmute")
            Slider(value: $model.musicVolume, in: 0...1).frame(width: 90).controlSize(.small)
            Text("\(Int((model.musicVolume * 100).rounded()))").font(.caption2).monospacedDigit()
                .foregroundColor(Theme.subtle).frame(width: 24, alignment: .trailing)
        }
        .help("Music volume for all songs")
    }

    private var icon: String {
        switch model.musicVolume {
        case 0: return "speaker.slash.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}


/// The SHEHDS bar's channel mode (its C.hnd menu). Must match the light, or colors land on the wrong channels.
struct ShehdsModePicker: View {
    @EnvironmentObject var model: AppModel
    let fixture: Fixture

    var body: some View {
        let perBeam = fixture.profileName == FixtureProfile.shehdsBeam38.name
        VStack(alignment: .leading, spacing: 6) {
            Text("Channel Mode  ·  on the light: MENU → C.hnd").font(.callout.bold())
            Picker("", selection: Binding(get: { perBeam }, set: { model.setShehdsMode(fixture.id, perBeam: $0) })) {
                Text("38ch · each beam").tag(true)
                Text("9ch · all together").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(perBeam ? "Set C.hnd to 38CH on the light. Every one of the 8 beams can do its own thing."
                         : "Set C.hnd to 9CH on the light. All 8 beams do the same thing; choose 38CH on both for separate beams.")
                .font(.caption2).foregroundColor(Theme.subtle).fixedSize(horizontal: false, vertical: true)
            Text("If colors look wrong (red shows as green), this doesn't match the light.")
                .font(.caption2).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true)
            TiltSpeedControl(fixture: fixture)
        }
    }
}


/// The bar's tilt-speed channel. The manual doesn't say which end is fast, so: Tilt Test swings the bars
/// end to end, and you slide until they move quickest and reach both ends.
struct TiltSpeedControl: View {
    @EnvironmentObject var model: AppModel
    let fixture: Fixture

    var body: some View {
        let v = fixture.tiltSpeed ?? 0
        let testing = model.testMode == .tiltTest
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Tilt Speed").font(.callout.bold())
                Spacer()
                Button(testing ? "Stop Test" : "Tilt Test") { model.testMode = testing ? .off : .tiltTest }
                    .controlSize(.small)
            }
            HStack {
                Text("0").font(.caption2).foregroundColor(Theme.subtle)
                Slider(value: Binding(get: { v }, set: { model.setTiltSpeed(fixture.id, ($0 / 5).rounded() * 5) }), in: 0...255)
                Text("255").font(.caption2).foregroundColor(Theme.subtle)
                Text("\(Int(v))").font(.caption).monospacedDigit().frame(width: 30)
            }
            Text("Press Tilt Test: the bar swings end to end. Slide until it moves fastest and reaches both ends.")
                .font(.caption2).foregroundColor(Theme.subtle).fixedSize(horizontal: false, vertical: true)
            let lead = fixture.moveLeadMs ?? 300
            HStack {
                Text("Movement Timing").font(.callout.bold())
                Spacer()
                Text("\(Int(lead)) ms early").font(.caption).monospacedDigit()
            }
            Slider(value: Binding(get: { lead }, set: { model.setMoveLead(fixture.id, ($0 / 10).rounded() * 10) }), in: 0...900)
            Text("If the bar turns after the hit, slide right (moves are sent earlier). If it turns before the hit, slide left.")
                .font(.caption2).foregroundColor(Theme.subtle).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }
}


/// The second play button: while a song plays, pick another song and fade into it (music + lights).
struct FadeToButton: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.isPlaying, let sel = model.selectedSongID, sel != model.playingSongID, let song = model.song(sel) {
            HStack(spacing: 0) {
                Button { model.fadeTo(sel) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.merge")
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Fade to").font(.system(size: 9, weight: .bold)).opacity(0.8)
                            Text(song.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        }
                    }
                    .padding(.leading, 10).padding(.trailing, 6).padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .help("Fade from the song playing into \(song.title) over \(Int(model.crossfadeSeconds)) seconds: music and lights")
                Menu {
                    ForEach([3.0, 6, 10, 16], id: \.self) { s in
                        Button("\(Int(s)) seconds\(model.crossfadeSeconds == s ? " ✓" : "")") { model.crossfadeSeconds = s }
                    }
                } label: { Text("\(Int(model.crossfadeSeconds))s").font(.system(size: 10, weight: .bold)) }
                    .menuStyle(.borderlessButton).fixedSize().padding(.trailing, 8)
                    .help("How long the fade takes")
            }
            .frame(maxWidth: 210)
            .background(Capsule().fill(Theme.accent.opacity(0.35)))
            .overlay(Capsule().stroke(Theme.accent))
        }
    }
}


/// Picture-in-picture view of the output: the same stage drawing as the Stage page, small, in a corner.
/// Click it to open the Stage page; the chevron folds it away.
struct MiniOutputPreview: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("miniPreviewShown") private var shown = true
    @AppStorage("miniPreviewLarge") private var large = false
    let openStage: () -> Void

    var body: some View {
        if shown {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Circle().fill(model.outputEnabled ? Color.green : Color.orange).frame(width: 7, height: 7)
                    Text(model.outputEnabled ? "LIVE · what your lights are doing" : "PREVIEW · lights untouched")
                        .font(.system(size: 10, weight: .bold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Button { large.toggle() } label: {
                        Image(systemName: large ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.plain).help(large ? "Smaller" : "Bigger")
                    Button { shown = false } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.plain).help("Hide the preview")
                }
                .font(.system(size: 10))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Color.black.opacity(0.85))
                StageCanvas(editing: false)
                    .frame(width: large ? 420 : 280, height: large ? 236 : 158)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture { openStage() }
                    .help("Open the Stage page")
            }
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(model.outputEnabled ? Color.green.opacity(0.7) : Color.white.opacity(0.15), lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
        } else {
            Button { shown = true } label: {
                Label("Preview", systemImage: "eye")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.85)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .help("Show a small preview of what your lights are doing")
        }
    }
}
