import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SceneKit

private struct LibraryAsset: Codable, Identifiable {
    let id: String
    let name: String
    let kind: String
    let source_format: String
    let model: String
}

struct AssetLibraryView: View {
    var onUseBody: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var assets: [LibraryAsset] = []
    @State private var query = ""
    @State private var category = "All"
    @State private var importKind = "body"
    @State private var busy = false
    @State private var status = "Drop a model or ZIP package here."
    @State private var selected: LibraryAsset?
    @State private var targeted = false
    private var library: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DMX Studio/AssetLibrary", isDirectory: true)
    }
    private var filtered: [LibraryAsset] {
        assets.filter { (category == "All" || $0.kind == category) &&
            (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
    }
    private func url(_ asset: LibraryAsset) -> URL {
        library.appendingPathComponent(asset.id).appendingPathComponent(asset.model)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Asset Library").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
            }
            HStack {
                TextField("Search assets", text: $query)
                Picker("Category", selection: $category) {
                    ForEach(["All", "body", "hair", "clothing", "accessory", "prop"], id: \.self) { Text($0.capitalized).tag($0) }
                }
            }
            HStack {
                Picker("Import as", selection: $importKind) {
                    ForEach(["body", "hair", "clothing", "accessory", "prop"], id: \.self) { Text($0.capitalized).tag($0) }
                }
                Button("Import file…") {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let file = panel.url { start(file) }
                }.disabled(busy)
            }
            Text(status).font(.caption).foregroundColor(.secondary).textSelection(.enabled)
            if busy { ProgressView().controlSize(.small) }
            HStack {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 10) {
                        ForEach(filtered) { asset in
                            Button { selected = asset } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: asset.kind == "body" ? "person.crop.rectangle" : "cube").font(.largeTitle)
                                    Text(asset.name).lineLimit(2)
                                    Text(asset.source_format.uppercased()).font(.caption).foregroundColor(.secondary)
                                }.frame(maxWidth: .infinity, minHeight: 90)
                            }
                        }
                    }
                }
                if let asset = selected {
                    VStack {
                        if let scene = try? SCNScene(url: url(asset), options: nil) {
                            SceneView(scene: scene, options: [.allowsCameraControl, .autoenablesDefaultLighting])
                                .frame(width: 300, height: 320)
                        }
                        Text(asset.name)
                        if asset.kind == "body" {
                            Button("Use on selected performer") { onUseBody(url(asset).path); dismiss() }
                        }
                    }
                }
            }
            .frame(minHeight: 360)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(targeted ? Color.accentColor : Color.secondary.opacity(0.3)))
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { providers in
                guard !busy, let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                    if let file = object as? URL { DispatchQueue.main.async { start(file) } }
                }
                return true
            }
        }.padding(20).frame(width: 780, height: 600).onAppear(perform: reload)
    }
    private func reload() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: library, includingPropertiesForKeys: nil)) ?? []
        assets = folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("asset.json")),
                  let asset = try? JSONDecoder().decode(LibraryAsset.self, from: data),
                  asset.id == folder.lastPathComponent, asset.model == "model.usdz" else { return nil }
            return asset
        }.sorted { $0.name < $1.name }
    }
    private func start(_ file: URL) {
        guard !busy else { return }
        guard let script = Bundle.main.url(forResource: "import-asset", withExtension: "py") else {
            status = "Importer is missing from this build."; return
        }
        let kind = importKind, destination = library
        busy = true; status = "Importing " + file.lastPathComponent + "…"
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            let blender = "/Applications/Blender.app/Contents/MacOS/Blender"
            process.arguments = ["python3", script.path, file.path, destination.path, "--kind", kind,
                "--blender", FileManager.default.isExecutableFile(atPath: blender) ? blender : "blender"]
            process.standardOutput = pipe; process.standardError = pipe
            var message = ""
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                message = process.terminationStatus == 0 ? "Import complete." : String(data: data, encoding: .utf8) ?? "Import failed."
            } catch { message = error.localizedDescription }
            let result = message
            DispatchQueue.main.async { busy = false; status = result; reload() }
        }
    }
}
