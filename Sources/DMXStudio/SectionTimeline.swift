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

    private var sections: [ShowSection] { song.shows.indices.contains(showIndex) ? song.shows[showIndex].sections : [] }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("Sections").font(.headline)
                    Text("Click a block to change it · drag a look onto it to replace it · press . while playing to cut a slot for a transition")
                        .font(.caption).foregroundColor(.secondary).lineLimit(1)
                    Spacer()
                    Image(systemName: "minus.magnifyingglass").foregroundColor(.secondary)
                    Slider(value: $zoom, in: 1...4).frame(width: 110).help("Zoom the timeline")
                    Image(systemName: "plus.magnifyingglass").foregroundColor(.secondary)
                }
                timeline
                looksStrip
                if let id = selected ?? sections.first?.id, let k = sections.firstIndex(where: { $0.id == id }) {
                    inspector(k)
                }
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
                        // light show track: one block per section, side by side
                        ZStack(alignment: .topLeading) {
                            ForEach(sections) { s in
                                let x0 = CGFloat(s.start / dur) * width
                                let w = max(18, CGFloat((s.end - s.start) / dur) * width - 4)
                                block(s, width: w)
                                    .frame(width: w, height: 78)
                                    .offset(x: x0 + 2)
                            }
                            // edges between blocks: drag to resize (the neighbor gives or takes the time)
                            ForEach(Array(sections.enumerated().dropLast()), id: \.element.id) { k, s in
                                edgeHandle(k)
                                    .offset(x: CGFloat(s.end / dur) * width - 6)
                            }
                        }
                        .frame(width: width, height: 78, alignment: .topLeading)
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
        .frame(height: 152)
    }

    /// The grab handle on the boundary after block k
    private func edgeHandle(_ k: Int) -> some View {
        Rectangle().fill(Color.white.opacity(edgeDragging == k ? 0.9 : 0.001))
            .frame(width: 12, height: 78)
            .overlay(Capsule().fill(Color.white.opacity(edgeDragging == k ? 1 : 0.35)).frame(width: 3, height: 30))
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
                Rectangle().fill(Color.red).frame(width: 2, height: 136)
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
                    if s.rate != 1, width > 60 { Text(s.rate < 1 ? "½×" : "2×").font(.system(size: 10, weight: .bold)) }
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
        .onTapGesture { select(s.id) }
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
            Button("Split in Two") { model.splitSection(songID: song.id, sectionID: s.id) }
            Button("Merge with Next") { model.mergeWithNext(songID: song.id, sectionID: s.id) }
            Divider()
            Button("Remove (Leave Empty)") { model.emptySection(songID: song.id, sectionID: s.id) }.disabled(s.empty == true)
        }
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
        .onTapGesture { if let id = selected ?? sections.first?.id { apply(p, to: id) } }
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
                Button { model.splitSection(songID: song.id, sectionID: s.id) } label: { Label("Split", systemImage: "scissors") }
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
                labeled("Movement") {
                    Picker("", selection: sec.movement) {
                        ForEach(MoveEffect.allCases) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().frame(width: 110)
                }
                labeled("Speed") {
                    Picker("", selection: sec.rate) {
                        Text("½ speed").tag(0.5)
                        Text("Normal").tag(1.0)
                        Text("2× speed").tag(2.0)
                    }.labelsHidden().frame(width: 100)
                }
                labeled("Brightness") { Slider(value: sec.intensity, in: 0.1...1).frame(width: 110) }
                labeled("Hit") { Toggle("", isOn: sec.accentStrobe).labelsHidden().help("Strobe hit on the first bar") }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
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
        song.shows[showIndex].sections[k] = s
        select(id)
    }
}

