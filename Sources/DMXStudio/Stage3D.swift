import SwiftUI
import SceneKit
import Metal
import AppKit

// MARK: - Materials

private enum Mat {
    static func make(_ color: NSColor, metal: Bool = false, rough: CGFloat = 0.6) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = metal ? 0.9 : 0.05
        m.roughness.contents = rough
        return m
    }
    static let black = make(NSColor(white: 0.05, alpha: 1), metal: true, rough: 0.45)
    static let darkGray = make(NSColor(white: 0.12, alpha: 1), rough: 0.8)
    static let aluminum = make(NSColor(white: 0.75, alpha: 1), metal: true, rough: 0.3)
    static let stageTop = make(NSColor(calibratedRed: 0.30, green: 0.19, blue: 0.11, alpha: 1), rough: 0.55)   // wood deck
    static let chrome = make(NSColor(white: 0.85, alpha: 1), metal: true, rough: 0.2)
    static let person = make(NSColor(white: 0.25, alpha: 1), rough: 0.9)

    static func beam() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor.white
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        m.transparency = 0
        return m
    }
    static func lens() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor(white: 0.15, alpha: 1)
        return m
    }
}

// MARK: - Models

private enum Build {
    static func cyl(_ r: CGFloat, _ h: CGFloat, _ m: SCNMaterial) -> SCNNode {
        let g = SCNCylinder(radius: r, height: h); g.materials = [m]; return SCNNode(geometry: g)
    }
    static func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ m: SCNMaterial, chamfer: CGFloat = 0) -> SCNNode {
        let g = SCNBox(width: w, height: h, length: d, chamferRadius: chamfer); g.materials = [m]; return SCNNode(geometry: g)
    }
    /// A pipe between two points.
    static func pipe(from a: SCNVector3, to b: SCNVector3, r: CGFloat, _ m: SCNMaterial) -> SCNNode {
        let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
        let len = sqrt(dx * dx + dy * dy + dz * dz)
        let n = cyl(r, len, m)
        n.position = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
        n.look(at: b, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
        return n
    }

    /// Square box truss (0.29 m) along +X, `length` meters, centered.
    static func truss(length: CGFloat) -> SCNNode {
        let root = SCNNode()
        let s: CGFloat = 0.145, r: CGFloat = 0.024
        let half = length / 2
        let corners = [(s, s), (s, -s), (-s, s), (-s, -s)]
        for (y, z) in corners {
            root.addChildNode(pipe(from: SCNVector3(-half, y, z), to: SCNVector3(half, y, z), r: r, Mat.aluminum))
        }
        var x = -half
        var flip = false
        while x < half - 0.01 {
            let nx = min(half, x + 0.5)
            for (y1, z1, y2, z2) in [(s, s, -s, s), (s, -s, -s, -s), (s, s, s, -s), (-s, s, -s, -s)] {
                root.addChildNode(pipe(from: SCNVector3(flip ? nx : x, y1, z1), to: SCNVector3(flip ? x : nx, y2, z2), r: 0.012, Mat.aluminum))
            }
            flip.toggle()
            x = nx
        }
        return root
    }

    /// SHEHDS LED Beam 8x12W: black bar, end brackets and a tilting head with 8 lenses.
    /// Returns the root and the tilting head node; each lens has a beam named "beam".
    /// SHEHDS LED Beam 8x12W RGBW, from its spec sheet and photos: 107 × 13 × 8 cm overall.
    /// Rounded end caps, a fixed lower housing with the rear panel (powerCON in/out, DMX in/out,
    /// power switch, fuse, red display + 4 buttons), and a tilting lens bar with 8 lenses.
    static func shehdsBar() -> (SCNNode, SCNNode, [SCNNode]) {
        let root = SCNNode()
        let len: CGFloat = 1.07, height: CGFloat = 0.13, depth: CGFloat = 0.08
        let capW: CGFloat = 0.065
        let inner = len - 2 * capW                       // 0.94 m between the end caps

        // End caps: flat bottom, rounded top ("D" shape), full height and depth
        for side in [-1.0, 1.0] {
            let x = CGFloat(side) * (len / 2 - capW / 2)
            let lower = box(capW, height - depth / 2, depth, Mat.black, chamfer: 0.004)
            lower.position = SCNVector3(x, (height - depth / 2) / 2, 0); root.addChildNode(lower)
            let top = cyl(depth / 2, capW, Mat.black)
            top.eulerAngles.z = .pi / 2
            top.position = SCNVector3(x, height - depth / 2, 0); root.addChildNode(top)
            // mounting holes on the outer face
            for (hy, hz) in [(0.03, -0.022), (0.03, 0.022), (0.085, -0.022), (0.085, 0.022)] {
                let hole = cyl(0.005, 0.004, Mat.darkGray); hole.eulerAngles.z = .pi / 2
                hole.position = SCNVector3(x + CGFloat(side) * (capW / 2 + 0.001), CGFloat(hy), CGFloat(hz)); root.addChildNode(hole)
            }
        }

        // Lower housing with the rear panel facing +z
        let baseH: CGFloat = 0.06
        let base = box(inner, baseH, depth - 0.006, Mat.black, chamfer: 0.003)
        base.position = SCNVector3(0, baseH / 2, 0); root.addChildNode(base)
        let face = depth / 2 - 0.002
        func onPanel(_ n: SCNNode, x: CGFloat, y: CGFloat) {
            n.position = SCNVector3(x, y, face); root.addChildNode(n)
        }
        func round(_ r: CGFloat, _ m: SCNMaterial) -> SCNNode { let c = cyl(r, 0.006, m); c.eulerAngles.x = .pi / 2; return c }
        let blue = Mat.make(NSColor(calibratedRed: 0.1, green: 0.35, blue: 0.85, alpha: 1), rough: 0.5)
        let white = Mat.make(NSColor(white: 0.85, alpha: 1), rough: 0.5)
        let x0 = -inner / 2
        onPanel(round(0.012, blue), x: x0 + 0.06, y: 0.032)        // POWER IN (blue powerCON)
        onPanel(round(0.012, white), x: x0 + 0.095, y: 0.032)      // POWER OUT (white powerCON)
        onPanel(round(0.011, Mat.darkGray), x: x0 + 0.15, y: 0.032)   // DMX IN
        onPanel(round(0.011, Mat.darkGray), x: x0 + 0.185, y: 0.032)  // DMX OUT
        onPanel(box(0.012, 0.02, 0.006, Mat.darkGray), x: x0 + 0.23, y: 0.032)   // ON/OFF switch
        onPanel(round(0.008, Mat.black), x: x0 + 0.26, y: 0.032)                // fuse
        let red = SCNMaterial(); red.lightingModel = .constant; red.diffuse.contents = NSColor(calibratedRed: 0.9, green: 0.1, blue: 0.1, alpha: 1)
        onPanel(box(0.04, 0.02, 0.003, red), x: x0 + 0.33, y: 0.04)            // display
        for k in 0..<4 { onPanel(round(0.003, Mat.darkGray), x: x0 + 0.312 + CGFloat(k) * 0.012, y: 0.019) }   // MENU UP DOWN ENTER
        // rubber feet
        for x in [-0.4, 0.4] { let f = cyl(0.012, 0.008, Mat.darkGray); f.position = SCNVector3(x, -0.004, 0); root.addChildNode(f) }

        // Tilting lens bar: pivots between the end caps, lenses face up (+y) at rest
        let head = SCNNode()
        head.position = SCNVector3(0, height - depth / 2, 0)      // same axis as the rounded cap tops
        let headBody = box(inner - 0.004, 0.06, depth - 0.012, Mat.black, chamfer: 0.006)
        head.addChildNode(headBody)
        // heat-sink fins on the back of the bar
        for k in 0..<5 {
            let fin = box(inner - 0.03, 0.003, 0.012, Mat.darkGray)
            fin.position = SCNVector3(0, -0.024 + CGFloat(k) * 0.012, -(depth - 0.012) / 2 - 0.005); head.addChildNode(fin)
        }
        var lenses: [SCNNode] = []
        let pitch: CGFloat = 0.106
        for i in 0..<8 {
            let lensNode = SCNNode()
            lensNode.position = SCNVector3(-3.5 * pitch + CGFloat(i) * pitch, 0.03, 0)
            let ring = cyl(0.03, 0.01, Mat.darkGray); ring.position = SCNVector3(0, 0.002, 0)
            let glass = cyl(0.024, 0.012, Mat.lens()); glass.name = "lens"; glass.position = SCNVector3(0, 0.004, 0)
            lensNode.addChildNode(ring); lensNode.addChildNode(glass)
            lensNode.addChildNode(beamNode(spreadDeg: 8, length: 9))
            head.addChildNode(lensNode)
            lenses.append(lensNode)
        }
        root.addChildNode(head)
        return (root, head, lenses)
    }

    /// Chauvet LED Followspot 75ST, modeled from its product photos:
    /// octagonal black body, front lens, rear control panel, top tilt handle with ball knob,
    /// U-yoke with side knobs, carry handle — on its tripod stand or on its own.
    /// Returns root, the aimable head (the light itself), and the lens.
    static func followspot(onStand: Bool) -> (SCNNode, SCNNode, SCNNode) {
        let root = SCNNode()
        let pivotHeight: CGFloat = onStand ? 1.72 : 0.15

        if onStand {
            // Tripod: three legs from the hub, braces to the pole, rubber feet
            let hubY: CGFloat = 0.55
            for a in [90.0, 210.0, 330.0] {
                let rad = a * .pi / 180
                let foot = SCNVector3(cos(rad) * 0.62, 0.02, sin(rad) * 0.62)
                root.addChildNode(pipe(from: SCNVector3(0, hubY, 0), to: foot, r: 0.016, Mat.black))
                root.addChildNode(pipe(from: SCNVector3(cos(rad) * 0.38, 0.22, sin(rad) * 0.38), to: SCNVector3(0, 0.3, 0), r: 0.008, Mat.black))
                let pad = cyl(0.025, 0.04, Mat.darkGray); pad.position = foot; root.addChildNode(pad)
            }
            let hub = cyl(0.05, 0.08, Mat.black); hub.position = SCNVector3(0, hubY, 0); root.addChildNode(hub)
            // Telescoping pole: thicker lower section, thinner upper section, locking knobs
            root.addChildNode(pipe(from: SCNVector3(0, 0.25, 0), to: SCNVector3(0, 1.05, 0), r: 0.022, Mat.black))
            root.addChildNode(pipe(from: SCNVector3(0, 1.05, 0), to: SCNVector3(0, pivotHeight - 0.16, 0), r: 0.016, Mat.black))
            for y in [CGFloat(0.66), CGFloat(1.05), pivotHeight - 0.2] {
                let collar = cyl(0.03, 0.05, Mat.black); collar.position = SCNVector3(0, y, 0); root.addChildNode(collar)
                let knob = cyl(0.025, 0.03, Mat.darkGray); knob.eulerAngles.z = .pi / 2; knob.position = SCNVector3(0.05, y, 0)
                root.addChildNode(knob)
            }
        } else {
            // On its own: the yoke's flat foot
            let foot = box(0.3, 0.015, 0.22, Mat.black, chamfer: 0.004); foot.position = SCNVector3(0, 0.008, 0); root.addChildNode(foot)
        }

        // U-yoke (fixed): bottom bar + two arms up to the pivot knobs
        let yokeBottom = pivotHeight - 0.13
        let yb = box(0.23, 0.015, 0.04, Mat.black); yb.position = SCNVector3(0, yokeBottom, 0); root.addChildNode(yb)
        for x in [CGFloat(-0.112), CGFloat(0.112)] {
            let arm = box(0.01, 0.14, 0.04, Mat.black); arm.position = SCNVector3(x, yokeBottom + 0.07, 0); root.addChildNode(arm)
            let knob = cyl(0.03, 0.026, Mat.darkGray); knob.eulerAngles.z = .pi / 2
            knob.position = SCNVector3(x + (x > 0 ? 0.019 : -0.019), pivotHeight, 0); root.addChildNode(knob)   // 27.4 cm across the knobs
        }

        // The light (tilts inside the yoke)
        let head = SCNNode()
        head.position = SCNVector3(0, pivotHeight, 0)
        // Official size: 55.8 cm long × 27.4 cm wide (with knobs) × 29.2 cm tall (with handle)
        let body = SCNCylinder(radius: 0.1, height: 0.5)
        body.radialSegmentCount = 8                       // octagonal housing
        body.materials = [Mat.black]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.eulerAngles = SCNVector3(Double.pi / 2, 0, Double.pi / 8)   // lie along Z, flat sides square
        head.addChildNode(bodyNode)
        // vents along the top
        for k in 0..<6 {
            let v = box(0.1, 0.004, 0.012, Mat.darkGray); v.position = SCNVector3(0, 0.098, -0.05 + Double(k) * 0.03); head.addChildNode(v)
        }
        // Front bezel plate
        let bezel = SCNCylinder(radius: 0.108, height: 0.03); bezel.radialSegmentCount = 8; bezel.materials = [Mat.black]
        let bezelNode = SCNNode(geometry: bezel); bezelNode.eulerAngles = SCNVector3(Double.pi / 2, 0, Double.pi / 8)
        bezelNode.position = SCNVector3(0, 0, -0.263); head.addChildNode(bezelNode)
        // Rear control panel with the red LED display and buttons
        let panel = box(0.17, 0.15, 0.01, Mat.darkGray); panel.position = SCNVector3(0, 0, 0.255); head.addChildNode(panel)
        let display = box(0.045, 0.02, 0.004, { let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = NSColor.red; return m }())
        display.position = SCNVector3(0.045, 0.035, 0.262); head.addChildNode(display)
        for r in 0..<2 { for c in 0..<4 {
            let btn = box(0.018, 0.018, 0.006, Mat.black)
            btn.position = SCNVector3(-0.065 + Double(c) * 0.026, -0.01 - Double(r) * 0.026, 0.262); head.addChildNode(btn)
        } }
        let power = box(0.022, 0.03, 0.008, { let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = NSColor(calibratedRed: 0.9, green: 0.05, blue: 0.05, alpha: 1); return m }())
        power.position = SCNVector3(0.06, -0.035, 0.262); head.addChildNode(power)
        // Top tilt handle: dome cover + stalk + ball knob
        let dome = SCNCylinder(radius: 0.05, height: 0.1); dome.materials = [Mat.black]
        let domeNode = SCNNode(geometry: dome); domeNode.eulerAngles.z = .pi / 2; domeNode.position = SCNVector3(0, 0.1, 0.1)
        head.addChildNode(domeNode)
        head.addChildNode(pipe(from: SCNVector3(0, 0.145, 0.1), to: SCNVector3(0, 0.172, 0.1), r: 0.005, Mat.aluminum))
        let ball = SCNNode(geometry: { let g = SCNSphere(radius: 0.02); g.materials = [Mat.black]; return g }())
        ball.position = SCNVector3(0, 0.19, 0.1); head.addChildNode(ball)
        // Carry handle under the back
        head.addChildNode(pipe(from: SCNVector3(-0.07, -0.08, 0.275), to: SCNVector3(0.07, -0.08, 0.275), r: 0.011, Mat.darkGray))
        // Focus knobs on the side
        for z in [CGFloat(-0.05), CGFloat(0.05)] {
            let fk = cyl(0.016, 0.03, Mat.darkGray); fk.eulerAngles.z = .pi / 2; fk.position = SCNVector3(0.105, -0.03, z); head.addChildNode(fk)
        }
        // Lens (beam leaves toward -Z)
        let lensNode = SCNNode()
        lensNode.position = SCNVector3(0, 0, -0.262)
        lensNode.eulerAngles.x = -.pi / 2
        let glass = cyl(0.07, 0.01, Mat.lens()); glass.name = "lens"
        lensNode.addChildNode(glass)
        lensNode.addChildNode(beamNode(spreadDeg: 10, length: 12))
        head.addChildNode(lensNode)
        root.addChildNode(head)
        return (root, head, lensNode)
    }

    /// Generic par / other light: a small can pointing up.
    static func genericLight() -> (SCNNode, SCNNode, SCNNode) {
        let root = SCNNode()
        let head = SCNNode(); head.position = SCNVector3(0, 0.15, 0)
        head.addChildNode(cyl(0.12, 0.25, Mat.black))
        let lensNode = SCNNode(); lensNode.position = SCNVector3(0, 0.13, 0)
        let glass = cyl(0.1, 0.01, Mat.lens()); glass.name = "lens"
        lensNode.addChildNode(glass)
        lensNode.addChildNode(beamNode(spreadDeg: 25, length: 6))
        head.addChildNode(lensNode)
        root.addChildNode(head)
        return (root, head, lensNode)
    }

    /// A light beam along +Y, made of fading cone segments.
    static func beamNode(spreadDeg: Double, length: Double) -> SCNNode {
        let beam = SCNNode(); beam.name = "beam"
        let segs = 4
        let tanH = tan(spreadDeg / 2 * .pi / 180)
        for i in 0..<segs {
            let d0 = length * Double(i) / Double(segs), d1 = length * Double(i + 1) / Double(segs)
            let g = SCNCone(topRadius: CGFloat(0.02 + d1 * tanH * 0.7), bottomRadius: CGFloat(0.02 + d0 * tanH * 0.7), height: CGFloat(d1 - d0))
            g.radialSegmentCount = 16
            g.materials = [Mat.beam()]
            let n = SCNNode(geometry: g)
            n.name = "seg\(i)"
            n.position = SCNVector3(0, (d0 + d1) / 2, 0)
            n.castsShadow = false
            beam.addChildNode(n)
        }
        return beam
    }

    static func prop(_ kind: PropKind, size: Double) -> SCNNode {
        let s = CGFloat(size)
        switch kind {
        case .stage:
            let n = box(6 * s, 0.6, 4, Mat.stageTop, chamfer: 0.02); n.position = SCNVector3(0, 0.3, 0)
            let root = SCNNode(); root.addChildNode(n)
            let edge = box(6 * s, 0.02, 0.03, { let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = NSColor(white: 0.5, alpha: 1); return m }())
            edge.position = SCNVector3(0, 0.6, 2); root.addChildNode(edge)
            return root
        case .truss:
            return truss(length: s)
        case .trussTower:
            let t = truss(length: s); t.eulerAngles.z = .pi / 2; t.position = SCNVector3(0, s / 2, 0)
            let root = SCNNode(); root.addChildNode(t)
            let plate = box(0.6, 0.02, 0.6, Mat.aluminum); plate.position = SCNVector3(0, 0.01, 0); root.addChildNode(plate)
            return root
        case .circleTruss:
            let root = SCNNode()
            let r: CGFloat = 1.3 * s
            for z in [CGFloat(-0.12), CGFloat(0.12)] {
                let t = SCNTorus(ringRadius: r, pipeRadius: 0.025); t.materials = [Mat.aluminum]
                let n = SCNNode(geometry: t); n.eulerAngles.x = .pi / 2; n.position = SCNVector3(0, r + 0.3, z); root.addChildNode(n)
                let t2 = SCNTorus(ringRadius: r - 0.22, pipeRadius: 0.02); t2.materials = [Mat.aluminum]
                let n2 = SCNNode(geometry: t2); n2.eulerAngles.x = .pi / 2; n2.position = SCNVector3(0, r + 0.3, z); root.addChildNode(n2)
            }
            for k in 0..<16 {
                let a = Double(k) / 16 * 2 * .pi
                let p1 = SCNVector3(cos(a) * Double(r - 0.22), Double(r) + 0.3 + sin(a) * Double(r - 0.22), 0)
                let p2 = SCNVector3(cos(a) * Double(r), Double(r) + 0.3 + sin(a) * Double(r), 0)
                root.addChildNode(pipe(from: p1, to: p2, r: 0.012, Mat.aluminum))
            }
            root.addChildNode(pipe(from: SCNVector3(0, 0, 0), to: SCNVector3(0, 0.35, 0), r: 0.05, Mat.aluminum))
            return root
        case .lightStand:
            let root = SCNNode()
            for a in [0.0, 120.0, 240.0] {
                let rad = a * .pi / 180
                root.addChildNode(pipe(from: SCNVector3(0, 0.6, 0), to: SCNVector3(cos(rad) * 0.7, 0, sin(rad) * 0.7), r: 0.018, Mat.black))
            }
            root.addChildNode(pipe(from: SCNVector3(0, 0.5, 0), to: SCNVector3(0, s, 0), r: 0.022, Mat.black))
            root.addChildNode(pipe(from: SCNVector3(-0.7, s, 0), to: SCNVector3(0.7, s, 0), r: 0.02, Mat.black))
            return root
        case .micStand:
            let root = SCNNode()
            let base = cyl(0.14, 0.02, Mat.black); base.position = SCNVector3(0, 0.01, 0); root.addChildNode(base)
            root.addChildNode(pipe(from: SCNVector3(0, 0, 0), to: SCNVector3(0, 1.45, 0), r: 0.01, Mat.black))
            let mic = SCNNode(geometry: { let g = SCNSphere(radius: 0.03); g.materials = [Mat.darkGray]; return g }())
            mic.position = SCNVector3(0, 1.5, 0.05); root.addChildNode(mic)
            return root
        case .speaker:
            let root = SCNNode()
            let cab = box(0.6, 1.0, 0.5, Mat.black, chamfer: 0.02); cab.position = SCNVector3(0, 0.5, 0); root.addChildNode(cab)
            for (y, r) in [(0.35, 0.2), (0.8, 0.07)] {
                let c = cyl(CGFloat(r), 0.02, Mat.darkGray); c.eulerAngles.x = .pi / 2; c.position = SCNVector3(0, y, 0.25); root.addChildNode(c)
            }
            return root
        case .djBooth:
            let root = SCNNode()
            let t = box(1.8, 1.0, 0.75, Mat.black, chamfer: 0.02); t.position = SCNVector3(0, 0.5, 0); root.addChildNode(t)
            let face = box(1.6, 0.6, 0.01, { let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = NSColor(calibratedRed: 0.5, green: 0.02, blue: 0.12, alpha: 1); return m }())
            face.position = SCNVector3(0, 0.55, 0.38); root.addChildNode(face)
            return root
        case .trussFrame:
            // Box frame: four towers + a square of truss on top (size = scale; 6 m × 4 m × 3.5 m)
            let root = SCNNode()
            let w = 6.5 * s, d = 4.5 * s, h: CGFloat = 3.6
            for (x, z) in [(-w / 2, -d / 2), (w / 2, -d / 2), (-w / 2, d / 2), (w / 2, d / 2)] {
                let t = truss(length: h); t.eulerAngles.z = .pi / 2; t.position = SCNVector3(x, h / 2, z); root.addChildNode(t)
            }
            for z in [-d / 2, d / 2] { let t = truss(length: w); t.position = SCNVector3(0, h + 0.15, z); root.addChildNode(t) }
            for x in [-w / 2, w / 2] { let t = truss(length: d); t.eulerAngles.y = .pi / 2; t.position = SCNVector3(x, h + 0.15, 0); root.addChildNode(t) }
            return root
        case .ledWall:
            // 1.5 m × 2.5 m video panel on a frame (shown dark so the light beams carry the color)
            let root = SCNNode()
            let frame = box(1.6 * s, 2.6 * s, 0.1, Mat.black); frame.position = SCNVector3(0, 1.3 * s, 0); root.addChildNode(frame)
            let screen = SCNNode(geometry: { let g = SCNPlane(width: 1.5 * s, height: 2.5 * s)
                let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = NSColor(white: 0.05, alpha: 1); g.materials = [m]; return g }())
            screen.name = "ledscreen"
            screen.position = SCNVector3(0, 1.3 * s, 0.052); root.addChildNode(screen)
            return root
        case .drumKit:
            let root = SCNNode()
            let kick = cyl(0.28, 0.4, Mat.black); kick.eulerAngles.x = .pi / 2; kick.position = SCNVector3(0, 0.3, 0); root.addChildNode(kick)
            let head = cyl(0.27, 0.01, Mat.make(NSColor(white: 0.9, alpha: 1))); head.eulerAngles.x = .pi / 2; head.position = SCNVector3(0, 0.3, 0.205); root.addChildNode(head)
            for (x, y, r) in [(-0.38, 0.62, 0.16), (0.38, 0.62, 0.15), (0.5, 0.48, 0.2)] {
                let tom = cyl(CGFloat(r), 0.2, Mat.make(NSColor(calibratedRed: 0.5, green: 0.02, blue: 0.1, alpha: 1), metal: true, rough: 0.3))
                tom.position = SCNVector3(x, y, -0.05); root.addChildNode(tom)
            }
            for (x, y) in [(-0.65, 1.15), (0.7, 1.25)] {
                root.addChildNode(pipe(from: SCNVector3(x, 0, -0.1), to: SCNVector3(x, y, -0.1), r: 0.01, Mat.chrome))
                let cym = cyl(0.22, 0.006, Mat.make(NSColor(calibratedRed: 0.8, green: 0.65, blue: 0.25, alpha: 1), metal: true, rough: 0.25))
                cym.position = SCNVector3(x, y, -0.1); cym.eulerAngles.z = 0.15; root.addChildNode(cym)
            }
            let stool = cyl(0.17, 0.5, Mat.black); stool.position = SCNVector3(0, 0.25, -0.65); root.addChildNode(stool)
            return root
        case .performer:
            let root = SCNNode()
            let body = SCNNode(geometry: { let g = SCNCapsule(capRadius: 0.2, height: 1.45); g.materials = [Mat.person]; return g }())
            body.position = SCNVector3(0, 0.75, 0); root.addChildNode(body)
            let head = SCNNode(geometry: { let g = SCNSphere(radius: 0.12); g.materials = [Mat.person]; return g }())
            head.position = SCNVector3(0, 1.62, 0); root.addChildNode(head)
            return root
        }
    }
}

