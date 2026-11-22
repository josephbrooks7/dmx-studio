import SwiftUI

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

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stage").font(.system(size: 22, weight: .heavy))
                    Text(model.stageEditing ? "Click something to select it, drag it across the floor. Fine-tune on the right."
                                            : "Your venue in 3D. Drag to orbit, scroll or pinch to zoom. Everything you play shows up here.")
                        .font(.caption).foregroundColor(Theme.subtle).lineLimit(1)
                }
                Spacer()
                ForEach(["Overview", "Audience", "Top", "Side", "Close-up"], id: \.self) { v in
                    Button(v) { model.stageCameraRequest = (v, UUID()) }.buttonStyle(PillButtonStyle())
                        .help(v == "Close-up" ? "Zoom in on your lights to see them tilt and move" : "")
                }
                HStack(spacing: 2) {
                    Button { model.stageCameraRequest = ("Zoom Out", UUID()) } label: { Image(systemName: "minus.magnifyingglass") }
                        .help("Zoom out")
                    Button { model.stageCameraRequest = ("Zoom In", UUID()) } label: { Image(systemName: "plus.magnifyingglass") }
                        .help("Zoom in (you can also scroll or pinch)")
                }
                .buttonStyle(PillButtonStyle())
                HStack(spacing: 6) {
                    Image(systemName: "cloud.fog").foregroundColor(Theme.subtle)
                    Slider(value: $model.haze, in: 0.1...1).frame(width: 90)
                }
                .help("Haze: how visible the beams are")
                Toggle("HQ", isOn: $model.stageHighQuality)
                    .toggleStyle(.switch).controlSize(.small)
                    .help("High-quality 3D: glow, smoothing, light pools on the floor, 60 fps. Leave off on older Intel MacBooks, where heavy 3D can restart the Mac.")
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
                Button { model.stageEditing.toggle(); if !model.stageEditing { model.selectedStageItem = nil } } label: {
                    Label(model.stageEditing ? "Done" : "Edit Venue", systemImage: model.stageEditing ? "checkmark" : "hammer")
                }
                .buttonStyle(PillButtonStyle(active: model.stageEditing))
            }
            HStack(spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    Stage3DView(model: model)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.panelBorder))
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
                RealLightsSwitch()
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
        .onAppear { model.ensureStageItems() }
        .onChange(of: model.fixtures) { _ in model.ensureStageItems() }
    }
}

/// Fine-tune the selected item: position, height, rotation, size, mounting.
struct StageInspector: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Panel {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let id = model.selectedStageItem, let item = model.stage.items.first(where: { $0.id == id }) {
                        let fx = item.fixtureID.flatMap { fid in model.fixtures.first { $0.id == fid } }
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
                        if let k = item.prop, [.stage, .truss, .trussTower, .circleTruss, .lightStand, .trussFrame, .ledWall].contains(k) {
                            slider(k == .truss ? "Length" : (k == .stage ? "Width" : "Size"), item.size,
                                   k == .truss ? 1...12 : (k == .trussTower || k == .lightStand ? 1...6 : 0.5...3),
                                   k == .stage || k == .circleTruss ? "×" : "m") { v in model.updateStageItem(id) { $0.size = v } }
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
                                Button("On the stage floor") { model.updateStageItem(id) { $0.y = 0.6; $0.hanging = false } }
                                Button("On the truss") { model.updateStageItem(id) { $0.y = 3.3; $0.hanging = true } }
                            }
                            .font(.caption)
                        }
                        Divider()
                        Button(role: .destructive) { model.deleteStageItem(id) } label: {
                            Label(item.fixtureID != nil ? "Remove light from session" : "Remove from venue", systemImage: "trash")
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
        let shown = model.fixtures.indices.filter { i in i < model.preview.count && model.fixtures[i].isOn }
        func compactOrigin(_ i: Int, _ p: StagePlacement) -> CGPoint {
            let k = shown.firstIndex(of: i) ?? 0
            let x = w * (CGFloat(k) + 0.5) / CGFloat(max(1, shown.count))
            switch p.mount {
            case .hanging: return CGPoint(x: x, y: h * 0.14)
            case .frontOfHouse: return CGPoint(x: x, y: h * 0.88)
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
                    ctx.fill(Path(roundedRect: CGRect(x: origin.x - barWidth / 2 - 5, y: origin.y - 6, width: barWidth + 10, height: 14), cornerRadius: 4),
                             with: .color(Color(white: 0.2)))
                } else {
                    ctx.fill(Path(roundedRect: CGRect(x: origin.x - 11, y: origin.y - 9, width: 22, height: 22), cornerRadius: 5),
                             with: .color(Color(white: 0.2)))
                }
            }
            for hIdx in 0..<n {
                let st = hIdx < rf.heads.count ? rf.heads[hIdx] : .off
                let level = st.intensity * master * gate
                let hx = n > 1 ? origin.x - barWidth / 2 + barWidth * (CGFloat(hIdx) + 0.5) / CGFloat(n) : origin.x
                let head = CGPoint(x: hx, y: origin.y)

                // Beam direction
                var angle: Double
                var length: Double
                var spread: Double = n > 1 ? 4.5 : 9          // degrees (SHEHDS lens is 8°)
                switch p.mount {
                case .floor:
                    angle = -90 + (rf.tilt - 0.5) * 150 + (rf.pan - 0.5) * (fx.channels.contains(.role(.pan, head: 0)) ? 120 : 0)
                    length = Double(h) * (compact ? 0.78 : 1.1)
                case .hanging:
                    angle = 90 + (rf.tilt - 0.5) * 150
                    length = Double(h) * (compact ? 0.7 : 0.9)
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
                let lr: CGFloat = compact ? 5 : 9
                glow.fill(Path(ellipseIn: CGRect(x: head.x - lr, y: head.y - lr, width: lr * 2, height: lr * 2)),
                          with: .radialGradient(Gradient(colors: [Color.white.opacity(level), col.opacity(0.8 * level), col.opacity(0)]),
                                                center: head, startRadius: 0, endRadius: lr))
            }

            if compact {
                let deg = Int(((rf.tilt - 0.5) * 180).rounded())
                ctx.draw(Text("\(fx.name) · tilt \(deg > 0 ? "+" : "")\(deg)°").font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .foregroundColor(Color.white.opacity(0.6)),
                         at: CGPoint(x: origin.x, y: origin.y + (p.mount == .hanging ? -16 : 18)))
                continue
            }
            // Fixture body + label
            if n > 1 {
                let body = CGRect(x: origin.x - barWidth / 2 - 6, y: origin.y + 6, width: barWidth + 12, height: 10)
                ctx.fill(Path(roundedRect: body, cornerRadius: 3), with: .color(Color(white: 0.16)))
            } else {
                ctx.fill(Path(roundedRect: CGRect(x: origin.x - 9, y: origin.y + 5, width: 18, height: 14), cornerRadius: 3),
                         with: .color(Color(white: 0.16)))
            }
            ctx.draw(Text(fx.name).font(.system(size: 10, weight: .semibold)).foregroundColor(Color.white.opacity(0.55)),
                     at: CGPoint(x: origin.x, y: origin.y + 28))
        }

        if !model.outputEnabled && !compact {
            ctx.draw(Text("PREVIEW ONLY · your lights aren't being controlled").font(.system(size: 11, weight: .heavy)).foregroundColor(.orange),
                     at: CGPoint(x: w - 12, y: 16), anchor: .trailing)
        }
    }
}
