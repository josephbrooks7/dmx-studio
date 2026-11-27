import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension LightEffect {
    /// Icon shown on its block in the section timeline
    var icon: String {
        switch self {
        case .steady: return "lightbulb.fill"
        case .breathe: return "wind"
        case .pulse: return "waveform.path.ecg"
        case .kickFlash: return "bolt.fill"
        case .snareHit: return "burst.fill"
        case .chase: return "arrow.forward"
        case .alternate: return "arrow.left.arrow.right"
        case .colorBeat: return "paintpalette.fill"
        case .rainbow: return "rainbow"
        case .sparkle: return "sparkles"
        case .strobe: return "bolt.horizontal.fill"
        case .soundLevel: return "speaker.wave.3.fill"
        case .blackout: return "moon.fill"
        case .wave: return "wave.3.right"
        case .centerOut: return "dot.radiowaves.left.and.right"
        case .split: return "square.split.2x1.fill"
        case .pixelPop: return "square.grid.3x3.fill"
        case .bounce: return "arrow.up.and.down"
        case .gradient: return "circle.lefthalf.filled"
        case .ripple: return "dot.radiowaves.right"
        case .scan: return "scope"
        case .fill: return "square.fill"
        case .fire: return "flame.fill"
        case .embers: return "flame"
        case .water: return "drop.fill"
        case .tide: return "drop.triangle.fill"
        case .magic: return "wand.and.stars"
        case .aurora: return "moon.stars.fill"
        case .glitch: return "waveform.path"
        case .shimmer: return "sparkle"
        case .goldDust: return "star.fill"
        case .blinderHits: return "sun.max.fill"
        case .stutter: return "bolt.circle.fill"
        default: return "sparkles"
        }
    }
}

extension MoveEffect {
    var icon: String? { self == .none ? nil : "arrow.triangle.2.circlepath" }
}

/// The song's sections as a row of colored blocks along the song. Click one to change it; drag a look
/// (or another block) onto a block to replace its look.
struct SectionTimelineEditor: View {
    @EnvironmentObject var model: AppModel
    @Binding var song: Song
    let showIndex: Int
    let analysis: SongAnalysis
    @State private var selected: UUID?
    @State private var zoom: Double = 1
    @State private var copied: ShowSection?
    @State private var dropTarget: UUID?
    @State private var looksGroup = "All"
    @State private var scrubTime: Double?
    @State private var edgeOrigin: Double?
    @State private var edgeDragging: Int?
    @State private var timelineWidth: CGFloat = 1
    @State private var stepsOpen = false
    @AppStorage("timelineBlockHeight") private var blockH: Double = 78
    @AppStorage("looksPanelHeight") private var looksH: Double = 330
    @State private var tool: TimelineTool = .pointer
    @State private var paint: Paint?                 // what the Pencil puts on a block (the last pad clicked)
    @State private var repeatFrom: UUID?             // block whose repeat handle is being dragged
    @State private var repeatTo: Double?

