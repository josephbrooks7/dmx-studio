import SwiftUI
import AppKit

/// Final Cut Pro style browser for the looks and transitions: categories on the left, search, and a grid of
/// thumbnails (a little light bar showing the look; hover to watch it play). Drag a tile onto a timeline block,
/// or click it to put it on the selected block.
struct EffectsBrowser: View {
    @EnvironmentObject var model: AppModel
    enum Item { case look(LookPreset), transition(HitKind) }
    var onPick: (Item) -> Void

    @AppStorage("fxCategory") private var category = "All"
    @State private var search = ""
    @State private var hovered: String?
    @State private var previewed: Item?          // last hovered / clicked tile, shown in the preview viewer
    var current: ShowSection? = nil              // the selected block (previewed until you hover a tile)

    private var groups: [String] {
        var seen: [String] = []
        for p in model.presets { let g = p.group ?? "Essentials"; if !seen.contains(g) { seen.append(g) } }
        return seen
    }
    private func matches(_ name: String, _ extra: String) -> Bool {
        search.isEmpty || name.localizedCaseInsensitiveContains(search) || extra.localizedCaseInsensitiveContains(search)
    }
    private var looks: [LookPreset] {
        model.presets.filter { p in
            (category == "All" || (p.group ?? "Essentials") == category) && category != "Transitions"
                && matches(p.name, p.effect.rawValue + " " + p.palette)
        }
    }
    private var transitions: [HitKind] {
        (category == "All" || category == "Transitions") ? HitKind.allCases.filter { matches($0.rawValue, $0.blurb) } : []
    }

