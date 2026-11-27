import SwiftUI
import AppKit
import Combine

// MARK: - Where each light sits on the simulated stage

struct StagePlacement {
    var x: Double
    var y: Double
    var mount: StageMount
}

extension AppModel {
    /// Saved position, or a sensible default: movers spread across the stage floor, spotlights at front of house.
    func placement(for fx: Fixture) -> StagePlacement {
        let isSpot = fx.colorWheel != nil
        let defaultMount: StageMount = isSpot ? .frontOfHouse : .floor
        if let x = fx.stageX, let y = fx.stageY {
            return StagePlacement(x: x, y: y, mount: fx.stageMount ?? defaultMount)
        }
        if isSpot {
            let spots = fixtures.filter { $0.colorWheel != nil }
            let i = spots.firstIndex { $0.id == fx.id } ?? 0
            let x = spots.count == 1 ? 0.5 : 0.35 + 0.3 * Double(i) / Double(max(1, spots.count - 1))
            return StagePlacement(x: x, y: 0.93, mount: .frontOfHouse)
        }
        let rig = fixtures.filter { $0.colorWheel == nil }
        let i = rig.firstIndex { $0.id == fx.id } ?? 0
        let x = rig.count == 1 ? 0.5 : 0.22 + 0.56 * Double(i) / Double(max(1, rig.count - 1))
        return StagePlacement(x: x, y: 0.74, mount: fx.stageMount ?? .floor)
    }

    func setPlacement(_ id: UUID, x: Double? = nil, y: Double? = nil, mount: StageMount? = nil) {
        guard let i = fixtures.firstIndex(where: { $0.id == id }) else { return }
        let cur = placement(for: fixtures[i])
        fixtures[i].stageX = x ?? cur.x
        fixtures[i].stageY = y ?? cur.y
        fixtures[i].stageMount = mount ?? cur.mount
    }

    func resetStageLayout() {
        for i in fixtures.indices { fixtures[i].stageX = nil; fixtures[i].stageY = nil; fixtures[i].stageMount = nil }
    }
}

// MARK: - Stage screen (3D venue)

