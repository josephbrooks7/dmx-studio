import Foundation
import AppKit
import SceneKit
import simd

/// Headwear fitting (docs/hat-fitting-reference.pdf, "DMX Studio Headwear fitting engine"):
/// fit the actual head at the wearing line, keep the hat's real dimensions, attach to the head bone.
/// Units: meters internally, millimeters in reports. Head-local frame: Y up, +Z face forward.
struct HeadFit {
    /// Center of the wearing ring (on the wearing plane), in the character's bind-pose space.
    var center: SIMD3<Float>
    /// Wearing-plane pitch in radians: positive raises the front (mid-forehead) and lowers the back.
    var pitch: Float
    /// Scalp ring at the wearing plane: radius per direction, 72 directions starting at the face (+Z),
    /// turning toward the character's left (+X).
    var radii: [Float]
    var circumference: Float
    var width: Float
    var length: Float
    var warning: String?
    /// Compressed hair between scalp and band (meters): the hat sits on the hair, not on bare scalp.
    var hairLayer: Float = 0
    /// Height of the skull's top above the wearing plane (meters).
    var crownTop: Float = 0.1

    static let directions = 72
    func angle(_ i: Int) -> Float { Float(i) / Float(HeadFit.directions) * 2 * .pi }
    /// Ring point offset in the plane (x, z) for direction i, scaled by `grow` meters outward.
    func point(_ i: Int, grow: Float = 0) -> SIMD2<Float> {
        let a = angle(i), r = radii[i % HeadFit.directions] + grow
        return SIMD2(sin(a) * r, cos(a) * r)
    }
    func radius(atAngle a: Float) -> Float {
        let n = Float(HeadFit.directions)
        var t = a / (2 * .pi) * n
        t = t.truncatingRemainder(dividingBy: n); if t < 0 { t += n }
        let i = Int(t), f = t - Float(i)
        return radii[i % HeadFit.directions] * (1 - f) + radii[(i + 1) % HeadFit.directions] * f
    }
    var usSize: String {
        let eighths = Int((circumference * 1000 / (25.4 * .pi) * 8).rounded())
        let whole = eighths / 8, rest = eighths % 8
        let names = ["", "1/8", "1/4", "3/8", "1/2", "5/8", "3/4", "7/8"]
        return rest == 0 ? "\(whole)" : "\(whole) \(names[rest])"
    }
}

/// A firm top hat's real dimensions (retail references in the fitting spec: classic 124–133 mm crown,
/// ~60 mm brim front/back, ~67 mm at the sides). Never scaled by the wearer's height.
struct TopHatStyle {
    var crownHeight: Float = 0.128
    var brimFrontBack: Float = 0.060
    var brimSides: Float = 0.067
    var shell: Float = 0.003
    /// Interior ring = scalp ring + this much circumference (firm band allowance, 2–6 mm).
    var allowance: Float = 0.004
    var sideCurl: Float = 0.02
    /// Crown widens slightly toward the roof, like a classic top hat's bell.
    var crownFlare: Float = 0.004
    var ribbonHeight: Float = 0.030
}

