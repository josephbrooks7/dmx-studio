import Foundation
import AppKit
import SceneKit
import CoreImage
import simd
import Metal

/// MakeHuman-based performers (CC0 body, skeleton and wardrobe; CC-BY items credited in
/// Characters/MakeHuman/CREDITS.md). The app assembles each character itself:
///   body      = base mesh + weighted adult shape targets (sex, muscle, weight, height)
///   skeleton  = joints averaged from helper vertices, so bones follow the body shape
///   clothes   = MakeHuman binding: each garment vertex follows three body vertices plus an offset
///               scaled by the body's own size; skin hidden under garments is removed
/// Everything is skinned to one skeleton, so poses move body, clothes and hair together.
/// Source data units are decimeters (Y up, front +Z, character's left +X).

// MARK: - Binary files (uint32 header length, JSON header, raw little-endian arrays)

struct MHBin {
    let arrays: [String: (offset: Int, count: Int)]
    let header: [String: Any]
    private let data: Data
    private let base: Int

    init?(url: URL) {
        guard let d = try? Data(contentsOf: url, options: .mappedIfSafe), d.count >= 4 else { return nil }
        var n: UInt32 = 0
        withUnsafeMutableBytes(of: &n) { $0.copyBytes(from: d.prefix(4)) }
        let headerEnd = 4 + Int(UInt32(littleEndian: n))
        guard d.count >= headerEnd,
              let h = try? JSONSerialization.jsonObject(with: d.subdata(in: 4..<headerEnd)) as? [String: Any] else { return nil }
        var table: [String: (Int, Int)] = [:]
        for (name, value) in (h["arrays"] as? [String: Any]) ?? [:] {
            guard let a = value as? [String: Any], let o = a["offset"] as? Int, let c = a["count"] as? Int else { continue }
            table[name] = (o, c)
        }
        arrays = table; header = h; data = d; base = headerEnd
    }

    private func raw<T>(_ name: String, _ type: T.Type, zero: T) -> [T] {
        guard let a = arrays[name] else { return [] }
        let start = base + a.offset
        let bytes = a.count * MemoryLayout<T>.stride
        guard start >= 0, start + bytes <= data.count else { return [] }
        var out = [T](repeating: zero, count: a.count)
        out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                dst.copyMemory(from: UnsafeRawBufferPointer(rebasing: src[start..<(start + bytes)]))
            }
        }
        return out
    }
    func floats(_ name: String) -> [Float] { raw(name, Float.self, zero: 0) }
    func uints(_ name: String) -> [UInt32] { raw(name, UInt32.self, zero: 0) }
}

// MARK: - Library

struct MHItem {
    let id: String
    let name: String
    let slot: String
    let gender: String
    let words: String            // lowercased name, tags and styles for matching
    let file: String
    let diffuse: String?
    let normal: String?
    let transparent: Bool
    let license: String
}

struct MHSkin {
    let name: String
    let texture: String
    let sex: String
    let ancestry: String
}

struct MHBone {
    let name: String
    let parent: Int?
    let head: String
    let tail: String
}

final class MHLibrary {
    let root: URL
    let basePositions: [SIMD3<Float>]      // every base vertex, helpers included
    let unweld: [Int]                      // visible body vertex -> base vertex
    let uvs: [Float]                       // 2 per visible body vertex
    let triangles: [UInt32]
    let bones: [MHBone]
    let joints: [String: [Int]]
    let boneIndex: [UInt32]                // 4 per base vertex
    let boneWeight: [Float]
    let items: [MHItem]
    let skins: [MHSkin]
    private let targetIndex: [UInt32]
    private let targetDelta: [Float]
    private let targetRanges: [String: (start: Int, count: Int)]

    static let shared: MHLibrary? = {
        let env = ProcessInfo.processInfo.environment["DMX_CHARACTER_LIBRARY"].map { URL(fileURLWithPath: $0) }
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Characters/MakeHuman", isDirectory: true)
        for url in [env, bundled].compactMap({ $0 }) {
            if let lib = MHLibrary(root: url) { return lib }
        }
        return nil
    }()

    init?(root: URL) {
        self.root = root
        guard let catalogData = try? Data(contentsOf: root.appendingPathComponent("catalog.json")),
              let catalog = try? JSONSerialization.jsonObject(with: catalogData) as? [String: Any],
              let base = MHBin(url: root.appendingPathComponent("base.bin")),
              let weights = MHBin(url: root.appendingPathComponent("weights.bin")),
              let targets = MHBin(url: root.appendingPathComponent("targets.bin")),
              let rigData = try? Data(contentsOf: root.appendingPathComponent("rig.json")),
              let rig = try? JSONSerialization.jsonObject(with: rigData) as? [String: Any] else { return nil }
        let all = base.floats("allPositions")
        guard all.count >= 3 else { return nil }
        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(all.count / 3)
        var i = 0
        while i + 2 < all.count { positions.append(SIMD3(all[i], all[i + 1], all[i + 2])); i += 3 }
        basePositions = positions
        unweld = base.uints("baseIndex").map { Int($0) }
        uvs = base.floats("uvs")
        triangles = base.uints("triangles")
        boneIndex = weights.uints("boneIndex")
        boneWeight = weights.floats("boneWeight")
        guard !unweld.isEmpty, uvs.count == unweld.count * 2, boneIndex.count == positions.count * 4 else { return nil }

        var names: [String: Int] = [:]
        var list: [MHBone] = []
        for (k, value) in ((rig["bones"] as? [[String: Any]]) ?? []).enumerated() {
            guard let name = value["name"] as? String, let head = value["head"] as? String, let tail = value["tail"] as? String else { return nil }
            let parent = (value["parent"] as? String).flatMap { names[$0] }
            list.append(MHBone(name: name, parent: parent, head: head, tail: tail))
            names[name] = k
        }
        bones = list
        var jointMap: [String: [Int]] = [:]
        for (name, value) in (rig["joints"] as? [String: Any]) ?? [:] {
            jointMap[name] = ((value as? [Any]) ?? []).compactMap { ($0 as? NSNumber)?.intValue }
        }
        joints = jointMap

        targetIndex = targets.uints("index")
        targetDelta = targets.floats("delta")
        var ranges: [String: (Int, Int)] = [:]
        for r in (targets.header["targets"] as? [[String: Any]]) ?? [] {
            if let n = r["name"] as? String, let s = r["start"] as? Int, let c = r["count"] as? Int { ranges[n] = (s, c) }
        }
        targetRanges = ranges

        var itemList: [MHItem] = []
        for raw in (catalog["items"] as? [[String: Any]]) ?? [] {
            guard let id = raw["id"] as? String, let file = raw["file"] as? String, let slot = raw["slot"] as? String else { continue }
            if MHLibrary.excluded(raw["name"] as? String ?? id) { continue }
            let name = raw["name"] as? String ?? id
            let tags = (raw["tags"] as? [String] ?? []).joined(separator: " ")
            let styles = (raw["styles"] as? [String] ?? []).joined(separator: " ")
            let textures = raw["textures"] as? [String: String] ?? [:]
            var gender = raw["gender"] as? String ?? "any"
            let lower = name.lowercased()
            if gender == "any" && (lower.hasPrefix("fem") || lower.contains("female") || lower.contains("heroine")) { gender = "female" }
            if gender == "any" && (lower.hasPrefix("male") || lower.contains(" male") || lower.hasPrefix("hero ")) { gender = "male" }
            itemList.append(MHItem(id: id, name: name, slot: slot, gender: gender,
                                   words: (name + " " + tags + " " + styles + " " + id).lowercased(),
                                   file: file, diffuse: textures["diffuseTexture"], normal: textures["normalmapTexture"],
                                   transparent: raw["transparent"] as? Bool ?? false, license: raw["license"] as? String ?? ""))
        }
        items = itemList
        skins = ((catalog["skins"] as? [[String: Any]]) ?? []).compactMap { s in
            guard let t = s["texture"] as? String else { return nil }
            return MHSkin(name: s["name"] as? String ?? t, texture: t, sex: s["sex"] as? String ?? "", ancestry: s["ancestry"] as? String ?? "")
        }
    }