// MARK: - The SceneKit view (orbit camera + click/drag editing)

final class StageSCNView: SCNView {
    var onSelect: ((UUID?) -> Void)?
    var onDrag: ((UUID, Double, Double) -> Void)?
    var editing = false
    private var draggingID: UUID?
    private var dragOffset = CGPoint.zero

    private func itemID(at p: CGPoint) -> UUID? {
        for hit in hitTest(p, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue]) {
            var n: SCNNode? = hit.node
            while let cur = n {
                if let name = cur.name, name.hasPrefix("item:"), let id = UUID(uuidString: String(name.dropFirst(5))) { return id }
                n = cur.parent
            }
        }
        return nil
    }

    /// Where the mouse ray hits the floor (y = 0).
    private func floorPoint(_ p: CGPoint) -> (Double, Double)? {
        let a = unprojectPoint(SCNVector3(p.x, p.y, 0))
        let b = unprojectPoint(SCNVector3(p.x, p.y, 1))
        let dy = b.y - a.y
        guard abs(dy) > 1e-6 else { return nil }
        let t = -a.y / dy
        guard t > 0 else { return nil }
        return (Double(a.x + (b.x - a.x) * t), Double(a.z + (b.z - a.z) * t))
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if editing, let id = itemID(at: p) {
            onSelect?(id)
            draggingID = id
            return
        }
        draggingID = nil
        if editing { onSelect?(nil) }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if let id = draggingID {
            let p = convert(event.locationInWindow, from: nil)
            if let (x, z) = floorPoint(p) { onDrag?(id, x, z) }
            return
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if draggingID != nil { draggingID = nil; return }
        super.mouseUp(with: event)
    }
}

