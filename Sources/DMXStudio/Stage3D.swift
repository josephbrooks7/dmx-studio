import SwiftUI
import SceneKit
import AVFoundation
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
    static let aluminum = make(NSColor(white: 0.82, alpha: 1), metal: true, rough: 0.22)
    static let stageTop = make(NSColor(calibratedRed: 0.24, green: 0.24, blue: 0.25, alpha: 1), rough: 0.4)   // black-grey stage deck, a little glossy
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
        let s: CGFloat = 0.12, r: CGFloat = 0.024
        let half = max(0.05,length / 2)
        let alloy = Mat.make(NSColor(white:0.76,alpha:1),metal:true,rough:0.28)
        let weld = Mat.make(NSColor(white:0.66,alpha:1),metal:true,rough:0.46)
        let corners: [(CGFloat,CGFloat)] = [(s,s),(s,-s),(-s,-s),(-s,s)]
        func tube(_ x: CGFloat,_ y: CGFloat,_ z: CGFloat,_ xx: CGFloat,_ yy: CGFloat,_ zz: CGFloat,_ radius: CGFloat,_ material: SCNMaterial) {
            root.addChildNode(pipe(from:SCNVector3(x,y,z),to:SCNVector3(xx,yy,zz),r:radius,material))
        }
        for (y,z) in corners {
            tube(-half,y,z,half,y,z,r,alloy)
            for end in [-half,half] {
                let collar = cyl(r+0.004,0.036,weld)
                collar.eulerAngles.z = .pi/2
                collar.position = SCNVector3(end,y,z); root.addChildNode(collar)
                let pin = cyl(0.006,0.057,Mat.chrome)
                pin.position = SCNVector3(end,y,z); root.addChildNode(pin)
            }
        }
        let bays = max(1,Int(ceil(2*half/0.38)))
        for bay in 0...bays {
            let x = -half + 2*half*CGFloat(bay)/CGFloat(bays)
            for side in 0..<4 {
                let (y,z) = corners[side], (yy,zz) = corners[(side+1)%4]
                if bay == 0 || bay == bays || bay % 2 == 0 {
                    tube(x,y,z,x,yy,zz,0.010,alloy)
                }
                if bay < bays {
                    let nx = -half + 2*half*CGFloat(bay+1)/CGFloat(bays)
                    let flip = (bay+side)%2 == 0
                    tube(x,flip ? y : yy,flip ? z : zz,nx,flip ? yy : y,flip ? zz : z,0.010,alloy)
                    if side % 2 == 0 {
                        tube(x,flip ? yy : y,flip ? zz : z,nx,flip ? y : yy,flip ? z : zz,0.008,alloy)
                    }
                }
            }
        }
        return root
    }

    /// SHEHDS LED Beam 8x12W: black bar, end brackets and a tilting head with 8 lenses.
    /// Returns the root and the tilting head node; each lens has a beam named "beam".
    /// SHEHDS LED Beam 8x12W RGBW, from its spec sheet and photos: 107 × 13 × 8 cm overall.
    /// Rounded end caps, a fixed lower housing with the rear panel (powerCON in/out, DMX in/out,
    /// power switch, fuse, red display + 4 buttons), and a tilting lens bar with 8 lenses.
    /// What the LED backdrop shows: the artist's name big, the song under it, on a dark wall with faint
    /// LED pixels (dark when nothing is playing, so the beams carry the color).
    static func backdropImage(artist: String, title: String, content: ScreenContent = .name, projected: Bool = false) -> NSImage {
        let size = NSSize(width: 1600, height: 900)
        let img = NSImage(size: size)
        img.lockFocus()
        // a projector on a white screen: the name in dark letters on white light
        if projected && content == .name {
            NSColor(white: 0.92, alpha: 1).setFill(); NSRect(origin: .zero, size: size).fill()
            let para = NSMutableParagraphStyle(); para.alignment = .center
            let name = artist.uppercased()
            var fontSize: CGFloat = 190
            var attrs: [NSAttributedString.Key: Any] = [:]
            repeat {
                attrs = [.font: NSFont.systemFont(ofSize: fontSize, weight: .black), .foregroundColor: NSColor(white: 0.08, alpha: 1),
                         .paragraphStyle: para, .kern: fontSize * 0.04]
                fontSize -= 10
            } while (name as NSString).size(withAttributes: attrs).width > size.width * 0.9 && fontSize > 50
            let h = (name as NSString).size(withAttributes: attrs).height
            (name as NSString).draw(in: NSRect(x: 0, y: size.height / 2 - h / 2, width: size.width, height: h), withAttributes: attrs)
            img.unlockFocus(); return img
        }
        NSColor(white: 0.03, alpha: 1).setFill(); NSRect(origin: .zero, size: size).fill()
        // show visuals: soft light rays bursting from the middle (tinted live by the lights' colors,
        // like the content on a real LED wall), dark at the edges
        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        if content == .off { img.unlockFocus(); return img }
        if content == .glow, let g = NSGradient(colors: [NSColor(white: 0.5, alpha: 1), NSColor(white: 0.12, alpha: 1), NSColor(white: 0.03, alpha: 1)]) {
            g.draw(fromCenter: center, radius: 0, toCenter: center, radius: size.width * 0.65, options: [])
        }
        if false, let g = NSGradient(colors: [NSColor(white: 0.55, alpha: 1), NSColor(white: 0.12, alpha: 1), NSColor(white: 0.03, alpha: 1)]) {
            g.draw(fromCenter: center, radius: 0, toCenter: center, radius: size.width * 0.6, options: [])
        }
        for k in 0..<0 {
            let a = Double(k) / 64 * 2 * .pi + (k % 2 == 0 ? 0.03 : 0)
            let len = size.width * (0.35 + 0.3 * Double((k * 37) % 11) / 10)
            let p = NSBezierPath()
            p.move(to: NSPoint(x: center.x + cos(a) * 40, y: center.y + sin(a) * 40))
            p.curve(to: NSPoint(x: center.x + cos(a + 0.25) * len, y: center.y + sin(a + 0.25) * len),
                    controlPoint1: NSPoint(x: center.x + cos(a) * len * 0.4, y: center.y + sin(a) * len * 0.4),
                    controlPoint2: NSPoint(x: center.x + cos(a + 0.15) * len * 0.75, y: center.y + sin(a + 0.15) * len * 0.75))
            p.lineWidth = CGFloat(3 + (k % 4) * 2)
            p.lineCapStyle = .round
            NSColor(white: 0.55 + 0.4 * Double(k % 3) / 2, alpha: 0.55).setStroke()
            p.stroke()
        }
        // LED panel grid
        NSColor(white: 0.07, alpha: 1).setFill()
        for x in stride(from: 0, to: size.width, by: 200) { NSRect(x: x, y: 0, width: 2, height: size.height).fill() }
        for y in stride(from: 0, to: size.height, by: 225) { NSRect(x: 0, y: y, width: size.width, height: 2).fill() }
        if !artist.isEmpty {
            let para = NSMutableParagraphStyle(); para.alignment = .center
            let glow = NSShadow(); glow.shadowColor = NSColor(calibratedRed: 1, green: 0.25, blue: 0.45, alpha: 0.9); glow.shadowBlurRadius = 28
            let name = artist.uppercased()
            if name.isEmpty { img.unlockFocus(); return img }
            var fontSize: CGFloat = 190
            var attrs: [NSAttributedString.Key: Any] = [:]
            repeat {
                attrs = [.font: NSFont.systemFont(ofSize: fontSize, weight: .black), .foregroundColor: NSColor.white,
                         .paragraphStyle: para, .shadow: glow, .kern: fontSize * 0.04]
                fontSize -= 10
            } while (name as NSString).size(withAttributes: attrs).width > size.width * 0.9 && fontSize > 50
            let h = (name as NSString).size(withAttributes: attrs).height
            (name as NSString).draw(in: NSRect(x: 0, y: size.height / 2 - h / 2 + 40, width: size.width, height: h), withAttributes: attrs)
            if false, !artist.isEmpty && !title.isEmpty {   // the backdrop shows the artist only, not the track name
                let sub: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 64, weight: .semibold),
                                                          .foregroundColor: NSColor(white: 0.8, alpha: 1), .paragraphStyle: para]
                (title as NSString).draw(in: NSRect(x: 40, y: size.height / 2 - h / 2 - 70, width: size.width - 80, height: 90), withAttributes: sub)
            }
        }
        img.unlockFocus()
        return img
    }

    /// A soft warm glow that always faces the camera (lamps, sconces): light without an extra light source
    static func warmHalo(_ size: CGFloat, at p: SCNVector3) -> SCNNode {
        let g = SCNPlane(width: size, height: size)
        let m = SCNMaterial(); m.lightingModel = .constant; m.blendMode = .add; m.writesToDepthBuffer = false
        m.diffuse.contents = Stage3DView.Coordinator.wallGlowImage(NSColor(calibratedRed: 1, green: 0.62, blue: 0.3, alpha: 1))
        g.materials = [m]
        let n = SCNNode(geometry: g); n.position = p
        n.constraints = [SCNBillboardConstraint()]
        return n
    }

    /// The wall behind the band. Screens named "backdropscreen…" get the artist's name drawn on them.
    static func backdrop(_ style: BackdropStyle, size: Double, panels: [Int]? = nil) -> SCNNode {
        let s = CGFloat(size)
        let root = SCNNode()
        func screen(_ w: CGFloat, _ h: CGFloat, glow: Bool) -> SCNNode {
            let g = SCNPlane(width: w, height: h)
            let m = SCNMaterial()
            // an LED wall / projection gives off its own light; a banner is only seen when lights hit it
            m.lightingModel = glow ? .constant : .physicallyBased
            if !glow { m.roughness.contents = 0.95; m.metalness.contents = 0.0 }
            m.diffuse.contents = backdropImage(artist: "", title: "")
            g.materials = [m]
            let n = SCNNode(geometry: g); n.name = "backdropscreen"
            return n
        }
        switch style {
        case .ledWall:
            // LED wall on the stage behind the band: 16:9, 5.3 m × 3 m, or built from 50 cm panels (columns × rows)
            let w: CGFloat = panels.map { CGFloat($0[0]) * 0.5 } ?? 5.3 * s
            let h: CGFloat = panels.map { CGFloat($0[1]) * 0.5 } ?? 3.0 * s
            let frame = box(w + 0.12, h + 0.12, 0.12, Mat.black); frame.position = SCNVector3(0, h / 2 + 0.05, 0); root.addChildNode(frame)
            let sc = screen(w, h, glow: true); sc.position = SCNVector3(0, h / 2 + 0.05, 0.062); root.addChildNode(sc)
        case .projection:
            // a white screen flown above the performer (bottom edge ~2.4 m up), so heads don't block it
            let w: CGFloat = 4.2 * s, h: CGFloat = w * 9 / 16, bottom: CGFloat = 2.4
            let border = box(w + 0.16, h + 0.16, 0.03, Mat.black); border.position = SCNVector3(0, bottom + h / 2, 0); root.addChildNode(border)
            let sc = screen(w, h, glow: true); sc.position = SCNVector3(0, bottom + h / 2, 0.017)
            sc.opacity = 0.8   // projected light is softer than an LED panel
            root.addChildNode(sc)
            // cables / pipe it hangs from
            for x in [-w / 2 + 0.2, w / 2 - 0.2] {
                root.addChildNode(pipe(from: SCNVector3(x, bottom + h + 0.08, 0), to: SCNVector3(x, bottom + h + 0.9, 0), r: 0.006, Mat.darkGray))
            }
            root.addChildNode(pipe(from: SCNVector3(-w / 2 - 0.2, bottom + h + 0.9, 0), to: SCNVector3(w / 2 + 0.2, bottom + h + 0.9, 0), r: 0.025, Mat.aluminum))
            // black drape behind, down to the stage
            let drape = box(w + 1.2, bottom + h + 0.9, 0.02, Mat.black); drape.position = SCNVector3(0, (bottom + h + 0.9) / 2, -0.25); root.addChildNode(drape)
        case .wallProjection:
            // a big projection right on the back wall (club / lounge): 16:9, from just above the stage up
            let w: CGFloat = 6.4 * s, h: CGFloat = w * 9 / 16, bottom: CGFloat = 0.45
            let sc = screen(w, h, glow: true); sc.position = SCNVector3(0, bottom + h / 2, 0.01)
            sc.opacity = 0.85
            root.addChildNode(sc)
        case .banner:
            // a printed fabric banner hung from a pipe, with grommets; lit only by the stage lights
            let w: CGFloat = 4.6 * s, h: CGFloat = 1.6 * s, top: CGFloat = 3.6
            let sc = screen(w, h, glow: false); sc.position = SCNVector3(0, top - h / 2, 0.01); root.addChildNode(sc)
            root.addChildNode(pipe(from: SCNVector3(-w / 2 - 0.15, top + 0.03, 0), to: SCNVector3(w / 2 + 0.15, top + 0.03, 0), r: 0.02, Mat.aluminum))
            for k in 0..<7 {
                let x = -w / 2 + 0.15 + CGFloat(k) * (w - 0.3) / 6
                let gr = cyl(0.015, 0.01, Mat.aluminum); gr.eulerAngles.x = .pi / 2; gr.position = SCNVector3(x, top - 0.06, 0.015); root.addChildNode(gr)
            }
            let drape = box(w + 1.2, top + 0.2, 0.02, Mat.black); drape.position = SCNVector3(0, (top + 0.2) / 2, -0.25); root.addChildNode(drape)
        case .blank:
            // a plain black drape with soft folds
            let w: CGFloat = 5.8 * s, h: CGFloat = 3.8
            let back = box(w, h, 0.02, Mat.black); back.position = SCNVector3(0, h / 2, -0.05); root.addChildNode(back)
            var x = -w / 2 + 0.15
            while x < w / 2 {
                let fold = cyl(0.06, h, Mat.black); fold.position = SCNVector3(x, h / 2, 0); root.addChildNode(fold)
                x += 0.3
            }
        }
        return root
    }

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

        // Lower housing with the rear panel (ports, display) on the back, facing upstage (-z), away from the audience
        let baseH: CGFloat = 0.06
        let base = box(inner, baseH, depth - 0.006, Mat.black, chamfer: 0.003)
        base.position = SCNVector3(0, baseH / 2, 0); root.addChildNode(base)
        let face = -(depth / 2 - 0.002)
        func onPanel(_ n: SCNNode, x: CGFloat, y: CGFloat) {
            n.position = SCNVector3(-x, y, face); root.addChildNode(n)   // mirrored: reads left-to-right from behind
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
        // Open tapered shells instead of closed cone sections: no bright horizontal caps.
        // A soft radial falloff reduces the hard rectangular edges of overlapping beams.
        for i in 0..<segs {
            let d0 = length * Double(i) / Double(segs), d1 = length * Double(i + 1) / Double(segs)
            let r0 = CGFloat(0.02 + d0 * tanH * 0.46)
            let r1 = CGFloat(0.02 + d1 * tanH * 0.46)
            let sides = 20
            var vertices: [SCNVector3] = []
            var normals: [SCNVector3] = []
            var indices: [Int32] = []
            for k in 0...sides {
                let a = CGFloat(k) * 2 * .pi / CGFloat(sides)
                let x = cos(a), z = sin(a)
                vertices.append(SCNVector3(x*r0, CGFloat(d0), z*r0))
                vertices.append(SCNVector3(x*r1, CGFloat(d1), z*r1))
                normals.append(SCNVector3(x,0,z)); normals.append(SCNVector3(x,0,z))
                if k < sides {
                    let j = Int32(k*2)
                    indices += [j,j+1,j+2,j+1,j+3,j+2]
                }
            }
            let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
            let g = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices),SCNGeometrySource(normals: normals)], elements: [element])
            let material = Mat.beam()
            g.materials = [material]
            let n = SCNNode(geometry: g)
            n.name = "seg\(i)"
            n.castsShadow = false
            beam.addChildNode(n)
        }
        return beam
    }

    // Stylized articulated stage avatar; all geometry remains lit by the actual stage lights.
    private static var avatarCache: [URL: SCNNode] = [:]
    private static let avatarCacheLock = NSLock()

    private static func avatarTemplate(_ url: URL) -> SCNNode? {
        avatarCacheLock.lock()
        defer { avatarCacheLock.unlock() }
        if let cached = avatarCache[url] { return cached }
        guard let scene = try? SCNScene(url: url, options: nil) else { return nil }
        let node = SCNNode()
        for child in scene.rootNode.childNodes { node.addChildNode(child.clone()) }
        if avatarCache.count >= 12 { avatarCache.removeAll() }
        avatarCache[url] = node
        return node
    }

    static func performer(_ a: PerformerAppearance) -> SCNNode {
        let root = SCNNode()
        // Imported self-contained USDZ assets retain their authored meshes and materials.
        let avatarFeminine = a.bodyStyle == "Feminine"
        let builtInName = avatarFeminine ? (a.skin >= 3 ? "priya_casual" : "emma_casual") :
            (a.skin >= 3 || a.clothingStyle == "Formal" ? "marcus_formal" : "andre_casual")
        let bundled = Bundle.main.url(forResource: builtInName, withExtension: "usdz", subdirectory: "Characters")
        let candidates = [a.modelPath.map { URL(fileURLWithPath: $0) }, bundled].compactMap { $0 }
        for url in candidates {
            guard let template = avatarTemplate(url) else { continue }
            let mesh = template.clone()
            let bounds = mesh.boundingBox
            let h = bounds.max.y - bounds.min.y
            if h.isFinite && h > 0.001 {
                let scale = CGFloat(a.height) / h
                // Preserve authored textures while allowing independent body width/depth.
                let build = CGFloat(min(max(a.build, 0.7), 1.4))
                let width = scale * build
                let depth = scale * sqrt(build)
                mesh.scale = SCNVector3(width, scale, depth)
                mesh.position = SCNVector3(-(bounds.min.x+bounds.max.x)*width/2, -bounds.min.y*scale, -(bounds.min.z+bounds.max.z)*depth/2)
                root.addChildNode(mesh)
                // Independent accessory geometry leaves imported skin/clothing textures untouched.
                // A hat is placed using the normalized avatar bounds, not a guessed bone name.
                if a.accessory == "Top Hat" && a.modelPath == nil {
                    let hat = SCNNode()
                    let felt = Mat.make(NSColor(white: 0.045, alpha: 1), rough: 0.85)
                    let brim = SCNCylinder(radius: 0.145 * build, height: 0.018)
                    brim.materials = [felt]
                    let brimNode = SCNNode(geometry: brim)
                    hat.addChildNode(brimNode)
                    let crown = SCNCylinder(radius: 0.095 * build, height: 0.13)
                    crown.materials = [felt]
                    let crownNode = SCNNode(geometry: crown)
                    crownNode.position.y = 0.073
                    hat.addChildNode(crownNode)
                    hat.position.y = CGFloat(a.height) - 0.025
                    root.addChildNode(hat)
                }
                return root
            }
        }
        let skinColors: [NSColor] = [
            NSColor(calibratedRed:0.96,green:0.78,blue:0.66,alpha:1),
            NSColor(calibratedRed:0.83,green:0.62,blue:0.46,alpha:1),
            NSColor(calibratedRed:0.66,green:0.42,blue:0.27,alpha:1),
            NSColor(calibratedRed:0.49,green:0.29,blue:0.19,alpha:1),
            NSColor(calibratedRed:0.32,green:0.18,blue:0.12,alpha:1),
            NSColor(calibratedRed:0.20,green:0.11,blue:0.08,alpha:1)]
        let outfits: [NSColor] = [.black,.systemRed,.systemBlue,.white,.systemPurple,.systemGreen]
        let hairs: [NSColor] = [.black,.brown,NSColor(calibratedRed:0.74,green:0.55,blue:0.28,alpha:1),.systemRed,.systemBlue,.lightGray]
        func pick(_ cs: [NSColor], _ i: Int) -> NSColor { cs[min(max(i,0),cs.count-1)] }
        let skin = Mat.make(pick(skinColors,a.skin),rough:0.72)
        let cloth = Mat.make(pick(outfits,a.outfit),rough:0.82)
        let hair = Mat.make(pick(hairs,a.hairColor),rough:0.68)
        let pants = Mat.make(NSColor(white:0.13,alpha:1),rough:0.9)
        func place(_ n: SCNNode,_ x: CGFloat,_ y: CGFloat,_ z: CGFloat) {
            n.position = SCNVector3(x,y,z); root.addChildNode(n)
        }
        func oval(_ x: CGFloat,_ y: CGFloat,_ z: CGFloat,_ rx: CGFloat,_ ry: CGFloat,_ rz: CGFloat,_ mat: SCNMaterial) {
            let g = SCNSphere(radius:1); g.segmentCount = 24; g.materials = [mat]
            let n = SCNNode(geometry:g); n.scale = SCNVector3(rx,ry,rz); place(n,x,y,z)
        }
        func limb(_ from: SCNVector3,_ to: SCNVector3,_ r: CGFloat,_ mat: SCNMaterial) {
            let dx = to.x-from.x, dy = to.y-from.y, dz = to.z-from.z
            let length = sqrt(dx*dx+dy*dy+dz*dz)
            let g = SCNCapsule(capRadius:r,height:length+2*r); g.materials = [mat]
            let n = SCNNode(geometry:g)
            n.position = SCNVector3((from.x+to.x)/2,(from.y+to.y)/2,(from.z+to.z)/2)
            n.look(at:to,up:SCNVector3(0,0,1),localFront:SCNVector3(0,1,0))
            root.addChildNode(n)
        }
        let seated = a.role == .drummer
        let hip: CGFloat = seated ? 0.59 : 0.91
        let shoulder = hip+0.43
        let headY = shoulder+0.23
        let feminine = a.bodyStyle == "Feminine"
        let neutral = a.bodyStyle == "Androgynous"
        let shoulderWidth: CGFloat = feminine ? 0.155 : (neutral ? 0.17 : 0.19)
        let hipWidth: CGFloat = feminine ? 0.185 : 0.16
        let fashion = a.clothingStyle ?? "Casual"
        let wide: CGFloat = a.pose == "Wide" ? 1.65 : (a.pose == "Performance" ? 1.35 : 1)
        // Smooth tapered torso surface with anatomically shaped cross sections.
        func torso(_ sections: [(CGFloat,CGFloat,CGFloat)], _ mat: SCNMaterial) {
            let sides = 32
            var vertices: [SCNVector3] = []
            var indices: [Int32] = []
            for (y,rx,rz) in sections {
                for j in 0..<sides {
                    let q = CGFloat(j)*2 * .pi/CGFloat(sides)
                    vertices.append(SCNVector3(cos(q)*rx,y,sin(q)*rz))
                }
            }
            for row in 0..<(sections.count-1) {
                for j in 0..<sides {
                    let p = Int32(row*sides+j), q = Int32(row*sides+(j+1)%sides)
                    let v = p+Int32(sides), w = q+Int32(sides)
                    indices += [p,v,q,q,v,w]
                }
            }
            let data = indices.withUnsafeBufferPointer { Data(buffer:$0) }
            let geo = SCNGeometry(sources:[SCNGeometrySource(vertices:vertices)],elements:[SCNGeometryElement(data:data,primitiveType:.triangles,primitiveCount:indices.count/3,bytesPerIndex:4)])
            geo.materials = [mat]
            let node = SCNNode(geometry:geo); root.addChildNode(node)
        }
        let waist: CGFloat = feminine ? 0.105 : 0.145
        torso([(hip-0.05,hipWidth,0.10),(hip+0.07,hipWidth,0.11),(hip+0.17,waist,0.09),(hip+0.31,shoulderWidth,0.12),(shoulder,shoulderWidth,0.09),(shoulder+0.07,0.055,0.055)],cloth)
        oval(0,hip,0,hipWidth,0.11,0.105,pants)
        if fashion == "Rock Jacket" || fashion == "Formal" {
            for side in [CGFloat(-1),CGFloat(1)] {
                let lapel = box(0.045,0.23,0.018,Mat.darkGray,chamfer:0.007)
                lapel.eulerAngles.z = side*0.24
                place(lapel,side*0.065,hip+0.30,0.115)
            }
            for j in 0..<4 { oval(0,hip+0.12+CGFloat(j)*0.055,0.12,0.008,0.008,0.004,Mat.aluminum) }
        }
        if fashion == "Punk" || fashion == "Glam" || fashion == "Fantasy" {
            place(cyl(hipWidth+0.008,0.035,Mat.black),0,hip+0.015,0)
            for j in 0..<9 { oval(-0.12+CGFloat(j)*0.03,hip+0.015,0.107,0.008,0.008,0.005,Mat.aluminum) }
        }
        place(cyl(0.052,0.11,skin),0,shoulder+0.095,0)
        oval(0,headY,0,0.102,0.135,0.103,skin)
        for side in [CGFloat(-1),CGFloat(1)] {
            oval(side*0.102,headY-0.005,0,0.018,0.035,0.025,skin)
            oval(side*0.040,headY+0.016,0.094,0.018,0.011,0.009,Mat.make(.white))
            oval(side*0.040,headY+0.016,0.103,0.008,0.009,0.004,Mat.darkGray)
            oval(side*0.040,headY+0.038,0.092,0.022,0.004,0.005,hair)
            let knee = SCNVector3(side*0.13*wide,seated ? 0.48 : 0.49,seated ? 0.32 : 0.04)
            let ankle = SCNVector3(side*0.15*wide,0.10,seated ? 0.44 : 0.03)
            limb(SCNVector3(side*0.10,hip,0),knee,0.073,pants)
            limb(knee,ankle,0.052,pants)
            oval(side*0.15*wide,0.055,seated ? 0.49 : 0.08,0.068,0.055,0.13,Mat.black)
            let playing = a.role == .guitarist || a.role == .bassist || a.role == .keyboardist || seated
            let elbow = SCNVector3(side*0.27,shoulder-0.19,playing ? 0.12 : 0)
            let hand = SCNVector3(side*(playing ? 0.20 : 0.27),shoulder-(playing ? 0.32 : 0.47),playing ? 0.28 : 0.02)
            limb(SCNVector3(side*shoulderWidth,shoulder,0),elbow,0.058,cloth)
            limb(elbow,hand,0.038,skin)
            oval(hand.x,hand.y,hand.z,0.041,0.06,0.033,skin)
        }
        oval(0,headY-0.005,0.105,0.018,0.026,0.025,skin)
        oval(0,headY-0.052,0.091,0.032,0.006,0.009,Mat.darkGray)
        if a.hair != .shaved {
            oval(0,headY+0.075,-0.017,0.111,0.082,0.108,hair)
            if a.hair == .long { oval(0,headY-0.075,-0.085,0.12,0.21,0.06,hair) }
            if a.hair == .swept { oval(0.04,headY+0.10,0.01,0.10,0.055,0.10,hair) }
            if a.hair == .ponytail { oval(0,headY-0.07,-0.13,0.055,0.18,0.055,hair) }
            if a.hair == .curly {
                for j in 0..<12 {
                    let q = CGFloat(j)*2 * .pi/12
                    oval(cos(q)*0.09,headY+0.065,sin(q)*0.09,0.045,0.055,0.045,hair)
                }
            }
            if a.hair == .spiked {
                for j in 0..<7 {
                    let q = CGFloat(j)*2 * .pi/7
                    let g = SCNCone(topRadius:0,bottomRadius:0.035,height:0.13); g.materials = [hair]
                    let n = SCNNode(geometry:g); n.eulerAngles.z = cos(q)*0.5
                    place(n,cos(q)*0.07,headY+0.16,sin(q)*0.07)
                }
            }
        }
        switch a.accessory ?? "None" {
        case "Top Hat":
            place(cyl(0.145,0.015,Mat.black),0,headY+0.115,0)
            place(cyl(0.098,0.15,Mat.black),0,headY+0.19,0)
        case "Glasses":
            for side in [CGFloat(-1),CGFloat(1)] { oval(side*0.044,headY+0.016,0.11,0.040,0.027,0.009,Mat.black) }
            place(box(0.03,0.008,0.012,Mat.black),0,headY+0.016,0.11)
        case "Choker":
            place(cyl(0.057,0.025,Mat.black),0,shoulder+0.095,0)
        case "Wings":
            for side in [CGFloat(-1),CGFloat(1)] {
                let g = SCNSphere(radius:1); g.materials = [cloth]
                let n = SCNNode(geometry:g); n.scale = SCNVector3(0.21,0.36,0.025); n.eulerAngles.z = -side*0.65
                place(n,side*0.25,hip+0.35,-0.14)
            }
        default: break
        }
        if a.role == .guitarist || a.role == .bassist {
            let guitar = SCNNode()
            let g = SCNSphere(radius:1); g.materials = [cloth]
            let body = SCNNode(geometry:g); body.scale = SCNVector3(0.16,0.22,0.043); guitar.addChildNode(body)
            let neck = box(0.065,a.role == .bassist ? 0.66 : 0.51,0.028,Mat.darkGray)
            neck.position = SCNVector3(0,0.39,0); guitar.addChildNode(neck)
            let peg = box(0.10,0.15,0.03,Mat.aluminum,chamfer:0.008); peg.position = SCNVector3(0,0.72,0); guitar.addChildNode(peg)
            guitar.eulerAngles.z = -.pi/2.8; place(guitar,-0.13,hip+0.13,0.22)
        } else if a.role == .keyboardist {
            let keys = box(0.88,0.08,0.30,Mat.black,chamfer:0.01); place(keys,0,hip+0.15,0.42)
            for i in 0..<24 { placeKey(root,i,hip+0.20) }
            for side in [CGFloat(-1),CGFloat(1)] { limb(SCNVector3(side*0.31,0.04,0.42),SCNVector3(-side*0.31,hip+0.10,0.42),0.018,Mat.black) }
        } else if seated {
            place(cyl(0.16,0.07,Mat.black),0,0.49,-0.10)
            place(cyl(0.024,0.46,Mat.chrome),0,0.23,-0.10)
        }
        let height = CGFloat(min(max(a.height,1.4),2.1)/1.75)
        let width = CGFloat(min(max(a.build,0.7),1.4))
        root.scale = SCNVector3(width*height,height,height)
        return root
    }
    private static func placeKey(_ root: SCNNode,_ i: Int,_ y: CGFloat) {
        let n = box(0.029,0.012,0.17,Mat.make(.white))
        n.position = SCNVector3(-0.35+CGFloat(i)*0.03,y,0.48); root.addChildNode(n)
    }

    static func prop(_ kind: PropKind, size: Double) -> SCNNode {
        let s = CGFloat(size)
        switch kind {
        case .stage:
            let root = SCNNode()
            let width = 6 * s
            let skirt = Mat.make(NSColor(white: 0.025, alpha: 1), rough: 0.96)
            let deck = Mat.make(NSColor(white: 0.07, alpha: 1), rough: 0.82)
            let trim = Mat.make(NSColor(white: 0.13, alpha: 1), metal: true, rough: 0.68)
            let base = box(width, 0.56, 4, skirt, chamfer: 0.012)
            base.position = SCNVector3(0, 0.28, 0); root.addChildNode(base)
            // Modular black touring deck panels, with small seams visible at normal zoom.
            let cols = max(1, Int(ceil(width / 1.5)))
            for i in 0..<cols { for j in 0..<2 {
                let dx = width / CGFloat(cols)
                let panel = box(dx - 0.008, 0.04, 1.992, deck, chamfer: 0.002)
                panel.position = SCNVector3(-width/2 + dx*(CGFloat(i)+0.5), 0.58, -1 + CGFloat(j)*2)
                root.addChildNode(panel)
            } }
            for z in [CGFloat(-1.995),1.995] {
                let rim = box(width, 0.045, 0.015, trim)
                rim.position = SCNVector3(0, 0.56, z); root.addChildNode(rim)
            }
            for x in [-width/2,width/2] {
                let rim = box(0.015, 0.045, 4, trim)
                rim.position = SCNVector3(x, 0.56, 0); root.addChildNode(rim)
            }
            // Black fabric skirt with restrained vertical folds.
            let folds = max(2, Int(ceil(width / 0.17)))
            for i in 0..<folds {
                let n = box(0.028, 0.50, 0.014, skirt, chamfer: 0.005)
                n.position = SCNVector3(-width/2 + width*(CGFloat(i)+0.5)/CGFloat(folds), 0.27, 2.002)
                root.addChildNode(n)
            }
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
            let castIron = Mat.make(NSColor(white: 0.075, alpha: 1), metal: true, rough: 0.82)
            let shaft = Mat.make(NSColor(white: 0.045, alpha: 1), metal: true, rough: 0.32)
            func place(_ n: SCNNode, _ y: CGFloat, _ z: CGFloat = 0) {
                n.position = SCNVector3(0,y,z); root.addChildNode(n)
            }
            // Weighted cast-iron round base with a domed shoulder and concentric relief.
            place(cyl(0.155,0.018,Mat.darkGray),0.009)
            let base = SCNCone(topRadius:0.112,bottomRadius:0.155,height:0.045)
            base.radialSegmentCount = 64; base.materials = [castIron]
            place(SCNNode(geometry:base),0.038)
            for radius in [CGFloat(0.044),0.068,0.092] {
                let g = SCNTorus(ringRadius:radius,pipeRadius:0.002)
                g.materials = [Mat.darkGray]; place(SCNNode(geometry:g),0.061)
            }
            place(cyl(0.027,0.017,shaft),0.069)
            place(cyl(0.012,0.87,shaft),0.51)
            place(cyl(0.009,0.52,shaft),1.19)
            // Knurled telescopic height adjustment collar.
            place(cyl(0.019,0.065,Mat.darkGray),0.96)
            for i in 0..<16 {
                let q = CGFloat(i)*2 * .pi/16
                let rib = cyl(0.0017,0.050,shaft)
                rib.position = SCNVector3(cos(q)*0.019,0.96,sin(q)*0.019)
                root.addChildNode(rib)
            }
            place(cyl(0.012,0.018,shaft),1.45)
            place(cyl(0.008,0.014,Mat.aluminum),1.465)
            // Short angled vocal microphone clip and handheld dynamic mic.
            let clip = SCNNode(); clip.position = SCNVector3(0,1.49,0)
            clip.eulerAngles.x = -.pi/3
            let holder = cyl(0.018,0.045,Mat.darkGray); clip.addChildNode(holder)
            let handle = cyl(0.012,0.14,shaft); handle.position = SCNVector3(0,0.025,0); clip.addChildNode(handle)
            let mesh = SCNSphere(radius:0.023); mesh.segmentCount = 24; mesh.materials = [Mat.aluminum]
            let grille = SCNNode(geometry:mesh); grille.position = SCNVector3(0,0.102,0); clip.addChildNode(grille)
            let band = cyl(0.023,0.005,Mat.darkGray); band.position = SCNVector3(0,0.102,0); clip.addChildNode(band)
            root.addChildNode(clip)
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
        case .backdrop:
            return backdrop(.ledWall, size: size)
        case .lineArray:
            let root = SCNNode()
            let towerH: CGFloat = 5.2 * s
            let t = truss(length:towerH); t.eulerAngles.z = .pi/2
            t.position = SCNVector3(0,towerH/2,-0.55); root.addChildNode(t)
            let base = box(0.9,0.03,0.9,Mat.aluminum); base.position = SCNVector3(0,0.015,-0.55); root.addChildNode(base)
            let arm = truss(length:0.9); arm.eulerAngles.y = .pi/2; arm.position = SCNVector3(0,towerH-0.1,-0.1); root.addChildNode(arm)
            // Reusable perforated metal grille texture, backed by recessed driver silhouettes.
            let img = NSImage(size:NSSize(width:256,height:128))
            img.lockFocus()
            NSColor(white:0.10,alpha:1).setFill(); NSRect(x:0,y:0,width:256,height:128).fill()
            NSColor(white:0.025,alpha:1).setFill()
            for row in 0..<24 { for col in 0..<48 {
                NSBezierPath(ovalIn:NSRect(x:CGFloat(col)*5.4+CGFloat(row%2)*2.7,y:CGFloat(row)*5.4,width:3.1,height:3.1)).fill()
            } }
            img.unlockFocus()
            let grilleMat = Mat.make(NSColor(white:0.10,alpha:1),metal:true,rough:0.68)
            grilleMat.diffuse.contents = img
            func put(_ n: SCNNode,_ p: SCNNode,_ x: CGFloat,_ y: CGFloat,_ z: CGFloat) {
                n.position = SCNVector3(x,y,z); p.addChildNode(n)
            }
            func cabinet(_ w: CGFloat,_ h: CGFloat,_ d: CGFloat,_ sub: Bool) -> SCNNode {
                let n = SCNNode()
                put(box(w,h,d,Mat.black,chamfer:0.018),n,0,0,0)
                put(box(w-0.065,h-0.055,0.014,grilleMat,chamfer:0.006),n,0,0,d/2+0.008)
                for side in [CGFloat(-1),CGFloat(1)] {
                    put(box(0.035,h-0.025,0.025,Mat.darkGray),n,side*(w/2-0.022),0,d/2+0.014)
                    put(box(0.014,h*0.34,d*0.34,Mat.darkGray,chamfer:0.008),n,side*(w/2+0.002),0,-d*0.12)
                    for yy in [-h*0.32,h*0.32] {
                        let bolt = cyl(0.009,0.012,Mat.aluminum); bolt.eulerAngles.z = .pi/2
                        put(bolt,n,side*(w/2+0.01),yy,-d*0.27)
                    }
                }
                if sub {
                    for xx in [-w*0.31,w*0.31] { put(box(0.18,0.035,d*0.75,Mat.darkGray),n,xx,-h/2-0.012,0) }
                } else {
                    put(box(0.08,0.028,0.009,Mat.darkGray),n,0,-h*0.39,d/2+0.019)
                }
                return n
            }
            for k in 0..<2 { put(cabinet(1.1,0.60,0.85,true),root,0,0.32+CGFloat(k)*0.64,0) }
            let hang = SCNNode(); put(hang,root,0,towerH-0.35,0.05)
            put(box(1.15,0.065,0.62,Mat.darkGray),hang,0,0,0)
            var yy: CGFloat = -0.22, zz: CGFloat = 0, angle: CGFloat = 0
            for k in 0..<5 {
                angle += k == 0 ? 0 : 0.035+CGFloat(k)*0.025
                let cab = cabinet(1.06,0.32,0.55,false)
                cab.eulerAngles.x = -angle
                put(cab,hang,0,yy,zz)
                for side in [CGFloat(-1),CGFloat(1)] {
                    put(box(0.016,0.22,0.045,Mat.darkGray),cab,side*0.54,-0.13,-0.18)
                }
                yy -= 0.33*cos(angle); zz -= 0.33*sin(angle)
            }
            for xx in [CGFloat(-0.4),CGFloat(0.4)] {
                root.addChildNode(pipe(from:SCNVector3(xx,towerH-0.10,0.05),to:SCNVector3(xx,towerH-0.33,0.05),r:0.009,Mat.darkGray))
            }
            return root
        case .curtain:
            // red velvet drape with deep folds, floor to ceiling (size = width in meters)
            let root = SCNNode()
            let w = CGFloat(size), h: CGFloat = 4.6
            let velvet = Mat.make(NSColor(calibratedRed: 0.55, green: 0.02, blue: 0.04, alpha: 1), rough: 0.85)
            let back = box(w, h, 0.02, velvet); back.position = SCNVector3(0, h / 2, -0.06); root.addChildNode(back)
            var x = -w / 2 + 0.1
            while x < w / 2 {
                let fold = cyl(0.085, h, velvet); fold.position = SCNVector3(x, h / 2, 0); root.addChildNode(fold)
                x += 0.22
            }
            return root
        case .discoBall:
            // a mirror ball on a short rod (hangs from the ceiling at its height)
            let root = SCNNode()
            let ball = SCNNode(geometry: { let g = SCNSphere(radius: 0.28); g.segmentCount = 24
                let m = SCNMaterial(); m.lightingModel = .physicallyBased; m.metalness.contents = 1.0; m.roughness.contents = 0.15
                m.diffuse.contents = NSColor(white: 0.85, alpha: 1); g.materials = [m]; return g }())
            ball.name = "discoball"
            root.addChildNode(ball)
            root.addChildNode(pipe(from: SCNVector3(0, 0.28, 0), to: SCNVector3(0, 1.2, 0), r: 0.008, Mat.darkGray))
            let spin = CABasicAnimation(keyPath: "eulerAngles.y"); spin.fromValue = 0; spin.toValue = Double.pi * 2
            spin.duration = 12; spin.repeatCount = .infinity
            ball.addAnimation(spin, forKey: "spin")
            return root
        case .cabaretTable:
            // a small round cocktail table with a candle and three bentwood chairs
            let root = SCNNode()
            let wood = Mat.make(NSColor(calibratedRed: 0.08, green: 0.05, blue: 0.04, alpha: 1), rough: 0.5)
            let top = cyl(0.32, 0.03, wood); top.position = SCNVector3(0, 0.74, 0); root.addChildNode(top)
            root.addChildNode(pipe(from: SCNVector3(0, 0, 0), to: SCNVector3(0, 0.74, 0), r: 0.025, Mat.black))
            let base = cyl(0.2, 0.02, Mat.black); base.position = SCNVector3(0, 0.01, 0); root.addChildNode(base)
            // a small table lamp: glowing shade with a soft warm halo around it
            let shade = SCNNode(geometry: { let g = SCNCone(topRadius: 0.05, bottomRadius: 0.09, height: 0.12)
                let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = NSColor(calibratedRed: 0.75, green: 0.5, blue: 0.27, alpha: 1); g.materials = [m]; return g }())
            shade.position = SCNVector3(0, 0.93, 0); root.addChildNode(shade)
            root.addChildNode(pipe(from: SCNVector3(0, 0.76, 0), to: SCNVector3(0, 0.87, 0), r: 0.01, Mat.aluminum))
            root.addChildNode(warmHalo(0.9, at: SCNVector3(0, 0.92, 0)))
            for a in [0.0, 2.1, 4.2] {
                let cx = CGFloat(cos(a)) * 0.55, cz = CGFloat(sin(a)) * 0.55
                let seat = cyl(0.19, 0.03, wood); seat.position = SCNVector3(cx, 0.46, cz); root.addChildNode(seat)
                for (dx, dz) in [(-0.13, -0.13), (0.13, -0.13), (-0.13, 0.13), (0.13, 0.13)] {
                    root.addChildNode(pipe(from: SCNVector3(cx + CGFloat(dx), 0, cz + CGFloat(dz)), to: SCNVector3(cx + CGFloat(dx) * 0.8, 0.46, cz + CGFloat(dz) * 0.8), r: 0.012, wood))
                }
                // back, on the side away from the table
                let bx = cx + CGFloat(cos(a)) * 0.17, bz = cz + CGFloat(sin(a)) * 0.17
                let backRest = cyl(0.17, 0.02, wood); backRest.eulerAngles.x = .pi / 2
                backRest.eulerAngles.y = CGFloat(-a) + .pi / 2
                backRest.position = SCNVector3(bx, 0.82, bz); root.addChildNode(backRest)
            }
            return root
        case .parCan:
            // a small LED PAR (blue in this venue), seen as a bright dot
            let root = SCNNode()
            let can = cyl(0.09, 0.16, Mat.black); can.position = SCNVector3(0, -0.08, 0); root.addChildNode(can)
            let lens = SCNNode(geometry: { let g = SCNCylinder(radius: 0.07, height: 0.01)
                let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = NSColor(calibratedRed: 0.15, green: 0.35, blue: 1, alpha: 1); g.materials = [m]; return g }())
            lens.position = SCNVector3(0, -0.165, 0); root.addChildNode(lens)
            return root
        case .monitorWedge:
            let root = SCNNode()
            let w: CGFloat = 0.60, d: CGFloat = 0.50
            let cabinet = Mat.make(NSColor(white:0.065,alpha:1),rough:0.86)
            let edge = Mat.make(NSColor(white:0.12,alpha:1),metal:true,rough:0.55)
            // Side profile: the grille faces upward and toward the performer (+z).
            let path = NSBezierPath()
            path.move(to:NSPoint(x:0,y:0)); path.line(to:NSPoint(x:d,y:0))
            path.line(to:NSPoint(x:d,y:0.12)); path.line(to:NSPoint(x:0.08,y:0.34))
            path.line(to:NSPoint(x:0,y:0.28)); path.close()
            let shape = SCNShape(path:path,extrusionDepth:w); shape.chamferRadius = 0.008
            shape.materials = [cabinet]
            let body = SCNNode(geometry:shape); body.eulerAngles.y = -.pi/2
            body.position = SCNVector3(0,0,-d/2); root.addChildNode(body)
            // Perforated steel grille with a dark backing and fine staggered holes.
            let img = NSImage(size:NSSize(width:256,height:256))
            img.lockFocus()
            NSColor(white:0.18,alpha:1).setFill(); NSRect(x:0,y:0,width:256,height:256).fill()
            NSColor(white:0.025,alpha:1).setFill()
            for row in 0..<48 { for col in 0..<48 {
                NSBezierPath(ovalIn:NSRect(x:CGFloat(col)*5.4+CGFloat(row%2)*2.7,y:CGFloat(row)*5.4,width:3.3,height:3.3)).fill()
            } }
            img.unlockFocus()
            let mesh = Mat.make(NSColor(white:0.18,alpha:1),metal:true,rough:0.62)
            mesh.diffuse.contents = img
            let face = SCNNode()
            face.position = SCNVector3(0,0.236,0.042); face.eulerAngles.x = -.pi/2+atan2(CGFloat(0.22),CGFloat(0.42))
            root.addChildNode(face)
            let frame = box(w-0.035,0.44,0.018,edge,chamfer:0.005); face.addChildNode(frame)
            let grille = SCNNode(geometry:SCNPlane(width:w-0.065,height:0.408))
            grille.geometry?.materials = [mesh]; grille.position.z = 0.010; face.addChildNode(grille)
            for x in [CGFloat(-0.265),0.265] { for y in [CGFloat(-0.20),0,0.20] {
                let screw = cyl(0.004,0.003,Mat.aluminum); screw.eulerAngles.x = .pi/2
                screw.position = SCNVector3(x,y,0.012); face.addChildNode(screw)
            } }
            // Recessed side-handle silhouettes and rubber feet.
            for side in [CGFloat(-1),1] {
                let handle = box(0.008,0.065,0.13,edge,chamfer:0.004)
                handle.position = SCNVector3(side*(w/2+0.001),0.13,-0.03); root.addChildNode(handle)
                let inset = box(0.009,0.040,0.10,Mat.black,chamfer:0.003)
                inset.position = SCNVector3(side*(w/2+0.005),0.13,-0.03); root.addChildNode(inset)
                for z in [CGFloat(-0.17),0.17] {
                    let foot = cyl(0.025,0.012,Mat.darkGray)
                    foot.position = SCNVector3(side*0.23,0.006,z); root.addChildNode(foot)
                }
            }
            root.scale = SCNVector3(s,s,s)
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
            let shell = Mat.make(NSColor(calibratedRed: 0.35, green: 0.035, blue: 0.07, alpha: 1), metal: true, rough: 0.28)
            let skin = Mat.make(NSColor(white: 0.85, alpha: 1), rough: 0.65)
            let bronze = Mat.make(NSColor(calibratedRed: 0.76, green: 0.52, blue: 0.20, alpha: 1), metal: true, rough: 0.3)
            func add(_ n: SCNNode, _ parent: SCNNode, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) {
                n.position = SCNVector3(x,y,z); parent.addChildNode(n)
            }
            func ring(_ r: CGFloat, _ p: CGFloat, _ mat: SCNMaterial) -> SCNNode {
                let g = SCNTorus(ringRadius: r, pipeRadius: p)
                g.ringSegmentCount = 48; g.pipeSegmentCount = 8; g.materials = [mat]
                return SCNNode(geometry: g)
            }
            func drum(_ r: CGFloat, _ d: CGFloat, _ mat: SCNMaterial, _ count: Int) -> SCNNode {
                let n = SCNNode()
                add(cyl(r,d,mat),n,0,0,0)
                for side in [CGFloat(-1),CGFloat(1)] {
                    add(cyl(r-0.008,0.008,skin),n,0,side*(d/2+0.004),0)
                    add(ring(r+0.002,0.006,Mat.chrome),n,0,side*(d/2+0.006),0)
                    for i in 0..<count {
                        let q = CGFloat(i)*2 * .pi / CGFloat(count)
                        let x = cos(q)*(r+0.008), z = sin(q)*(r+0.008)
                        add(box(0.016,0.035,0.016,Mat.chrome,chamfer:0.003),n,x,side*(d/2-0.034),z)
                        add(cyl(0.003,0.035,Mat.chrome),n,x,side*(d/2-0.012),z)
                    }
                }
                return n
            }
            func stand(_ x: CGFloat,_ z: CGFloat,_ h: CGFloat,_ spread: CGFloat = 0.18) {
                add(cyl(0.012,h*0.68,Mat.chrome),root,x,h*0.34,z)
                add(cyl(0.008,h*0.48,Mat.chrome),root,x,h*0.76,z)
                add(cyl(0.021,0.045,Mat.chrome),root,x,h*0.58,z)
                for i in 0..<3 {
                    let q = CGFloat(i)*2 * .pi/3
                    let fx = x+cos(q)*spread, fz = z+sin(q)*spread
                    root.addChildNode(pipe(from: SCNVector3(x,0.16,z),to: SCNVector3(fx,0.025,fz),r:0.009,Mat.chrome))
                    add(box(0.035,0.025,0.035,Mat.darkGray,chamfer:0.005),root,fx,0.014,fz)
                }
            }
            func cymbal(_ x: CGFloat,_ y: CGFloat,_ z: CGFloat,_ r: CGFloat,_ tilt: CGFloat,_ hat: Bool = false) {
                stand(x,z,y)
                let n = SCNNode()
                let g = SCNCone(topRadius:r*0.23,bottomRadius:r,height:0.027)
                g.radialSegmentCount = 64; g.materials = [bronze]
                add(SCNNode(geometry:g),n,0,0.008,0)
                for i in 1...5 {
                    let rr = r*(0.30+CGFloat(i)*0.11)
                    add(ring(rr,0.0008,bronze),n,0,0.022-0.027*(rr/r-0.23)/0.77,0)
                }
                let bell = SCNNode(geometry:SCNSphere(radius:r*0.21))
                bell.geometry?.materials = [bronze]; bell.scale = SCNVector3(1,0.36,1)
                add(bell,n,0,0.02,0)
                if hat { add(cyl(r,0.006,bronze),n,0,-0.026,0) }
                add(cyl(0.013,0.018,Mat.darkGray),n,0,0.043,0)
                add(cyl(0.006,0.025,Mat.chrome),n,0,0.058,0)
                n.eulerAngles.z = tilt; add(n,root,x,y,z)
            }
            let kick = drum(0.28,0.43,shell,10); kick.eulerAngles.x = .pi/2
            add(kick,root,0,0.30,0.10)
            for side in [CGFloat(-1),CGFloat(1)] {
                root.addChildNode(pipe(from:SCNVector3(side*0.22,0.23,0.17),to:SCNVector3(side*0.34,0.025,0.31),r:0.012,Mat.chrome))
            }
            for (x,r,d) in [(CGFloat(-0.17),CGFloat(0.13),CGFloat(0.20)),(0.16,0.15,0.23)] {
                let tom = drum(r,d,shell,6); tom.eulerAngles.x = -0.20
                add(tom,root,x,0.73,0.01)
                root.addChildNode(pipe(from:SCNVector3(0,0.52,0.06),to:SCNVector3(x,0.68,0.01),r:0.012,Mat.chrome))
            }
            add(drum(0.20,0.36,shell,8),root,-0.49,0.43,-0.20)
            for i in 0..<3 {
                let q = CGFloat(i)*2 * .pi/3
                let x = -0.49+cos(q)*0.19, z = -0.20+sin(q)*0.19
                root.addChildNode(pipe(from:SCNVector3(x,0.39,z),to:SCNVector3(x+cos(q)*0.045,0.025,z+sin(q)*0.045),r:0.008,Mat.chrome))
            }
            stand(0.32,-0.29,0.55,0.13)
            add(drum(0.18,0.14,Mat.chrome,8),root,0.32,0.63,-0.29)
            cymbal(0.65,0.92,-0.28,0.18,0.02,true)
            cymbal(0.57,1.23,0.14,0.23,-0.15)
            cymbal(-0.60,1.13,-0.08,0.27,0.16)
            cymbal(-0.38,1.30,0.27,0.21,0.12)
            stand(0,-0.78,0.48,0.20)
            add(cyl(0.17,0.075,Mat.darkGray),root,0,0.53,-0.78)
            let pedal = box(0.075,0.025,0.23,Mat.aluminum,chamfer:0.006)
            pedal.eulerAngles.x = -0.12; add(pedal,root,0,0.035,-0.27)
            return root
        case .performer:
            return performer(PerformerAppearance())
        }
    }
}