    /// Items never offered: copyrighted characters, political merchandise, anything made for children.
    static func excluded(_ name: String) -> Bool {
        let n = name.lowercased()
        return ["ayanami", "spider gwen", "spider-gwen", "yoko tsuno", "deathnote", "death note", "maga", "child", "pillow man",
                "scifi-armor guardian", "scifi-armor jupiter"]
            .contains { n.contains($0) }
    }

    func hasTarget(_ name: String) -> Bool { targetRanges[name] != nil }

    /// Body with shape targets applied: every base vertex (helpers included), decimeters.
    func body(_ weights: [String: Float]) -> [SIMD3<Float>] {
        var v = basePositions
        for (name, w) in weights where w != 0 {
            guard let r = targetRanges[name] else { continue }
            for k in r.start..<(r.start + r.count) {
                let vi = Int(targetIndex[k])
                guard vi < v.count, k * 3 + 2 < targetDelta.count else { continue }
                v[vi] += w * SIMD3(targetDelta[k * 3], targetDelta[k * 3 + 1], targetDelta[k * 3 + 2])
            }
        }
        return v
    }

    func joint(_ name: String, in v: [SIMD3<Float>]) -> SIMD3<Float> {
        guard let idx = joints[name], !idx.isEmpty else { return .zero }
        var s = SIMD3<Float>(repeating: 0)
        for i in idx where i < v.count { s += v[i] }
        return s / Float(idx.count)
    }

    func url(_ relative: String) -> URL { root.appendingPathComponent(relative) }

    // Textures are shared between characters.
    private var textureCache: [String: NSImage] = [:]
    private var hairCache: [String: CGImage] = [:]
    private let cacheLock = NSLock()

    func image(_ relative: String) -> NSImage? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let cached = textureCache[relative] { return cached }
        guard let img = NSImage(contentsOf: url(relative)) else { return nil }
        textureCache[relative] = img
        return img
    }

    /// Texture with a color baked in (and, for hair, its own color removed first), cached.
    /// Baking keeps the chosen color under every lighting setup (HDR, reflections, bloom).
    private var tintCache: [String: CGImage] = [:]
    func tinted(_ relative: String, r: CGFloat, g: CGFloat, b: CGFloat, neutral: Bool) -> CGImage? {
        let key = relative + String(format: "|%.3f|%.3f|%.3f|%d", r, g, b, neutral ? 1 : 0)
        cacheLock.lock()
        if let cached = tintCache[key] { cacheLock.unlock(); return cached }
        cacheLock.unlock()
        let source: CIImage?
        if neutral { source = neutralHair(relative).map { CIImage(cgImage: $0) } } else { source = CIImage(contentsOf: url(relative)) }
        guard let input = source else { return nil }
        let out = input.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0)])
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        guard let cg = context.createCGImage(out, from: input.extent) else { return nil }
        cacheLock.lock(); tintCache[key] = cg; cacheLock.unlock()
        return cg
    }

    /// Hair texture with its color removed and brightness normalized, alpha kept, so any hair color
    /// can be multiplied in while the strand detail stays.
    func neutralHair(_ relative: String) -> CGImage? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let cached = hairCache[relative] { return cached }
        guard let input = CIImage(contentsOf: url(relative)) else { return nil }
        let gray = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        var level: Float = 0.5
        if let avg = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: gray, kCIInputExtentKey: CIVector(cgRect: gray.extent)])?.outputImage {
            var px = [UInt8](repeating: 0, count: 4)
            context.render(avg, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
            // premultiplied average: divide by alpha to get the strands' own level
            if px[3] > 8 { level = Float(px[0]) / Float(px[3]) }
        }
        // Average strand brightness lifted to ~1.0 so the chosen color reads true on matte hair.
        let gain = CGFloat(min(6, max(0.8, 1.0 / max(level, 0.05))))
        let lifted = gray.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0)])
        guard let cg = context.createCGImage(lifted, from: input.extent) else { return nil }
        hairCache[relative] = cg
        return cg
    }
}

// MARK: - Character assembly

enum MHCharacter {
    struct Shape {
        var female: Float = 0          // 0 male … 1 female (0.5 = androgynous)
        var muscle: Float = 0.5        // 0 … 1, 0.5 average
        var weight: Float = 0.5
        var height: Float = 0.5        // MakeHuman height target, 0.5 average
        var heightMeters: Float = 1.75
    }

    /// Shape targets for an adult. Children and babies are never used.
    static func targets(_ s: Shape, lib: MHLibrary) -> [String: Float] {
        var t: [String: Float] = [:]
        func blend(_ x: Float) -> [(String, Float)] {
            x < 0.5 ? [("min", 1 - x * 2), ("average", x * 2)] : [("average", 2 - x * 2), ("max", x * 2 - 1)]
        }
        for (sex, sw) in [("male", 1 - s.female), ("female", s.female)] where sw > 0 {
            for race in ["african", "asian", "caucasian"] {
                t["macrodetails/\(race)-\(sex)-young", default: 0] += sw / 3
            }
            for (m, wm) in blend(s.muscle) where wm > 0 {
                for (w, ww) in blend(s.weight) where ww > 0 {
                    let key = "\(sex)-young-\(m)muscle-\(w)weight"
                    t["macrodetails/universal-" + key, default: 0] += sw * wm * ww
                    if abs(s.height - 0.5) > 0.001 {
                        let hk = s.height > 0.5 ? "maxheight" : "minheight"
                        t["macrodetails/height/\(key)-\(hk)", default: 0] += sw * wm * ww * abs(s.height - 0.5) * 2
                    }
                }
            }
        }
        return t
    }

    static func shape(for a: PerformerAppearance) -> Shape {
        var s = Shape()
        switch a.bodyStyle ?? "Masculine" {
        case "Feminine": s.female = 1
        case "Androgynous": s.female = 0.5
        default: s.female = 0
        }
        let meters = Float(a.body.map { $0.heightCm / 100 } ?? a.height)
        s.heightMeters = min(2.2, max(1.4, meters))
        // Average adult heights (ANSUR II medians): steer the height target, then scale exactly.
        let average: Float = 1.756 - 0.13 * s.female
        s.height = min(1, max(0, 0.5 + (s.heightMeters - average) / 0.4))
        var build = Float(a.build)
        if let b = a.body, let kg = b.weightKg {
            let bmi = Float(kg) / (s.heightMeters * s.heightMeters)
            build = bmi / 23.8
        }
        s.weight = min(1, max(0, 0.5 + (build - 1) / 0.8))
        s.muscle = 0.5
        return s
    }

    // MARK: wardrobe choice

    static func score(_ item: MHItem, sex: String, want: [String], avoid: [String], mismatch: Int = 6) -> Int {
        var s = 0
        if item.gender == sex { s += 3 } else if item.gender != "any" { s -= mismatch }
        for w in want where item.words.contains(w) { s += 2 }
        for w in avoid where item.words.contains(w) { s -= 5 }
        return s
    }

