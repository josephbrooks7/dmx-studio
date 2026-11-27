import AppKit
import SceneKit
import Metal

/// Isolated diagnostic render; never attaches to the live stage.
enum CharacterDiagnosticCapture {
    enum CaptureError: Error { case disabled, invalidBounds, encodingFailed }

    @MainActor
    static func png(appearance: PerformerAppearance, enabled: Bool) throws -> Data {
        guard enabled else { throw CaptureError.disabled }
        let scene = SCNScene()
        scene.background.contents = NSColor(white: 0.12, alpha: 1)
        let character = Build.performer(appearance)
        scene.rootNode.addChildNode(character)
        let bounds = character.boundingBox
        let lo = bounds.min, hi = bounds.max
        guard [lo.x, lo.y, lo.z, hi.x, hi.y, hi.z].allSatisfy({ $0.isFinite }),
              hi.y > lo.y else { throw CaptureError.invalidBounds }
        let center = SCNVector3((lo.x + hi.x)/2, (lo.y + hi.y)/2, (lo.z + hi.z)/2)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 37
        camera.camera?.wantsExposureAdaptation = false
        let halfAngle = CGFloat(37 * Double.pi / 360)
        let distance = max((hi.y-lo.y)*0.65, (hi.x-lo.x)*0.65/0.75)/tan(halfAngle) + (hi.z-lo.z)/2
        camera.position = SCNVector3(center.x, center.y, center.z + distance)
        camera.look(at: center)
        scene.rootNode.addChildNode(camera)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 55
        scene.rootNode.addChildNode(ambient)
        for (x,y,z,intensity) in [(CGFloat(2),CGFloat(3),CGFloat(4),CGFloat(220)),(-3,2,2,90),(1,3,-3,120)] {
            let light = SCNNode()
            light.light = SCNLight()
            light.light?.type = .omni
            light.light?.intensity = intensity
            light.position = SCNVector3(x,y,z)
            scene.rootNode.addChildNode(light)
        }
        let renderer = SCNRenderer(device: MTLCopyAllDevices().first(where: { $0.isLowPower }) ?? MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 768, height: 1024), antialiasingMode: .multisampling2X)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]),
              png.count <= 4 * 1024 * 1024 else { throw CaptureError.encodingFailed }
        return png
    }

    /// Publish a request-specific image only after a successful render.
    @MainActor
    static func export(appearance: PerformerAppearance, requestID: UUID, enabled: Bool) throws -> URL {
        guard enabled else { throw CaptureError.disabled }
        let data = try png(appearance: appearance, enabled: enabled)
        let root = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("DMX Studio", isDirectory: true)
            .appendingPathComponent("DiagnosticPreviews", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let attributes = try FileManager.default.attributesOfItem(atPath: root.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o077 == 0 else { throw CaptureError.encodingFailed }
        let destination = root.appendingPathComponent(requestID.uuidString.lowercased() + ".png")
        try data.write(to: destination, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        return destination
    }
}