struct StageScreen: View {
    @EnvironmentObject var model: AppModel
    @State private var charactersOpen = false
    @State private var assetsOpen = false
    @State private var studioAngle = 0.0
    @State private var studioFace = false
    @AppStorage("diagnosticCharacterCaptureEnabled") private var diagnosticCaptureEnabled = false
    private let diagnosticCaptureTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    private var stageToolbar: some View {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stage").font(.system(size: 22, weight: .heavy))
                    Text(model.stageEditing ? "Click something to select it, drag it across the floor. Fine-tune on the right."
                                            : "Your venue in 3D. Drag to orbit, scroll, pinch or ⌘+ / ⌘− to zoom. Everything you play shows up here.")
                        .font(.caption).foregroundColor(Theme.subtle).lineLimit(1)
                }
                Spacer()
                Group {
                ForEach(["Overview", "Audience", "Top", "Side", "Close-up"], id: \.self) { v in
                    Button(v) { model.stageCameraRequest = (v, UUID()) }.buttonStyle(PillButtonStyle())
                        .help(v == "Close-up" ? "Zoom in on your lights to see them tilt and move" : "")
                }
                HStack(spacing: 2) {
                    Button { model.stageCameraRequest = ("Zoom Out", UUID()) } label: { Image(systemName: "minus.magnifyingglass") }
                        .keyboardShortcut("-", modifiers: .command)
                        .help("Zoom out (⌘−)")
                    Button { model.stageCameraRequest = ("Zoom In", UUID()) } label: { Image(systemName: "plus.magnifyingglass") }
                        .keyboardShortcut("=", modifiers: .command)
                        .help("Zoom in (⌘+ · you can also scroll or pinch)")
                }
                .background(
                    // ⌘+ typed with Shift, and ⌘0 to go back to the full view
                    ZStack {
                        Button("") { model.stageCameraRequest = ("Zoom In", UUID()) }.keyboardShortcut("+", modifiers: .command)
                        Button("") { model.stageCameraRequest = ("Overview", UUID()) }.keyboardShortcut("0", modifiers: .command)
                    }.opacity(0).allowsHitTesting(false)
                )
                .buttonStyle(PillButtonStyle())
                HStack(spacing: 6) {
                    Image(systemName: "cloud.fog").foregroundColor(Theme.subtle)
                    Slider(value: $model.haze, in: 0.1...1).frame(width: 90)
                }
                .help("Haze: how visible the beams are")
                Toggle("Diagnostic captures", isOn: $diagnosticCaptureEnabled)
                    .toggleStyle(.switch).controlSize(.small)
                    .help("Allow private character-only diagnostic renders while playback and physical DMX output are off.")
                Toggle("HQ", isOn: $model.stageHighQuality)
                    .toggleStyle(.switch).controlSize(.small)
                    .help("High-quality 3D: glow, smoothing, light pools on the floor, 60 fps. Leave off on older Intel MacBooks, where heavy 3D can restart the Mac.")
                Menu {
                    Button("Bars lying flat on the floor") { model.stageScenario(.floor) }
                    Button("Bars upright on truss legs (vertical)") { model.stageScenario(.upright) }
                    Button("Bars hanging from the truss") { model.stageScenario(.hanging) }
                } label: { Label("Mounting", systemImage: "rectangle.portrait.on.rectangle.portrait") }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Show your stage with the bars mounted another way: lying flat (beams go front to back) or upright (beams sweep side to side)")
                }
                Group {
                Menu {
                    Section("Venue") {
                        Button { model.stage = StageLayout.concert(keeping: model.stage, fixtures: model.fixtures) } label: {
                            Label("Concert stage (truss, LED wall, line arrays)", systemImage: "music.mic")
                        }
                        Button {
                            model.stage = StageLayout.lounge(keeping: model.stage)
                            if model.stage.screenContent == nil { model.stage.screenContent = .glow }
                        } label: {
                            Label("Club lounge (curtains, projection, tables)", systemImage: "wineglass")
                        }
                        Button { model.stage = StageLayout.losGlobos(upstairs: false, keeping: model.stage) } label: {
                            Label("Los Globos · Downstairs (16'7\" stage, 10×4 LED wall, DJ booth)", systemImage: "building.2")
                        }
                        Button { model.stage = StageLayout.losGlobos(upstairs: true, keeping: model.stage) } label: {
                            Label("Los Globos · Upstairs (29'7\" stage, 6×3 LED wall, drums)", systemImage: "building.2")
                        }
                    }
                    Section("Drum kit") {
                        Button {
                            if !model.stage.items.contains(where: { $0.prop == .drumKit }) {
                                model.addProp(.drumKit)
                            }
                        } label: {
                            Label("Show drum kit", systemImage: model.stage.items.contains(where: { $0.prop == .drumKit }) ? "checkmark" : "drum")
                        }
                        Button {
                            if let id = model.selectedStageItem, model.stage.items.contains(where: { $0.id == id && $0.prop == .drumKit }) {
                                model.selectedStageItem = nil
                            }
                            model.stage.items.removeAll { $0.prop == .drumKit }
                        } label: {
                            Label("No drum kit", systemImage: model.stage.items.contains(where: { $0.prop == .drumKit }) ? "minus.circle" : "checkmark")
                        }
                    }
                    Section("Backdrop") {
                        ForEach(BackdropStyle.allCases) { st in
                            Button { model.setBackdrop(st) } label: { Label(st.rawValue, systemImage: st.icon) }
                        }
                    }
                    Section("On the screen") {
                        ForEach(ScreenContent.allCases.filter { ![.image, .video, .rays].contains($0) }) { c in
                            Button { model.stage.screenContent = c == .name ? nil : c } label: {
                                Label(c.rawValue, systemImage: (model.stage.screenContent ?? .name) == c ? "checkmark" : "")
                            }
                        }
                        Button { model.pickScreenMedia(video: false) } label: {
                            Label("Your image…", systemImage: model.stage.screenContent == .image ? "checkmark" : "photo")
                        }
                        Button { model.pickScreenMedia(video: true) } label: {
                            Label("Your video…", systemImage: model.stage.screenContent == .video ? "checkmark" : "film")
                        }
                    }
                } label: { Label("Venue", systemImage: "rectangle.inset.filled") }
                .menuStyle(.borderlessButton).fixedSize()
                .help("The venue (concert stage or club lounge), what's behind the band, and what the screen shows")
                Menu {
                    Section("Lights") {
                        ForEach(FixtureProfile.all) { p in Button(p.name) { model.stageEditing = true; model.addStageLight(p) } }
                    }
                    Section("Venue") {
                        ForEach(PropKind.allCases) { k in Button(k.rawValue) { model.stageEditing = true; model.addProp(k) } }
                    }
                } label: { Label("Add", systemImage: "plus") }
                .menuStyle(.borderlessButton).fixedSize()
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.09)))
                Button { model.showVideoExport = true } label: { Image(systemName: "film") }
                    .buttonStyle(PillButtonStyle())
                    .help("Export Stage to Video: an .mp4 of the show on this stage, with the music")
                Button { model.stageEditing.toggle(); if !model.stageEditing { model.selectedStageItem = nil } } label: {
                    Label(model.stageEditing ? "Done" : "Edit Venue", systemImage: model.stageEditing ? "checkmark" : "hammer")
                }
                .buttonStyle(PillButtonStyle(active: model.stageEditing))
                }
            }
    }

    var body: some View {
        VStack(spacing: 12) {
            stageToolbar
            HStack {
                Button {
                    if model.stage.items.first(where: { $0.id == model.selectedStageItem && $0.prop == .performer }) == nil {
                        if let performer = model.stage.items.first(where: { $0.prop == .performer }) {
                            model.selectedStageItem = performer.id
                        } else {
                            model.addProp(.performer)
                            model.selectedStageItem = model.stage.items.last(where: { $0.prop == .performer })?.id
                        }
                    }
                    charactersOpen = true
                } label: { Label("Character Studio", systemImage: "person.crop.rectangle") }
                .buttonStyle(PillButtonStyle(active: true))
                Button { assetsOpen = true } label: { Label("Asset Library", systemImage: "cube.box") }
                    .buttonStyle(PillButtonStyle())
                Text("Choose, create and customize performers").font(.caption).foregroundColor(Theme.subtle)
                Spacer()
            }
            .sheet(isPresented: $assetsOpen) {
                AssetLibraryView { path in
                    if model.stage.items.first(where: { $0.id == model.selectedStageItem && $0.prop == .performer }) == nil {
                        model.addProp(.performer)
                        model.selectedStageItem = model.stage.items.last(where: { $0.prop == .performer })?.id
                    }
                    if let id = model.selectedStageItem {
                        model.updateStageItem(id) {
                            var a = $0.performerAppearance ?? PerformerAppearance()
                            a.modelPath = path
                            $0.performerAppearance = a
                        }
                    }
                }
            }
            .sheet(isPresented: $charactersOpen) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Character Studio").font(.title2.bold())
                        Spacer()
                        Button("Done") { charactersOpen = false }
                    }
                    Picker("Performer", selection: $model.selectedStageItem) {
                        ForEach(model.stage.items.filter { $0.prop == .performer }) { item in
                            Text(item.performerName ?? "Performer").tag(Optional(item.id))
                        }
                    }
                    HStack(alignment: .top, spacing: 16) {
                        if let performer = model.stage.items.first(where: { $0.id == model.selectedStageItem && $0.prop == .performer }) {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Character name", text: Binding(get: { performer.performerName ?? "" }, set: { name in model.updateStageItem(performer.id) { $0.performerName = name } }))
                                    .font(.title2.bold())
                                if performer.performerAppearance?.modelPath == nil {
                                    HStack(spacing: 12) {
                                        ForEach(["Masculine", "Feminine", "Androgynous"], id: \.self) { style in
                                            Button {
                                                model.updateStageItem(performer.id) {
                                                    var a = $0.performerAppearance ?? PerformerAppearance()
                                                    a.bodyStyle = style
                                                    $0.performerAppearance = a
                                                }
                                            } label: {
                                                Label(style == "Masculine" ? "Male" : (style == "Feminine" ? "Female" : "Androgynous"), systemImage: "person.crop.rectangle")
                                                    .frame(maxWidth: .infinity)
                                            }
                                            .buttonStyle(PillButtonStyle(active: (performer.performerAppearance?.bodyStyle ?? "Masculine") == style))
                                        }
                                    }
                                }
                                CharacterModelPreview(appearance: performer.performerAppearance ?? PerformerAppearance(), faceCloseup: studioFace, rotation: studioAngle)
                                    .frame(minWidth: 340, minHeight: 420)
                                Picker("View", selection: $studioFace) { Text("Full body").tag(false); Text("Face").tag(true) }.pickerStyle(.segmented)
                                HStack {
                                    Button("Front") { studioAngle = 0 }
                                    Button("Left") { studioAngle = -90 }
                                    Button("Right") { studioAngle = 90 }
                                    Button("Back") { studioAngle = 180 }
                                }.buttonStyle(PillButtonStyle())
                                HStack { Text("Rotate preview"); Slider(value: $studioAngle, in: -180...180); Button("Reset") { studioAngle = 0 } }
                                .onChange(of: studioFace) { isFace in if isFace { studioAngle = 0 } }
                                Text("Drag to orbit · scroll to zoom").font(.caption).foregroundColor(Theme.subtle)
                            }
                        }
                        StageInspector(characterOnly: true).frame(width: 340)
                    }
                }
                .padding(24).frame(minWidth: 900, idealWidth: 980, minHeight: 700, idealHeight: 760)
            }
            HStack(spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    Stage3DView(model: model)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.panelBorder))
                        .overlay(StageSectionBadge().padding(12), alignment: .topLeading)
                    if !model.outputEnabled {
                        Text("PREVIEW ONLY · your lights aren't being controlled").font(.system(size: 11, weight: .heavy)).foregroundColor(.orange)
                            .padding(8).background(Capsule().fill(Color.black.opacity(0.6))).padding(12)
                    }
                }
                if model.stageEditing {
                    StageInspector().frame(width: 270)
                }
            }
            HStack(spacing: 10) {
                Text("Quick looks").font(.caption).foregroundColor(Theme.subtle)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.presets) { p in
                            HStack(spacing: 6) {
                                Circle().fill(LinearGradient(colors: Palette.named(p.palette).colors.prefix(3).map { $0.color },
                                                             startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 14, height: 14)
                                Text(p.name).lineLimit(1)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(model.activePresetID == p.id ? Theme.accent.opacity(0.45) : Color.white.opacity(0.08)))
                            .overlay(Capsule().stroke(model.activePresetID == p.id ? Color.white : Color.clear, lineWidth: 1.5))
                            .modifier(HoldPresetGesture(presetID: p.id))
                        }
                    }
                }
                HoldPad(title: "FLASH", icon: "sun.max.fill", color: .white, isHeld: $model.flashHeld).frame(width: 64)
                Button { model.blackout.toggle() } label: {
                    Label(model.blackout ? "Blackout ON" : "Blackout", systemImage: "lightbulb.slash.fill")
                }
                .buttonStyle(PillButtonStyle(active: model.blackout))
            }
        }
        .padding(16)
        .onAppear {
            model.ensureStageItems()
            // CI-only character preview selection; never alter normal user sessions.
            let env = ProcessInfo.processInfo.environment
            if let style = env["DMX_DEMO_CHARACTER"], ["Masculine", "Feminine"].contains(style),
               env["DMX_DEMO_OPEN"] == "1" {
                if !model.stage.items.contains(where: { $0.prop == .performer }) { model.addProp(.performer) }
                if let id = model.stage.items.first(where: { $0.prop == .performer })?.id {
                    model.selectedStageItem = id
                    model.updateStageItem(id) {
                        var appearance = PerformerAppearance()
                        appearance.bodyStyle = style
                        appearance.skin = Int(env["DMX_DEMO_SKIN"] ?? "2") ?? 2
                        $0.performerAppearance = appearance
                    }
                    studioFace = env["DMX_DEMO_FACE"] == "1"
                    studioAngle = Double(env["DMX_DEMO_ANGLE"] ?? "0") ?? 0
                    charactersOpen = true
                }
            }
        }
        .onReceive(diagnosticCaptureTimer) { _ in
            guard diagnosticCaptureEnabled, model.playingSongID == nil, !model.outputEnabled else { return }
            _ = try? CharacterCaptureRequests.processOne(enabled: diagnosticCaptureEnabled, playing: model.playingSongID != nil || model.outputEnabled)
        }
        .onChange(of: model.fixtures) { _ in model.ensureStageItems() }
    }
}