    static func best(_ lib: MHLibrary, slot: String, sex: String, want: [String], avoid: [String] = [], minimum: Int = Int.min, mismatch: Int = 6) -> MHItem? {
        var top: (MHItem, Int)? = nil
        for item in lib.items where item.slot == slot {
            let s = score(item, sex: sex, want: want, avoid: avoid, mismatch: mismatch)
            if s < minimum { continue }
            if top == nil || s > top!.1 || (s == top!.1 && item.id < top!.0.id) { top = (item, s) }
        }
        return top?.0
    }

    /// Outfit and shoes per Character Studio clothing style, chosen from the contact sheets
    /// (packaging/makehuman/app-review). First name found wins; keyword scoring is the fallback.
    static let outfitByStyle: [String: (male: [String], female: [String])] = [
        "Casual": (["male casualsuit01", "male casualsuit04"], ["female casualsuit01"]),
        "Rock Jacket": (["male casualsuit05"], ["male casualsuit05"]),
        "Punk": (["male casualsuit04"], ["Dress Shift", "female casualsuit02"]),
        "Glam": (["Suit Double Breasted", "male casualsuit03"], ["frill partydress1", "elvs mini halterdress", "Fem Suit2"]),
        "Formal": (["Suit3", "male elegantsuit01"], ["elvs long halterdress1", "Fem Suit Double Breasted"]),
        "Fantasy": (["Monks Robe", "male casualsuit06"], ["elvs goddess dress4", "elvs goddess dress5", "male casualsuit06"]),
        "Base": ([], ["female sportsuit01"])]
    static let shoesByStyle: [String: (male: [String], female: [String])] = [
        "Casual": (["shoes05", "shoes03"], ["shoes05", "shoes03"]),
        "Rock Jacket": (["Boots Ankle Male", "male boots"], ["Boots Ankle"]),
        "Punk": (["Boots Ankle Male", "male boots"], ["Boots Ankle"]),
        "Glam": (["Shoes Oxford male", "tbar", "MJ-Shoes"], ["Booties stiletto", "Flats"]),
        "Formal": (["Shoes Oxford male", "tbar", "MJ-Shoes"], ["Booties stiletto", "Flats"]),
        "Fantasy": (["BootsViking", "male boots"], ["elvs basic elfshoe1", "Flats ballet"])]

    static func named(_ lib: MHLibrary, slot: String, _ names: [String]) -> MHItem? {
        for n in names {
            if let item = lib.items.first(where: { $0.slot == slot && $0.name.lowercased() == n.lowercased() }) { return item }
        }
        return nil
    }

    static func wardrobe(_ a: PerformerAppearance, female: Float, lib: MHLibrary) -> [MHItem] {
        let sex = female >= 0.5 ? "female" : "male"
        let style = outfitByStyle[a.clothingStyle ?? "Casual"] != nil ? (a.clothingStyle ?? "Casual") : "Casual"
        var picks: [MHItem?] = []
        let outfitNames = outfitByStyle[style].map { sex == "female" ? $0.female : $0.male } ?? []
        if style == "Base" {
            // Base layer only: plain shorts (and a sports top for women), barefoot.
            picks.append(named(lib, slot: "outfit", outfitNames) ?? named(lib, slot: "bottom", ["jean shorts", "cargo pants"]))
        } else if let outfit = named(lib, slot: "outfit", outfitNames) {
            picks.append(outfit)
        } else {
            let avoid = ["tucked", "crop", "camisole", "tank", "tube", "bodice", "halter", "keyhole"]
            picks.append(best(lib, slot: "top", sex: sex, want: ["shirt", "tee", "t-shirt", "polo"], avoid: avoid))
            picks.append(best(lib, slot: "bottom", sex: sex, want: ["pants", "jean", "trouser", "cargo"], avoid: ["short", "harem", "jacket"]))
        }
        let shoeNames = shoesByStyle[style].map { sex == "female" ? $0.female : $0.male } ?? []
        if style != "Base" { picks.append(named(lib, slot: "shoes", shoeNames)
            ?? best(lib, slot: "shoes", sex: sex, want: ["shoes0"], avoid: ["hero", "gogo", "overknee", "botas", "leatherboots", "stiletto"])) }
        picks.append(hair(a.hair, sex: sex, lib: lib))
        switch a.accessory ?? "None" {
        case "Glasses": picks.append(best(lib, slot: "glasses", sex: sex, want: ["glasses", "round", "classic"], avoid: ["sun", "goggle", "visor"]))
        case "Wings": picks.append(best(lib, slot: "wings", sex: sex, want: ["wing", "fairy", "butterfly", "angel"]))
        default: break
        }
        picks.append(best(lib, slot: "eyes", sex: sex, want: ["highpoly"]))
        picks.append(named(lib, slot: "eyebrows", ["eyebrow001"]) ?? best(lib, slot: "eyebrows", sex: sex, want: ["eyebrow"]))
        picks.append(named(lib, slot: "eyelashes", ["Eyelashes01"]) ?? best(lib, slot: "eyelashes", sex: sex, want: ["eyelash"]))
        return picks.compactMap { $0 }
    }

    static func hair(_ style: PerformerHair, sex: String, lib: MHLibrary) -> MHItem? {
        let want: [String]
        switch style {
        case .bald: return nil
        case .shaved: want = ["short04", "short", "buzz"]
        case .short: want = ["short", "crop", "buzz"]
        case .long: want = ["long"]
        case .swept: want = sex == "female" ? ["bob01", "bob", "swept"] : ["short messy", "messy", "swept"]
        case .spiked: want = ["shaggy", "spik", "punk", "messy"]
        case .ponytail: want = ["ponytail01", "ponytail", "bun"]
        case .curly: want = ["afro01", "afro", "curl"]
        }
        let avoid: [String] = style == .long || style == .ponytail ? ["short"] : (style == .short || style == .shaved ? ["long"] : [])
        return best(lib, slot: "hair", sex: sex, want: want, avoid: avoid + ["green", "anime", "jungle", "strawberry", "headband"], mismatch: 1)
    }

    // MARK: geometry helpers

    struct Mesh {
        var positions: [SIMD3<Float>]
        var uvs: [Float]
        var triangles: [UInt32]
        var influences: [(bones: SIMD4<UInt32>, weights: SIMD4<Float>)]
    }

    static func normals(_ p: [SIMD3<Float>], _ tris: [UInt32]) -> [SIMD3<Float>] {
        // Smooth across UV seams: accumulate face normals per welded position.
        var key: [SIMD3<Int32>: Int] = [:]
        var slot = [Int](repeating: 0, count: p.count)
        var sums: [SIMD3<Float>] = []
        for (i, v) in p.enumerated() {
            let k = SIMD3<Int32>(Int32((v.x * 20000).rounded()), Int32((v.y * 20000).rounded()), Int32((v.z * 20000).rounded()))
            if let s = key[k] { slot[i] = s } else { key[k] = sums.count; slot[i] = sums.count; sums.append(.zero) }
        }
        var t = 0
        while t + 2 < tris.count {
            let a = Int(tris[t]), b = Int(tris[t + 1]), c = Int(tris[t + 2])
            t += 3
            guard a < p.count, b < p.count, c < p.count else { continue }
            let n = cross(p[b] - p[a], p[c] - p[a])
            sums[slot[a]] += n; sums[slot[b]] += n; sums[slot[c]] += n
        }
        return slot.map { s in
            let n = sums[s]
            let l = length(n)
            return l > 1e-12 ? n / l : SIMD3(0, 1, 0)
        }
    }