    enum TimelineTool: String, CaseIterable, Identifiable {
        case pointer = "Pointer", scissors = "Scissors", eraser = "Eraser", pencil = "Pencil", join = "Join"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .pointer: return "cursorarrow"
            case .scissors: return "scissors"
            case .eraser: return "xmark.square"
            case .pencil: return "pencil"
            case .join: return "link"
            }
        }
        var help: String {
            switch self {
            case .pointer: return "Pointer: select blocks, drag edges, drop looks"
            case .scissors: return "Scissors: click a block to cut it right there (on the beat)"
            case .eraser: return "Eraser: click a block to empty it (its time stays)"
            case .pencil: return "Pencil: click a block or slot to paint it with the last look / transition you clicked"
            case .join: return "Join: click a block to merge it with the next one"
            }
        }
    }
    enum Paint: Equatable { case look(UUID), transition(HitKind) }

    private var sections: [ShowSection] { song.shows.indices.contains(showIndex) ? song.shows[showIndex].sections : [] }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("Sections").font(.headline)
                    Text("Click a block to change it · drag a look onto it to replace it · press . while playing to cut a slot for a transition")
                        .font(.caption).foregroundColor(.secondary).lineLimit(1)
                    Spacer()
                    Picker("", selection: $tool) {
                        ForEach(TimelineTool.allCases) { tl in Image(systemName: tl.icon).help(tl.help).tag(tl) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                    .help(tool.help)
                    Image(systemName: "arrow.up.and.down").foregroundColor(.secondary)
                    Slider(value: $blockH, in: 50...150).frame(width: 70).help("Track height")
                    Image(systemName: "minus.magnifyingglass").foregroundColor(.secondary)
                    Slider(value: $zoom, in: 1...4).frame(width: 110).help("Zoom the timeline")
                    Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary)
                }
                timeline
                // drag to make the tracks taller or shorter
                ResizeHandle(width: $blockH, range: 50...150, resetTo: 78, vertical: true)
                if let id = selected ?? sections.first?.id, let k = sections.firstIndex(where: { $0.id == id }) {
                    inspector(k)
                }
                // drag up for a bigger looks browser, down for a smaller one
                ResizeHandle(width: $looksH, range: 160...800, growsLeft: true, resetTo: 330, vertical: true)
                EffectsBrowser(onPick: { item in
                    switch item {
                    case .look(let p):
                        paint = .look(p.id)
                        if tool != .pencil, let id = selected ?? sections.first?.id { apply(p, to: id) }
                    case .transition(let k):
                        paint = .transition(k)
                        guard tool != .pencil else { return }
                        let target = selected.flatMap { id in sections.first { $0.id == id } }
                            ?? sections.first { $0.empty == true && $0.end > (scrubTime ?? 0) }
                        if let s = target { model.setTransition(k, songID: song.id, sectionID: s.id); select(s.id) }
                    }
                }, current: (selected ?? sections.first?.id).flatMap { id in sections.first { $0.id == id } })
                .frame(height: looksH)
            }
        }
        // a cut made with "." selects the new slot
        .onChange(of: model.timelineSelection) { sel in
            if let sel, sel.song == song.id, sel.section != selected { selected = sel.section }
        }
    }

    // MARK: Blocks

    private var timeline: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, geo.size.width * zoom)
            let dur = max(analysis.duration, 1)
            let _ = DispatchQueue.main.async { if abs(timelineWidth - width) > 0.5 { timelineWidth = width } }
            ScrollView(.horizontal, showsIndicators: zoom > 1.01) {
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        ruler(width: width, dur: dur).frame(height: 16)
                        arrangementLane(width: width, dur: dur).frame(height: 16)
                        // light show track: one block per section, side by side
                        ZStack(alignment: .topLeading) {
                            ForEach(sections) { s in
                                let x0 = CGFloat(s.start / dur) * width
                                let w = max(18, CGFloat((s.end - s.start) / dur) * width - 4)
                                block(s, width: w)
                                    .frame(width: w, height: blockH)
                                    .offset(x: x0 + 2)
                            }
                            // edges between blocks: drag to resize (the neighbor gives or takes the time)
                            ForEach(Array(sections.enumerated().dropLast()), id: \.element.id) { k, s in
                                edgeHandle(k)
                                    .offset(x: CGFloat(s.end / dur) * width - 6)
                            }
                        }
                        .frame(width: width, height: blockH, alignment: .topLeading)
                        // audio track
                        waveform(width: width, dur: dur)
                            .frame(width: width, height: 40)
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                                scrub(to: Double(v.location.x / width) * dur)
                            })
                            .help("The song · click or drag to move the playhead")
                    }
                    playhead(width: width, dur: dur)
                }
                .frame(width: width, alignment: .topLeading)
                .padding(.top, 2)
            }
        }
        .frame(height: blockH + 74)
    }

    /// The grab handle on the boundary after block k
    private func edgeHandle(_ k: Int) -> some View {
        Rectangle().fill(Color.white.opacity(edgeDragging == k ? 0.9 : 0.001))
            .frame(width: 12, height: blockH)
            .overlay(Capsule().fill(Color.white.opacity(edgeDragging == k ? 1 : 0.35)).frame(width: 3, height: 30))
            .overlay(alignment: .bottom) {
                if edgeDragging == k, sections.indices.contains(k) {
                    let s = sections[k]
                    let delta = s.end - (edgeOrigin ?? s.end)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Length Change").font(.system(size: 10, weight: .bold))
                        Text("\(s.name): \(barsBeats(s.end - s.start))  (\(String(format: "%.1f", s.end - s.start)) s)").font(.system(size: 10))
                        Text("\(delta >= 0 ? "+" : "−")\(barsBeats(abs(delta)))  · ends \(formatTime(s.end))").font(.system(size: 10)).foregroundColor(.yellow)
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.88)))
                    .fixedSize()
                    .offset(x: 70, y: 52)
                }
            }
            .contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { v in
                    guard sections.indices.contains(k + 1) else { return }
                    if edgeOrigin == nil { edgeOrigin = sections[k].end; edgeDragging = k }
                    let dur = max(analysis.duration, 1)
                    let dt = Double(v.translation.width / max(timelineWidth, 1)) * dur
                    moveBoundary(after: k, to: (edgeOrigin ?? sections[k].end) + dt, snap: !NSEvent.modifierFlags.contains(.option))
                }
                .onEnded { _ in edgeOrigin = nil; edgeDragging = nil })
            .help("Drag to make this block longer or shorter (the next one adjusts) · ⌥ for free placement")
    }

    /// Move the boundary between block k and k+1, keeping everything else where it is
    private func moveBoundary(after k: Int, to raw: Double, snap: Bool) {
        guard song.shows[showIndex].sections.indices.contains(k + 1) else { return }
        let a = song.shows[showIndex].sections[k], b = song.shows[showIndex].sections[k + 1]
        var t = raw
        if snap, let near = analysis.beats.min(by: { abs($0 - raw) < abs($1 - raw) }), abs(near - raw) < 0.2 { t = near }
        t = max(a.start + 0.2, min(b.end - 0.2, t))
        song.shows[showIndex].sections[k].end = t
        song.shows[showIndex].sections[k + 1].start = t
    }

    /// Times along the top (click to jump there)
    /// The song's arrangement (Verse 1, Pre-Chorus, Chorus…) as labeled bars above the blocks
    private func arrangementLane(width: CGFloat, dur: Double) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(analysis.detectedSections.enumerated()), id: \.offset) { _, d in
                let x0 = CGFloat(d.start / dur) * width
                let w = max(10, CGFloat((d.end - d.start) / dur) * width - 2)
                let tint: Color = {
                    switch d.name.split(separator: " ").first.map(String.init) ?? d.name {
                    case "Chorus", "Drop", "Post-Chorus": return .pink
                    case "Pre-Chorus", "Build": return .orange
                    case "Bridge": return .purple
                    case "Intro", "Outro": return .gray
                    case "Breakdown", "Interlude", "Instrumental": return .teal
                    default: return .blue
                    }
                }()
                Text(d.name).font(.system(size: 9, weight: .bold)).lineLimit(1)
                    .padding(.horizontal, 4)
                    .frame(width: w, height: 15, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 3).fill(tint.opacity(0.35)))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(tint.opacity(0.7), lineWidth: 1))
                    .offset(x: x0)
                    .help("\(d.name) · \(formatTime(d.start))–\(formatTime(d.end))")
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    private func ruler(width: CGFloat, dur: Double) -> some View {
        let step: Double = dur / Double(zoom) > 240 ? 30 : (dur / Double(zoom) > 90 ? 15 : 5)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(stride(from: 0.0, through: dur, by: step)), id: \.self) { t in
                VStack(alignment: .leading, spacing: 0) {
                    Text(formatTime(t)).font(.system(size: 9)).foregroundColor(.secondary).monospacedDigit()
                    Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: 4)
                }
                .offset(x: CGFloat(t / dur) * width)
            }
        }
        .frame(width: width, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in scrub(to: Double(v.location.x / width) * dur) })
    }

    /// The song's loudness as a waveform, on a purple audio track
    private func waveform(width: CGFloat, dur: Double) -> some View {
        Canvas { ctx, size in
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 7), with: .color(Color(red: 0.42, green: 0.36, blue: 0.75).opacity(0.85)))
            let e = analysis.energy
            guard !e.isEmpty else { return }
            let bars = max(1, Int(size.width / 3))
            let peak = max(0.0001, e.max() ?? 1)
            for b in 0..<bars {
                let i0 = b * e.count / bars, i1 = max(i0 + 1, (b + 1) * e.count / bars)
                var m: Float = 0
                for i in i0..<min(i1, e.count) { m = max(m, e[i]) }
                let hgt = max(1, CGFloat(m / peak) * (size.height - 8))
                let x = CGFloat(b) * size.width / CGFloat(bars)
                ctx.fill(Path(roundedRect: CGRect(x: x, y: (size.height - hgt) / 2, width: 1.6, height: hgt), cornerRadius: 0.8),
                         with: .color(.white.opacity(0.75)))
            }
            // section edges on the audio too
            for s in sections.dropFirst() {
                let x = CGFloat(s.start / max(analysis.duration, 1)) * size.width
                ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(.black.opacity(0.45)))
            }
        }
    }

    /// Red playhead with a triangle on top, across both tracks
    private func playhead(width: CGFloat, dur: Double) -> some View {
        LiveReader(model.live) {
            let t = model.playingSongID == song.id ? model.currentTime : (scrubTime ?? 0)
            let x = CGFloat(t / dur) * width
            VStack(spacing: 0) {
                Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: 14, y: 0)); p.addLine(to: CGPoint(x: 7, y: 11)); p.closeSubpath() }
                    .fill(Color.red).frame(width: 14, height: 11)
                Rectangle().fill(Color.red).frame(width: 2, height: blockH + 58)
            }
            .shadow(color: .black.opacity(0.5), radius: 2)
            .offset(x: x - 7)
            .allowsHitTesting(false)
        }
    }

    private func scrub(to t: Double) {
        let t = max(0, min(analysis.duration, t))
        scrubTime = t
        model.timelinePlayhead = t
        if model.playingSongID == song.id { model.seek(to: t) }
    }

    @ViewBuilder private func block(_ s: ShowSection, width: CGFloat) -> some View {
        withActions(s.empty == true ? AnyView(emptyBlock(s, width: width))
                    : s.transition != nil ? AnyView(transitionBlock(s, width: width)) : AnyView(filledBlock(s, width: width)), s)
            .overlay(alignment: .topTrailing) { if s.empty != true && width > 34 { repeatHandle(s) } }
            .simultaneousGesture(DragGesture(minimumDistance: 0).onEnded { v in
                guard abs(v.translation.width) < 4, abs(v.translation.height) < 4 else { return }
                click(s, at: s.start + Double(max(0, min(1, v.location.x / max(width, 1)))) * (s.end - s.start))
            })
    }

    /// A removed block: same time, dashed, waiting for a look
    private func emptyBlock(_ s: ShowSection, width: CGFloat) -> some View {
        let isSel = (selected ?? sections.first?.id) == s.id
        return ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.05))
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: dropTarget == s.id || isSel ? 2.5 : 1.5, dash: [6, 4]))
                .foregroundColor(dropTarget == s.id ? .yellow : (isSel ? .white : .white.opacity(0.45)))
            VStack(spacing: 2) {
                Image(systemName: "plus").font(.system(size: width > 40 ? 20 : 12, weight: .bold))
                if width > 80 { Text("Drop a look").font(.system(size: 10, weight: .semibold)) }
                if width > 60 { Text(s.name).font(.system(size: 9)).opacity(0.7).lineLimit(1) }
            }
            .foregroundColor(.white.opacity(0.8))
        }
    }

    /// A transition block: a short hit (flash, strobe burst…) over the look before it
    private func transitionBlock(_ s: ShowSection, width: CGFloat) -> some View {
        let k = s.transition ?? .flash
        let isSel = (selected ?? sections.first?.id) == s.id
        return ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(k.color.color.opacity(0.9))
            // stripes: it's a short one-time hit
            GeometryReader { g in
                Path { p in
                    var x: CGFloat = -g.size.height
                    while x < g.size.width { p.move(to: CGPoint(x: x, y: g.size.height)); p.addLine(to: CGPoint(x: x + g.size.height, y: 0)); x += 9 }
                }
                .stroke(Color.black.opacity(0.18), lineWidth: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(spacing: 2) {
                Image(systemName: k.icon).font(.system(size: width > 34 ? 15 : 10, weight: .heavy))
                if width > 70 { Text(k.rawValue).font(.system(size: 10, weight: .bold)).lineLimit(1) }
            }
            .foregroundColor(k == .blackout ? .white : .black.opacity(0.85))
        }
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .stroke(dropTarget == s.id ? Color.yellow : (isSel ? Color.white : Color.black.opacity(0.3)), lineWidth: dropTarget == s.id || isSel ? 2.5 : 1))
    }

    @ViewBuilder private func filledBlock(_ s: ShowSection, width: CGFloat) -> some View {
        let pal = Palette.named(s.palette)
        let n = max(1, min(4, pal.colors.count))
        let isSel = (selected ?? sections.first?.id) == s.id
        let colors = (0..<n).map { pal.color(($0 + (s.colorShift ?? 0)) % n).color }
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: s.effect == .blackout ? [Color(white: 0.12)] : colors, startPoint: .leading, endPoint: .trailing))
                .opacity(0.35 + 0.6 * s.intensity)
            // darken for legible text
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.15)], startPoint: .top, endPoint: .bottom))
            // loudness along the top edge
            Capsule().fill(levelColor(s.level)).frame(height: 3).padding(.horizontal, 6).padding(.top, 3)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: s.effect.icon).font(.system(size: 13, weight: .bold))
                    if width > 70 { Text(s.effect.rawValue).font(.system(size: 12, weight: .bold)).lineLimit(1) }
                }
                if width > 50 { Text(s.name).font(.system(size: 11, weight: .semibold)).opacity(0.85).lineLimit(1) }
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    if let mi = s.movement.icon, width > 40 { Image(systemName: mi).font(.system(size: 10)) }
                    if s.rate != 1, width > 60 { Text(s.rate == 0 ? "❄︎" : s.rate < 1 ? "½×" : "\(Int(s.rate))×").font(.system(size: 10, weight: .bold)) }
                    if s.accentStrobe, width > 30 { Image(systemName: "bolt.fill").font(.system(size: 10)) }
                    if width > 110 { Text(formatTime(s.start)).font(.system(size: 10)).opacity(0.7).monospacedDigit() }
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 7).padding(.top, 9).padding(.bottom, 6)
        }
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .stroke(dropTarget == s.id ? Color.yellow : (isSel ? Color.white : Color.white.opacity(0.12)), lineWidth: dropTarget == s.id || isSel ? 2.5 : 1))
    }

    /// Click, drag, drop and right-click on a timeline block (filled or empty)
    private func withActions<V: View>(_ v: V, _ s: ShowSection) -> some View {
        v
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .help("\(s.name) · \(s.effect.rawValue) · \(s.palette) · \(formatTime(s.start))–\(formatTime(s.end))")
        .onDrag {
            select(s.id)
            return NSItemProvider(object: "section:\(s.id.uuidString)" as NSString)
        }
        .onDrop(of: [UTType.plainText], isTargeted: Binding(get: { dropTarget == s.id }, set: { dropTarget = $0 ? s.id : (dropTarget == s.id ? nil : dropTarget) })) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: NSString.self) { obj, _ in
                guard let str = obj as? String else { return }
                DispatchQueue.main.async { dropped(str, on: s.id) }
            }
            return true
        }
        .contextMenu {
            Group {
            Button("Play from Here") { play(from: s.start) }
            Button("Move Playhead Here") { scrub(to: s.start) }
            Divider()
            Menu("Replace with") {
                ForEach(lookGroups, id: \.self) { g in
                    Menu(g) {
                        ForEach(model.presets.filter { ($0.group ?? "Essentials") == g }) { p in
                            Button(p.name) { apply(p, to: s.id) }
                        }
                    }
                }
            }
            Menu("Make a Transition") {
                ForEach(HitKind.allCases) { k in Button(k.rawValue) { model.setTransition(k, songID: song.id, sectionID: s.id); select(s.id) } }
            }
            Button("Copy Look") { copied = s }
            Button("Paste Look") { if let c = copied { applyLook(of: c, to: s.id) } }.disabled(copied == nil)
            Divider()
            }
            Button("Split in Two") { model.splitSection(songID: song.id, sectionID: s.id) }
            Button("Merge with Next") { model.mergeWithNext(songID: song.id, sectionID: s.id) }
            Divider()
            Button("Remove (Leave Empty)") { model.emptySection(songID: song.id, sectionID: s.id) }.disabled(s.empty == true)
        }
    }

    /// A click on a block, by tool
    private func click(_ s: ShowSection, at time: Double) {
        switch tool {
        case .pointer:
            select(s.id)
        case .scissors:
            let t = analysis.beats.min(by: { abs($0 - time) < abs($1 - time) }).flatMap { abs($0 - time) < 0.25 ? $0 : nil } ?? time
            model.cutAt(songID: song.id, sectionID: s.id, time: t)
        case .eraser:
            model.emptySection(songID: song.id, sectionID: s.id)
        case .pencil:
            switch paint {
            case .look(let id)?: if let p = model.presets.first(where: { $0.id == id }) { apply(p, to: s.id) }
            case .transition(let k)?: model.setTransition(k, songID: song.id, sectionID: s.id)
            case nil: select(s.id)
            }
        case .join:
            model.mergeWithNext(songID: song.id, sectionID: s.id)
        }
    }

    /// Small ↻ at a block's top-right corner: drag right to repeat its look over the blocks that follow
    private func repeatHandle(_ s: ShowSection) -> some View {
        Image(systemName: "arrow.clockwise.circle.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.white.opacity(repeatFrom == s.id ? 1 : 0.6))
            .padding(3)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { v in
                    repeatFrom = s.id
                    repeatTo = s.end + Double(v.translation.width / max(timelineWidth, 1)) * max(analysis.duration, 1)
                }
                .onEnded { _ in
                    if let to = repeatTo {
                        for o in sections where o.start >= s.end - 0.01 && o.start < to - 0.05 && o.id != s.id { applyLook(of: s, to: o.id) }
                    }
                    repeatFrom = nil; repeatTo = nil
                    select(s.id)
                })
            .overlay(alignment: .bottomTrailing) {
                if repeatFrom == s.id, let to = repeatTo {
                    let n = sections.filter { $0.start >= s.end - 0.01 && $0.start < to - 0.05 }.count
                    Text(n == 0 ? "Drag right to repeat" : "Repeat over \(n) block\(n == 1 ? "" : "s")")
                        .font(.caption2.bold()).padding(5)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.85)))
                        .fixedSize().offset(x: 120, y: 28)
                }
            }
            .help("Drag right to repeat this look over the following blocks (their times don't change)")
    }

    /// "4 bars 2 beats" style length
    private func barsBeats(_ seconds: Double) -> String {
        let beat = 60 / max(analysis.bpm, 40)
        let beats = Int((seconds / beat).rounded())
        let bars = beats / 4, rest = beats % 4
        var parts: [String] = []
        if bars > 0 { parts.append("\(bars) bar\(bars == 1 ? "" : "s")") }
        if rest > 0 || bars == 0 { parts.append("\(rest) beat\(rest == 1 ? "" : "s")") }
        return parts.joined(separator: " ")
    }

    /// Selecting a block (Delete then empties it)
    func select(_ id: UUID) {
        selected = id
        model.timelineSelection = AppModel.TimelineSel(song: song.id, section: id)
    }

    // MARK: Looks to drag onto blocks

    private var lookGroups: [String] {
        var seen: [String] = []
        for p in model.presets { let g = p.group ?? "Essentials"; if !seen.contains(g) { seen.append(g) } }
        return seen
    }

    private var looksStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Looks").font(.subheadline.bold())
                Text("drag a pad onto a block, or click it to put it on the selected block").font(.caption).foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $looksGroup) {
                    Text("All").tag("All")
                    ForEach(lookGroups, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 180)
            }
            HStack(spacing: 6) {
                Text("Transitions").font(.caption.bold()).foregroundColor(.secondary).frame(width: 74, alignment: .leading)
                ForEach(HitKind.allCases) { k in transitionPad(k) }
                Spacer(minLength: 0)
            }
            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 6)], spacing: 6) {
                    ForEach(model.presets.filter { looksGroup == "All" || ($0.group ?? "Essentials") == looksGroup }) { p in
                        lookPad(p)
                    }
                }
            }
            .frame(maxHeight: 160)
        }
    }

    /// Short one-time hits for the empty slots "." leaves (or any block)
    private func transitionPad(_ k: HitKind) -> some View {
        HStack(spacing: 4) {
            Image(systemName: k.icon).font(.system(size: 11, weight: .heavy))
            Text(k.rawValue).font(.system(size: 10, weight: .bold)).lineLimit(1)
        }
        .foregroundColor(k == .blackout ? .white : .black.opacity(0.85))
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(k.color.color.opacity(0.9)))
        .contentShape(Rectangle())
        .onTapGesture {
            paint = .transition(k)
            guard tool != .pencil else { return }
            // into the selected block, or the next empty slot after the playhead
            let target = selected.flatMap { id in sections.first { $0.id == id } }
                ?? sections.first { $0.empty == true && $0.end > (scrubTime ?? 0) }
            if let s = target { model.setTransition(k, songID: song.id, sectionID: s.id); select(s.id) }
        }
        .onDrag { NSItemProvider(object: "hit:\(k.rawValue)" as NSString) }
        .help("\(k.rawValue): \(k.blurb). Drop it into a slot (press . while playing to cut one), or click to put it on the selected block")
    }

    private func lookPad(_ p: LookPreset) -> some View {
        let pal = Palette.named(p.palette)
        let n = max(1, min(4, pal.colors.count))
        let base = p.effect == .blackout ? Color(white: 0.15) : pal.color(0).color
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(base)
            // the look's other colors as a thin strip
            HStack(spacing: 0) { ForEach(0..<n, id: \.self) { i in pal.color(i).color } }
                .frame(height: 4).clipShape(Capsule()).padding(.horizontal, 5).padding(.top, 34)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0.05)], startPoint: .top, endPoint: .bottom))
            HStack(spacing: 4) {
                Image(systemName: p.effect.icon).font(.system(size: 11, weight: .bold))
                Text(p.name).font(.system(size: 11, weight: .bold)).lineLimit(1)
            }
            .foregroundColor(.white).padding(.horizontal, 6).padding(.top, 7)
            Text(p.effect.rawValue).font(.system(size: 9)).foregroundColor(.white.opacity(0.8)).lineLimit(1)
                .padding(.horizontal, 6).padding(.top, 21)
        }
        .frame(height: 44)
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.black.opacity(0.4)))
        .contentShape(Rectangle())
        .onTapGesture {
            paint = .look(p.id)
            if tool != .pencil, let id = selected ?? sections.first?.id { apply(p, to: id) }
        }
        .onDrag { NSItemProvider(object: "preset:\(p.id.uuidString)" as NSString) }
        .help("\(p.name): \(p.effect.rawValue), \(p.palette)\(p.movement == .none ? "" : ", " + p.movement.rawValue)")
    }

    // MARK: The selected block

    @ViewBuilder private func inspector(_ k: Int) -> some View {
        let sec = Binding<ShowSection>(
            get: { song.shows[showIndex].sections.indices.contains(k) ? song.shows[showIndex].sections[k] : sections[0] },
            set: { if song.shows[showIndex].sections.indices.contains(k) { song.shows[showIndex].sections[k] = $0 } })
        let s = sec.wrappedValue
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: s.effect.icon).font(.title3)
                TextField("Name", text: sec.name).textFieldStyle(.roundedBorder).frame(width: 160)
                Text("\(formatTime(s.start)) – \(formatTime(s.end))").monospacedDigit().foregroundColor(.secondary)
                Text(s.level.rawValue).font(.caption.bold())
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(levelColor(s.level).opacity(0.35)))
                Spacer()
                Button { play(from: s.start) } label: { Label("Play from Here", systemImage: "play.fill") }
                Button { select(s.id); model.splitKey() } label: { Label("Cut  ( . )", systemImage: "scissors") }
                    .help("Cut this block (at the playhead if it's inside, else in the middle) and leave a short slot for a transition")
                Button { model.mergeWithNext(songID: song.id, sectionID: s.id) } label: { Label("Merge with Next", systemImage: "arrow.right.to.line") }
                Button { model.emptySection(songID: song.id, sectionID: s.id) } label: { Label("Remove", systemImage: "trash") }
                    .disabled(s.empty == true)
                    .help("Remove this block's look and leave an empty slot of the same length (Delete key)")
            }
            if let k = s.transition {
                HStack(spacing: 10) {
                    Text("Transition").font(.caption.bold()).foregroundColor(.secondary)
                    Picker("", selection: Binding(get: { k }, set: { model.setTransition($0, songID: song.id, sectionID: s.id) })) {
                        ForEach(HitKind.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                    }.labelsHidden().frame(width: 170)
                    Text(k.blurb + ", over the look before it").font(.caption).foregroundColor(.secondary)
                }
            }
            if s.empty == true {
                Text("Empty slot: click a look pad, drag one here, or pick an effect below to fill it. Until then the lights play the idle look.")
                    .font(.callout).foregroundColor(.orange)
            }
            HStack(spacing: 14) {
                labeled("Effect") {
                    Picker("", selection: Binding(get: { sec.wrappedValue.effect }, set: { sec.wrappedValue.effect = $0; sec.wrappedValue.empty = nil })) {
                        ForEach(LightEffect.allCases) { e in Label(e.rawValue, systemImage: e.icon).tag(e) }
                    }.labelsHidden().frame(width: 170)
                }
                labeled("Colors") {
                    HStack(spacing: 6) {
                        Picker("", selection: sec.palette) {
                            ForEach(Palette.all) { p in Text(p.id).tag(p.id) }
                        }.labelsHidden().frame(width: 140)
                        HStack(spacing: 2) {
                            ForEach(0..<min(4, Palette.named(s.palette).colors.count), id: \.self) { i in
                                RoundedRectangle(cornerRadius: 2).fill(Palette.named(s.palette).color(i).color).frame(width: 9, height: 18)
                            }
                        }
                    }
                }
                labeled("Screen") {
                    Menu {
                        Button("Keep what's on") { sec.screen.wrappedValue = nil }
                        Divider()
                        ForEach(ScreenContent.allCases.filter { ![.image, .video, .rays].contains($0) }) { c in
                            Button(c.rawValue) { sec.screen.wrappedValue = ScreenCue(content: c) }
                        }
                        Button("Your image…") { if let p = AppModel.pickMedia(video: false) { sec.screen.wrappedValue = ScreenCue(content: .image, mediaPath: p) } }
                        Button("Your video…") { if let p = AppModel.pickMedia(video: true) { sec.screen.wrappedValue = ScreenCue(content: .video, mediaPath: p) } }
                    } label: {
                        Text(s.screen.map { c in c.mediaPath.map { ($0 as NSString).lastPathComponent } ?? c.content.rawValue } ?? "Keep what's on")
                            .lineLimit(1)
                    }
                    .menuStyle(.borderlessButton).frame(width: 170)
                    .help("What the LED wall / projection screen shows from this part on (stays until a later part changes it)")
                }
                labeled("Movement") {
                    Picker("", selection: sec.movement) {
                        ForEach(MoveEffect.allCases) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().frame(width: 110)
                }
                if s.movement == .none {
                    labeled("Aim") {
                        HStack(spacing: 4) {
                            Text("Back").font(.caption2).foregroundColor(.secondary)
                            Slider(value: Binding(get: { s.aim ?? 0.5 }, set: { sec.aim.wrappedValue = ($0 * 20).rounded() / 20 }), in: 0...1)
                                .frame(width: 110)
                            Text("Crowd").font(.caption2).foregroundColor(.secondary)
                            Text("\(Int((((s.aim ?? 0.5) - 0.5) * 180).rounded()))°").font(.caption.monospacedDigit()).frame(width: 34)
                        }
                        .help("Where the heads point while this part holds still: straight up in the middle, toward the audience on the right (the bar's 180° tilt)")
                    }
                } else {
                    labeled("Amount") {
                        Picker("", selection: Binding(get: { (s.moveSize ?? 1) <= 0.3 ? 0 : (s.moveSize ?? 1) < 0.9 ? 1 : 2 },
                                                      set: { v in
                                                          sec.moveSize.wrappedValue = [0.2, 0.5, nil][v]
                                                          sec.moveSpeed.wrappedValue = [0.25, 0.5, nil][v]
                                                      })) {
                            Text("Subtle").tag(0); Text("Gentle").tag(1); Text("Full").tag(2)
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                        .help("How far and how fast the heads move: a slow small drift, half the swing at half speed, or end to end")
                    }
                }
                labeled("Speed") {
                    Picker("", selection: sec.rate) {
                        Text("Freeze").tag(0.0)
                        Text("½ speed").tag(0.5)
                        Text("Normal").tag(1.0)
                        Text("2× speed").tag(2.0)
                        Text("4× speed").tag(4.0)
                        Text("8× speed").tag(8.0)
                    }.labelsHidden().frame(width: 100)
                }
                labeled("Brightness") { Slider(value: sec.intensity, in: 0.1...1).frame(width: 110) }
                labeled("Hit") { Toggle("", isOn: sec.accentStrobe).labelsHidden().help("Strobe hit on the first bar") }
            }
            HStack(spacing: 14) {
                labeled("Phase") {
                    Slider(value: Binding(get: { sec.wrappedValue.phase ?? 0 }, set: { sec.wrappedValue.phase = $0 < 0.01 ? nil : $0 }), in: 0...1)
                        .frame(width: 120).help("Each head runs a little later than the one before, so the look rolls across the light")
                }
                labeled("Order") {
                    Picker("", selection: Binding(get: { sec.wrappedValue.order ?? .forward }, set: { sec.wrappedValue.order = $0 == .forward ? nil : $0 })) {
                        ForEach(HeadOrder.allCases) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().frame(width: 110).help("Which way the pattern runs across the heads (Symmetric mirrors it from the middle)")
                }
                labeled("Beam steps") {
                    HStack(spacing: 6) {
                        Menu {
                            Button("Off (all heads)") { sec.wrappedValue.beamSteps = nil }
                            Divider()
                            ForEach(BeamPattern.allCases) { p in Button(p.rawValue) { sec.wrappedValue.beamSteps = p.steps } }
                        } label: { Text(sec.wrappedValue.beamSteps == nil ? "Off" : "Custom") }
                        .frame(width: 90)
                        Button { stepsOpen.toggle() } label: { Image(systemName: "square.grid.4x3.fill") }
                            .help("Edit the 16 steps: which heads are on at each step")
                    }
                }
                labeled("Fan") {
                    Slider(value: Binding(get: { sec.wrappedValue.fan ?? 0 }, set: { sec.wrappedValue.fan = $0 < 0.01 ? nil : $0 }), in: 0...1)
                        .frame(width: 120).help("Spread the beams of your lights apart")
                }
                Spacer()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
        if stepsOpen {
            BeamStepGrid(steps: Binding(get: { sec.wrappedValue.beamSteps ?? Array(repeating: 0xFF, count: 16) },
                                        set: { sec.wrappedValue.beamSteps = $0 }),
                         color: Palette.named(s.palette).color(0).color)
        }
    }

    private func labeled<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundColor(.secondary)
            c()
        }
    }

    // MARK: Actions

    private func levelColor(_ l: EnergyLevel) -> Color {
        switch l { case .low: return .blue; case .medium: return .yellow; case .high: return .orange; case .drop: return .red }
    }

    private func play(from t: Double) {
        if model.playingSongID == song.id { model.seek(to: t) } else { model.play(song.id, from: t) }
    }

    private func dropped(_ str: String, on target: UUID) {
        dropTarget = nil
        if str.hasPrefix("hit:"), let k = HitKind(rawValue: String(str.dropFirst(4))) {
            model.setTransition(k, songID: song.id, sectionID: target)
            select(target)
        } else if str.hasPrefix("preset:"), let id = UUID(uuidString: String(str.dropFirst(7))), let p = model.presets.first(where: { $0.id == id }) {
            apply(p, to: target)
        } else if str.hasPrefix("section:"), let id = UUID(uuidString: String(str.dropFirst(8))), let src = sections.first(where: { $0.id == id }), id != target {
            applyLook(of: src, to: target)
        }
    }

    /// Replace a block's look with a preset (its place in the song, name and loudness stay)
    private func apply(_ p: LookPreset, to id: UUID) {
        guard let k = song.shows[showIndex].sections.firstIndex(where: { $0.id == id }) else { return }
        var s = song.shows[showIndex].sections[k]
        s.effect = p.effect; s.palette = p.palette; s.movement = p.movement; s.rate = p.rate; s.intensity = p.intensity
        s.colorShift = nil
        s.empty = nil
        s.transition = nil
        song.shows[showIndex].sections[k] = s
        select(id)
    }

    private func applyLook(of src: ShowSection, to id: UUID) {
        guard let k = song.shows[showIndex].sections.firstIndex(where: { $0.id == id }) else { return }
        var s = song.shows[showIndex].sections[k]
        s.effect = src.effect; s.palette = src.palette; s.movement = src.movement; s.rate = src.rate
        s.intensity = src.intensity; s.accentStrobe = src.accentStrobe; s.colorShift = src.colorShift; s.accents = src.accents
        s.empty = src.empty
        s.transition = src.transition
        s.phase = src.phase; s.order = src.order; s.fan = src.fan; s.beamSteps = src.beamSteps
        song.shows[showIndex].sections[k] = s
        select(id)
    }
}



/// 16 steps × 8 heads: click (or drag across) the pads to switch heads on or off at each step
struct BeamStepGrid: View {
    @Binding var steps: [UInt8]
    let color: Color
    @State private var painting: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Beam sequencer").font(.subheadline.bold())
                Text("16 steps, two per beat · a lit pad = that head is on at that step · click or drag to paint").font(.caption).foregroundColor(.secondary)
                Spacer()
                Menu("Pattern") { ForEach(BeamPattern.allCases) { p in Button(p.rawValue) { steps = p.steps } } }
                    .frame(width: 110)
                Button("All On") { steps = Array(repeating: 0xFF, count: 16) }
                Button("Clear") { steps = Array(repeating: 0, count: 16) }
            }
            VStack(spacing: 3) {
                ForEach(0..<8, id: \.self) { head in
                    HStack(spacing: 3) {
                        Text("\(head + 1)").font(.system(size: 9)).foregroundColor(.secondary).frame(width: 14)
                        ForEach(0..<16, id: \.self) { step in
                            let on = steps.indices.contains(step) && steps[step] & UInt8(1 << head) != 0
                            RoundedRectangle(cornerRadius: 3)
                                .fill(on ? color : Color.white.opacity(step % 4 == 0 ? 0.12 : 0.06))
                                .shadow(color: on ? color.opacity(0.7) : .clear, radius: 3)
                                .frame(width: 22, height: 14)
                                .contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 0)
                                    .onChanged { _ in
                                        if painting == nil { painting = !on }
                                        set(step, head, painting ?? true)
                                    }
                                    .onEnded { _ in painting = nil })
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.3)))
    }

    private func set(_ step: Int, _ head: Int, _ on: Bool) {
        var s = steps.count == 16 ? steps : Array(repeating: 0xFF, count: 16)
        if on { s[step] |= UInt8(1 << head) } else { s[step] &= ~UInt8(1 << head) }
        steps = s
    }
}
