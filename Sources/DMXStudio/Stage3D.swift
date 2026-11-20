import SwiftUI
import SceneKit
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
    static let stageTop = make(NSColor(white: 0.07, alpha: 1), rough: 0.5)
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
    static func shehdsBar() -> (SCNNode, SCNNode, [SCNNode]) {
        let root = SCNNode()
        // Base housing (sits on the floor / clamps to truss)
        let base = box(1.0, 0.09, 0.16, Mat.black, chamfer: 0.01)
        base.position = SCNVector3(0, 0.045, 0)
        root.addChildNode(base)
        // Feet + display panel
        for x in [-0.42, 0.42] { let f = box(0.06, 0.02, 0.18, Mat.darkGray); f.position = SCNVector3(x, -0.005, 0); root.addChildNode(f) }
        let disp = box(0.07, 0.025, 0.002, { let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = NSColor.red; return m }())
        disp.position = SCNVector3(-0.15, 0.05, 0.081); root.addChildNode(disp)
        // End yokes
        for x in [-0.505, 0.505] { let y = box(0.03, 0.2, 0.17, Mat.black, chamfer: 0.01); y.position = SCNVector3(x, 0.15, 0); root.addChildNode(y) }
        // Tilting head
        let head = SCNNode()
        head.position = SCNVector3(0, 0.17, 0)
        let headBody = box(0.98, 0.1, 0.13, Mat.black, chamfer: 0.015)
        head.addChildNode(headBody)
        var lenses: [SCNNode] = []
        for i in 0..<8 {
            let lensNode = SCNNode()
            lensNode.position = SCNVector3(-0.4375 + Double(i) * 0.125, 0.05, 0)
            let ring = cyl(0.04, 0.012, Mat.darkGray); ring.position = SCNVector3(0, 0.002, 0)
            let glass = cyl(0.032, 0.014, Mat.lens()); glass.name = "lens"; glass.position = SCNVector3(0, 0.004, 0)
            lensNode.addChildNode(ring); lensNode.addChildNode(glass)
            lensNode.addChildNode(beamNode(spreadDeg: 8, length: 9))
            head.addChildNode(lensNode)
            lenses.append(lensNode)
        }
        root.addChildNode(head)
        return (root, head, lenses)
    }

    /// Chauvet LED Followspot 75ST on its tripod. Returns root, the aimable head, and its lens.
    static func followspot() -> (SCNNode, SCNNode, SCNNode) {
        let root = SCNNode()
        for a in [0.0, 120.0, 240.0] {
            let rad = a * .pi / 180
            root.addChildNode(pipe(from: SCNVector3(0, 1.2, 0), to: SCNVector3(cos(rad) * 0.55, 0, sin(rad) * 0.55), r: 0.015, Mat.black))
        }
        root.addChildNode({ let p = pipe(from: SCNVector3(0, 1.2, 0), to: SCNVector3(0, 1.5, 0), r: 0.02, Mat.black); return p }())
        let head = SCNNode()
        head.position = SCNVector3(0, 1.62, 0)
        let body = cyl(0.11, 0.55, Mat.black); body.eulerAngles.x = .pi / 2
        head.addChildNode(body)
        let lensNode = SCNNode()
        lensNode.position = SCNVector3(0, 0, -0.28)
        lensNode.eulerAngles.x = -.pi / 2          // beam axis (+Y of lens) points toward -Z of head
        let glass = cyl(0.09, 0.01, Mat.lens()); glass.name = "lens"
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
            g.radialSegmentCount = 24
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
        let v = StageSCNView(frame: .zero)
        v.scene = context.coordinator.scene
        v.backgroundColor = .black
        v.allowsCameraControl = true
        v.antialiasingMode = .multisampling4X
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
            camera.camera?.bloomIntensity = 0.5
            camera.camera?.bloomThreshold = 0.8
            setCamera("Audience")
            scene.rootNode.addChildNode(camera)
        }

        func start() {
            timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.animate() }
            RunLoop.main.add(timer!, forMode: .common)
            sync()
        }

        func stop() { timer?.invalidate(); timer = nil }

        func setCamera(_ name: String) {
            switch name {
            case "Top": camera.position = SCNVector3(0, 16, 1); camera.look(at: SCNVector3(0, 0, -1))
            case "Side": camera.position = SCNVector3(12, 3, -1); camera.look(at: SCNVector3(0, 1.8, -1.5))
            default: camera.position = SCNVector3(0, 2.3, 8.2); camera.look(at: SCNVector3(0, 2.2, -2))
            }
            view?.pointOfView = camera
        }

        private func buildRoom() {
            let floor = SCNFloor()
            floor.reflectivity = 0.06
            floor.materials = [Mat.make(NSColor(white: 0.06, alpha: 1), rough: 0.7)]
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
                    if old.prop == item.prop && old.size == item.size && old.fixtureID == item.fixtureID {
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
            light.light?.spotOuterAngle = fx.colorWheel != nil ? 14 : 30
            light.light?.spotInnerAngle = 4
            light.light?.intensity = 0
            light.light?.attenuationEndDistance = 20
            if fx.profileName.hasPrefix("SHEHDS") || fx.headCount == 8 {
                let (bar, head, lenses) = Build.shehdsBar()
                root.addChildNode(bar)
                light.eulerAngles.x = -.pi / 2       // point along +Y of the head
                head.addChildNode(light)
                fixtureParts[item.id] = (head, lenses, light)
            } else if fx.colorWheel != nil {
                let (spot, head, lens) = Build.followspot()
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

        /// 30 times a second: copy what every light is doing onto its 3D model.
        private func animate() {
            let now = Date().timeIntervalSinceReferenceDate
            let master = model.blackout ? 0 : model.master
            let haze = model.haze
            let performer = model.stage.items.first { $0.prop == .performer } ?? model.stage.items.first { $0.prop == .micStand }
            let aim = performer.map { SCNVector3($0.x, $0.y + 1.3, $0.z) } ?? SCNVector3(0, 1.8, -1)

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
                    if let glass = lens.childNode(withName: "lens", recursively: false)?.geometry?.firstMaterial {
                        glass.diffuse.contents = level > 0.02 ? (c.blended(withFraction: 0.35 * (1 - level), of: .black) ?? c) : NSColor(white: 0.12, alpha: 1)
                    }
                    if let beam = lens.childNode(withName: "beam", recursively: false) {
                        for (k, fade) in [0.30, 0.15, 0.07, 0.025].enumerated() {
                            guard let m = beam.childNode(withName: "seg\(k)", recursively: false)?.geometry?.firstMaterial else { continue }
                            m.diffuse.contents = c
                            m.transparency = CGFloat(level * fade * haze)
                        }
                    }
                    avg.r += st.color.r * level; avg.g += st.color.g * level; avg.b += st.color.b * level; avg.i += level
                }
                if let l = parts.light?.light {
                    let n = Double(max(1, parts.lenses.count))
                    let mx = max(avg.r, avg.g, avg.b, 0.0001)
                    l.color = NSColor(calibratedRed: avg.r / mx, green: avg.g / mx, blue: avg.b / mx, alpha: 1)
                    l.intensity = CGFloat(avg.i / n * (fx.colorWheel != nil ? 3500 : 2200))
                }
            }
            SCNTransaction.commit()
        }
    }
}