    static func geometry(_ m: Mesh) -> SCNGeometry {
        let n = normals(m.positions, m.triangles)
        var flat: [Float] = []; flat.reserveCapacity(m.positions.count * 3)
        var nflat: [Float] = []; nflat.reserveCapacity(m.positions.count * 3)
        for (p, q) in zip(m.positions, n) { flat += [p.x, p.y, p.z]; nflat += [q.x, q.y, q.z] }
        var uv: [Float] = []; uv.reserveCapacity(m.uvs.count)
        var i = 0
        while i + 1 < m.uvs.count { uv += [m.uvs[i], 1 - m.uvs[i + 1]]; i += 2 }
        let count = m.positions.count
        func source(_ a: [Float], _ semantic: SCNGeometrySource.Semantic, _ comps: Int) -> SCNGeometrySource {
            let data = a.withUnsafeBufferPointer { Data(buffer: $0) }
            return SCNGeometrySource(data: data, semantic: semantic, vectorCount: count, usesFloatComponents: true,
                                     componentsPerVector: comps, bytesPerComponent: 4, dataOffset: 0, dataStride: comps * 4)
        }
        let element = SCNGeometryElement(data: m.triangles.withUnsafeBufferPointer { Data(buffer: $0) },
                                         primitiveType: .triangles, primitiveCount: m.triangles.count / 3, bytesPerIndex: 4)
        return SCNGeometry(sources: [source(flat, .vertex, 3), source(nflat, .normal, 3), source(uv, .texcoord, 2)], elements: [element])
    }

    /// Geometry and skin binding of one mesh, independent of materials and bone nodes (cached).
    struct Part {
        let name: String
        let item: MHItem?
        let geometry: SCNGeometry
        let bones: [Int]
        let indices: SCNGeometrySource
        let weights: SCNGeometrySource
    }