    var body: some View {
        HStack(spacing: 0) {
            // categories
            VStack(alignment: .leading, spacing: 2) {
                Text("EFFECTS").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary).padding(.horizontal, 10).padding(.top, 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        categoryRow("All", icon: "square.grid.2x2", count: model.presets.count + HitKind.allCases.count)
                        categoryRow("Transitions", icon: "bolt.fill", count: HitKind.allCases.count)
                        Divider().padding(.vertical, 4)
                        ForEach(groups, id: \.self) { g in
                            categoryRow(g, icon: "folder.fill", count: model.presets.filter { ($0.group ?? "Essentials") == g }.count)
                        }
                    }
                    .padding(.horizontal, 6)
                }
            }
            .frame(width: 190)
            .background(Color.black.opacity(0.25))
            Divider()
            // grid
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(category).font(.system(size: 13, weight: .semibold))
                    Text("\(looks.count + transitions.count) items").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("Search effects", text: $search).textFieldStyle(.plain).frame(width: 160)
                        if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundColor(.secondary) }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.07)))
                }
                .padding(.horizontal, 10).padding(.top, 8)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 116, maximum: 140), spacing: 10)], alignment: .leading, spacing: 12) {
                        ForEach(transitions) { k in
                            tile(key: "hit:\(k.rawValue)", name: k.rawValue, sub: "Transition", icon: k.icon,
                                 drag: "hit:\(k.rawValue)", help: "\(k.rawValue): \(k.blurb)") {
                                FXThumb.transition(k, live: hovered == "hit:\(k.rawValue)")
                            } pick: { onPick(.transition(k)) }
                        }
                        ForEach(looks) { p in
                            tile(key: p.id.uuidString, name: p.name, sub: p.effect.rawValue, icon: p.effect.icon,
                                 drag: "preset:\(p.id.uuidString)", help: "\(p.name): \(p.effect.rawValue), \(p.palette)\(p.movement == .none ? "" : ", " + p.movement.rawValue)") {
                                FXThumb.look(p, live: hovered == p.id.uuidString)
                            } pick: { onPick(.look(p)) }
                        }
                    }
                    .padding(10)
                }
            }
            Divider()
            previewPane.frame(width: 330)
        }
        .overlay(alignment: .trailing) { EmptyView() }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.3)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08)))
    }

    // MARK: Preview viewer

    @ViewBuilder private var previewPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PREVIEW").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
            StagePreviewSim(item: previewed, base: current)
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1)))
            switch previewed {
            case .look(let p)?:
                Text(p.name).font(.headline)
                Text("\(p.effect.rawValue) · \(p.palette)\(p.movement == .none ? "" : " · " + p.movement.rawValue)\(p.rate == 1 ? "" : (p.rate < 1 ? " · ½ speed" : " · 2× speed"))")
                    .font(.caption).foregroundColor(.secondary)
                HStack(spacing: 3) {
                    let pal = Palette.named(p.palette)
                    ForEach(0..<min(6, pal.colors.count), id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2).fill(pal.color(i).color).frame(width: 14, height: 10)
                    }
                }
                Button { onPick(.look(p)) } label: { Label("Apply to Selected Block", systemImage: "checkmark") }
            case .transition(let k)?:
                Text(k.rawValue).font(.headline)
                Text("Transition · \(k.blurb)").font(.caption).foregroundColor(.secondary)
                Text("Plays over the look before it, for the length of its block (default \(k.beats == 1 ? "1 beat" : "\(Int(k.beats)) beats")).")
                    .font(.caption2).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                Button { onPick(.transition(k)) } label: { Label("Put in Selected Slot", systemImage: "checkmark") }
            case nil:
                if let c = current {
                    Text(c.name).font(.headline)
                    Text("Selected block · \(c.effect.rawValue) · \(c.palette)").font(.caption).foregroundColor(.secondary)
                }
                Text("Hover over an effect to see it on your lights.").font(.caption).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
    }

    private func categoryRow(_ name: String, icon: String, count: Int) -> some View {
        Button { category = name } label: {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 11)).frame(width: 16)
                    .foregroundColor(name == "Transitions" ? .yellow : (category == name ? .white : .secondary))
                Text(name).font(.system(size: 12)).lineLimit(1)
                Spacer()
                Text("\(count)").font(.system(size: 10)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 5).fill(category == name ? Color.accentColor.opacity(0.45) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func itemFor(_ key: String) -> Item? {
        if key.hasPrefix("hit:") { return HitKind(rawValue: String(key.dropFirst(4))).map { .transition($0) } }
        return model.presets.first { $0.id.uuidString == key }.map { .look($0) }
    }

    private func tile<T: View>(key: String, name: String, sub: String, icon: String, drag: String, help: String,
                               @ViewBuilder thumb: () -> T, pick: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            thumb()
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(hovered == key ? Color.white.opacity(0.8) : Color.white.opacity(0.1), lineWidth: hovered == key ? 1.5 : 1))
                .overlay(alignment: .topLeading) {
                    Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                        .padding(4).background(Circle().fill(Color.black.opacity(0.55))).padding(4)
                }
            Text(name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            Text(sub).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = key; previewed = itemFor(key) } else if hovered == key { hovered = nil }
        }
        .onTapGesture { previewed = itemFor(key); pick() }
        .onDrag { NSItemProvider(object: drag as NSString) }
        .help(help + " · drag onto a block, or click to put it on the selected block")
    }
}

/// The little light-bar picture on a tile: the look rendered on 8 beam heads (playing while hovered)
enum FXThumb {
    private static let fixture = Fixture(name: "Preview", address: 1, profileName: FixtureProfile.shehdsBeam38.name,
                                         layout: FixtureProfile.shehdsBeam38.layout)
    private static var cache: [String: [FixtureState]] = [:]

    private static func frame(_ sections: [ShowSection], hits: [ShowHit], at t: Double, bpm: Double = 124) -> [FixtureState] {
        var clock = BeatClock(); clock.bpm = bpm; clock.anchor = 0
        let la = clock.liveAnalysis(now: t, onsets: [], level: 0.8, useOnsetsAsKicks: false)
        var r = ShowRenderer(analysis: la, sections: sections, fixtures: [fixture])
        r.hits = hits
        return r.render(at: t).first?.heads ?? []
    }