struct Stage3DView: NSViewRepresentable {
    @ObservedObject var model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> StageSCNView {
        // Draw on the built-in, low-power graphics chip when the Mac has two (2016-2019 MacBook Pros).
        // The separate AMD chip in those models can restart the whole Mac under sustained 3D load.
        var opts: [String: Any] = [:]
        if let low = MTLCopyAllDevices().first(where: { $0.isLowPower }) {
            opts[SCNView.Option.preferredDevice.rawValue] = low
        }
        opts[SCNView.Option.preferLowPowerDevice.rawValue] = true
        let v = StageSCNView(frame: .zero, options: opts)
        v.scene = context.coordinator.scene
        v.backgroundColor = .black
        v.allowsCameraControl = true
        context.coordinator.applyQuality(model.stageHighQuality, to: v)
        v.pointOfView = context.coordinator.camera
        v.onSelect = { [weak model] id in model?.selectedStageItem = id }
        v.onDrag = { [weak model] id, x, z in
            model?.updateStageItem(id) { $0.x = (x * 10).rounded() / 10; $0.z = (z * 10).rounded() / 10 }
        }
        context.coordinator.view = v
        context.coordinator.start()
        return v
    }

    func updateNSView(_ v: StageSCNView, context: Context) {
        v.editing = model.stageEditing
        context.coordinator.applyQuality(model.stageHighQuality, to: v)
        context.coordinator.sync()
    }

