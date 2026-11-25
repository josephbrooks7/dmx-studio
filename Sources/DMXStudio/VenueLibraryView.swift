import SwiftUI
import SceneKit
import AppKit
import UniformTypeIdentifiers

// Phase 1: local, non-destructive venue imports. Calibration is explicit;
// imported coordinates are not assumed to be verified physical measurements.
struct LocalVenue: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var filename: String
    var importedAt = Date()
    var metersPerUnit: Double = 1
    var yawDegrees: Double? = nil
    var referenceUnits: Double? = nil
    var referenceMeters: Double? = nil
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DMX Studio/Venues", isDirectory: true)
    }
    var folder: URL { Self.directory.appendingPathComponent(id.uuidString, isDirectory: true) }
    var url: URL { folder.appendingPathComponent(filename) }
    func save() throws {
        try JSONEncoder().encode(self).write(to: folder.appendingPathComponent("venue.json"), options: .atomic)
    }
    static func load() -> [LocalVenue] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("venue.json")) else { return nil }
            return try? JSONDecoder().decode(LocalVenue.self, from: data)
        }.sorted { $0.importedAt > $1.importedAt }
    }
}

struct VenueLibraryView: View {
    var onUse: (LocalVenue) -> Void = { _ in }
    @State private var yaw = 0.0
    @State private var measured: Double?
    @Environment(\.dismiss) private var dismiss
    @State private var venues = LocalVenue.load()
    @State private var selected: UUID?
    @State private var preview: SCNScene?
    @State private var dimensions: SCNVector3?
    @State private var referenceUnits = ""
    @State private var referenceMeters = ""
    @State private var status = ""
    @State private var busy = false
    private var venue: LocalVenue? { venues.first { $0.id == selected } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Venue Library").font(.title2.bold())
                Spacer()
                Button("Import USDZ…", action: importVenue).disabled(busy)
                Button("Done") { dismiss() }
            }
            HStack(alignment: .top, spacing: 16) {
                List(selection: $selected) {
                    ForEach(venues) { v in Text(v.name).tag(v.id) }
                }.frame(width: 220)
                VStack(alignment: .leading, spacing: 10) {
                    if let preview = preview {
                        VenueMeasurePreview(scene: preview, onDistance: { measured = $0 })
                            .frame(minHeight: 300)
                    } else { Text("Import a self-contained USDZ venue to inspect its geometry.").frame(maxWidth: .infinity, minHeight: 300) }
                    if let v = venue, let d = dimensions {
                        Text(String(format: "Model bounds: %.2f × %.2f × %.2f m", Double(d.x)*v.metersPerUnit, Double(d.y)*v.metersPerUnit, Double(d.z)*v.metersPerUnit))
                        Text(v.referenceMeters == nil ? "Uncalibrated — assumed 1 meter per model unit" : "User-calibrated — not independently verified").font(.caption)
                        Text("Double-click two surface points to measure their distance.").font(.caption)
                        if let measured = measured {
                            Text(String(format: "Selected points: %.3f m (model estimate)", measured * v.metersPerUnit))
                            Button("Use selected distance for calibration") { referenceUnits = String(measured) }
                        }
                        HStack {
                            Text("Orientation")
                            Slider(value: $yaw, in: -180...180)
                            Text(String(format: "%.0f°", yaw))
                            Button("Save orientation") { saveOrientation() }
                            Button("Use in Stage") { var chosen = v; chosen.yawDegrees = yaw; onUse(chosen); dismiss() }
                        }
                        HStack {
                            TextField("Known distance in model units", text: $referenceUnits)
                            TextField("Physical distance (meters)", text: $referenceMeters)
                            Button("Calibrate", action: calibrate)
                        }
                    }
                    Text(status).font(.caption)
                }
            }
        }.padding(20).frame(minWidth: 850, minHeight: 500)
        .onChange(of: selected) { _ in loadPreview() }
    }
    private func loadPreview() {
        preview = nil; dimensions = nil; measured = nil
        guard let v = venue else { return }
        yaw = v.yawDegrees ?? 0
        referenceUnits = v.referenceUnits.map { String($0) } ?? ""
        referenceMeters = v.referenceMeters.map { String($0) } ?? ""
        do {
            let scene = try SCNScene(url: v.url, options: nil)
            let b = scene.rootNode.boundingBox
            dimensions = SCNVector3(b.max.x-b.min.x, b.max.y-b.min.y, b.max.z-b.min.z)
            preview = scene
        } catch { status = error.localizedDescription }
    }
    private func saveOrientation() {
        guard var v = venue else { return }
        v.yawDegrees = yaw
        do { try v.save(); venues = LocalVenue.load(); status = "Orientation saved." }
        catch { status = error.localizedDescription }
    }
    private func calibrate() {
        guard var v = venue, let u = Double(referenceUnits), let m = Double(referenceMeters),
              u.isFinite, m.isFinite, u > 0, m > 0, (m/u).isFinite else {
            status = "Enter two positive finite distances."; return
        }
        v.metersPerUnit = m/u; v.referenceUnits = u; v.referenceMeters = m
        do { try v.save(); venues = LocalVenue.load(); status = "Calibration saved." }
        catch { status = error.localizedDescription }
    }
    private func importVenue() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "usdz") ?? .data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let v = LocalVenue(name: source.deletingPathExtension().lastPathComponent, filename: "venue.usdz")
        busy = true; status = "Importing…"
        DispatchQueue.global(qos: .utility).async {
            do {
                try FileManager.default.createDirectory(at: v.folder, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: v.url)
                _ = try SCNScene(url: v.url, options: nil)
                try v.save()
                DispatchQueue.main.async { venues = LocalVenue.load(); selected = v.id; busy = false; status = "Imported." }
            } catch {
                try? FileManager.default.removeItem(at: v.folder)
                DispatchQueue.main.async { busy = false; status = error.localizedDescription }
            }
        }
    }
}

private struct VenueMeasurePreview: NSViewRepresentable {
    let scene: SCNScene
    let onDistance: (Double) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onDistance) }
    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pick(_:)))
        click.numberOfClicksRequired = 2
        view.addGestureRecognizer(click)
        return view
    }
    func updateNSView(_ view: SCNView, context: Context) {
        if view.scene !== scene { view.scene = scene; context.coordinator.first = nil }
        context.coordinator.onDistance = onDistance
    }
    final class Coordinator: NSObject {
        var first: SCNVector3?
        var onDistance: (Double) -> Void
        init(_ callback: @escaping (Double) -> Void) { onDistance = callback }
        @objc func pick(_ gesture: NSClickGestureRecognizer) {
            guard let view = gesture.view as? SCNView,
                  let hit = view.hitTest(gesture.location(in: view), options: nil).first else { return }
            let p = hit.worldCoordinates
            if let a = first {
                let dx = Double(p.x-a.x), dy = Double(p.y-a.y), dz = Double(p.z-a.z)
                onDistance(sqrt(dx*dx+dy*dy+dz*dz)); first = nil
            } else { first = p }
        }
    }
}