enum HeadwearFitter {
    /// Fit the wearing ring on the visible scalp. `scalp` is the visible body mesh (no hair), `eyeY` the eye
    /// height. Front of the plane sits near mid-forehead, sides just above the ears, dropping over the back.
    static func fit(scalp: [SIMD3<Float>], eyeY: Float) -> HeadFit? {
        // Skull above the eyes gives the head's center and length.
        var cx: Float = 0, cn: Float = 0, front = -Float.greatestFiniteMagnitude, back = Float.greatestFiniteMagnitude
        for p in scalp where p.y > eyeY + 0.02 { cx += p.x; cn += 1; front = max(front, p.z); back = min(back, p.z) }
        guard cn > 20 else { return nil }
        cx /= cn
        var cz = (front + back) / 2
        let half = max(0.05, (front - back) / 2)
        // Eye centers sit ~2 cm below the brows; mid-forehead is ~4 cm above the eyes, the top of the ear
        // attachment about level with the brows. Sides of the ring just above the ears, front at mid-forehead.
        // Worn as in reference photos of men and women in top hats: the brim a finger's width above the
        // brows, the band nearly level (a few degrees higher in front), resting just above the ears.
        let centerY = eyeY + 0.02
        let pitch = atan(0.012 / half)                  // ≈7°
        func planeY(_ z: Float) -> Float { centerY + tan(pitch) * (z - cz) }

        var radii = [Float](repeating: 0, count: HeadFit.directions)
        for pass in 0..<2 {
            // Samples near the plane per direction: (radius, distance from the plane).
            var samples = [[(r: Float, dy: Float)]](repeating: [], count: HeadFit.directions)
            for p in scalp {
                let dx = p.x - cx, dz = p.z - cz
                let dy = abs(p.y - planeY(p.z))
                guard dy < 0.008, abs(dx) < 0.13, abs(dz) < 0.15 else { continue }
                var a = atan2(dx, dz); if a < 0 { a += 2 * .pi }
                let i = Int(a / (2 * .pi) * Float(HeadFit.directions)) % HeadFit.directions
                samples[i].append(((dx * dx + dz * dz).squareRoot(), dy))
            }
            // Skull radius at the plane: among samples on the skull (ears stand >12% further out), the one
            // closest to the plane. Taking the plain minimum would read the narrower head just above it.
            var best = [Float](repeating: .greatestFiniteMagnitude, count: HeadFit.directions)
            for i in 0..<HeadFit.directions where !samples[i].isEmpty {
                let rmin = samples[i].map { $0.r }.min() ?? 0
                let skull = samples[i].filter { $0.r <= rmin * 1.12 }
                best[i] = skull.min(by: { $0.dy < $1.dy })?.r ?? rmin
            }
            // Fill directions without samples from their neighbours.
            let known = best.enumerated().filter { $0.element < 1 }
            guard known.count >= HeadFit.directions / 3 else { return nil }
            for i in 0..<HeadFit.directions where best[i] >= 1 {
                var lo = i, hi = i
                repeat { lo = (lo - 1 + HeadFit.directions) % HeadFit.directions } while best[lo] >= 1
                repeat { hi = (hi + 1) % HeadFit.directions } while best[hi] >= 1
                let span = (hi - lo + HeadFit.directions) % HeadFit.directions
                let t = Float((i - lo + HeadFit.directions) % HeadFit.directions) / Float(max(1, span))
                best[i] = best[lo] * (1 - t) + best[hi] * t
            }
            radii = best
            if pass == 0 {
                // Re-center on the ring itself, then measure again.
                var sx: Float = 0, sz: Float = 0
                for i in 0..<HeadFit.directions {
                    let a = Float(i) / Float(HeadFit.directions) * 2 * .pi
                    sx += sin(a) * radii[i]; sz += cos(a) * radii[i]
                }
                cx += sx / Float(HeadFit.directions); cz += sz / Float(HeadFit.directions)
            }
        }
        var fit = HeadFit(center: SIMD3(cx, centerY, cz), pitch: pitch, radii: radii, circumference: 0, width: 0, length: 0, warning: nil)
        fit.crownTop = 0
        for p in scalp where abs(p.x - cx) < 0.12 && abs(p.z - cz) < 0.14 { fit.crownTop = max(fit.crownTop, p.y - centerY) }
        var perimeter: Float = 0, minX: Float = 0, maxX: Float = 0, minZ: Float = 0, maxZ: Float = 0
        for i in 0..<HeadFit.directions {
            let p = fit.point(i), q = fit.point(i + 1)
            perimeter += length(q - p)
            minX = min(minX, p.x); maxX = max(maxX, p.x); minZ = min(minZ, p.y); maxZ = max(maxZ, p.y)
        }
        fit.circumference = perimeter; fit.width = maxX - minX; fit.length = maxZ - minZ
        if perimeter < 0.50 || perimeter > 0.66 {
            fit.warning = String(format: "head %.0f mm is outside the supported 500–660 mm hat range", perimeter * 1000)
        }
        return fit
    }