    @ViewBuilder static func look(_ p: LookPreset, live: Bool) -> some View {
        if live {
            SwiftUI.TimelineView(.periodic(from: .now, by: 1.0 / 24)) { tl in
                bar(frame([p.asSection(start: 0)], hits: [], at: tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 600)))
            }
        } else {
            let key = "\(p.effect.rawValue)|\(p.palette)|\(p.rate)|\(p.intensity)|\(p.movement.rawValue)"
            let heads = cache[key] ?? {
                let h = frame([p.asSection(start: 0)], hits: [], at: 8.37)
                cache[key] = h
                return h
            }()
            bar(heads)
        }
    }

    @ViewBuilder static func transition(_ k: HitKind, live: Bool) -> some View {
        let base = ShowSection(name: "Base", start: 0, end: 1e9, level: .medium, effect: .gradient, palette: "Deep Blue", intensity: 0.8)
        if live {
            SwiftUI.TimelineView(.periodic(from: .now, by: 1.0 / 24)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 600)
                // the hit again every 2 seconds
                let at = floor(t / 2) * 2 + (k.buildsUp ? 1.9 : 0.2)
                bar(frame([base], hits: [ShowHit(time: at, kind: k, beats: k.beats)], at: t))
            }
        } else {
            let key = "hit|\(k.rawValue)"
            let heads = cache[key] ?? {
                let at = 8.0
                let h = frame([base], hits: [ShowHit(time: at, kind: k, beats: k.beats)], at: k.buildsUp ? at - 0.4 : at + 0.06)
                cache[key] = h
                return h
            }()
            bar(heads)
        }
    }

    /// 8 glowing beam heads on a dark bar
    static func bar(_ heads: [FixtureState]) -> some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.09), Color(white: 0.03)], startPoint: .top, endPoint: .bottom)
            // soft glow behind the heads
            HStack(spacing: 0) {
                ForEach(Array(heads.enumerated()), id: \.offset) { _, h in
                    lit(h).opacity(0.35).blur(radius: 9)
                }
            }
            HStack(spacing: 4) {
                ForEach(Array(heads.enumerated()), id: \.offset) { _, h in
                    Circle().fill(lit(h))
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                        .frame(width: 10, height: 10)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.7)))
        }
    }

    private static func lit(_ h: FixtureState) -> Color {
        let k = max(0, min(1, h.intensity))
        return Color(red: h.color.r * k, green: h.color.g * k, blue: h.color.b * k)
    }
}


/// A close-up of one light (your first beam bar) with its beams in haze, playing a look or a transition
struct StagePreviewSim: View {
    @EnvironmentObject var model: AppModel
    let item: EffectsBrowser.Item?
    let base: ShowSection?