/// Independent character studio: no DMX output, no stage geometry, orbit camera and neutral lighting.
struct CharacterModelPreview: NSViewRepresentable {
    var appearance: PerformerAppearance
    var faceCloseup: Bool = false

    final class Coordinator {
        var appearance: PerformerAppearance?
        var closeup: Bool?
        var character: SCNNode?
        var camera: SCNNode?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        let scene = SCNScene()
        view.scene = scene
        view.backgroundColor = NSColor(white: 0.12, alpha: 1)
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling2X
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 37
        scene.rootNode.addChildNode(camera); view.pointOfView = camera
        context.coordinator.camera = camera
        let ambient = SCNNode(); ambient.light = SCNLight()
        ambient.light?.type = .ambient; ambient.light?.intensity = 380
        scene.rootNode.addChildNode(ambient)
        for (x,y,z,intensity) in [(CGFloat(2),CGFloat(3),CGFloat(4),CGFloat(850)),(-3,2,2,500),(1,3,-3,650)] {
            let light = SCNNode(); light.light = SCNLight(); light.light?.type = .omni
            light.light?.intensity = intensity; light.position = SCNVector3(x,y,z)
            scene.rootNode.addChildNode(light)
        }
        let floor = SCNFloor(); floor.reflectivity = 0.06; floor.materials = [Mat.darkGray]
        scene.rootNode.addChildNode(SCNNode(geometry: floor))
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: SCNView, context: Context) {
        let c = context.coordinator
        if c.appearance != appearance {
            c.character?.removeFromParentNode()
            let node = Build.performer(appearance)
            view.scene?.rootNode.addChildNode(node); c.character = node
            c.appearance = appearance
        }
        if c.closeup != faceCloseup {
            let y = CGFloat(appearance.height) * (faceCloseup ? 0.88 : 0.50)
            c.camera?.position = SCNVector3(0,y,faceCloseup ? 0.85 : 3.5)
            c.camera?.look(at: SCNVector3(0,y,0))
            view.defaultCameraController.target = SCNVector3(0,y,0)
            c.closeup = faceCloseup
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
        context.coordinator.setCamera("Overview")   // sets up the turntable orbit (no flipping upside down)
        context.coordinator.start()
        return v
    }

    func updateNSView(_ v: StageSCNView, context: Context) {
        v.editing = model.stageEditing
        guard model.stagePageVisible else { v.isPlaying = false; return }
        context.coordinator.applyQuality(model.stageHighQuality, to: v)
        v.isPlaying = true
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
            camera.camera?.fieldOfView = 38   // a normal lens: 50 on a wide window shrank the stage to the middle
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
            // Allow navigation to render before assembling the detailed venue.
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.timer != nil else { return }
                self.sync()
            }
        }