    /// Hair thickness around the wearing line, compressed the way a firm band presses it (the reference's
    /// suggested 30–80% volume reduction; coily/curly hair keeps a thicker layer). Median over directions.
    static func hairLayer(_ hair: [[SIMD3<Float>]], fit: HeadFit, curly: Bool) -> Float {
        let toHat = simd_quatf(angle: fit.pitch, axis: SIMD3(1, 0, 0))
        var thickest = [Float](repeating: 0, count: HeadFit.directions)
        for mesh in hair {
            for p in mesh {
                let q = toHat.act(p - fit.center)
                guard abs(q.y) < 0.012 else { continue }
                var a = atan2(q.x, q.z); if a < 0 { a += 2 * .pi }
                let i = Int(a / (2 * .pi) * Float(HeadFit.directions)) % HeadFit.directions
                let r = (q.x * q.x + q.z * q.z).squareRoot()
                thickest[i] = max(thickest[i], r - fit.radii[i])
            }
        }
        let covered = thickest.filter { $0 > 0.001 }.sorted()
        guard covered.count >= HeadFit.directions / 4 else { return 0 }
        let median = covered[covered.count / 2]
        let kept: Float = curly ? 0.45 : 0.35
        return min(0.014, median * kept)
    }

    /// Hair policy for rigid hats: hair above the wearing plane is drawn in under the band (compressed into the
    /// crown cavity, where the closed hat hides it); strands below the brim stay where they are.
    static func tuckHair(_ positions: inout [SIMD3<Float>], fit: HeadFit, style: TopHatStyle) {
        // Work in the hat's own frame (the wearing plane, pitched like the hat), so the limits match the
        // crown wall exactly even though the hat leans back.
        let toHat = simd_quatf(angle: fit.pitch, axis: SIMD3(1, 0, 0))     // undo the hat's -pitch
        let toWorld = toHat.inverse
        let grow = style.allowance / (2 * .pi)
        let layer = fit.hairLayer
        for i in positions.indices {
            let q = toHat.act(positions[i] - fit.center)                   // y = height above the plane
            guard q.y > -0.03 else { continue }
            var a = atan2(q.x, q.z); if a < 0 { a += 2 * .pi }
            let ring = fit.radius(atAngle: a)
            let r = (q.x * q.x + q.z * q.z).squareRoot()
            var out = q
            let limit: Float
            if q.y >= 0 {
                limit = (ring + layer) * 0.97                              // flattened inside the hollow crown
                out.y = min(q.y, style.crownHeight - 0.012)
            } else {
                // Under the band: pressed to the band, fanning back to its own shape 3 cm lower.
                limit = ring + layer + grow + 0.002 + (-q.y) * 1.2
            }
            if r > limit, r > 0 { out.x = q.x * limit / r; out.z = q.z * limit / r }
            positions[i] = fit.center + toWorld.act(out)
        }
    }