/// Fine-tune the selected item: position, height, rotation, size, mounting.
struct StageInspector: View {
    var characterOnly = false
    @EnvironmentObject var model: AppModel
    @AppStorage("stage.savedPerformers.v1") private var savedCharacterData: Data = Data()
    @State private var characterNotice = ""
    @State private var characterPreviewOpen = false
    @State private var characterFaceCloseup = false
    @State private var characterPreviewAngle: Double = 0
    private var savedCharacters: [SavedPerformer] {
        (try? JSONDecoder().decode([SavedPerformer].self, from: savedCharacterData)) ?? []
    }
    private func storeCharacters(_ entries: [SavedPerformer]) {
        if let data = try? JSONEncoder().encode(entries) { savedCharacterData = data }
    }
    private func applyCharacter(_ character: SavedPerformer, to id: UUID) {
        model.updateStageItem(id) { $0.performerAppearance = character.appearance; $0.performerName = character.name }
        characterNotice = "Loaded " + character.name
    }


    var body: some View {
        Panel {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let id = model.selectedStageItem, let item = model.stage.items.first(where: { $0.id == id }) {
                        let fx = item.fixtureID.flatMap { fid in model.fixtures.first { $0.id == fid } }
                        if !characterOnly {
                        HStack {
                            Image(systemName: item.prop?.icon ?? "lightbulb.fill").foregroundColor(Theme.accent)
                            Text(fx?.name ?? item.prop?.rawValue ?? "Item").font(.headline).lineLimit(1)
                            Spacer()
                            if let fx {
                                Toggle("", isOn: Binding(get: { fx.isOn }, set: { model.setLightOn(fx.id, $0) }))
                                    .toggleStyle(.switch).labelsHidden().help("Turn this light on or off")
                            }
                        }
                        if let fx { Text(fx.profileName).font(.caption2).foregroundColor(Theme.subtle).lineLimit(2) }
                        slider("Left / right", item.x, -8...8, "m") { v in model.updateStageItem(id) { $0.x = v } }
                        slider("Front / back", item.z, -6...10, "m") { v in model.updateStageItem(id) { $0.z = v } }
                        slider("Height", item.y, 0...6, "m") { v in model.updateStageItem(id) { $0.y = v } }
                        slider("Rotation", item.rotation, -180...180, "°") { v in model.updateStageItem(id) { $0.rotation = v } }
                        if let k = item.prop, [.stage, .truss, .trussTower, .circleTruss, .lightStand, .trussFrame, .ledWall, .backdrop].contains(k) {
                            slider(k == .truss ? "Length" : (k == .stage ? "Width" : "Size"), item.size,
                                   k == .truss ? 1...12 : (k == .trussTower || k == .lightStand ? 1...6 : 0.5...3),
                                   k == .stage || k == .circleTruss ? "×" : "m") { v in model.updateStageItem(id) { $0.size = v } }
                        }
                        }
                        if !characterOnly && (item.prop == .stage || item.prop == .cabaretTable) {
                            Divider()
                            Text("Materials Library").font(.headline)
                            let surface = item.woodSurface ?? WoodSurface()
                            Picker("Wood finish", selection: Binding<WoodFinish?>(get: { item.woodSurface?.finish ?? (item.prop == .cabaretTable ? .walnut : nil) }, set: { value in
                                model.updateStageItem(id) { entry in
                                    if let value { var settings = entry.woodSurface ?? WoodSurface(); settings.finish = value; entry.woodSurface = settings }
                                    else { entry.woodSurface = nil }
                                }
                            })) {
                                if item.prop == .stage { Text("Original deck").tag(nil as WoodFinish?) }
                                ForEach(WoodFinish.allCases) { finish in Text(finish.rawValue).tag(Optional(finish)) }
                            }
                            if item.woodSurface != nil || item.prop == .cabaretTable {
                                slider("Roughness", surface.roughness, 0.1...1, "") { v in model.updateStageItem(id) { var settings = $0.woodSurface ?? WoodSurface(); settings.roughness = v; $0.woodSurface = settings } }
                                slider("Texture repeat", surface.repeatScale, 0.5...8, "×") { v in model.updateStageItem(id) { var settings = $0.woodSurface ?? WoodSurface(); settings.repeatScale = v; $0.woodSurface = settings } }
                            }
                        }
                        if item.prop == .performer {
                            Divider()
                            Text("Character").font(.headline)
                            if !characterOnly {
                            Button {
                                characterFaceCloseup = false
                                characterPreviewOpen = true
                            } label: { Label("Character Studio", systemImage: "person.crop.rectangle") }
                            .buttonStyle(PillButtonStyle())
                            .sheet(isPresented: $characterPreviewOpen) {
                                if let current = model.stage.items.first(where: { $0.id == id }) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack {
                                            Text(current.performerName ?? "Character Studio").font(.title2.bold())
                                            Spacer()
                                            Picker("View", selection: $characterFaceCloseup) {
                                                Text("Full body").tag(false)
                                                Text("Face").tag(true)
                                            }.pickerStyle(.segmented).frame(width: 200)
                                            Button("Done") { characterPreviewOpen = false }.keyboardShortcut(.defaultAction)
                                        }
                                        HStack(alignment: .top, spacing: 20) {
                                            VStack {
                                                CharacterModelPreview(appearance: current.performerAppearance ?? PerformerAppearance(), faceCloseup: characterFaceCloseup, rotation: characterPreviewAngle)
                                                    .frame(minWidth: 420, minHeight: 420)
                                                HStack {
                                                    Button("Front") { characterPreviewAngle = 0 }
                                                    Button("Left") { characterPreviewAngle = -90 }
                                                    Button("Right") { characterPreviewAngle = 90 }
                                                    Button("Back") { characterPreviewAngle = 180 }
                                                }.buttonStyle(PillButtonStyle())
                                                Slider(value: $characterPreviewAngle, in: -180...180)
                                            }
                                            .onChange(of: characterFaceCloseup) { isFace in if isFace { characterPreviewAngle = 0 } }
                                            ScrollView {
                                                VStack(alignment: .leading, spacing: 14) {
                                                    let a = current.performerAppearance ?? PerformerAppearance()
                                                    Text("Appearance").font(.headline)
                                                    TextField("Character name", text: Binding(get: { current.performerName ?? "" }, set: { v in model.updateStageItem(id) { $0.performerName = v } }))
                                                    if a.modelPath == nil {
                                                        Picker("Body style", selection: Binding(get: { a.bodyStyle ?? "Masculine" }, set: { v in model.updateStageItem(id) { var p = $0.performerAppearance ?? PerformerAppearance(); p.bodyStyle = v; $0.performerAppearance = p } })) {
                                                            ForEach(["Masculine", "Feminine"], id: \.self) { Text($0).tag($0) }
                                                        }
                                                        Picker("Model tone", selection: Binding(get: { a.skin >= 3 ? 3 : 0 }, set: { v in model.updateStageItem(id) { var p = $0.performerAppearance ?? PerformerAppearance(); p.skin = v; $0.performerAppearance = p } })) {
                                                            Text("Lighter").tag(0)
                                                            Text("Darker").tag(3)
                                                        }
                                                        Text("Body style and tone select an authored base model, not a skin recolor.").font(.caption).foregroundColor(Theme.subtle)
                                                    }
                                                    slider("Height", a.height, 1.4...2.1, "m") { v in model.updateStageItem(id) { var p = $0.performerAppearance ?? PerformerAppearance(); p.height = v; $0.performerAppearance = p } }
                                                    slider("Body build", a.build, 0.7...1.4, "×") { v in model.updateStageItem(id) { var p = $0.performerAppearance ?? PerformerAppearance(); p.build = v; $0.performerAppearance = p } }
                                                    Divider()
                                                    Text("Hairstyle, hair color, skin tone and outfit color are set in the panel on the right.").font(.caption).foregroundColor(Theme.subtle)
                                                }
                                                .padding(.trailing, 8)
                                            }
                                            .frame(width: 250)
                                        }
                                        Text("Drag to rotate · scroll to zoom. Textured models retain their authored materials.")
                                            .font(.caption).foregroundColor(Theme.subtle)
                                        HStack {
                                            Menu("Choose starter") {
                                                ForEach(SavedPerformer.starters) { p in Button(p.name) { applyCharacter(p, to: id) } }
                                            }
                                            Menu("My characters") {
                                                ForEach(savedCharacters) { p in Button(p.name) { applyCharacter(p, to: id) } }
                                            }
                                            Spacer()
                                            let a = current.performerAppearance ?? PerformerAppearance()
                                            Text(a.role.rawValue).foregroundColor(Theme.subtle)
                                        }
                                    }.padding(20).frame(width: 860, height: 590)
                                }
                            }

                            }
                            let appearance = item.performerAppearance ?? PerformerAppearance()
                            Button("Import 3D Character…") {
                                let panel = NSOpenPanel()
                                panel.allowedFileTypes = ["usdz"]
                                panel.allowsMultipleSelection = false
                                panel.canChooseDirectories = false
                                guard panel.runModal() == .OK, let url = panel.url else { return }
                                do {
                                    let fm = FileManager.default
                                    let dir = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                                        .appendingPathComponent("DMX Studio/Character Assets", isDirectory: true)
                                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                                    let copy = dir.appendingPathComponent(UUID().uuidString + ".usdz")
                                    try fm.copyItem(at: url, to: copy)
                                    model.updateStageItem(id) {
                                        var a = $0.performerAppearance ?? PerformerAppearance()
                                        a.modelPath = copy.path; $0.performerAppearance = a
                                        $0.performerName = url.deletingPathExtension().lastPathComponent
                                    }
                                    characterNotice = "Imported 3D model. Save Character to reuse it."
                                } catch { characterNotice = error.localizedDescription }
                            }.buttonStyle(PillButtonStyle())
                            if appearance.modelPath != nil {
                                Text("Imported mesh · appearance is authored in the asset.").font(.caption).foregroundColor(Theme.subtle)
                                Button("Use built-in character instead") {
                                    model.updateStageItem(id) { var a = $0.performerAppearance ?? PerformerAppearance(); a.modelPath = nil; $0.performerAppearance = a }
                                }
                            }
                            Menu("Choose a character") {
                                Section("Starter characters") {
                                    ForEach(SavedPerformer.starters) { p in
                                        Button(p.name) { applyCharacter(p, to: id) }
                                    }
                                }
                                Section("My characters") {
                                    if savedCharacters.isEmpty { Text("No saved characters yet") }
                                    ForEach(savedCharacters) { p in
                                        Button(p.name) { applyCharacter(p, to: id) }
                                    }
                                }
                                Divider()
                                Button("Create from scratch") {
                                    model.updateStageItem(id) { $0.performerAppearance = PerformerAppearance(); $0.performerName = "New Character" }
                                    characterNotice = ""
                                }
                            }
                            Button("Move to Center Stage") {
                                guard let deck = model.stage.items.first(where: { $0.prop == .stage }) else {
                                    characterNotice = "No stage platform found."; return
                                }
                                model.updateStageItem(id) {
                                    $0.x = deck.x; $0.z = deck.z
                                    $0.y = deck.y + 0.60; $0.rotation = deck.rotation
                                }
                                characterNotice = "Character moved to center stage."
                            }
                            .buttonStyle(PillButtonStyle())
                            TextField("Character name", text: Binding(get: { item.performerName ?? "" }, set: { v in model.updateStageItem(id) { $0.performerName = v } }))
                            Button {
                                let name = (item.performerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !name.isEmpty else { characterNotice = "Enter a character name first."; return }
                                var entries = savedCharacters
                                if let index = entries.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                                    entries[index].appearance = appearance
                                } else {
                                    entries.append(SavedPerformer(name: name, appearance: appearance))
                                }
                                storeCharacters(entries)
                                characterNotice = "Saved " + name
                            } label: { Label("Save Character", systemImage: "square.and.arrow.down") }
                            .buttonStyle(PillButtonStyle())
                            if !savedCharacters.isEmpty {
                                Menu("Manage saved characters") {
                                    ForEach(savedCharacters) { p in
                                        Button("Duplicate " + p.name) {
                                            var copy = p; copy.id = UUID()
                                            let existing = Set(savedCharacters.map { $0.name.lowercased() })
                                            var n = 1
                                            repeat { copy.name = p.name + " Copy" + (n == 1 ? "" : " " + String(n)); n += 1 } while existing.contains(copy.name.lowercased())
                                            storeCharacters(savedCharacters + [copy])
                                            applyCharacter(copy, to: id)
                                        }
                                    }
                                }
                            }
                            if !characterNotice.isEmpty { Text(characterNotice).font(.caption).foregroundColor(Theme.subtle) }

                            performanceControls(appearance, id: id)
                            bodyControls(appearance, id: id)
                            wardrobeControls(appearance, id: id)
                            complexionControls(appearance, id: id)
                            measurementControls(appearance, id: id)
                            faceControls(appearance, id: id)
                        }
                        if fx?.colorWheel != nil {
                            Picker("", selection: Binding(get: { item.onStand ?? true }, set: { v in
                                model.updateStageItem(id) { $0.onStand = v; if !v && $0.y == 0 { $0.y = 0.6 } }
                            })) {
                                Text("On its stand").tag(true)
                                Text("Off the stand").tag(false)
                            }
                            .pickerStyle(.segmented).labelsHidden()
                            Text("Off the stand, put it on the stage edge, a table or hang it from a truss.")
                                .font(.caption2).foregroundColor(Theme.subtle)
                        }
                        if item.fixtureID != nil {
                            Toggle("Hang upside down (on a truss)", isOn: Binding(get: { item.hanging }, set: { v in model.updateStageItem(id) { $0.hanging = v } }))
                            HStack {
                                Button("On the stage floor") { model.updateStageItem(id) { $0.y = 0.6; $0.hanging = false; $0.upright = nil }; model.syncMount(id) }
                                Button("On the truss") { model.updateStageItem(id) { $0.y = 3.3; $0.hanging = true; $0.upright = nil }; model.syncMount(id) }
                                Button("Upright on a truss leg") { model.updateStageItem(id) { $0.y = 1.2; $0.hanging = false; $0.upright = true }; model.syncMount(id) }
                                    .help("Standing on end with the foot brackets: the tilt sweeps the beams side to side")
                            }
                            .font(.caption)
                        }
                        if !characterOnly {
                        Divider()
                        Button(role: .destructive) { model.deleteStageItem(id) } label: {
                            Label(item.fixtureID != nil ? "Remove light from session" : "Remove from venue", systemImage: "trash")
                        }
                        }
                    } else {
                        Text("Nothing selected").font(.headline)
                        Text("Click a light or a prop in the 3D view to select it, then drag it across the floor. Use Add to put in more lights, truss, stands, a mic stand, speakers, a DJ booth or a performer.")
                            .font(.caption).foregroundColor(Theme.subtle)
                        Divider()
                        Button("Reset to starter venue") {
                            model.stage = StageLayout.starter(for: model.fixtures)
                            model.selectedStageItem = nil
                        }
                        Text("The venue is saved with this session.").font(.caption2).foregroundColor(Theme.subtle)
                    }
                }
            }
        }
    }

    @ViewBuilder private func performanceControls(_ appearance: PerformerAppearance, id: UUID) -> some View {
                            Divider()
                            Text("Performance").font(.headline)
                            Picker("Role", selection: Binding(get: { appearance.role }, set: { v in model.updateStageItem(id) { var a = $0.performerAppearance ?? PerformerAppearance(); a.role = v; $0.performerAppearance = a } })) {
                                ForEach(PerformerRole.allCases) { Text($0.rawValue).tag($0) }
                            }

    }

    @ViewBuilder private func bodyControls(_ appearance: PerformerAppearance, id: UUID) -> some View {
                            Divider()
                            Text("Body & proportions").font(.headline)
                            Picker("Body shape", selection: Binding(get: { appearance.bodyStyle ?? "Masculine" }, set: { v in model.updateStageItem(id) { var a = $0.performerAppearance ?? PerformerAppearance(); a.bodyStyle = v; $0.performerAppearance = a } })) {
                                ForEach(["Masculine","Feminine","Androgynous"], id: \.self) { Text($0).tag($0) }
                            }

    }

    @ViewBuilder private func wardrobeControls(_ appearance: PerformerAppearance, id: UUID) -> some View {
                            Divider()
                            Text("Wardrobe & accessories").font(.headline)
                            Picker("Clothing", selection: Binding(get: { appearance.clothingStyle ?? "Casual" }, set: { v in model.updateStageItem(id) { var a = $0.performerAppearance ?? PerformerAppearance(); a.clothingStyle = v; $0.performerAppearance = a } })) {
                                ForEach(["Casual","Rock Jacket","Punk","Glam","Formal","Fantasy"], id: \.self) { Text($0).tag($0) }
                            }
                            Picker("Accessory", selection: Binding(get: { appearance.accessory ?? "None" }, set: { v in model.updateStageItem(id) { var a = $0.performerAppearance ?? PerformerAppearance(); a.accessory = v; $0.performerAppearance = a } })) {
                                ForEach(["None","Top Hat","Glasses","Choker","Wings"], id: \.self) { Text($0).tag($0) }
                            }
                            Picker("Stance", selection: Binding(get: { appearance.pose ?? "Natural" }, set: { v in model.updateStageItem(id) { var a = $0.performerAppearance ?? PerformerAppearance(); a.pose = v; $0.performerAppearance = a } })) {
                                ForEach(["Natural","Wide","Performance"], id: \.self) { Text($0).tag($0) }
                            }

    }

    @ViewBuilder private func complexionControls(_ appearance: PerformerAppearance, id: UUID) -> some View {
                            Divider()
                            Text("Hair & complexion").font(.headline)
                            Picker("Hair", selection: Binding(get: { appearance.hair }, set: { v in model.updateStageItem(id) { var a = $0.performerAppearance ?? PerformerAppearance(); a.hair = v; $0.performerAppearance = a } })) {
                                ForEach(PerformerHair.allCases) { Text($0.rawValue).tag($0) }
                            }
                            Picker("Skin tone", selection: Binding(get: { appearance.skin }, set: { v in model.updateStageItem(id) { var a = $0.performerAppearance ?? PerformerAppearance(); a.skin = v; $0.performerAppearance = a } })) {
                                ForEach(0..<6) { Text("Tone " + String($0 + 1)).tag($0) }
                            }
                            Picker("Outfit", selection: Binding(get: { appearance.outfit }, set: { v in model.updateStageItem(id) { var a = $0.performerAppearance ?? PerformerAppearance(); a.outfit = v; $0.performerAppearance = a } })) {
                                ForEach(Array(["Black", "Red", "Blue", "White", "Purple", "Green"].enumerated()), id: \.offset) { i, name in Text(name).tag(i) }
                            }
                            Picker("Hair color", selection: Binding(get: { appearance.hairColor }, set: { v in model.updateStageItem(id) { var a = $0.performerAppearance ?? PerformerAppearance(); a.hairColor = v; $0.performerAppearance = a } })) {
                                ForEach(Array(["Black", "Brown", "Blonde", "Red", "Blue", "Silver"].enumerated()), id: \.offset) { i, name in Text(name).tag(i) }
                            }

    }

    @ViewBuilder private func measurementControls(_ appearance: PerformerAppearance, id: UUID) -> some View {
                            Divider()
                            Text("Measurements").font(.headline)
                            let inches = Int((appearance.height / 0.0254).rounded())
                            let heightFeet = inches / 12
                            let heightInches = inches % 12
                            let heightCentimeters = Int((appearance.height * 100).rounded())
                            Text("Height: \(heightFeet) ft \(heightInches) in · \(heightCentimeters) cm").font(.caption)
                            Slider(value: Binding(get: { appearance.height }, set: { v in model.updateStageItem(id) { var a = $0.performerAppearance ?? PerformerAppearance(); a.height = v; $0.performerAppearance = a } }), in: 1.4...2.1, step: 0.01)
                            let heightRatio: Double = appearance.height / 1.75
                            let baseWeight: Double = 73.0 * heightRatio * heightRatio
                            let estimatedWeight: Double = baseWeight * appearance.build
                            let pounds = Int(estimatedWeight * 2.20462)
                            let kilograms = Int(estimatedWeight)
                            let weightRange: ClosedRange<Double> = (baseWeight * 0.7)...(baseWeight * 1.4)
                            let weightBinding = Binding<Double>(get: { estimatedWeight }, set: { value in
                                model.updateStageItem(id) { item in
                                    var a = item.performerAppearance ?? PerformerAppearance()
                                    let ratio: Double = a.height / 1.75
                                    let baseline: Double = 73.0 * ratio * ratio
                                    a.build = min(1.4, max(0.7, value / baseline))
                                    item.performerAppearance = a
                                }
                            })
                            Text("Estimated weight: \(pounds) lb · \(kilograms) kg").font(.caption)
                            Slider(value: weightBinding, in: weightRange)
                            Text("Weight is an approximate visual build control, not a physical simulation.").font(.caption2).foregroundColor(Theme.subtle)

    }

    @ViewBuilder private func faceControls(_ appearance: PerformerAppearance, id: UUID) -> some View {
                            Divider()
                            Text("Face").font(.headline)
                            Text("Independent face meshes are not available for the current bundled models. Use Face view to inspect the authored face.").font(.caption).foregroundColor(Theme.subtle)
                            slider("Body build", appearance.build, 0.7...1.4, "×") { v in model.updateStageItem(id) { var a = $0.performerAppearance ?? PerformerAppearance(); a.build = v; $0.performerAppearance = a } }
    }

    private func slider(_ label: String, _ value: Double, _ range: ClosedRange<Double>, _ unit: String, set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text(String(format: "%.1f%@", value, unit)).font(.caption).monospacedDigit().foregroundColor(Theme.subtle)
            }
            Slider(value: Binding(get: { value }, set: { set(($0 * 10).rounded() / 10) }), in: range)
        }
    }
}