    static func dismantleNSView(_ v: StageSCNView, coordinator: Coordinator) { coordinator.stop() }

    final class Coordinator {
        let model: AppModel
        let scene = SCNScene()
        let camera = SCNNode()
        weak var view: StageSCNView?
        private var itemNodes: [UUID: SCNNode] = [:]
        private var itemSnapshot: [UUID: StageItem] = [:]
        private var fixtureParts: [UUID: (head: SCNNode, lenses: [SCNNode], light: SCNNode?)] = [:]
        private var spotTargets: [UUID: SCNNode] = [:]
        private var timer: Timer?
        private var selection: SCNNode?
        private var lastCameraRequest: UUID?

        init(model: AppModel) {
            self.model = model
            buildRoom()
            camera.camera = SCNCamera()
            camera.camera?.zFar = 200
            camera.camera?.fieldOfView = 50
            camera.camera?.wantsHDR = true
            camera.camera?.wantsExposureAdaptation = false   // keep the venue dark, like a real show
            camera.camera?.exposureOffset = 0
            camera.camera?.bloomIntensity = 0.5
            camera.camera?.bloomThreshold = 0.8
            setCamera("Overview")
            scene.rootNode.addChildNode(camera)
        }

        func start() {
            timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.animate() }
            RunLoop.main.add(timer!, forMode: .common)
            sync()
        }