    static func part(_ m: Mesh, name: String, item: MHItem?) -> Part {
        let geo = geometry(m)
        var used: [UInt32: UInt16] = [:]
        var order: [Int] = []
        var idx: [UInt16] = []; idx.reserveCapacity(m.influences.count * 4)
        var wts: [Float] = []; wts.reserveCapacity(m.influences.count * 4)
        for inf in m.influences {
            for k in 0..<4 {
                let b = inf.bones[k]
                let w = inf.weights[k]
                var local: UInt16 = 0
                if w > 0 {
                    if let u = used[b] { local = u } else {
                        local = UInt16(order.count); used[b] = local; order.append(Int(b))
                    }
                }
                idx.append(local); wts.append(w)
            }
        }
        if order.isEmpty { order = [0] }
        let count = m.influences.count
        let wSource = SCNGeometrySource(data: wts.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .boneWeights,
                                        vectorCount: count, usesFloatComponents: true, componentsPerVector: 4,
                                        bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        let iSource = SCNGeometrySource(data: idx.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .boneIndices,
                                        vectorCount: count, usesFloatComponents: false, componentsPerVector: 4,
                                        bytesPerComponent: 2, dataOffset: 0, dataStride: 8)
        return Part(name: name, item: item, geometry: geo, bones: order, indices: iSource, weights: wSource)
    }

    /// Skinned node bound to the shared skeleton; only the bones this mesh uses are passed.
    static func skinned(_ p: Part, material: SCNMaterial, boneNodes: [SCNNode], inverseBind: [NSValue], skeleton: SCNNode) -> SCNNode {
        // Shallow copy: shares vertex data with the cache, owns its materials.
        let geo = (p.geometry.copy() as? SCNGeometry) ?? p.geometry
        geo.materials = [material]
        let node = SCNNode(geometry: geo)
        node.name = p.name
        let skinner = SCNSkinner(baseGeometry: geo, bones: p.bones.map { boneNodes[$0] },
                                 boneInverseBindTransforms: p.bones.map { inverseBind[$0] },
                                 boneWeights: p.weights, boneIndices: p.indices)
        skinner.skeleton = skeleton
        node.skinner = skinner
        return node
    }

    /// Everything that depends on body shape, clothing and hair; colors and pose are applied per node.
    final class Prepared {
        let parts: [Part]
        let heads: [SIMD3<Float>]
        let tails: [SIMD3<Float>]
        let female: Float
        var neck: (center: SIMD3<Float>, radius: Float) = (.zero, 0.055)
        init(parts: [Part], heads: [SIMD3<Float>], tails: [SIMD3<Float>], female: Float) {
            self.parts = parts; self.heads = heads; self.tails = tails; self.female = female
        }
    }
    private static var cache: [String: Prepared] = [:]
    private static var cacheOrder: [String] = []
    private static let cacheLock = NSLock()

    static func cacheKey(_ a: PerformerAppearance) -> String {
        let body = a.body.map { "\($0.heightCm)/\($0.weightKg ?? 0)" } ?? "-"
        return [a.bodyStyle ?? "", String(format: "%.3f", a.height), String(format: "%.3f", a.build), body,
                a.clothingStyle ?? "", a.hair.rawValue, a.accessory ?? "", overrideItems.joined(separator: ",")].joined(separator: "|")
    }

    // MARK: materials

    static let skinTones: [(ancestry: String, tint: CGFloat)] = [
        ("caucasian", 1.0), ("caucasian", 0.9), ("asian", 1.0), ("asian", 0.84), ("african", 1.0), ("african", 0.78)]
    static let outfitColors: [NSColor] = [
        NSColor(white: 0.16, alpha: 1), NSColor(calibratedRed: 0.86, green: 0.16, blue: 0.16, alpha: 1),
        NSColor(calibratedRed: 0.2, green: 0.34, blue: 0.86, alpha: 1), NSColor(white: 0.96, alpha: 1),
        NSColor(calibratedRed: 0.56, green: 0.26, blue: 0.84, alpha: 1), NSColor(calibratedRed: 0.2, green: 0.7, blue: 0.3, alpha: 1)]
    static let hairColors: [NSColor] = [
        NSColor(calibratedRed: 0.06, green: 0.05, blue: 0.045, alpha: 1), NSColor(calibratedRed: 0.28, green: 0.15, blue: 0.08, alpha: 1),
        NSColor(calibratedRed: 0.78, green: 0.6, blue: 0.32, alpha: 1), NSColor(calibratedRed: 0.55, green: 0.16, blue: 0.06, alpha: 1),
        NSColor(calibratedRed: 0.12, green: 0.2, blue: 0.62, alpha: 1), NSColor(calibratedRed: 0.72, green: 0.72, blue: 0.74, alpha: 1)]

    static func skinMaterial(_ a: PerformerAppearance, female: Float, lib: MHLibrary) -> SCNMaterial {
        let m = SCNMaterial()
        m.name = "mh_skin"
        m.lightingModel = .physicallyBased
        m.roughness.contents = 0.62
        m.metalness.contents = 0.0
        let tone = skinTones[min(max(a.skin, 0), skinTones.count - 1)]
        let sex = female >= 0.5 ? "female" : "male"
        let skin = lib.skins.first(where: { $0.sex == sex && $0.ancestry == tone.ancestry })
            ?? lib.skins.first(where: { $0.ancestry == tone.ancestry }) ?? lib.skins.first
        // Slightly below full albedo: skin textures are bright and read white under the studio reflections.
        let level = tone.tint * 0.86
        if let s = skin, let img = lib.tinted(s.texture, r: level, g: level, b: level, neutral: false) {
            m.diffuse.contents = img
        } else {
            m.diffuse.contents = NSColor(calibratedRed: 0.8, green: 0.62, blue: 0.5, alpha: 1)
        }
        return m
    }

    static func itemMaterial(_ item: MHItem, _ a: PerformerAppearance, lib: MHLibrary) -> SCNMaterial {
        let m = SCNMaterial()
        m.name = "mh_" + item.slot
        m.lightingModel = .physicallyBased
        m.metalness.contents = 0.0
        let hairLike = item.slot == "hair" || item.slot == "eyebrows" || item.slot == "eyelashes"
        m.roughness.contents = item.slot == "eyes" ? 0.15 : (hairLike ? 0.7 : 0.82)
        if item.slot == "hair", let d = item.diffuse {
            let c = (hairColors[min(max(a.hairColor, 0), hairColors.count - 1)].usingColorSpace(.deviceRGB)) ?? NSColor.black
            if let img = lib.tinted(d, r: c.redComponent, g: c.greenComponent, b: c.blueComponent, neutral: true) {
                m.diffuse.contents = img
            }
        } else if item.slot == "top", let d = item.diffuse {
            // Outfit color: tint the garment's own (usually light) fabric.
            let c = (outfitColors[min(max(a.outfit, 0), outfitColors.count - 1)].usingColorSpace(.deviceRGB)) ?? NSColor.gray
            m.diffuse.contents = lib.tinted(d, r: c.redComponent, g: c.greenComponent, b: c.blueComponent, neutral: false) ?? lib.image(d)
        } else if let d = item.diffuse, let img = lib.image(d) {
            m.diffuse.contents = img
        } else {
            m.diffuse.contents = NSColor(white: 0.5, alpha: 1)
        }
        if let n = item.normal, let img = lib.image(n) {
            m.normal.contents = img
            m.normal.intensity = 0.6
        }
        if hairLike {
            // Matte: hair cards seen edge-on catch bright reflections that the hair color can't tint.
            m.lightingModel = .lambert
        }
        if hairLike || item.transparent {
            m.isDoubleSided = true
            m.transparencyMode = .aOne
            m.blendMode = .alpha
            m.writesToDepthBuffer = true
            m.shaderModifiers = [.fragment: "if (_output.color.a < 0.42) { discard_fragment(); }"]
        }
        return m
    }

    // MARK: build

    /// Items forced by id (tests and contact sheets); they replace the chosen item in the same slot.
    static var overrideItems: [String] = []
    static var debugLog = false
    static var unlit = false

    static func build(_ a: PerformerAppearance) -> SCNNode? {
        guard let lib = MHLibrary.shared else { return nil }
        let key = cacheKey(a)
        cacheLock.lock()
        var prepared = cache[key]
        cacheLock.unlock()
        if prepared == nil {
            prepared = prepare(a, lib: lib)
            if let made = prepared {
                cacheLock.lock()
                cache[key] = made
                cacheOrder.removeAll { $0 == key }
                cacheOrder.append(key)
                while cacheOrder.count > 16 { cache.removeValue(forKey: cacheOrder.removeFirst()) }
                cacheLock.unlock()
            }
        }
        guard let p = prepared else { return nil }
        return assemble(p, a, lib: lib)
    }

    static func prepare(_ a: PerformerAppearance, lib: MHLibrary) -> Prepared? {
        let shape = shape(for: a)
        let body = lib.body(targets(shape, lib: lib))

        // Exact height: measure the visible body (sole to crown) and scale uniformly to meters.
        var lo: Float = .greatestFiniteMagnitude, hi: Float = -.greatestFiniteMagnitude
        for vi in lib.unweld { lo = min(lo, body[vi].y); hi = max(hi, body[vi].y) }
        guard hi > lo else { return nil }
        let k = shape.heightMeters / (hi - lo)

        // Joints and skin weights in meters.
        let heads = lib.bones.map { lib.joint($0.head, in: body) * k }
        let tails = lib.bones.map { lib.joint($0.tail, in: body) * k }
        func influence(_ vi: Int) -> (bones: SIMD4<UInt32>, weights: SIMD4<Float>) {
            let o = vi * 4
            return (SIMD4(lib.boneIndex[o], lib.boneIndex[o + 1], lib.boneIndex[o + 2], lib.boneIndex[o + 3]),
                    SIMD4(lib.boneWeight[o], lib.boneWeight[o + 1], lib.boneWeight[o + 2], lib.boneWeight[o + 3]))
        }

        // Garments, hair, eyes … fitted to this body.
        var deleted = Set<Int>()
        var fitted: [(MHItem, Mesh)] = []
        var chosen = wardrobe(a, female: shape.female, lib: lib)
        for id in overrideItems {
            guard let forced = lib.items.first(where: { $0.id == id }) else { continue }
            let covers: Set<String> = forced.slot == "outfit" ? ["outfit", "top", "bottom"] : (forced.slot == "top" || forced.slot == "bottom" ? [forced.slot, "outfit"] : [forced.slot])
            chosen.removeAll { covers.contains($0.slot) }
            chosen.append(forced)
        }
        for item in chosen {
            guard let bin = MHBin(url: lib.url(item.file)) else { continue }
            let pos = bin.floats("positions"), uv = bin.floats("uvs"), tris = bin.uints("triangles")
            let bi = bin.uints("bindIndex"), bw = bin.floats("bindWeight"), off = bin.floats("bindOffset")
            let n = pos.count / 3
            guard n > 0, bi.count == n * 3, bw.count == n * 3, off.count == n * 3, uv.count == n * 2 else { continue }
            var scale = SIMD3<Float>(1, 1, 1)
            if let scales = bin.header["scales"] as? [[Any]] {
                for (axis, s) in scales.prefix(3).enumerated() {
                    guard s.count == 3, let i1 = (s[0] as? NSNumber)?.intValue, let i2 = (s[1] as? NSNumber)?.intValue,
                          let ref = (s[2] as? NSNumber)?.floatValue, ref > 0, i1 < body.count, i2 < body.count else { continue }
                    scale[axis] = abs(body[i1][axis] - body[i2][axis]) / ref
                }
            }
            var mesh = Mesh(positions: [], uvs: uv, triangles: tris, influences: [])
            mesh.positions.reserveCapacity(n); mesh.influences.reserveCapacity(n)
            for v in 0..<n {
                var p = SIMD3<Float>(repeating: 0)
                var gBones = [UInt32](repeating: 0, count: 12), gW = [Float](repeating: 0, count: 12), gN = 0
                for j in 0..<3 {
                    let vi = Int(bi[v * 3 + j]); let w = bw[v * 3 + j]
                    guard vi < body.count, w != 0 else { continue }
                    p += w * body[vi]
                    let inf = influence(vi)
                    for q in 0..<4 where inf.weights[q] > 0 {
                        let bone = inf.bones[q], add = inf.weights[q] * abs(w)
                        var found = false
                        for g in 0..<gN where gBones[g] == bone { gW[g] += add; found = true; break }
                        if !found { gBones[gN] = bone; gW[gN] = add; gN += 1 }
                    }
                }
                p += SIMD3(off[v * 3], off[v * 3 + 1], off[v * 3 + 2]) * scale
                mesh.positions.append(p * k)
                let top = (0..<gN).sorted { gW[$0] > gW[$1] }.prefix(4)
                let total = top.reduce(Float(0)) { $0 + gW[$1] }
                var bones = SIMD4<UInt32>(0, 0, 0, 0), weights = SIMD4<Float>(0, 0, 0, 0)
                for (q, g) in top.enumerated() { bones[q] = gBones[g]; weights[q] = total > 0 ? gW[g] / total : 0 }
                if total == 0 { weights[0] = 1 }
                mesh.influences.append((bones, weights))
            }
            // Hide skin only where this garment really covers it. MakeHuman's lists are written for its default
            // proportions and can reach past a garment's edge (e.g. above a shoe), which leaves a see-through gap.
            let removes = bin.uints("deleteVerts")
            let cell: Float = 0.015
            var occupied = Set<SIMD3<Int32>>()
            occupied.reserveCapacity(mesh.positions.count)
            for q in mesh.positions {
                occupied.insert(SIMD3<Int32>(Int32((q.x / cell).rounded(.down)), Int32((q.y / cell).rounded(.down)), Int32((q.z / cell).rounded(.down))))
            }
            // Shoes: hide the foot below the shoe's top edge (the foot inside can sit far from a heel's surface),
            // keep the skin above it. Other garments: hide only skin the garment lies over.
            var rim: Float = -.greatestFiniteMagnitude
            if item.slot == "shoes" { for q in mesh.positions { rim = max(rim, q.y) } }
            for d in removes {
                let vi = Int(d)
                guard vi < body.count else { continue }
                let q = body[vi] * k
                if item.slot == "shoes" {
                    if q.y < rim - 0.008 { deleted.insert(vi) }
                    continue
                }
                let c = SIMD3<Int32>(Int32((q.x / cell).rounded(.down)), Int32((q.y / cell).rounded(.down)), Int32((q.z / cell).rounded(.down)))
                var covered = false
                search: for dx in Int32(-1)...1 { for dy in Int32(-1)...1 { for dz in Int32(-1)...1 {
                    if occupied.contains(c &+ SIMD3(dx, dy, dz)) { covered = true; break search }
                } } }
                if covered { deleted.insert(vi) }
            }
            if debugLog { print("MH_ITEM", item.slot, item.name, "vertices", n, "hides", removes.count) }
            fitted.append((item, mesh))
        }

        // Visible body, minus the skin hidden under garments.
        var bodyMesh = Mesh(positions: lib.unweld.map { body[$0] * k }, uvs: lib.uvs, triangles: [], influences: lib.unweld.map { influence($0) })
        bodyMesh.triangles.reserveCapacity(lib.triangles.count)
        var t = 0
        while t + 2 < lib.triangles.count {
            let a0 = Int(lib.triangles[t]), a1 = Int(lib.triangles[t + 1]), a2 = Int(lib.triangles[t + 2])
            t += 3
            if deleted.contains(lib.unweld[a0]) || deleted.contains(lib.unweld[a1]) || deleted.contains(lib.unweld[a2]) { continue }
            bodyMesh.triangles += [UInt32(a0), UInt32(a1), UInt32(a2)]
        }

        if debugLog { print("MH_BODY triangles kept", bodyMesh.triangles.count / 3, "of", lib.triangles.count / 3, "height m", shape.heightMeters) }
        // Ground the character: lowest point of body and shoes at y = 0, centered on x/z.
        var floor = Float.greatestFiniteMagnitude
        for p in bodyMesh.positions { floor = min(floor, p.y) }
        for (item, mesh) in fitted where item.slot == "shoes" { for p in mesh.positions { floor = min(floor, p.y) } }
        let pelvis = heads.first ?? .zero
        let shift = SIMD3<Float>(-pelvis.x, -floor, -pelvis.z)
        bodyMesh.positions = bodyMesh.positions.map { $0 + shift }
        for i in fitted.indices { fitted[i].1.positions = fitted[i].1.positions.map { $0 + shift } }
        let boneHeads = heads.map { $0 + shift }
        let boneTails = tails.map { $0 + shift }

        // Under a top hat, hair above the brim would push through the crown: remove it, as a real hat flattens it.
        var scalpTop: Float = -.greatestFiniteMagnitude
        for p in bodyMesh.positions { scalpTop = max(scalpTop, p.y) }
        if a.accessory == "Top Hat" {
            let brim = scalpTop - 0.035 * shape.heightMeters / 1.75
            for i in fitted.indices where fitted[i].0.slot == "hair" {
                let m = fitted[i].1
                var kept: [UInt32] = []; kept.reserveCapacity(m.triangles.count)
                var t = 0
                while t + 2 < m.triangles.count {
                    let a0 = Int(m.triangles[t]), a1 = Int(m.triangles[t + 1]), a2 = Int(m.triangles[t + 2])
                    t += 3
                    guard a0 < m.positions.count, a1 < m.positions.count, a2 < m.positions.count else { continue }
                    let cy = (m.positions[a0].y + m.positions[a1].y + m.positions[a2].y) / 3
                    if cy > brim { continue }
                    kept += [UInt32(a0), UInt32(a1), UInt32(a2)]
                }
                fitted[i].1.triangles = kept
            }
        }
        var parts = [part(bodyMesh, name: "mh_body", item: nil)]
        for (item, mesh) in fitted { parts.append(part(mesh, name: "mh_" + item.slot, item: item)) }
        let prepared = Prepared(parts: parts, heads: boneHeads, tails: boneTails, female: shape.female)
        // Neck ring for a choker: a third of the way from the neck base to the head joint.
        var bi: [String: Int] = [:]
        for (i, b) in lib.bones.enumerated() { bi[b.name] = i }
        if let n = bi["neck01"], let h = bi["head"] {
            let center = boneHeads[n] + (boneHeads[h] - boneHeads[n]) * 0.35
            var sum: Float = 0, count: Float = 0
            for p in bodyMesh.positions where abs(p.y - center.y) < 0.008 && abs(p.x - center.x) < 0.09 && abs(p.z - center.z) < 0.09 {
                sum += length(SIMD2(p.x - center.x, p.z - center.z)); count += 1
            }
            prepared.neck = (center, count > 0 ? sum / count : 0.055)
        }
        return prepared
    }

    static func assemble(_ p: Prepared, _ a: PerformerAppearance, lib: MHLibrary) -> SCNNode {
        let boneHeads = p.heads, boneTails = p.tails
        // Skeleton: identity orientations, each bone at its head, so a rotation turns a limb about its joint.
        let rigRoot = SCNNode()
        rigRoot.name = "character_body_for_framing"
        let armature = SCNNode()
        armature.name = "mh_armature"
        rigRoot.addChildNode(armature)
        var boneNodes: [SCNNode] = []
        var inverseBind: [NSValue] = []
        for (i, bone) in lib.bones.enumerated() {
            let node = SCNNode()
            node.name = bone.name
            let parentHead = bone.parent.map { boneHeads[$0] } ?? .zero
            node.simdPosition = boneHeads[i] - parentHead
            if let par = bone.parent { boneNodes[par].addChildNode(node) } else { armature.addChildNode(node) }
            boneNodes.append(node)
            let h = boneHeads[i]
            inverseBind.append(NSValue(scnMatrix4: SCNMatrix4MakeTranslation(CGFloat(-h.x), CGFloat(-h.y), CGFloat(-h.z))))
        }
        for part in p.parts {
            let material = part.item.map { itemMaterial($0, a, lib: lib) } ?? skinMaterial(a, female: p.female, lib: lib)
            let node = skinned(part, material: material, boneNodes: boneNodes, inverseBind: inverseBind, skeleton: armature)
            if let slot = part.item?.slot, slot == "hair" || slot == "eyebrows" || slot == "eyelashes" { node.renderingOrder = 10 }
            if unlit { node.geometry?.materials.forEach { $0.lightingModel = .constant } }
            rigRoot.addChildNode(node)
        }

        var index: [String: Int] = [:]
        for (i, b) in lib.bones.enumerated() { index[b.name] = i }
        if a.accessory == "Choker", let n = index["neck01"] {
            let ring = SCNTorus(ringRadius: CGFloat(p.neck.radius + 0.006), pipeRadius: 0.0065)
            let m = SCNMaterial(); m.lightingModel = .physicallyBased
            m.diffuse.contents = NSColor(white: 0.03, alpha: 1); m.roughness.contents = 0.35; m.metalness.contents = 0.2
            ring.materials = [m]
            let node = SCNNode(geometry: ring)
            node.name = "mh_choker"
            node.simdPosition = p.neck.center - boneHeads[n]     // bone frame = world frame before posing
            node.eulerAngles.x = -0.12                            // follows the neck's slight forward lean
            boneNodes[n].addChildNode(node)
        }
        MHPose.apply(a.pose ?? "Natural", bones: boneNodes, index: index, heads: boneHeads, tails: boneTails)
        MHPose.idle(bones: boneNodes, index: index, seed: a.hashValue)

        let root = SCNNode()
        root.addChildNode(rigRoot)
        return root
    }
}

// MARK: - Poses

enum MHPose {
    /// Aim a limb segment chain: rotate `bone` so the direction from its head to `endBone`'s head
    /// points along `direction` (world space), accounting for rotations already set on ancestors.
    static func aim(_ bone: String, to endBone: String, direction: SIMD3<Float>, bones: [SCNNode], index: [String: Int],
                    heads: [SIMD3<Float>]) {
        guard let b = index[bone], let e = index[endBone] else { return }
        let rest = heads[e] - heads[b]
        guard length(rest) > 1e-5, length(direction) > 1e-5 else { return }
        let node = bones[b]
        let parentWorld = node.parent.map { simd_quatf($0.simdWorldTransform) } ?? simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        let current = parentWorld.act(normalize(rest))
        let turn = simd_quatf(from: current, to: normalize(direction))
        let world = turn * parentWorld
        node.simdOrientation = parentWorld.inverse * world
    }