/// Real lights on/off. Off = simulate only (the real lights stay dark).
struct RealLightsSwitch: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Button { model.outputEnabled.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: model.outputEnabled ? "lightbulb.fill" : "lightbulb.slash")
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.outputEnabled ? "LIVE" : "GO LIVE").font(.system(size: 12, weight: .bold))
                    Text(model.outputEnabled ? "Lights follow the app · click for preview" : "Preview only · lights untouched").font(.system(size: 9)).opacity(0.8)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(model.outputEnabled ? Color.green.opacity(0.25) : Color.orange.opacity(0.3)))
            .overlay(Capsule().stroke(model.outputEnabled ? Color.green.opacity(0.6) : Color.orange.opacity(0.7)))
        }
        .buttonStyle(.plain)
        .help("Live: your lights follow the app. Preview: shows play on screen only and your lights are left alone")
    }
}

// MARK: - The rendered stage

struct StageCanvas: View {
    @EnvironmentObject var model: AppModel
    let editing: Bool
    /// Small corner preview: a close-up where the lights themselves stay visible, with shorter, wider rays
    var compact = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { tl in
                    Canvas { ctx, size in
                        draw(ctx: ctx, size: size, time: tl.date.timeIntervalSinceReferenceDate)
                    }
                }
                if editing {
                    ForEach(model.fixtures) { fx in
                        let p = model.placement(for: fx)
                        let isBar = fx.headCount > 1
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                            .foregroundColor(Theme.accent)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.12)))
                            .frame(width: isBar ? geo.size.width * 0.17 + 16 : 44, height: 40)
                            .overlay(Text(fx.name).font(.system(size: 10, weight: .bold)).offset(y: 30))
                            .position(x: p.x * geo.size.width, y: p.y * geo.size.height)
                            .gesture(DragGesture().onChanged { v in
                                model.setPlacement(fx.id,
                                                   x: min(0.97, max(0.03, Double(v.location.x / geo.size.width))),
                                                   y: min(0.97, max(0.05, Double(v.location.y / geo.size.height))))
                            })
                            .contextMenu {
                                ForEach(StageMount.allCases) { m in
                                    Button {
                                        model.setPlacement(fx.id, mount: m)
                                    } label: {
                                        Text((p.mount == m ? "✓ " : "") + m.rawValue)
                                    }
                                }
                            }
                    }
                }
            }
        }
        .frame(minHeight: 380)
    }

    // MARK: drawing

    private func draw(ctx: GraphicsContext, size: CGSize, time: Double) {
        let w = size.width, h = size.height
        let horizon = h * 0.62

        // Room: back wall + floor
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizon)),
                 with: .linearGradient(Gradient(colors: [Color(white: 0.02), Color(red: 0.06, green: 0.06, blue: 0.09)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
        var floor = Path()
        floor.move(to: CGPoint(x: w * 0.07, y: horizon))
        floor.addLine(to: CGPoint(x: w * 0.93, y: horizon))
        floor.addLine(to: CGPoint(x: w, y: h))
        floor.addLine(to: CGPoint(x: 0, y: h))
        floor.closeSubpath()
        ctx.fill(floor, with: .linearGradient(Gradient(colors: [Color(white: 0.09), Color(white: 0.03)]),
                                              startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: h)))
        // stage lip
        ctx.fill(Path(CGRect(x: 0, y: h * 0.86, width: w, height: 3)), with: .color(Color.white.opacity(0.06)))
        // truss
        ctx.fill(Path(CGRect(x: w * 0.08, y: h * 0.07, width: w * 0.84, height: 6)), with: .color(Color(white: 0.18)))

        let master = model.blackout ? 0 : model.master
        let haze = model.haze
        let target = CGPoint(x: w * 0.5, y: h * 0.7)

        var glow = ctx
        glow.blendMode = .plusLighter

        // close-up layout: lights spread in a row (floor ones low, hanging ones high), big enough to see
        func sameType(_ f: Fixture) -> Int { model.fixtures.filter { $0.isOn && $0.profileName == f.profileName && $0.layout == f.layout }.count }
        // one light of each type (e.g. one beam bar, one followspot), not two copies of the same light
        let shown: [Int] = {
            var seen = Set<String>(); var out: [Int] = []
            for i in model.fixtures.indices where i < model.preview.count && model.fixtures[i].isOn {
                let f = model.fixtures[i]
                if !compact || seen.insert(f.profileName + "|" + f.layout).inserted { out.append(i) }
            }
            return out
        }()
        func compactOrigin(_ i: Int, _ p: StagePlacement) -> CGPoint {
            let k = shown.firstIndex(of: i) ?? 0
            let x = w * (CGFloat(k) + 0.5) / CGFloat(max(1, shown.count))
            switch p.mount {
            case .hanging: return CGPoint(x: x, y: h * 0.14)
            case .frontOfHouse: return CGPoint(x: x, y: h * 0.88)
            case .upright: return CGPoint(x: x, y: h * 0.55)
            case .floor: return CGPoint(x: x, y: h * 0.80)
            }
        }
        for (i, fx) in model.fixtures.enumerated() {
            guard i < model.preview.count else { continue }
            if compact && !shown.contains(i) { continue }
            let rf = model.preview[i]
            let p = model.placement(for: fx)
            let origin = compact ? compactOrigin(i, p) : CGPoint(x: p.x * w, y: p.y * h)

            // Strobe flicker
            var gate = 1.0
            if rf.strobe > 0 {
                let hz = 6 + 8 * rf.strobe
                gate = Int(time * hz * 2) % 2 == 0 ? 1 : 0
            }

            let n = max(1, rf.heads.count)
            let barWidth = n > 1 ? (compact ? min(w * 0.82 / CGFloat(max(1, shown.count)), w * 0.44) : w * 0.17) : 0
            if compact {
                // the light's body first, so the lenses and rays sit on it
                if n > 1 {
                    let r = p.mount == .upright
                        ? CGRect(x: origin.x - 7, y: origin.y - barWidth / 2 - 5, width: 14, height: barWidth + 10)
                        : CGRect(x: origin.x - barWidth / 2 - 5, y: origin.y - 6, width: barWidth + 10, height: 14)
                    ctx.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(Color(white: 0.2)))
                } else {
                    ctx.fill(Path(roundedRect: CGRect(x: origin.x - 11, y: origin.y - 9, width: 22, height: 22), cornerRadius: 5),
                             with: .color(Color(white: 0.2)))
                }
            }
            for hIdx in 0..<n {
                let st = hIdx < rf.heads.count ? rf.heads[hIdx] : .off
                let level = st.intensity * master * gate
                let along = n > 1 ? -barWidth / 2 + barWidth * (CGFloat(hIdx) + 0.5) / CGFloat(n) : 0
                // upright bars: lenses stacked bottom to top
                let head = p.mount == .upright ? CGPoint(x: origin.x, y: origin.y - along) : CGPoint(x: origin.x + along, y: origin.y)

                // Beam direction
                var angle: Double
                var length: Double
                var spread: Double = n > 1 ? 4.5 : 9          // degrees (SHEHDS lens is 8°)
                // Tilt turns the head front to back (the SHEHDS bar: 180°, no side to side). This view
                // looks at the stage from the front, so a tilt shows as the beam leaning toward you or
                // away: shorter and wider the further it tilts. Only lights with pan swing sideways.
                let hasPan = fx.channels.contains(.role(.pan, head: 0))
                let side = hasPan ? (rf.pan - 0.5) * 120 : 0
                // A rigid beam bar has one tilt axis: all lenses remain parallel.
                // Represent depth using a shared projected length, never per-lens fan angles.
                let a = (rf.tilt - 0.5) * .pi
                let toward = sin(a)                     // + toward the audience, − away
                let up = cos(a)
                let fanX = 0.0
                let downY = toward > 0 ? toward * 0.45 : 0
                let lenK = toward > 0 ? 1 + toward * 0.35 : max(0.22, 1 + toward * 0.75)
                switch p.mount {
                case .floor:
                    angle = atan2(-up + downY, fanX) * 180 / .pi + side
                    length = Double(h) * (compact ? 0.78 : 1.1) * lenK
                case .hanging:
                    angle = atan2(up - downY, fanX) * 180 / .pi + side
                    length = Double(h) * (compact ? 0.7 : 0.9) * lenK
                case .upright:
                    // tilt turns the head around the upright bar: from facing you (short), out to the
                    // left or right (full length) — the crossing sweeps on a truss leg
                    let a = (rf.tilt - 0.5) * .pi
                    let sideways = max(0.14, abs(sin(a)))
                    angle = sin(a) >= 0 ? -8 : 188
                    length = Double(w) * (compact ? 0.62 : 0.5) * sideways
                case .frontOfHouse:
                    angle = atan2(Double(target.y - head.y), Double(target.x - head.x)) * 180 / .pi
                    length = Double(hypot(target.x - head.x, target.y - head.y)) * 1.05
                    spread = 7
                }
                if compact { spread *= 1.8 }
                guard level > 0.01 else {
                    // dark lens
                    ctx.fill(Path(ellipseIn: CGRect(x: head.x - 4, y: head.y - 4, width: 8, height: 8)), with: .color(Color(white: 0.15)))
                    continue
                }
                let col = st.color.color
                let rad = angle * .pi / 180
                let end = CGPoint(x: head.x + CGFloat(cos(rad) * length), y: head.y + CGFloat(sin(rad) * length))
                let halfW = CGFloat(tan(spread / 2 * .pi / 180) * length)
                let nx = CGFloat(-sin(rad)), ny = CGFloat(cos(rad))
                var beam = Path()
                beam.move(to: CGPoint(x: head.x + nx * 3, y: head.y + ny * 3))
                beam.addLine(to: CGPoint(x: end.x + nx * halfW, y: end.y + ny * halfW))
                beam.addLine(to: CGPoint(x: end.x - nx * halfW, y: end.y - ny * halfW))
                beam.addLine(to: CGPoint(x: head.x - nx * 3, y: head.y - ny * 3))
                beam.closeSubpath()
                glow.fill(beam, with: .linearGradient(
                    Gradient(colors: [col.opacity(0.85 * level * haze), col.opacity(0.25 * level * haze), col.opacity(0)]),
                    startPoint: head, endPoint: end))

                // Where the light lands
                if p.mount == .frontOfHouse {
                    let r = CGFloat(tan(spread / 2 * .pi / 180) * length) * 1.4
                    glow.fill(Path(ellipseIn: CGRect(x: target.x - r, y: target.y - r * 1.2, width: r * 2, height: r * 2.4)),
                              with: .radialGradient(Gradient(colors: [col.opacity(0.7 * level), col.opacity(0)]),
                                                    center: target, startRadius: 0, endRadius: r * 1.2))
                } else if p.mount == .hanging, end.y > horizon {
                    let fy = min(end.y, h * 0.95)
                    let fx2 = head.x + (fy - head.y) / max(0.001, CGFloat(sin(rad))) * CGFloat(cos(rad))
                    glow.fill(Path(ellipseIn: CGRect(x: fx2 - halfW * 0.8, y: fy - halfW * 0.25, width: halfW * 1.6, height: halfW * 0.5)),
                              with: .color(col.opacity(0.35 * level)))
                }

                // Lens glow
                // pointed at you, the lens flares (as in a phone video of the bar)
                let lr: CGFloat = (compact ? 5 : 9) * CGFloat(1 + max(0, toward - 0.4) * 2.2)
                glow.fill(Path(ellipseIn: CGRect(x: head.x - lr, y: head.y - lr, width: lr * 2, height: lr * 2)),
                          with: .radialGradient(Gradient(colors: [Color.white.opacity(level), col.opacity(0.8 * level), col.opacity(0)]),
                                                center: head, startRadius: 0, endRadius: lr))
            }

            if compact {
                let deg = Int(((rf.tilt - 0.5) * 180).rounded())
                ctx.draw(Text("\(sameType(fx) > 1 ? "\(fx.profileName) ×\(sameType(fx))" : fx.name) · tilt \(deg > 0 ? "+" : "")\(deg)°").font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .foregroundColor(Color.white.opacity(0.6)),
                         at: CGPoint(x: origin.x, y: origin.y + (p.mount == .hanging ? -16 : p.mount == .upright ? barWidth / 2 + 14 : 18)))
                continue
            }
            // Fixture body + label
            if n > 1 {
                let body = p.mount == .upright
                    ? CGRect(x: origin.x - 5, y: origin.y - barWidth / 2 - 6, width: 10, height: barWidth + 12)
                    : CGRect(x: origin.x - barWidth / 2 - 6, y: origin.y + 6, width: barWidth + 12, height: 10)
                ctx.fill(Path(roundedRect: body, cornerRadius: 3), with: .color(Color(white: 0.16)))
            } else {
                ctx.fill(Path(roundedRect: CGRect(x: origin.x - 9, y: origin.y + 5, width: 18, height: 14), cornerRadius: 3),
                         with: .color(Color(white: 0.16)))
            }
            ctx.draw(Text(fx.name).font(.system(size: 10, weight: .semibold)).foregroundColor(Color.white.opacity(0.55)),
                     at: CGPoint(x: origin.x, y: origin.y + (p.mount == .upright ? barWidth / 2 + 18 : 28)))
        }

        if !model.outputEnabled && !compact {
            ctx.draw(Text("PREVIEW ONLY · your lights aren't being controlled").font(.system(size: 11, weight: .heavy)).foregroundColor(.orange),
                     at: CGPoint(x: w - 12, y: 16), anchor: .trailing)
        }
    }
}