        func stop() { timer?.invalidate(); timer = nil; view?.isPlaying = false; view?.scene = nil }

        private var quality: Bool?
        /// Light mode: no glow/HDR, no smoothing, 30 fps, fewer real light sources.
        func applyQuality(_ high: Bool, to v: SCNView) {
            guard quality != high else { return }
            quality = high
            v.antialiasingMode = high ? .multisampling4X : .none
            v.preferredFramesPerSecond = high ? 60 : 30
            camera.camera?.wantsHDR = high
            camera.camera?.bloomIntensity = high ? 0.5 : 0
            lightPools = high
        }
        private var lightPools = true

        func setCamera(_ name: String) {
            switch name {
            case "Zoom In", "Zoom Out":
                // move the camera along where it's looking (keeps any orbit you've done)
                let pov = view?.pointOfView ?? camera
                let f = pov.worldFront
                let step: CGFloat = name == "Zoom In" ? 1.4 : -1.4
                pov.position = SCNVector3(pov.position.x + f.x * step, pov.position.y + f.y * step, pov.position.z + f.z * step)
                return
            case "Close-up":
                // in front of the lights, slightly below them, so you see each one tilt and its beams move
                let pts = itemNodes.compactMap { id, n -> SCNVector3? in
                    itemSnapshot[id]?.fixtureID != nil ? n.worldPosition : nil
                }
                guard !pts.isEmpty else { setCamera("Audience"); return }
                let c = SCNVector3(pts.map { $0.x }.reduce(0, +) / CGFloat(pts.count),
                                   pts.map { $0.y }.reduce(0, +) / CGFloat(pts.count),
                                   pts.map { $0.z }.reduce(0, +) / CGFloat(pts.count))
                let spread = pts.map { abs($0.x - c.x) }.max() ?? 1
                // from the front-side (3/4 view): the bars tilt forward and back, which a straight-on
                // view hides; from here you see the heads rotate and the beams swing
                let d = max(3.2, spread * 1.6 + 2)
                camera.position = SCNVector3(c.x + d * 0.75, c.y + 1.3, c.z + d * 0.75)
                camera.look(at: SCNVector3(c.x, c.y + 0.9, c.z))
                view?.pointOfView = camera
                return
            case "Top": camera.position = SCNVector3(0, 16, 1); camera.look(at: SCNVector3(0, 0, -1))
            case "Side": camera.position = SCNVector3(12, 3, -1); camera.look(at: SCNVector3(0, 1.8, -1.5))
            case "Audience": camera.position = SCNVector3(0, 2.3, 8.2); camera.look(at: SCNVector3(0, 2.2, -2))
            default: camera.position = SCNVector3(-7.5, 6.5, 8.5); camera.look(at: SCNVector3(0, 1.2, -1.8))   // Overview
            }
            view?.pointOfView = camera
        }