    /// Just one light, up close: the first beam bar (the one with the most heads), else a demo bar
    private var rig: [Fixture] {
        if let bar = model.fixtures.filter({ $0.effectiveBehavior == .sequence }).max(by: { $0.headCount < $1.headCount }), bar.headCount > 1 {
            return [bar]
        }
        let p = FixtureProfile.shehdsBeam38
        return [Fixture(name: "Beam Bar", address: 1, profileName: p.name, layout: p.layout)]
    }

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { tl in
            // a short run-through: 4 bars, then it starts again (fades out and in at the loop)
            let loop = 16 * 60.0 / 124
            let p = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: loop)
            let fade = min(1, p / 0.35, (loop - p) / 0.35)
            let frame = render(8 + p)
            Canvas { ctx, size in draw(ctx, size, frame, fade: fade) }
        }
        .background(Color.black)
    }

    private func render(_ t: Double) -> [RenderedFixture] {
        var clock = BeatClock(); clock.bpm = 124; clock.anchor = 0
        let la = clock.liveAnalysis(now: t, onsets: [], level: 0.8, useOnsetsAsKicks: false)
        var sections: [ShowSection]
        var hits: [ShowHit] = []
        switch item {
        case .look(let p)?:
            sections = [p.asSection(start: 0)]
        case .transition(let k)?:
            sections = [base.map { var b = $0; b.start = 0; b.end = 1e9; b.empty = nil; b.transition = nil; return b }
                        ?? ShowSection(name: "Base", start: 0, end: 1e9, level: .medium, effect: .gradient, palette: "Deep Blue", intensity: 0.8)]
            // the hit lands in the middle of the run-through
            let at = 8 + 8 * 60.0 / 124
            hits = [ShowHit(time: at, kind: k, beats: k.beats)]
        case nil:
            if let b = base, b.empty != true { var s = b; s.start = 0; s.end = 1e9; s.transition = nil; sections = [s] }
            else { return rig.map { RenderedFixture(heads: Array(repeating: .off, count: $0.headCount)) } }
        }
        var r = ShowRenderer(analysis: la, sections: sections, fixtures: rig)
        r.hits = hits
        return r.render(at: t)
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ frame: [RenderedFixture], fade: Double) {
        // a black room: dark back wall, a floor line
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        ctx.fill(Path(CGRect(x: 0, y: size.height - 26, width: size.width, height: 26)),
                 with: .linearGradient(Gradient(colors: [Color(white: 0.05), Color(white: 0.0)]),
                                       startPoint: CGPoint(x: 0, y: size.height - 26), endPoint: CGPoint(x: 0, y: size.height)))
        let n = max(1, frame.count)
        let floorY = size.height - 30
        let slotW = size.width / CGFloat(n)
        var glow = ctx
        glow.blendMode = .plusLighter
        for (fi, f) in frame.enumerated() {
            let cx = slotW * (CGFloat(fi) + 0.5)
            let barW = min(slotW - 24, size.width * 0.86)
            let heads = max(1, f.heads.count)
            // movement: pan swings the beams sideways, tilt changes their reach
            let swing = CGFloat(f.pan - 0.5) * 1.3
            let reach = size.height * (0.55 + 0.4 * CGFloat(f.tilt))
            for (hi, h) in f.heads.enumerated() {
                let k = max(0, min(1, h.intensity)) * fade
                guard k > 0.02 else { continue }
                let hx = cx - barW / 2 + barW * (CGFloat(hi) + 0.5) / CGFloat(heads)
                let c = Color(red: h.color.r, green: h.color.g, blue: h.color.b)
                let tipX = hx + swing * reach * 0.6
                let tipY = floorY - reach
                var beam = Path()
                beam.move(to: CGPoint(x: hx - 5, y: floorY))
                beam.addLine(to: CGPoint(x: tipX - 16, y: tipY))
                beam.addLine(to: CGPoint(x: tipX + 16, y: tipY))
                beam.addLine(to: CGPoint(x: hx + 5, y: floorY))
                beam.closeSubpath()
                glow.fill(beam, with: .linearGradient(Gradient(colors: [c.opacity(0.55 * k), c.opacity(0)]),
                                                      startPoint: CGPoint(x: hx, y: floorY), endPoint: CGPoint(x: tipX, y: tipY)))
                // the lens
                glow.fill(Path(ellipseIn: CGRect(x: hx - 12, y: floorY - 12, width: 24, height: 24)), with: .color(c.opacity(0.35 * k)))
                glow.fill(Path(ellipseIn: CGRect(x: hx - 7, y: floorY - 7, width: 14, height: 14)), with: .color(c.opacity(k)))
                glow.fill(Path(ellipseIn: CGRect(x: hx - 16, y: size.height - 18, width: 32, height: 8)), with: .color(c.opacity(0.18 * k)))
            }
            // the bar itself
            ctx.fill(Path(roundedRect: CGRect(x: cx - barW / 2 - 8, y: floorY + 8, width: barW + 16, height: 12), cornerRadius: 4),
                     with: .color(Color(white: 0.2)))
            ctx.draw(Text(rig.first?.name ?? "").font(.system(size: 9)).foregroundColor(.white.opacity(0.4)),
                     at: CGPoint(x: cx, y: size.height - 6))
        }
    }
}