    /// Turn a bone about its own current direction (forearm twist), keeping its aim.
    static func twist(_ bone: String, toward endBone: String, degrees: Float, bones: [SCNNode], index: [String: Int], heads: [SIMD3<Float>]) {
        guard let b = index[bone], let e = index[endBone], degrees != 0 else { return }
        let node = bones[b]
        let parentWorld = node.parent.map { simd_quatf($0.simdWorldTransform) } ?? simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        let current = parentWorld * node.simdOrientation
        let axis = normalize(current.act(heads[e] - heads[b]))
        let world = simd_quatf(angle: degrees * .pi / 180, axis: axis) * current
        node.simdOrientation = parentWorld.inverse * world
    }

    /// Relaxed hand: bend each finger joint about the knuckle line (index to pinky); thumb less.
    static func curlFingers(side: String, degrees: Float, bones: [SCNNode], index: [String: Int]) {
        guard degrees != 0, let i2 = index["finger2-1.\(side)"], let i5 = index["finger5-1.\(side)"] else { return }
        let across = bones[i2].simdWorldPosition - bones[i5].simdWorldPosition
        guard length(across) > 1e-5 else { return }
        let axis = normalize(across)
        for f in 1...5 {
            for j in 1...3 {
                guard let b = index["finger\(f)-\(j).\(side)"] else { continue }
                let node = bones[b]
                let parentWorld = node.parent.map { simd_quatf($0.simdWorldTransform) } ?? simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
                let current = parentWorld * node.simdOrientation
                let amount = degrees * (f == 1 ? 0.35 : (j == 1 ? 0.7 : 1.0))
                let world = simd_quatf(angle: amount * .pi / 180, axis: axis) * current
                node.simdOrientation = parentWorld.inverse * world
            }
        }
    }