        private func buildRoom() {
            let floor = SCNFloor()
            floor.reflectivity = 0.05
            floor.materials = [Mat.make(NSColor(white: 0.16, alpha: 1), rough: 0.75)]   // light enough to show beam pools
            scene.rootNode.addChildNode(SCNNode(geometry: floor))
            let wall = SCNNode(geometry: { let g = SCNPlane(width: 40, height: 14); g.materials = [Mat.make(NSColor(white: 0.03, alpha: 1), rough: 1)]; return g }())
            wall.position = SCNVector3(0, 7, -6)
            scene.rootNode.addChildNode(wall)
            let amb = SCNNode(); amb.light = SCNLight(); amb.light?.type = .ambient; amb.light?.intensity = 60
            scene.rootNode.addChildNode(amb)
            let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional; key.light?.intensity = 120
            key.eulerAngles = SCNVector3(-1.0, 0.4, 0)
            scene.rootNode.addChildNode(key)
        }

        /// Rebuild items that were added, removed or changed.
        func sync() {
            if let req = model.stageCameraRequest, req.id != lastCameraRequest {
                lastCameraRequest = req.id
                setCamera(req.name)
            }
            let items = model.stage.items
            let ids = Set(items.map(\.id))
            for (id, n) in itemNodes where !ids.contains(id) {
                n.removeFromParentNode(); itemNodes[id] = nil; itemSnapshot[id] = nil; fixtureParts[id] = nil
            }
            for item in items {
                if let old = itemSnapshot[item.id], let node = itemNodes[item.id] {
                    if old.prop == item.prop && old.size == item.size && old.fixtureID == item.fixtureID && old.onStand == item.onStand {
                        if old != item { place(node, item) }
                        itemSnapshot[item.id] = item
                        continue
                    }
                    node.removeFromParentNode()
                }
                let node = makeNode(item)
                place(node, item)
                scene.rootNode.addChildNode(node)
                itemNodes[item.id] = node
                itemSnapshot[item.id] = item
            }
            // Selection ring
            selection?.removeFromParentNode(); selection = nil
            if model.stageEditing, let sid = model.selectedStageItem, let n = itemNodes[sid] {
                let ring = SCNNode(geometry: { let t = SCNTorus(ringRadius: 0.75, pipeRadius: 0.02)
                    let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = NSColor(calibratedRed: 0.95, green: 0.16, blue: 0.36, alpha: 1)
                    t.materials = [m]; return t }())
                ring.position = SCNVector3(n.position.x, 0.02, n.position.z)
                scene.rootNode.addChildNode(ring)
                selection = ring
            }
        }