    /// Hair under any fitted hat mesh (library caps, fedoras, hoods): the hat's own inner surface is the limit.
    /// Hair inside the hat's footprint is pressed just under that surface; hair below its lower edge keeps its
    /// shape, so it shows under the brim or band as in real life.
    static func pressHair(_ hair: inout [SIMD3<Float>], under hat: [SIMD3<Float>], fit: HeadFit, clearance: Float = 0.003) {
        guard !hat.isEmpty else { return }
        let n = HeadFit.directions, slice: Float = 0.01
        var low = Float.greatestFiniteMagnitude, high = -Float.greatestFiniteMagnitude
        for p in hat { low = min(low, p.y); high = max(high, p.y) }
        let rows = max(1, Int(((high - low) / slice).rounded(.up)) + 1)
        // Innermost hat radius per direction and height slice, and each direction's lower edge.
        var inner = [Float](repeating: .greatestFiniteMagnitude, count: n * rows)
        var edge = [Float](repeating: .greatestFiniteMagnitude, count: n)
        func dir(_ x: Float, _ z: Float) -> Int {
            var a = atan2(x, z); if a < 0 { a += 2 * .pi }
            return Int(a / (2 * .pi) * Float(n)) % n
        }
        for p in hat {
            let dx = p.x - fit.center.x, dz = p.z - fit.center.z
            let i = dir(dx, dz), row = min(rows - 1, Int((p.y - low) / slice))
            let r = (dx * dx + dz * dz).squareRoot()
            inner[i * rows + row] = min(inner[i * rows + row], r)
            edge[i] = min(edge[i], p.y)
        }
        // Height map of the hat's underside over the top of the head (1 cm cells): hair rising above a hat's dome
        // is pressed down under it, not only inward from the sides.
        let cell: Float = 0.01
        var under: [SIMD2<Int32>: Float] = [:]
        for p in hat {
            let key = SIMD2<Int32>(Int32(((p.x - fit.center.x) / cell).rounded(.down)), Int32(((p.z - fit.center.z) / cell).rounded(.down)))
            under[key] = min(under[key] ?? .greatestFiniteMagnitude, p.y)
        }
        for k in hair.indices {
            var p = hair[k]
            let dx = p.x - fit.center.x, dz = p.z - fit.center.z
            let i = dir(dx, dz)
            let r0 = (dx * dx + dz * dz).squareRoot()
            if r0 < fit.radii[i] * 0.9,
               let top = under[SIMD2<Int32>(Int32((dx / cell).rounded(.down)), Int32((dz / cell).rounded(.down)))],
               p.y > top - clearance {
                p.y = top - clearance
                hair[k] = p
            }
            guard edge[i] < .greatestFiniteMagnitude, p.y > edge[i] + 0.004, p.y <= high else { continue }
            let row = min(rows - 1, Int((p.y - low) / slice))
            var limit = inner[i * rows + row]
            if limit == .greatestFiniteMagnitude {        // no hat surface sampled here: nearest slice below
                var rr = row
                while rr > 0 && inner[i * rows + rr] == .greatestFiniteMagnitude { rr -= 1 }
                limit = inner[i * rows + rr]
            }
            guard limit < .greatestFiniteMagnitude else { continue }
            limit = max(fit.radii[i] * 0.98, limit - clearance)
            let r = (dx * dx + dz * dz).squareRoot()
            if r > limit, r > 0 { p.x = fit.center.x + dx * limit / r; p.z = fit.center.z + dz * limit / r }
            hair[k] = p
        }
    }

    // MARK: geometry