    static var palmTwist: Float = 60
    static var fingerCurl: Float = -20

    static func apply(_ pose: String, bones: [SCNNode], index: [String: Int], heads: [SIMD3<Float>], tails: [SIMD3<Float>]) {
        // Arms down from MakeHuman's rest pose (arms angled out, forearms forward), elbows softly bent.
        var upper = SIMD3<Float>(0.16, -1, -0.02)
        var fore = SIMD3<Float>(0.07, -1, 0.2)
        var spread: Float = 0.0
        switch pose {
        case "Wide": spread = 0.12; upper = SIMD3(0.22, -1, 0); fore = SIMD3(0.12, -1, 0.18)
        case "Performance": spread = 0.06; upper = SIMD3(0.2, -1, 0.06); fore = SIMD3(0.1, -0.9, 0.35)
        default: break
        }
        for (side, sx) in [("L", Float(1)), ("R", Float(-1))] {
            let u = SIMD3(upper.x * sx, upper.y, upper.z)
            let f = SIMD3(fore.x * sx, fore.y, fore.z)
            aim("upperarm01.\(side)", to: "lowerarm01.\(side)", direction: u, bones: bones, index: index, heads: heads)
            aim("lowerarm01.\(side)", to: "wrist.\(side)", direction: f, bones: bones, index: index, heads: heads)
            // Palms toward the thighs: split the turn over the two forearm bones to avoid a wrist pinch.
            twist("lowerarm01.\(side)", toward: "lowerarm02.\(side)", degrees: palmTwist * sx * 0.4, bones: bones, index: index, heads: heads)
            twist("lowerarm02.\(side)", toward: "wrist.\(side)", degrees: palmTwist * sx * 0.6, bones: bones, index: index, heads: heads)
            curlFingers(side: side, degrees: fingerCurl * sx, bones: bones, index: index)
            if spread > 0 {
                aim("upperleg01.\(side)", to: "lowerleg01.\(side)", direction: SIMD3(spread * sx, -1, 0.02),
                    bones: bones, index: index, heads: heads)
                aim("lowerleg01.\(side)", to: "foot.\(side)", direction: SIMD3(spread * 0.5 * sx, -1, -0.02),
                    bones: bones, index: index, heads: heads)
            }
        }
    }

    /// Subtle breathing and head drift so performers never stand frozen.
    static func idle(bones: [SCNNode], index: [String: Int], seed: Int) {
        let phase = Double(abs(seed % 1000)) / 1000
        func sway(_ name: String, x: CGFloat, y: CGFloat, z: CGFloat, period: Double) {
            guard let i = index[name] else { return }
            let half = period / 2
            let out = SCNAction.rotateBy(x: x, y: y, z: z, duration: half); out.timingMode = .easeInEaseOut
            let back = SCNAction.rotateBy(x: -x, y: -y, z: -z, duration: half); back.timingMode = .easeInEaseOut
            let loop = SCNAction.repeatForever(.sequence([out, back]))
            bones[i].runAction(.sequence([.wait(duration: phase * period), loop]))
        }
        sway("spine03", x: -0.018, y: 0, z: 0, period: 4.2)
        sway("spine01", x: 0.01, y: 0, z: 0, period: 4.2)
        sway("head", x: 0.012, y: 0.05, z: 0, period: 7.5)
    }
}

// MARK: - Contact sheet (CI): every item of one slot on one body, front views

enum MHSheetCLI {
    static func run(out: String, args: [String]) -> Bool {
        guard let lib = MHLibrary.shared else { return false }
        let slot = args.first(where: { $0.hasPrefix("Slot=") }).map { String($0.dropFirst(5)) } ?? "outfit"
        let a = MHRenderCLI.appearance(args)
        let items = lib.items.filter { $0.slot == slot }
        let cell = CGSize(width: 300, height: 450)
        let cols = 6
        let rows = (items.count + cols - 1) / cols
        guard rows > 0 else { return false }
        let sheet = NSImage(size: NSSize(width: cell.width * CGFloat(cols), height: cell.height * CGFloat(rows)))
        var images: [(NSImage, String)] = []
        for item in items {
            MHCharacter.overrideItems = [item.id]
            guard let character = MHCharacter.build(a) else { continue }
            images.append((MHRenderCLI.snapshot(character, height: CGFloat(a.height), angle: 0, size: cell), item.name))
        }
        MHCharacter.overrideItems = []
        sheet.lockFocus()
        NSColor(white: 0.42, alpha: 1).setFill(); NSRect(origin: .zero, size: sheet.size).fill()
        for (i, (img, name)) in images.enumerated() {
            let x = CGFloat(i % cols) * cell.width, y = sheet.size.height - CGFloat(i / cols + 1) * cell.height
            img.draw(in: NSRect(x: x, y: y, width: cell.width, height: cell.height))
            (name as NSString).draw(at: NSPoint(x: x + 6, y: y + 6), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white])
        }
        sheet.unlockFocus()
        guard let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: out))) != nil
    }
}