        private func place(_ node: SCNNode, _ item: StageItem) {
            node.position = SCNVector3(item.x, item.y, item.z)
            node.eulerAngles = SCNVector3(0, -item.rotation * .pi / 180, item.hanging ? .pi : 0)
            if item.hanging { node.position.y += 0.35 }   // clamp sits below the truss
        }

        private func makeNode(_ item: StageItem) -> SCNNode {
            let root = SCNNode()
            root.name = "item:\(item.id.uuidString)"
            if let kind = item.prop {
                root.addChildNode(Build.prop(kind, size: item.size))
                return root
            }
            guard let fid = item.fixtureID, let fx = model.fixtures.first(where: { $0.id == fid }) else { return root }
            let light = SCNNode()
            light.light = SCNLight()
            light.light?.type = .spot
            // Followspot: crisp hard-edged circle (like the real 75ST). Beam bars: softer.
            light.light?.spotOuterAngle = fx.colorWheel != nil ? 11 : 40
            light.light?.spotInnerAngle = fx.colorWheel != nil ? 10 : 4
            light.light?.intensity = 0
            light.light?.attenuationEndDistance = 20
            if fx.profileName.hasPrefix("SHEHDS") || fx.headCount == 8 {
                let (bar, head, lenses) = Build.shehdsBar()
                root.addChildNode(bar)
                light.eulerAngles.x = -.pi / 2       // point along +Y of the head
                head.addChildNode(light)
                fixtureParts[item.id] = (head, lenses, light)
            } else if fx.colorWheel != nil {
                let (spot, head, lens) = Build.followspot(onStand: item.onStand ?? true)
                root.addChildNode(spot)
                lens.addChildNode(light)
                light.eulerAngles.x = -.pi / 2
                fixtureParts[item.id] = (head, [lens], light)
            } else {
                let (can, head, lens) = Build.genericLight()
                root.addChildNode(can)
                lens.addChildNode(light)
                light.eulerAngles.x = -.pi / 2
                fixtureParts[item.id] = (head, [lens], light)
            }
            return root
        }