    private static func surface(_ positions: [SIMD3<Float>], _ normals: [SIMD3<Float>], _ triangles: [UInt32], _ material: SCNMaterial, name: String) -> SCNNode {
        func data(_ v: [SIMD3<Float>]) -> Data {
            var flat: [Float] = []; flat.reserveCapacity(v.count * 3)
            for p in v { flat += [p.x, p.y, p.z] }
            return flat.withUnsafeBufferPointer { Data(buffer: $0) }
        }
        let n = positions.count
        let vs = SCNGeometrySource(data: data(positions), semantic: .vertex, vectorCount: n, usesFloatComponents: true,
                                   componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let ns = SCNGeometrySource(data: data(normals), semantic: .normal, vectorCount: n, usesFloatComponents: true,
                                   componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let el = SCNGeometryElement(data: triangles.withUnsafeBufferPointer { Data(buffer: $0) }, primitiveType: .triangles,
                                    primitiveCount: triangles.count / 3, bytesPerIndex: 4)
        let g = SCNGeometry(sources: [vs, ns], elements: [el])
        g.materials = [material]
        let node = SCNNode(geometry: g); node.name = name
        return node
    }

    /// Strip between two closed rings (same point count); normals given per ring.
    private static func band(_ a: [SIMD3<Float>], _ b: [SIMD3<Float>], na: [SIMD3<Float>], nb: [SIMD3<Float>],
                             _ material: SCNMaterial, name: String) -> SCNNode {
        let n = a.count
        var tris: [UInt32] = []
        for i in 0..<n {
            let j = (i + 1) % n
            let a0 = UInt32(i), a1 = UInt32(j), b0 = UInt32(n + i), b1 = UInt32(n + j)
            tris += [a0, b0, a1, a1, b0, b1]
        }
        return surface(a + b, na + nb, tris, material, name: name)
    }

    private static func disk(_ ring: [SIMD3<Float>], center: SIMD3<Float>, normal: SIMD3<Float>, _ material: SCNMaterial, name: String) -> SCNNode {
        let n = ring.count
        var tris: [UInt32] = []
        for i in 0..<n { tris += [UInt32(n), UInt32(i), UInt32((i + 1) % n)] }
        return surface(ring + [center], Array(repeating: normal, count: n + 1), tris, material, name: name)
    }

    /// Baseball cap shape: a soft six-panel crown (superellipse dome, flatter than a helmet), a curved bill across
    /// the front only, top button, rear opening above the strap.
    struct CapShape {
        var crownHeight: Float = 0.088
        var roundness: Float = 2.2           // slightly >2: rounded crown that follows the head
        var billHalfAngle: Float = 0.72      // ±41° of the front
        var billDepth: Float = 0.072
        var openingHalfAngle: Float = 0.42
        var openingHeight: Float = 0.032
        /// Caps sit lower than a firm hat's band: front about 1.5 cm above the brows.
        var seatDrop: Float = 0.012
        /// Worn backwards the cap tips back: forehead edge (the strap side) rides higher, hairline showing.
        var backwardsTilt: Float = 0.14
        func pitch(_ fit: HeadFit, backwards: Bool) -> Float { fit.pitch + (backwards ? backwardsTilt : 0) }
        /// Crown tall enough for this head: skull top above the seat, plus pressed hair and clearance.
        func height(_ fit: HeadFit) -> Float { max(crownHeight, fit.crownTop + seatDrop + fit.hairLayer * 0.5 + 0.004) }
        func dome(_ r: Float, _ R: Float, _ H: Float) -> Float {
            guard r < R else { return 0 }
            return H * pow(max(0, 1 - pow(r / R, roundness)), 1 / roundness)
        }
    }

    static func capRing(_ fit: HeadFit) -> Float { 0.002 / (2 * .pi) + fit.hairLayer + 0.002 }

    static func baseballCap(_ fit: HeadFit, backwards: Bool = false, color: NSColor = NSColor(calibratedRed: 0.08, green: 0.1, blue: 0.16, alpha: 1),
                            shape: CapShape = CapShape()) -> SCNNode {
        let cloth = SCNMaterial(); cloth.lightingModel = .physicallyBased
        cloth.lightingModel = .lambert                      // matte cotton twill, no studio reflections
        cloth.diffuse.contents = color; cloth.isDoubleSided = true
        let n = HeadFit.directions, rows = 14
        let grow = capRing(fit)
        let front: Float = backwards ? .pi : 0
        func angleDist(_ a: Float, _ b: Float) -> Float { var d = abs(a - b).truncatingRemainder(dividingBy: 2 * .pi); if d > .pi { d = 2 * .pi - d }; return d }
        let e = 2 / shape.roundness
        let H = shape.height(fit)
        var pos: [SIMD3<Float>] = [], nor: [SIMD3<Float>] = []
        for r in 0...rows {
            let phi = Float(r) / Float(rows) * (.pi / 2)
            let c = pow(cos(phi), e), sn = pow(sin(phi), e)
            for i in 0..<n {
                let a = fit.angle(i), R = fit.radii[i] + grow
                pos.append(SIMD3(sin(a) * R * c, H * sn, cos(a) * R * c))
                let radialN = cos(phi), upN = sin(phi)
                nor.append(normalize(SIMD3(sin(a) * radialN, upN * 1.2, cos(a) * radialN)))
            }
        }
        var tris: [UInt32] = []
        for r in 0..<rows {
            for i in 0..<n {
                let a = fit.angle(i)
                let y0 = H * pow(sin(Float(r) / Float(rows) * (.pi / 2)), e)
                if y0 > 0.009 && y0 < shape.openingHeight && angleDist(a, front + .pi) < shape.openingHalfAngle { continue }
                let j = (i + 1) % n
                let a0 = UInt32(r * n + i), a1 = UInt32(r * n + j), b0 = UInt32((r + 1) * n + i), b1 = UInt32((r + 1) * n + j)
                tris += [a0, b0, a1, a1, b0, b1]
            }
        }
        let cap = SCNNode(); cap.name = "mh_baseball_cap"
        cap.addChildNode(surface(pos, nor, tris, cloth, name: "cap_crown"))
        // Adjustable strap across the bottom of the rear opening.
        do {
            var top: [SIMD3<Float>] = [], bot: [SIMD3<Float>] = [], out: [SIMD3<Float>] = []
            let steps = 12
            for k in 0...steps {
                var a = front + .pi + (Float(k) / Float(steps) * 2 - 1) * shape.openingHalfAngle
                if a < 0 { a += 2 * .pi }; a = a.truncatingRemainder(dividingBy: 2 * .pi)
                let R = fit.radius(atAngle: a) + grow + 0.0015
                bot.append(SIMD3(sin(a) * R, 0.004, cos(a) * R)); top.append(SIMD3(sin(a) * R, 0.016, cos(a) * R))
                out.append(SIMD3(sin(a), 0, cos(a)))
            }
            var t: [UInt32] = []
            for i in 0..<steps { let a0 = UInt32(i), a1 = UInt32(i + 1), b0 = UInt32(steps + 1 + i), b1 = UInt32(steps + 2 + i); t += [a0, b0, a1, a1, b0, b1] }
            let strapMat = SCNMaterial(); strapMat.lightingModel = .lambert; strapMat.isDoubleSided = true
            strapMat.diffuse.contents = color.blended(withFraction: 0.35, of: .black) ?? color
            cap.addChildNode(surface(bot + top, out + out, t, strapMat, name: "cap_strap"))
        }
        let button = SCNCylinder(radius: 0.008, height: 0.005); button.materials = [cloth]
        let b = SCNNode(geometry: button); b.position.y = CGFloat(H + 0.0015); cap.addChildNode(b)
        // Bill: rooted on the band across the front, projecting straight forward, arched side to side.
        let steps = 20
        let fwd = SIMD3<Float>(sin(front), 0, cos(front)), side = SIMD3<Float>(cos(front), 0, -sin(front))
        var root: [SIMD3<Float>] = [], tip: [SIMD3<Float>] = []
        for k in 0...steps {
            let t = Float(k) / Float(steps) * 2 - 1
            var a = front + t * shape.billHalfAngle; if a < 0 { a += 2 * .pi }
            let R = fit.radius(atAngle: a) + grow
            let base = SIMD3(sin(a) * R, Float(0.003), cos(a) * R)
            let reach = shape.billDepth * (1 - 0.42 * t * t)
            var end = base + fwd * reach + side * (t * 0.012)
            end.y = 0.003 - 0.022 - 0.014 * t * t              // bill dips over the eyes and curves at the sides
            root.append(base); tip.append(end)
        }
        let thick = SIMD3<Float>(0, -0.0035, 0)
        func strip(_ a: [SIMD3<Float>], _ c: [SIMD3<Float>], _ normal: SIMD3<Float>, name: String) -> SCNNode {
            var t: [UInt32] = []
            let m = a.count
            for i in 0..<(m - 1) {
                let a0 = UInt32(i), a1 = UInt32(i + 1), b0 = UInt32(m + i), b1 = UInt32(m + i + 1)
                t += [a0, b0, a1, a1, b0, b1]
            }
            return surface(a + c, Array(repeating: normal, count: 2 * m), t, cloth, name: name)
        }
        cap.addChildNode(strip(root, tip, SIMD3(0, 1, 0), name: "bill_top"))
        cap.addChildNode(strip(root.map { $0 + thick }, tip.map { $0 + thick }, SIMD3(0, -1, 0), name: "bill_under"))
        cap.addChildNode(strip(tip, tip.map { $0 + thick }, fwd, name: "bill_edge"))
        cap.eulerAngles.x = CGFloat(-shape.pitch(fit, backwards: backwards))
        return cap
    }

    /// Hair under the cap, using its exact shape: inside the crown it is pressed under the dome; just under the band
    /// it is pressed in and fans back out; through the rear opening it passes freely (ponytails, buns).
    static func pressHairUnderCap(_ positions: inout [SIMD3<Float>], fit: HeadFit, backwards: Bool, shape: CapShape = CapShape()) {
        let toCap = simd_quatf(angle: shape.pitch(fit, backwards: backwards), axis: SIMD3(1, 0, 0)), toWorld = toCap.inverse
        let origin = fit.center - SIMD3(0, shape.seatDrop, 0)
        let grow = capRing(fit), back: Float = backwards ? 0 : .pi
        let n = shape.roundness, H = shape.height(fit) - 0.005
        func angleDist(_ a: Float, _ b: Float) -> Float { var d = abs(a - b).truncatingRemainder(dividingBy: 2 * .pi); if d > .pi { d = 2 * .pi - d }; return d }
        for i in positions.indices {
            var q = toCap.act(positions[i] - origin)
            guard q.y > -0.035 else { continue }
            var a = atan2(q.x, q.z); if a < 0 { a += 2 * .pi }
            let R = fit.radius(atAngle: a) + grow - 0.005
            let r = (q.x * q.x + q.z * q.z).squareRoot()
            // Only a ponytail or bun passes through the opening: hair that already sits well outside the head there.
            let throughOpening = angleDist(a, back) < shape.openingHalfAngle * 0.8 && q.y < shape.openingHeight - 0.004 && r > R * 1.25
            if q.y >= 0 {
                // Inside the crown: scale toward the center until the point lies within the dome (superellipse).
                let sCap = pow(pow(r / R, n) + pow(max(0, q.y) / H, n), 1 / n)
                if sCap > 0.97 && !throughOpening {
                    let k = 0.97 / sCap
                    q.x *= k; q.z *= k; q.y *= k
                }
            } else if !throughOpening {
                // Under the band: pressed to the band, fanning back out lower down.
                let limit = R + 0.006 + (-q.y) * 1.3
                if r > limit, r > 0 { q.x *= limit / r; q.z *= limit / r }
            }
            positions[i] = origin + toWorld.act(q)
        }
    }

    /// Top hat built on the fitted ring, pivot at the inner band center, in the wearing plane's frame.
    static func topHat(_ fit: HeadFit, style: TopHatStyle = TopHatStyle()) -> SCNNode {
        func mat(_ white: CGFloat, rough: CGFloat) -> SCNMaterial {
            let m = SCNMaterial(); m.lightingModel = .physicallyBased
            m.diffuse.contents = NSColor(white: white, alpha: 1); m.roughness.contents = rough; m.metalness.contents = 0.0
            m.isDoubleSided = true
            return m
        }
        let felt = mat(0.05, rough: 0.85), lining = mat(0.11, rough: 0.6), satin = mat(0.015, rough: 0.32)
        let n = HeadFit.directions
        let grow = style.allowance / (2 * .pi) + fit.hairLayer   // band allowance plus the compressed hair under it
        func ring(_ extra: Float, y: Float) -> [SIMD3<Float>] { (0..<n).map { let p = fit.point($0, grow: grow + extra); return SIMD3(p.x, y, p.y) } }
        func radial(_ sign: Float) -> [SIMD3<Float>] { (0..<n).map { let a = fit.angle($0); return SIMD3(sin(a) * sign, 0, cos(a) * sign) } }
        let H = style.crownHeight, t = style.shell
        let inner0 = ring(0, y: 0), innerTop = ring(style.crownFlare, y: H - t)
        let outer0 = ring(t, y: 0), outerTop = ring(t + style.crownFlare, y: H)
        let hat = SCNNode(); hat.name = "mh_top_hat"
        hat.addChildNode(band(outer0, outerTop, na: radial(1), nb: radial(1), felt, name: "crown_outer"))
        hat.addChildNode(band(inner0, innerTop, na: radial(-1), nb: radial(-1), lining, name: "crown_lining"))
        hat.addChildNode(disk(outerTop, center: SIMD3(0, H, 0), normal: SIMD3(0, 1, 0), felt, name: "crown_roof"))
        hat.addChildNode(disk(innerTop, center: SIMD3(0, H - t, 0), normal: SIMD3(0, -1, 0), lining, name: "crown_roof_lining"))
        // Ribbon on the lower crown.
        let rib0 = ring(t + 0.0012, y: 0.004), rib1 = ring(t + 0.0012, y: 0.004 + style.ribbonHeight)
        hat.addChildNode(band(rib0, rib1, na: radial(1), nb: radial(1), satin, name: "ribbon"))
        // Brim: wider at the sides, edges curling up at the sides; upper and lower surfaces plus a rolled edge.
        let brimT: Float = 0.006
        var topIn: [SIMD3<Float>] = [], topOut: [SIMD3<Float>] = [], botIn: [SIMD3<Float>] = [], botOut: [SIMD3<Float>] = []
        var upN: [SIMD3<Float>] = [], downN: [SIMD3<Float>] = []
        for i in 0..<n {
            let a = fit.angle(i), side = sin(a) * sin(a)
            let width = style.brimFrontBack + (style.brimSides - style.brimFrontBack) * side
            let base = fit.point(i, grow: grow + t)
            let dir = SIMD2(sin(a), cos(a))
            let edge = base + dir * width
            let curl = style.sideCurl * side
            topIn.append(SIMD3(base.x, brimT, base.y)); topOut.append(SIMD3(edge.x, brimT + curl, edge.y))
            botIn.append(SIMD3(base.x, 0, base.y)); botOut.append(SIMD3(edge.x, curl, edge.y))
            let tiltN = normalize(SIMD3(-dir.x * curl / width, 1, -dir.y * curl / width))
            upN.append(tiltN); downN.append(-tiltN)
        }
        hat.addChildNode(band(topIn, topOut, na: Array(repeating: SIMD3(0, 1, 0), count: n), nb: upN, felt, name: "brim_top"))
        hat.addChildNode(band(botIn, botOut, na: Array(repeating: SIMD3(0, -1, 0), count: n), nb: downN, felt, name: "brim_under"))
        hat.addChildNode(band(botOut, topOut, na: radial(1), nb: radial(1), felt, name: "brim_edge"))
        // Closed underside between the band and the brim root (no see-through gap at the seam).
        hat.addChildNode(band(inner0, botIn, na: Array(repeating: SIMD3(0, -1, 0), count: n), nb: Array(repeating: SIMD3(0, -1, 0), count: n), felt, name: "band_seat"))
        hat.eulerAngles.x = CGFloat(-fit.pitch)          // seat on the wearing plane: front up, back down
        hat.castsShadow = true
        return hat
    }
}
