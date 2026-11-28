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
    var sideCurl: Float = 0.012
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
        let centerY = eyeY + 0.035                     // just above the ears
        let pitch = atan(0.028 / half)                  // mid-forehead in front, lower over the occiput
        func planeY(_ z: Float) -> Float { centerY + tan(pitch) * (z - cz) }

        var radii = [Float](repeating: 0, count: HeadFit.directions)
        for pass in 0..<2 {
            var best = [Float](repeating: .greatestFiniteMagnitude, count: HeadFit.directions)
            for p in scalp {
                let dx = p.x - cx, dz = p.z - cz
                guard abs(p.y - planeY(p.z)) < 0.005, abs(dx) < 0.13, abs(dz) < 0.15 else { continue }
                var a = atan2(dx, dz); if a < 0 { a += 2 * .pi }
                let i = Int(a / (2 * .pi) * Float(HeadFit.directions)) % HeadFit.directions
                // Innermost surface in each direction: the skull, never the ear standing off it.
                best[i] = min(best[i], (dx * dx + dz * dz).squareRoot())
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

    /// Hair policy for rigid hats: hair above the wearing plane is drawn in under the band (compressed into the
    /// crown cavity, where the closed hat hides it); strands below the brim stay where they are.
    static func tuckHair(_ positions: inout [SIMD3<Float>], fit: HeadFit, style: TopHatStyle) {
        for i in positions.indices {
            var p = positions[i]
            let dx = p.x - fit.center.x, dz = p.z - fit.center.z
            let plane = fit.center.y + tan(fit.pitch) * dz
            guard p.y > plane - 0.002 else { continue }
            var a = atan2(dx, dz); if a < 0 { a += 2 * .pi }
            let limit = fit.radius(atAngle: a) * 0.97
            let r = (dx * dx + dz * dz).squareRoot()
            if r > limit, r > 0 { p.x = fit.center.x + dx * limit / r; p.z = fit.center.z + dz * limit / r }
            p.y = min(p.y, plane + style.crownHeight - 0.012)
            positions[i] = p
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
        let grow = style.allowance / (2 * .pi)          // circumference allowance as a radial offset
        func ring(_ extra: Float, y: Float) -> [SIMD3<Float>] { (0..<n).map { let p = fit.point($0, grow: grow + extra); return SIMD3(p.x, y, p.y) } }
        func radial(_ sign: Float) -> [SIMD3<Float>] { (0..<n).map { let a = fit.angle($0); return SIMD3(sin(a) * sign, 0, cos(a) * sign) } }
        let H = style.crownHeight, t = style.shell
        let inner0 = ring(0, y: 0), innerTop = ring(0, y: H - t)
        let outer0 = ring(t, y: 0), outerTop = ring(t, y: H)
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
