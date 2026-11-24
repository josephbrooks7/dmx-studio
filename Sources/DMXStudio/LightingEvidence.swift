import SwiftUI
import AppKit
import AVFoundation
import AVKit
import UniformTypeIdentifiers

// Camera is active only while this evidence sheet is open. No automatic upload.
final class LightingCamera: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dmx.evidence.camera")
    private let output = AVCapturePhotoOutput()
    private let movie = AVCaptureMovieFileOutput()
    private var recordingURL: URL?
    @Published var recording = false
    @Published var video: URL?
    private var configured = false
    private var wanted = false
    @Published var ready = false
    @Published var image: NSImage?
    @Published var message = ""
    private func fail(_ text: String) {
        DispatchQueue.main.async { self.ready = false; self.message = text }
    }
    func start() {
        queue.async { self.wanted = true }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                if allowed { self?.configure() } else { self?.fail("Camera permission was not granted. You can enable it in System Preferences > Security & Privacy > Camera.") }
            }
        default: fail("Camera access is disabled. Enable DMX Studio in your Mac's Camera privacy settings, or choose an existing photo.")
        }
    }
    private func configure() {
        queue.async {
            guard self.wanted else { return }
            if !self.configured {
                guard let device = AVCaptureDevice.default(for: .video) else { self.fail("No camera found. You can choose a photo instead."); return }
                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    self.session.beginConfiguration()
                    guard self.session.canAddInput(input), self.session.canAddOutput(self.output) else {
                        self.session.commitConfiguration(); self.fail("Camera could not be configured."); return
                    }
                    self.session.addInput(input)
                    self.session.addOutput(self.output)
                    if self.session.canAddOutput(self.movie) {
                        self.session.addOutput(self.movie)
                        self.movie.maxRecordedDuration = CMTime(seconds: 15, preferredTimescale: 600)
                    }
                    self.session.commitConfiguration()
                    self.configured = true
                } catch { self.fail(error.localizedDescription); return }
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.ready = self.session.isRunning; self.message = self.ready ? "" : "Camera unavailable." }
        }
    }
    func stop() {
        queue.async {
            self.wanted = false
            if self.movie.isRecording { self.movie.stopRecording() }
            if self.session.isRunning { self.session.stopRunning() }
        }
        ready = false
    }
    func capture() {
        queue.async {
            guard self.wanted, self.session.isRunning, self.configured else { return }
            self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { fail(error.localizedDescription); return }
        guard let data = photo.fileDataRepresentation(), let photoImage = NSImage(data: data) else { fail("Could not read captured photo."); return }
        DispatchQueue.main.async { self.image = photoImage; self.video = nil }
    }
    func recordVideo() {
        queue.async {
            guard self.wanted, self.session.isRunning, self.configured, !self.movie.isRecording else { return }
            guard self.session.outputs.contains(where: { $0 === self.movie }) else { self.fail("Video recording is unavailable on this camera."); return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("DMX-" + UUID().uuidString + ".mov")
            self.recordingURL = url
            DispatchQueue.main.async { self.image = nil; self.video = nil; self.recording = true }
            self.movie.startRecording(to: url, recordingDelegate: self)
        }
    }
    func stopVideo() {
        queue.async { if self.movie.isRecording { self.movie.stopRecording() } }
    }
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let finished = error == nil || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true)
        DispatchQueue.main.async {
            self.recording = false
            if finished { self.video = outputFileURL; self.image = nil }
            else { self.message = error?.localizedDescription ?? "Recording failed." }
        }
    }
    func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { video = url; image = nil }
    }
    func saveEvidence() -> URL? {
        guard let video else { return savePhoto() }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.movie]
        panel.nameFieldStringValue = "DMX-Lighting-" + String(UUID().uuidString.prefix(8)) + "." + video.pathExtension
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            if url.standardizedFileURL != video.standardizedFileURL {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                try FileManager.default.copyItem(at: video, to: url)
            }
            return url
        } catch { message = error.localizedDescription; return nil }
    }
    func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let photo = NSImage(contentsOf: url) { image = photo; video = nil }
    }
    func savePhoto() -> URL? {
        guard let image, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return nil }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg]
        panel.nameFieldStringValue = "DMX-Lighting-" + String(UUID().uuidString.prefix(8)) + ".jpg"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do { try data.write(to: url, options: .atomic); return url }
        catch { message = error.localizedDescription; return nil }
    }
}

struct LightingCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    final class Preview: NSView {
        override func layout() { super.layout(); layer?.sublayers?.forEach { $0.frame = bounds } }
    }
    func makeNSView(context: Context) -> Preview {
        let view = Preview()
        view.wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspect
        view.layer?.addSublayer(preview)
        return view
    }
    func updateNSView(_ view: Preview, context: Context) {}
}

struct LightingEvidenceSheet: View {
    @StateObject private var camera = LightingCamera()
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var saved: URL?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lighting evidence").font(.title2.bold())
            Text("Aim your camera at the real lights, or select a photo or short video. Nothing is uploaded automatically. GitHub reports in this public repository are visible to others.").foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            ZStack {
                Color.black
                if let image = camera.image { Image(nsImage: image).resizable().scaledToFit() }
                else if let video = camera.video { VideoPlayer(player: AVPlayer(url: video)).id(video) }
                else { LightingCameraPreview(session: camera.session) }
            }.frame(height: 300).cornerRadius(8)
            if !camera.message.isEmpty { Text(camera.message).foregroundColor(.orange) }
            HStack {
                Button("Enable Camera") { camera.start() }
                Button("Take Photo") { camera.capture(); saved = nil }.disabled(!camera.ready || camera.recording)
                Button(camera.recording ? "Stop Recording" : "Record 15s Clip") {
                    if camera.recording { camera.stopVideo() } else { camera.recordVideo(); saved = nil }
                }.disabled(!camera.ready)
                Button("Choose Photo…") { camera.choosePhoto(); saved = nil }.disabled(camera.recording)
                Button("Choose Video…") { camera.chooseVideo(); saved = nil }.disabled(camera.recording)
                Button("Clear") { camera.image = nil; camera.video = nil; saved = nil }.disabled(camera.recording || (camera.image == nil && camera.video == nil))
            }
            if camera.recording { Label("Recording · maximum 15 seconds · no audio", systemImage: "record.circle").foregroundColor(.red) }
            TextField("What are the lights doing?", text: $description)
            if let saved { Text("Saved: " + saved.lastPathComponent + " — attach this file to the GitHub report.").font(.caption).textSelection(.enabled) }
            HStack {
                Button("Save Media…") { saved = camera.saveEvidence() }.disabled(camera.recording || (camera.image == nil && camera.video == nil))
                Button("Open GitHub Report…") {
                    if (camera.image != nil || camera.video != nil) && saved == nil { saved = camera.saveEvidence(); guard saved != nil else { return } }
                    let note = saved.map { "\nMedia saved: " + $0.lastPathComponent + " (attach manually in GitHub)." } ?? ""
                    let problem = AppProblem(area: "Physical lighting", message: description.isEmpty ? "Physical light behavior" : description, details: "Lighting evidence report." + note)
                    ErrorCenter.shared.sendReport(problem)
                    if let saved { NSWorkspace.shared.activateFileViewerSelecting([saved]) }
                }
                .disabled(camera.recording)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(20).frame(width: 620)
        .onDisappear { camera.stop() }
    }
}