// MARK: - Test render (CI): `DMXStudio --character-render out.png Body=Feminine Hair=Long …`

enum MHRenderCLI {
    static var studio = false
    static var face = false
    static var feet = false
    static func appearance(_ args: [String]) -> PerformerAppearance {
        var a = PerformerAppearance()
        a.pose = "Natural"
        for arg in args {
            let kv = arg.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            let v = kv[1]
            switch kv[0] {
            case "Body": a.bodyStyle = v
            case "Skin": a.skin = Int(v) ?? a.skin
            case "Hair": a.hair = PerformerHair(rawValue: v) ?? a.hair
            case "HairColor": a.hairColor = Int(v) ?? a.hairColor
            case "Clothing": a.clothingStyle = v
            case "Outfit": a.outfit = Int(v) ?? a.outfit
            case "Height": a.height = Double(v) ?? a.height
            case "Build": a.build = Double(v) ?? a.build
            case "Pose": a.pose = v
            case "Accessory": a.accessory = v
            case "Twist": MHPose.palmTwist = Float(v) ?? 0
            case "Curl": MHPose.fingerCurl = Float(v) ?? -20
            case "Lighting": MHCharacter.unlit = v == "unlit"; MHRenderCLI.studio = v == "studio"
            case "Face": MHRenderCLI.face = v == "1"
            case "Feet": MHRenderCLI.feet = v == "1"
            default: break
            }
        }
        return a
    }

    /// Front, side and back views of one character in a single PNG. Prints the chosen wardrobe.
    static func run(out: String, args: [String]) -> Bool {
        guard let lib = MHLibrary.shared else { print("MH_RENDER no character library"); return false }
        let a = appearance(args)
        let shape = MHCharacter.shape(for: a)
        let picks = MHCharacter.wardrobe(a, female: shape.female, lib: lib).map { "\($0.slot)=\($0.name)" }
        print("MH_RENDER", args.joined(separator: " "), "->", picks.joined(separator: ", "))
        MHCharacter.debugLog = true
        MHCharacter.overrideItems = args.first(where: { $0.hasPrefix("Items=") }).map { $0.dropFirst(6).split(separator: ",").map(String.init) } ?? []
        let started = Date()
        guard let character = MHCharacter.build(a) else { print("MH_RENDER build failed"); return false }
        print("MH_TIME build seconds", String(format: "%.3f", Date().timeIntervalSince(started)))
        var recolor = a; recolor.skin = (a.skin + 1) % 6; recolor.outfit = (a.outfit + 1) % 6
        let again = Date()
        _ = MHCharacter.build(recolor)
        print("MH_TIME rebuild after color change seconds", String(format: "%.3f", Date().timeIntervalSince(again)))
        var taller = a; taller.height = a.height + 0.03
        let reshape = Date()
        _ = MHCharacter.build(taller)
        print("MH_TIME rebuild after height change seconds", String(format: "%.3f", Date().timeIntervalSince(reshape)))
        MHCharacter.overrideItems = []
        Build.addTopHat(root: character, body: character.childNode(withName: "mh_body", recursively: true) ?? character, a)
        let size = CGSize(width: 600, height: 900)
        let images = [0.0, 90.0, 180.0].map { snapshot(character, height: CGFloat(a.height), angle: $0, size: size) }
        let sheet = NSImage(size: NSSize(width: size.width * 3, height: size.height))
        sheet.lockFocus()
        for (i, img) in images.enumerated() { img.draw(in: NSRect(x: CGFloat(i) * size.width, y: 0, width: size.width, height: size.height)) }
        sheet.unlockFocus()
        guard let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return false }
        do { try png.write(to: URL(fileURLWithPath: out)) } catch { return false }
        print("MH_RENDER wrote", out)
        return true
    }

    static func snapshot(_ character: SCNNode, height: CGFloat, angle: Double, size: CGSize) -> NSImage {
        let scene = SCNScene()
        scene.background.contents = NSColor(white: studio ? 0.12 : 0.42, alpha: 1)
        scene.rootNode.addChildNode(character)
        let camera = SCNNode(); camera.camera = SCNCamera()
        if studio {
            // Same lights as Character Studio's preview (StageView / Stage3D CharacterPreview).
            camera.camera?.wantsHDR = true
            camera.camera?.wantsExposureAdaptation = false
            camera.camera?.screenSpaceAmbientOcclusionIntensity = 0.55
            camera.camera?.screenSpaceAmbientOcclusionRadius = 0.12
            scene.lightingEnvironment.contents = Stage3DView.Coordinator.studioEnvironment
            scene.lightingEnvironment.intensity = 0.12
            let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient; ambient.light?.intensity = 45
            scene.rootNode.addChildNode(ambient)
            for (x, y, z, i) in [(CGFloat(2), CGFloat(3), CGFloat(4), CGFloat(165)), (-3, 2, 2, 70), (1, 3, -3, 95)] {
                let l = SCNNode(); l.light = SCNLight(); l.light?.type = x == 2 ? .spot : .omni; l.light?.intensity = i
                if x == 2 { l.light?.spotInnerAngle = 30; l.light?.spotOuterAngle = 65 }
                l.position = SCNVector3(x, y, z); scene.rootNode.addChildNode(l)
                if x == 2 { l.look(at: SCNVector3(0, 0.9, 0)) }
            }
        } else {
            let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient; ambient.light?.intensity = 120
            scene.rootNode.addChildNode(ambient)
            for (x, y, z, i) in [(CGFloat(2), CGFloat(3), CGFloat(4), CGFloat(420)), (-3, 2, 2, 180), (1, 3, -3, 200)] {
                let l = SCNNode(); l.light = SCNLight(); l.light?.type = .omni; l.light?.intensity = i
                l.position = SCNVector3(x, y, z); scene.rootNode.addChildNode(l)
            }
        }
        let h = max(height, 1.4) * 1.08
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = Double(face ? h * 0.09 : (feet ? h * 0.1 : h * 0.55))
        camera.camera?.zNear = 0.01; camera.camera?.zFar = 50
        scene.rootNode.addChildNode(camera)
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        let r = angle * Double.pi / 180
        let target: CGFloat = face ? max(height, 1.4) * 0.93 : (feet ? 0.1 : h * 0.5)
        camera.position = SCNVector3(CGFloat(sin(r)) * 6, target, CGFloat(cos(r)) * 6)
        camera.look(at: SCNVector3(0, target, 0))
        let image = renderer.snapshot(atTime: 1, with: size, antialiasingMode: .multisampling4X)
        character.removeFromParentNode()
        return image
    }
}