        func stop() { timer?.invalidate(); timer = nil; view?.isPlaying = false; view?.scene = nil; screenVideo?.pause() }

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
            scene.lightingEnvironment.contents = high ? Self.studioEnvironment : nil
            scene.lightingEnvironment.intensity = 0.65
            camera.camera?.screenSpaceAmbientOcclusionIntensity = high ? 0.65 : 0
            camera.camera?.screenSpaceAmbientOcclusionRadius = 0.35
        }

        // Neutral studio reflection map: broad softboxes define metallic truss and hardware
        // without adding extra real lights or changing the programmed DMX colors.
        private static let studioEnvironment: NSImage = {
            let image = NSImage(size: NSSize(width: 512, height: 256))
            image.lockFocus()
            NSColor(white: 0.10, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 512, height: 256).fill()
            for (x, y, w, h, brightness) in [(24.0, 145.0, 92.0, 62.0, 0.85), (235.0, 160.0, 115.0, 42.0, 0.65), (420.0, 100.0, 65.0, 96.0, 0.42)] {
                let rect = NSRect(x: x, y: y, width: w, height: h)
                NSGradient(starting: NSColor(white: brightness, alpha: 1), ending: NSColor(white: 0.10, alpha: 1))?.draw(in: rect, relativeCenterPosition: .zero)
            }
            image.unlockFocus()
            return image
        }()
        private var lightPools = true

        /// What the camera orbits around (dragging turns around this point, like a turntable)
        private var orbitTarget = SCNVector3(0, 1.4, -1.8)

        /// Put the camera somewhere, upright, looking at a point; dragging then orbits around that point
        private func place(at p: SCNVector3, lookAt target: SCNVector3, up: SCNVector3 = SCNVector3(0, 1, 0)) {
            camera.eulerAngles = SCNVector3Zero
            camera.position = p
            camera.look(at: target, up: up, localFront: SCNVector3(0, 0, -1))
            orbitTarget = target
            view?.pointOfView = camera
            if let c = view?.defaultCameraController {
                c.pointOfView = camera
                c.target = target
                c.worldUp = SCNVector3(0, 1, 0)
                c.interactionMode = .orbitTurntable    // can't roll or flip upside down
                c.maximumVerticalAngle = 88
                c.minimumVerticalAngle = -10
                c.inertiaEnabled = false
            }
        }

        func setCamera(_ name: String) {
            switch name {
            case "Zoom In", "Zoom Out":
                // move toward / away from what you're looking at, but never through it (that flipped the view)
                let pov = view?.pointOfView ?? camera
                let tgt = view?.defaultCameraController.target ?? orbitTarget
                let d = SCNVector3(tgt.x - pov.position.x, tgt.y - pov.position.y, tgt.z - pov.position.z)
                let dist = sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
                guard dist > 0.01 else { return }
                let newDist = name == "Zoom In" ? max(1.5, dist * 0.78) : min(40, dist / 0.78)
                let k = 1 - newDist / dist
                pov.position = SCNVector3(pov.position.x + d.x * k, pov.position.y + d.y * k, pov.position.z + d.z * k)
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
                let d = max(3.2, spread * 1.6 + 2)
                place(at: SCNVector3(c.x + d * 0.75, c.y + 1.3, c.z + d * 0.75), lookAt: SCNVector3(c.x, c.y + 0.9, c.z))
            case "Top":
                // straight down needs its own "up" (toward the back of the stage), or the view spins
                place(at: SCNVector3(0, 16, 1.5), lookAt: SCNVector3(0, 0, -1), up: SCNVector3(0, 0, -1))
            case "Side": place(at: SCNVector3(12, 3, -1), lookAt: SCNVector3(0, 1.8, -1.5))
            case "Audience": place(at: SCNVector3(0, 2.3, 8.2), lookAt: SCNVector3(0, 2.2, -2))
            // Overview (the starting view): the stage centered and filling the frame; zoom out / in from here
            default: place(at: SCNVector3(-2.6, 3.0, 3.9), lookAt: SCNVector3(-0.55, 1.35, -1.7))
            }
        }

        private func buildRoom() {
            // a venue, not a void: a polished concrete floor that catches a little of the beams, dark walls you
            // can still make out, house lights down low, and a soft front wash on the stage like real venues have
            let floor = SCNFloor()
            floor.reflectivity = 0.12
            floor.reflectionFalloffEnd = 6
            floor.materials = [Mat.make(NSColor(white: 0.22, alpha: 1), rough: 0.55)]
            scene.rootNode.addChildNode(SCNNode(geometry: floor))
            let wallMat = Mat.make(NSColor(calibratedRed: 0.09, green: 0.085, blue: 0.095, alpha: 1), rough: 0.9)
            let wall = SCNNode(geometry: { let g = SCNPlane(width: 40, height: 14); g.materials = [wallMat]; return g }())
            wall.position = SCNVector3(0, 7, -6)
            scene.rootNode.addChildNode(wall)
            // Architectural depth behind the stage: acoustic panels with alternating recessed
            // seams, rather than a featureless background plane.
            let panel = Mat.make(NSColor(white: 0.075, alpha: 1), rough: 0.92)
            let rib = Mat.make(NSColor(white: 0.14, alpha: 1), rough: 0.70)
            for i in -9...9 {
                let x = CGFloat(i) * 1.35
                let n = Build.box(1.29, 5.8, 0.10, panel, chamfer: 0.015)
                n.position = SCNVector3(x, 3.0, -5.91)
                scene.rootNode.addChildNode(n)
                let seam = Build.box(0.035, 5.8, 0.12, rib)
                seam.position = SCNVector3(x + 0.67, 3.0, -5.87)
                scene.rootNode.addChildNode(seam)
            }
            for x in [-14.0, 14.0] {
                let side = SCNNode(geometry: { let g = SCNPlane(width: 30, height: 14); g.materials = [wallMat]; return g }())
                side.position = SCNVector3(x, 7, 6); side.eulerAngles.y = x < 0 ? .pi / 2 : -.pi / 2
                scene.rootNode.addChildNode(side)
            }
            // house lights at a low level
            let amb = SCNNode(); amb.light = SCNLight(); amb.light?.type = .ambient; amb.light?.intensity = 210   // every venue has some light in the room
            amb.light?.color = NSColor(calibratedRed: 0.85, green: 0.88, blue: 1.0, alpha: 1)
            scene.rootNode.addChildNode(amb)
            let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional; key.light?.intensity = 250
            key.light?.color = NSColor(calibratedRed: 0.9, green: 0.92, blue: 1.0, alpha: 1)
            key.eulerAngles = SCNVector3(-0.9, 0.35, 0)
            scene.rootNode.addChildNode(key)
            // front-of-house wash: two soft warm spots from out front onto the stage and performer
            for x in [-3.5, 3.5] {
                let fw = SCNNode(); fw.light = SCNLight(); fw.light?.type = .spot
                fw.light?.intensity = 340
                fw.light?.spotInnerAngle = 25; fw.light?.spotOuterAngle = 55
                fw.light?.attenuationStartDistance = 6; fw.light?.attenuationEndDistance = 22
                fw.light?.color = NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.7, alpha: 1)
                fw.position = SCNVector3(x, 6.5, 9)
                fw.look(at: SCNVector3(0, 1.2, -2))
                scene.rootNode.addChildNode(fw)
            }
            // house lights, dimmed: a broad soft fill from the ceiling over the audience
            let house = SCNNode(); house.light = SCNLight(); house.light?.type = .omni
            house.light?.color = NSColor(calibratedRed: 1.0, green: 0.9, blue: 0.8, alpha: 1); house.light?.intensity = 170
            house.light?.attenuationStartDistance = 3; house.light?.attenuationEndDistance = 18
            house.position = SCNVector3(0, 7, 5); scene.rootNode.addChildNode(house)
            // warm pendant lamps hanging over the audience
            for (x, z) in [(-4.5, 3.0), (0.0, 4.0), (4.5, 3.0), (-3.0, 7.5), (3.0, 7.5)] {
                let p = SCNVector3(CGFloat(x), 4.6, CGFloat(z))
                scene.rootNode.addChildNode(Build.pipe(from: SCNVector3(p.x, 7.5, p.z), to: SCNVector3(p.x, p.y + 0.12, p.z), r: 0.006, Mat.darkGray))
                let bulb = SCNNode(geometry: { let g = SCNCone(topRadius: 0.06, bottomRadius: 0.2, height: 0.22)
                    let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = NSColor(calibratedRed: 0.7, green: 0.48, blue: 0.26, alpha: 1); g.materials = [m]; return g }())
                bulb.position = p; scene.rootNode.addChildNode(bulb)
                scene.rootNode.addChildNode(Build.warmHalo(1.6, at: SCNVector3(p.x, p.y - 0.05, p.z)))
            }
            let pendants = SCNNode(); pendants.light = SCNLight(); pendants.light?.type = .omni
            pendants.light?.color = NSColor(calibratedRed: 1, green: 0.7, blue: 0.42, alpha: 1); pendants.light?.intensity = 140
            pendants.light?.attenuationStartDistance = 1; pendants.light?.attenuationEndDistance = 9
            pendants.position = SCNVector3(0, 4.3, 5); scene.rootNode.addChildNode(pendants)
            // the room's own light, on even when the stage is dark: a bar at the back with a warm under-glow and
            // lit shelves, warm wall sconces, faint blue uplights on the walls and green exit signs
            func glow(_ c: NSColor) -> SCNMaterial { let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = c; return m }
            let warm = NSColor(calibratedRed: 0.72, green: 0.44, blue: 0.2, alpha: 1)   // dimmed, not full
            let barZ: CGFloat = 11.5
            let counter = SCNNode(geometry: SCNBox(width: 9, height: 1.1, length: 0.7, chamferRadius: 0.03))
            counter.geometry?.materials = [Mat.make(NSColor(calibratedRed: 0.07, green: 0.045, blue: 0.035, alpha: 1), rough: 0.35)]
            counter.position = SCNVector3(0, 0.55, barZ); scene.rootNode.addChildNode(counter)
            let strip = SCNNode(geometry: SCNBox(width: 9, height: 0.03, length: 0.02, chamferRadius: 0))
            strip.geometry?.materials = [glow(NSColor(calibratedRed: 0.55, green: 0.65, blue: 0.8, alpha: 1))]   // cool under-counter LED
            strip.position = SCNVector3(0, 0.08, barZ - 0.36); scene.rootNode.addChildNode(strip)
            for y in [1.6, 2.1, 2.6] {   // backlit shelves behind the bar
                let shelf = SCNNode(geometry: SCNBox(width: 7, height: 0.04, length: 0.3, chamferRadius: 0))
                shelf.geometry?.materials = [glow(NSColor(calibratedRed: 0.9, green: 0.55, blue: 0.25, alpha: 1))]
                shelf.position = SCNVector3(0, CGFloat(y), barZ + 1.3); scene.rootNode.addChildNode(shelf)
            }
            // Edison-bulb pendants over the bar: clear glass, a glowing amber filament, hung at different heights
            let glass: SCNMaterial = { let m = SCNMaterial(); m.lightingModel = .physicallyBased
                m.diffuse.contents = NSColor(calibratedRed: 0.9, green: 0.8, blue: 0.6, alpha: 1); m.transparency = 0.22
                m.roughness.contents = 0.05; m.metalness.contents = 0.0; m.isDoubleSided = true; return m }()
            let filament = glow(NSColor(calibratedRed: 1.0, green: 0.66, blue: 0.28, alpha: 1))
            for (k, x) in stride(from: -3.6, through: 3.6, by: 1.2).enumerated() {
                let y = CGFloat(2.75 + [0.0, 0.35, 0.12, 0.45, 0.05, 0.3, 0.18][k % 7])
                let p = SCNVector3(CGFloat(x), y, barZ)
                scene.rootNode.addChildNode(Build.pipe(from: SCNVector3(p.x, 4.6, p.z), to: SCNVector3(p.x, y + 0.22, p.z), r: 0.004, Mat.black))
                let cap = SCNNode(geometry: SCNCylinder(radius: 0.025, height: 0.05)); cap.geometry?.materials = [Mat.aluminum]
                cap.position = SCNVector3(p.x, y + 0.2, p.z); scene.rootNode.addChildNode(cap)
                // the glass: a tall diamond / teardrop shape (two cones)
                let top = SCNNode(geometry: SCNCone(topRadius: 0.02, bottomRadius: 0.075, height: 0.12)); top.geometry?.materials = [glass]
                top.position = SCNVector3(p.x, y + 0.11, p.z); scene.rootNode.addChildNode(top)
                let bottom = SCNNode(geometry: SCNCone(topRadius: 0.075, bottomRadius: 0.012, height: 0.2)); bottom.geometry?.materials = [glass]
                bottom.position = SCNVector3(p.x, y - 0.05, p.z); scene.rootNode.addChildNode(bottom)
                // the spiral filament (a glowing coil)
                let coil = SCNNode(geometry: SCNCylinder(radius: 0.012, height: 0.22)); coil.geometry?.materials = [filament]
                coil.position = SCNVector3(p.x, y + 0.02, p.z); scene.rootNode.addChildNode(coil)
                scene.rootNode.addChildNode(Build.warmHalo(0.55, at: SCNVector3(p.x, y + 0.02, p.z)))
            }
            let barLight = SCNNode(); barLight.light = SCNLight(); barLight.light?.type = .omni
            barLight.light?.color = warm; barLight.light?.intensity = 220
            barLight.light?.attenuationStartDistance = 0.5; barLight.light?.attenuationEndDistance = 6
            barLight.position = SCNVector3(0, 2.4, barZ + 0.4); scene.rootNode.addChildNode(barLight)
            // sconces: small glowing shades on the side walls (glow only, no extra light sources)
            for x in [-13.9, 13.9] {
                for z in stride(from: -2.0, through: 12.0, by: 3.5) {
                    let sconce = SCNNode(geometry: SCNCylinder(radius: 0.12, height: 0.22)); sconce.geometry?.materials = [glow(warm)]
                    sconce.position = SCNVector3(CGFloat(x), 2.4, CGFloat(z)); scene.rootNode.addChildNode(sconce)
                    let wash = SCNNode(geometry: SCNPlane(width: 1.1, height: 1.6))
                    wash.geometry?.materials = [{ let m = glow(warm.withAlphaComponent(1)); m.diffuse.contents = Self.wallGlowImage(warm); m.blendMode = .add; m.writesToDepthBuffer = false; return m }()]
                    wash.position = SCNVector3(CGFloat(x) + (x < 0 ? 0.02 : -0.02), 2.6, CGFloat(z)); wash.eulerAngles.y = x < 0 ? .pi / 2 : -.pi / 2
                    scene.rootNode.addChildNode(wash)
                }
                // faint blue house uplight on each side wall
                let up = SCNNode(); up.light = SCNLight(); up.light?.type = .omni
                up.light?.color = NSColor(calibratedRed: 0.35, green: 0.45, blue: 1.0, alpha: 1); up.light?.intensity = 110
                up.light?.attenuationStartDistance = 1; up.light?.attenuationEndDistance = 8
                up.position = SCNVector3(CGFloat(x) * 0.93, 0.6, 4); scene.rootNode.addChildNode(up)
            }
            // blue LED cove strips tracing the room (along the tops of the side walls and around the back wall),
            // like the accent lighting in real venues — dim, so they outline the room without lighting it up
            let cove = glow(NSColor(calibratedRed: 0.12, green: 0.28, blue: 0.85, alpha: 1))
            for x in [-13.95, 13.95] {
                for y in [4.6, 1.0] {
                    let s = SCNNode(geometry: SCNBox(width: 0.04, height: 0.035, length: 18, chamferRadius: 0)); s.geometry?.materials = [cove]
                    s.position = SCNVector3(CGFloat(x), CGFloat(y), 4); scene.rootNode.addChildNode(s)
                }
            }
            let backCove = SCNNode(geometry: SCNBox(width: 27.8, height: 0.035, length: 0.04, chamferRadius: 0)); backCove.geometry?.materials = [cove]
            backCove.position = SCNVector3(0, 4.6, 13.45); scene.rootNode.addChildNode(backCove)
            let frontCove = SCNNode(geometry: SCNBox(width: 39, height: 0.035, length: 0.04, chamferRadius: 0)); frontCove.geometry?.materials = [cove]
            frontCove.position = SCNVector3(0, 6.2, -5.95); scene.rootNode.addChildNode(frontCove)
            // exit signs in the back corners
            for x in [-12.5, 12.5] {
                let sign = SCNNode(geometry: SCNPlane(width: 0.5, height: 0.2)); sign.geometry?.materials = [glow(NSColor(calibratedRed: 0.1, green: 0.95, blue: 0.35, alpha: 1))]
                sign.position = SCNVector3(CGFloat(x), 3.2, 13.4); sign.eulerAngles.y = .pi; scene.rootNode.addChildNode(sign)
            }
            let backWall = SCNNode(geometry: { let g = SCNPlane(width: 30, height: 14); g.materials = [wallMat]; return g }())
            backWall.position = SCNVector3(0, 7, 13.5); backWall.eulerAngles.y = .pi; scene.rootNode.addChildNode(backWall)

            // (no light aimed at the back wall: up close it made a hard hotspot)
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
            var built = 0
            for item in items {
                if let old = itemSnapshot[item.id], let node = itemNodes[item.id] {
                    if old.prop == item.prop && old.size == item.size && old.fixtureID == item.fixtureID && old.onStand == item.onStand && old.backdropStyle == item.backdropStyle && old.panels == item.panels && old.performerAppearance == item.performerAppearance {
                        if old != item { place(node, item) }
                        itemSnapshot[item.id] = item
                        continue
                    }
                    if built >= 2 { continue }
                    node.removeFromParentNode()
                }
                if built >= 2 { continue }
                built += 1
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
            if item.upright == true {
                // bar stands on its end: its length goes up, lenses face the audience, and the 180° tilt
                // (around the bar) sweeps the beams side to side. SceneKit applies z first, then y.
                node.eulerAngles = SCNVector3(0, .pi / 2 - item.rotation * .pi / 180, .pi / 2)
                node.position.y += 0.48
            } else {
                node.eulerAngles = SCNVector3(0, -item.rotation * .pi / 180, item.hanging ? .pi : 0)
                if item.hanging { node.position.y += 0.35 }   // clamp sits below the truss
            }
        }

        private func makeNode(_ item: StageItem) -> SCNNode {
            let root = SCNNode()
            root.name = "item:\(item.id.uuidString)"
            if let kind = item.prop {
                root.addChildNode(kind == .backdrop ? Build.backdrop(item.backdropStyle ?? .ledWall, size: item.size, panels: item.panels)
                                                    : (kind == .performer ? Build.performer(item.performerAppearance ?? PerformerAppearance()) : Build.prop(kind, size: item.size)))
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
                light.eulerAngles.x = .pi / 2        // a spot shines along its -Z: turned +90° it points along +Y, the way the lenses face
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

        /// A soft glow on a wall around a sconce
        static func wallGlowImage(_ c: NSColor) -> NSImage {
            let size = 128
            let img = NSImage(size: NSSize(width: size, height: size))
            img.lockFocus()
            if let ctx = NSGraphicsContext.current?.cgContext,
               let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [c.withAlphaComponent(0.32).cgColor, c.withAlphaComponent(0.07).cgColor, c.withAlphaComponent(0).cgColor] as CFArray,
                                  locations: [0, 0.4, 1]) {
                let center = CGPoint(x: size / 2, y: size / 2)
                ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: CGFloat(size / 2), options: [])
            }
            img.unlockFocus()
            return img
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
            guard model.stagePageVisible, let w = view?.window, w.isVisible, w.occlusionState.contains(.visible), !w.isMiniaturized else {
                if view?.isPlaying == true { view?.isPlaying = false }
                return
            }
            if view?.isPlaying == false { view?.isPlaying = true }
            if itemSnapshot != Dictionary(uniqueKeysWithValues: model.stage.items.map { ($0.id, $0) }) { sync() }
            applyFrame(model.preview, now: Date().timeIntervalSinceReferenceDate, master: model.blackout ? 0 : model.master)
            // remember the camera for "Same as my Stage view" video exports
            if let v = view, let pov = v.pointOfView, let cam = pov.camera, v.bounds.height > 10 {
                let aspect = Double(v.bounds.width / v.bounds.height)
                let vFOV = Double(cam.fieldOfView) * .pi / 180
                let h = cam.projectionDirection == .horizontal ? Double(cam.fieldOfView) : 2 * atan(tan(vFOV / 2) * aspect) * 180 / .pi
                model.stageCameraNow = (pov.worldTransform, h)
            }
        }

        /// The song the LED backdrop names (a video export sets it; otherwise the playing song)
        var backdropSong: (artist: String, title: String)? = nil
        var backdropSongID: UUID? = nil     // a video export: which song, and where in it
        var backdropTime: Double? = nil
        private var backdropKey: String? = nil
        private var backdropContents: Any? = nil
        private var screenVideo: AVQueuePlayer? = nil
        private var screenLooper: AVPlayerLooper? = nil
        private var backdropCache: [SCNNode] = []
        private var backdropCheckedAt = -1.0
        private func backdropNodes() -> [SCNNode] {
            // look for the screens about once a second (cheap), not every frame
            let now = Date().timeIntervalSinceReferenceDate
            if now - backdropCheckedAt > 1 || backdropSong != nil && backdropCache.isEmpty {
                backdropCheckedAt = now
                backdropCache = scene.rootNode.childNodes { n, _ in n.name?.hasPrefix("backdropscreen") == true }
            }
            return backdropCache
        }
        private func updateBackdrop() {
            let s: (artist: String, title: String) = backdropSong ?? model.playingSongID.flatMap { model.song($0) }.map { ($0.artist ?? "", $0.title) } ?? ("", "")
            // the show's screen cue right now (or the venue's choice)
            let cue = model.screenCue(song: backdropSongID ?? model.playingSongID, at: backdropTime ?? model.showTimeNow)
            let content = cue.content == .rays ? .name : cue.content
            let media = cue.mediaPath ?? ""
            let projected = model.stage.items.first { $0.prop == .backdrop }?.backdropStyle == .projection
            let key = s.artist + "|" + s.title + "|" + content.rawValue + "|" + media + "|\(projected)"
            if key != backdropKey {
                backdropKey = key
                screenVideo?.pause(); screenVideo = nil; screenLooper = nil
                switch content {
                case .image:
                    backdropContents = NSImage(contentsOfFile: media) ?? Build.backdropImage(artist: s.artist, title: s.title, content: .off)
                case .video where FileManager.default.fileExists(atPath: media):
                    // your video, looping silently on the screen
                    let item = AVPlayerItem(url: URL(fileURLWithPath: media))
                    let q = AVQueuePlayer(); q.isMuted = true
                    screenLooper = AVPlayerLooper(player: q, templateItem: item)
                    q.play()
                    screenVideo = q
                    backdropContents = q
                default:
                    backdropContents = Build.backdropImage(artist: s.artist, title: s.title, content: content == .video ? .off : content, projected: projected)
                }
            }
            // new screens (added or rebuilt) pick it up too
            for n in backdropNodes() where (n.name ?? "") != "backdropscreen|" + key {
                n.geometry?.firstMaterial?.diffuse.contents = backdropContents
                n.name = "backdropscreen|" + key
            }
        }

        /// Puts one moment of the show on the 3D lights (the Stage view, or a frame of an exported video).
        func applyFrame(_ preview: [RenderedFixture], now: Double, master: Double) {
            updateBackdrop()
            let haze = model.haze
            let performer = model.stage.items.first { $0.prop == .performer } ?? model.stage.items.first { $0.prop == .micStand }
            let aim = performer.map { SCNVector3($0.x, $0.y + 1.3, $0.z) } ?? SCNVector3(0, 1.8, -1)

            var roomGlow = (r: 0.0, g: 0.0, b: 0.0, n: 0.0)
            SCNTransaction.begin()
            SCNTransaction.disableActions = true
            for item in model.stage.items {
                guard let fid = item.fixtureID, let parts = fixtureParts[item.id],
                      let fi = model.fixtures.firstIndex(where: { $0.id == fid }), fi < preview.count else { continue }
                let fx = model.fixtures[fi]
                let rf = preview[fi]
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
                    // off means gone: the room's haze would otherwise tint the invisible beam shapes grey
                    halo.isHidden = hk < 0.004
                    halo.geometry?.firstMaterial?.multiply.contents = NSColor(calibratedRed: st.color.r * hk, green: st.color.g * hk, blue: st.color.b * hk, alpha: 1)
                    roomGlow.r += st.color.r * level; roomGlow.g += st.color.g * level; roomGlow.b += st.color.b * level; roomGlow.n += 1
                    if let glass = lens.childNode(withName: "lens", recursively: false)?.geometry?.firstMaterial {
                        glass.diffuse.contents = level > 0.02 ? (c.blended(withFraction: 0.35 * (1 - level), of: .black) ?? c) : NSColor(white: 0.12, alpha: 1)
                    }
                    if let beam = lens.childNode(withName: "beam", recursively: false) {
                        beam.isHidden = level * haze < 0.004
                        for (k, fade) in [1.0, 0.62, 0.34, 0.13].enumerated() {
                            guard let m = beam.childNode(withName: "seg\(k)", recursively: false)?.geometry?.firstMaterial else { continue }
                            // Additive glow: brightness comes from the color itself, so dim the color.
                            // A followspot's narrow shaft is see-through in haze, not a solid bar.
                            let k = level * fade * haze * (fx.colorWheel != nil ? 0.12 : 0.28)
                            m.diffuse.contents = NSColor(calibratedRed: st.color.r * k, green: st.color.g * k, blue: st.color.b * k, alpha: 1)
                            m.transparency = 0.72
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
            // the haze picks up the lights' color, so the room glows with the show instead of sitting flat black
            let base = 0.025 + 0.025 * haze
            scene.fogColor = NSColor(calibratedRed: base + tint.r * 0.10 * haze, green: base + tint.g * 0.10 * haze,
                                     blue: base + tint.b * 0.10 * haze, alpha: 1)
            // the LED wall / projection content takes on the show's colors (a banner is lit by the beams instead)
            let mx = max(tint.r, tint.g, tint.b, 0.0001), lvl = min(1, mx * 3)
            let wall = NSColor(calibratedRed: 0.18 + 0.82 * lvl * tint.r / mx, green: 0.18 + 0.82 * lvl * tint.g / mx,
                               blue: 0.18 + 0.82 * lvl * tint.b / mx, alpha: 1)
            let tinted = [.glow, .rays].contains(model.screenCue(song: backdropSongID ?? model.playingSongID, at: backdropTime ?? model.showTimeNow).content) && model.screenCue(song: backdropSongID ?? model.playingSongID, at: backdropTime ?? model.showTimeNow).content != .rays
            for n in backdropNodes() where n.geometry?.firstMaterial?.lightingModel == .constant {
                n.geometry?.firstMaterial?.multiply.contents = tinted ? wall : NSColor.white
            }
            scene.fogStartDistance = 2
            scene.fogEndDistance = CGFloat(55 - 35 * haze)
            scene.fogDensityExponent = 1.3
            SCNTransaction.commit()
        }
    }
}