        private static let haloImage: NSImage = {
            let size = 128
            let img = NSImage(size: NSSize(width: size, height: size))
            img.lockFocus()
            if let ctx = NSGraphicsContext.current?.cgContext,
               let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0.35), CGColor(gray: 1, alpha: 0)] as CFArray,
                                  locations: [0, 0.25, 1]) {
                let c = CGPoint(x: size / 2, y: size / 2)
                ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(size / 2), options: [])
            }
            img.unlockFocus()
            return img
        }()

        /// A soft glow that always faces the camera, added once per lens.
        static func makeHalo(on lens: SCNNode, big: Bool) -> SCNNode {
            let plane = SCNPlane(width: big ? 0.7 : 0.32, height: big ? 0.7 : 0.32)
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = haloImage
            m.multiply.contents = NSColor.black
            m.blendMode = .add
            m.writesToDepthBuffer = false
            m.isDoubleSided = true
            plane.firstMaterial = m
            let node = SCNNode(geometry: plane)
            node.name = "halo"
            node.position = SCNVector3(0, 0.03, 0)
            node.constraints = [SCNBillboardConstraint()]
            node.castsShadow = false
            lens.addChildNode(node)
            return node
        }

        /// 30 times a second: copy what every light is doing onto its 3D model.
        private func animate() {
            // Only draw while the Stage view is actually on screen (not minimized, hidden or covered)
            guard let w = view?.window, w.isVisible, w.occlusionState.contains(.visible), !w.isMiniaturized else {
                if view?.isPlaying == true { view?.isPlaying = false }
                return
            }
            let now = Date().timeIntervalSinceReferenceDate
            let master = model.blackout ? 0 : model.master
            let haze = model.haze
            let performer = model.stage.items.first { $0.prop == .performer } ?? model.stage.items.first { $0.prop == .micStand }
            let aim = performer.map { SCNVector3($0.x, $0.y + 1.3, $0.z) } ?? SCNVector3(0, 1.8, -1)

            var roomGlow = (r: 0.0, g: 0.0, b: 0.0, n: 0.0)
            SCNTransaction.begin()
            SCNTransaction.disableActions = true
            for item in model.stage.items {
                guard let fid = item.fixtureID, let parts = fixtureParts[item.id],
                      let fi = model.fixtures.firstIndex(where: { $0.id == fid }), fi < model.preview.count else { continue }
                let fx = model.fixtures[fi]
                let rf = model.preview[fi]
                var gate = 1.0
                if rf.strobe > 0 { gate = Int(now * (6 + 8 * rf.strobe) * 2) % 2 == 0 ? 1 : 0 }

                if fx.colorWheel != nil {
                    // Followspot aims at the performer
                    parts.head.look(at: aim, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
                } else {
                    // SHEHDS head tilts through 180°
                    parts.head.eulerAngles.x = CGFloat((rf.tilt - 0.5) * .pi)
                    if fx.channels.contains(.role(.pan, head: 0)) { parts.head.eulerAngles.y = CGFloat((rf.pan - 0.5) * .pi) }
                }

                var avg = (r: 0.0, g: 0.0, b: 0.0, i: 0.0)
                for (h, lens) in parts.lenses.enumerated() {
                    let st = h < rf.heads.count ? rf.heads[h] : (rf.heads.first ?? .off)
                    let level = st.intensity * master * gate
                    let c = NSColor(calibratedRed: st.color.r, green: st.color.g, blue: st.color.b, alpha: 1)
                    // Haze glow around each lens (light scattering in the air right in front of it)
                    let halo = lens.childNode(withName: "halo", recursively: false) ?? Self.makeHalo(on: lens, big: fx.colorWheel != nil)
                    let hk = level * haze * 0.55
                    halo.geometry?.firstMaterial?.multiply.contents = NSColor(calibratedRed: st.color.r * hk, green: st.color.g * hk, blue: st.color.b * hk, alpha: 1)
                    roomGlow.r += st.color.r * level; roomGlow.g += st.color.g * level; roomGlow.b += st.color.b * level; roomGlow.n += 1
                    if let glass = lens.childNode(withName: "lens", recursively: false)?.geometry?.firstMaterial {
                        glass.diffuse.contents = level > 0.02 ? (c.blended(withFraction: 0.35 * (1 - level), of: .black) ?? c) : NSColor(white: 0.12, alpha: 1)
                    }
                    if let beam = lens.childNode(withName: "beam", recursively: false) {
                        for (k, fade) in [1.0, 0.62, 0.34, 0.13].enumerated() {
                            guard let m = beam.childNode(withName: "seg\(k)", recursively: false)?.geometry?.firstMaterial else { continue }
                            // Additive glow: brightness comes from the color itself, so dim the color.
                            // A followspot's narrow shaft is see-through in haze, not a solid bar.
                            let k = level * fade * haze * (fx.colorWheel != nil ? 0.16 : 1)
                            m.diffuse.contents = NSColor(calibratedRed: st.color.r * k, green: st.color.g * k, blue: st.color.b * k, alpha: 1)
                            m.transparency = 1
                        }
                    }
                    avg.r += st.color.r * level; avg.g += st.color.g * level; avg.b += st.color.b * level; avg.i += level
                }
                if let l = parts.light?.light {
                    let n = Double(max(1, parts.lenses.count))
                    let mx = max(avg.r, avg.g, avg.b, 0.0001)
                    l.color = NSColor(calibratedRed: avg.r / mx, green: avg.g / mx, blue: avg.b / mx, alpha: 1)
                    // Light mode skips the floor pools: fewer real lights for the graphics chip
                    l.intensity = lightPools ? CGFloat(avg.i / n * (fx.colorWheel != nil ? 3500 : 4000)) : 0
                }
            }
            // Haze in the room: the air takes on a little of the lights' color and swallows distance
            let n = max(1, roomGlow.n)
            let tint = (r: roomGlow.r / n, g: roomGlow.g / n, b: roomGlow.b / n)
            let base = 0.035 + 0.05 * haze
            scene.fogColor = NSColor(calibratedRed: base + tint.r * 0.10 * haze, green: base + tint.g * 0.10 * haze,
                                     blue: base + tint.b * 0.10 * haze, alpha: 1)
            scene.fogStartDistance = 2
            scene.fogEndDistance = CGFloat(55 - 35 * haze)
            scene.fogDensityExponent = 1.3
            SCNTransaction.commit()
        }
    }
}
