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

    private var sections: [ShowSection] { song.shows.indices.contains(showIndex) ? song.shows[showIndex].sections : [] }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("Sections").font(.headline)
                    Text("Click a block to change it · drag a look or another block onto it to replace it · right-click for more")
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
    }

    // MARK: Blocks

    private var timeline: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, geo.size.width * zoom)
            let dur = max(analysis.duration, 1)
            ScrollView(.horizontal, showsIndicators: zoom > 1.01) {
                ZStack(alignment: .topLeading) {
                    ForEach(sections) { s in
                        let x0 = CGFloat(s.start / dur) * width
                        let w = max(18, CGFloat((s.end - s.start) / dur) * width - 3)
                        block(s, width: w)
                            .frame(width: w, height: 84)
                            .offset(x: x0)
                    }
                    // playhead
                    if model.playingSongID == song.id {
                        LiveReader(model.live) {
                            Rectangle().fill(Color.white).frame(width: 2, height: 92)
                                .shadow(color: .white, radius: 3)
                                .offset(x: CGFloat(model.currentTime / dur) * width, y: -4)
                        }
                        .allowsHitTesting(false)
                    }
                }
                .frame(width: width, height: 92, alignment: .topLeading)
                .padding(.top, 4)
            }
        }
        .frame(height: 100)
    }

    @ViewBuilder private func block(_ s: ShowSection, width: CGFloat) -> some View {
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
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onTapGesture { selected = s.id }
        .help("\(s.name) · \(s.effect.rawValue) · \(s.palette) · \(formatTime(s.start))–\(formatTime(s.end))")
        .onDrag {
            selected = s.id
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
            Button("Copy Look") { copied = s }
            Button("Paste Look") { if let c = copied { applyLook(of: c, to: s.id) } }.disabled(copied == nil)
            Divider()
            Button("Split in Two") { model.splitSection(songID: song.id, sectionID: s.id) }
            Button("Merge with Next") { model.mergeWithNext(songID: song.id, sectionID: s.id) }
        }
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
                Text("drag onto a block, or click to put it on the selected block").font(.caption).foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $looksGroup) {
                    Text("All").tag("All")
                    ForEach(lookGroups, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 180)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 6) {
                    ForEach(model.presets.filter { looksGroup == "All" || ($0.group ?? "Essentials") == looksGroup }) { p in
                        lookChip(p)
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    private func lookChip(_ p: LookPreset) -> some View {
        let pal = Palette.named(p.palette)
        let n = max(1, min(4, pal.colors.count))
        return HStack(spacing: 6) {
            Image(systemName: p.effect.icon).font(.system(size: 12, weight: .bold))
            VStack(alignment: .leading, spacing: 0) {
                Text(p.name).font(.system(size: 11, weight: .bold)).lineLimit(1)
                Text(p.effect.rawValue).font(.system(size: 9)).opacity(0.75).lineLimit(1)
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: (0..<n).map { pal.color($0).color }, startPoint: .leading, endPoint: .trailing))
                RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.4))
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.15)))
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
            }
            HStack(spacing: 14) {
                labeled("Effect") {
                    Picker("", selection: sec.effect) {
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
        if str.hasPrefix("preset:"), let id = UUID(uuidString: String(str.dropFirst(7))), let p = model.presets.first(where: { $0.id == id }) {
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
        song.shows[showIndex].sections[k] = s
        selected = id
    }

    private func applyLook(of src: ShowSection, to id: UUID) {
        guard let k = song.shows[showIndex].sections.firstIndex(where: { $0.id == id }) else { return }
        var s = song.shows[showIndex].sections[k]
        s.effect = src.effect; s.palette = src.palette; s.movement = src.movement; s.rate = src.rate
        s.intensity = src.intensity; s.accentStrobe = src.accentStrobe; s.colorShift = src.colorShift; s.accents = src.accents
        song.shows[showIndex].sections[k] = s
        selected = id
    }
}