/// On the Stage page: which part of the song is playing (Verse 1, Pre-Chorus, Chorus 2…), what comes next
/// and when, and the look that's on — so you can tell where you are without the timeline.
struct StageSectionBadge: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        CoarseReader(model.coarse) {
            if let id = model.playingSongID, let song = model.song(id), let show = song.activeShow, let t = model.showTimeNow {
                let parts = show.sections.filter { $0.transition == nil && $0.empty != true }
                let cur = parts.last { $0.start <= t + 0.05 }
                let next = parts.first { $0.start > t + 0.05 && base($0.name) != base(cur?.name ?? "") }
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.displayName).font(.system(size: 10)).foregroundColor(Theme.subtle).lineLimit(1)
                        Text(base(cur?.name ?? "—")).font(.system(size: 20, weight: .heavy))
                        if let c = cur {
                            Text("\(c.effect.rawValue) · \(c.level.rawValue)").font(.system(size: 10)).foregroundColor(Theme.subtle)
                        }
                    }
                    if let n = next {
                        Divider().frame(height: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("NEXT").font(.system(size: 9, weight: .heavy)).foregroundColor(Theme.subtle)
                            Text(base(n.name)).font(.system(size: 13, weight: .semibold))
                            Text("in \(Int(max(0, n.start - t).rounded())) s").font(.system(size: 10).monospacedDigit()).foregroundColor(Theme.subtle)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.6)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12)))
            }
        }
    }

    /// "Chorus 1 ·2" → "Chorus 1" (a phrase inside a part is still that part)
    private func base(_ n: String) -> String {
        (n.components(separatedBy: "·").first ?? n).trimmingCharacters(in: .whitespaces)
    }
}
