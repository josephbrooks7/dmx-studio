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
                        SceneView(scene: preview, options: [.allowsCameraControl, .autoenablesDefaultLighting])
                            .frame(minHeight: 300)
                    } else { Text("Import a self-contained USDZ venue to inspect its geometry.").frame(maxWidth: .infinity, minHeight: 300) }
                    if let v = venue, let d = dimensions {
                        Text(String(format: "Model bounds: %.2f × %.2f × %.2f m", Double(d.x)*v.metersPerUnit, Double(d.y)*v.metersPerUnit, Double(d.z)*v.metersPerUnit))
                        Text(v.referenceMeters == nil ? "Uncalibrated — assumed 1 meter per model unit" : "User-calibrated — not independently verified").font(.caption)
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
        preview = nil; dimensions = nil
        guard let v = venue else { return }
        referenceUnits = v.referenceUnits.map { String($0) } ?? ""
        referenceMeters = v.referenceMeters.map { String($0) } ?? ""
        do {
            let scene = try SCNScene(url: v.url, options: nil)
            let b = scene.rootNode.boundingBox
            dimensions = SCNVector3(b.max.x-b.min.x, b.max.y-b.min.y, b.max.z-b.min.z)
            preview = scene
        } catch { status = error.localizedDescription }
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
