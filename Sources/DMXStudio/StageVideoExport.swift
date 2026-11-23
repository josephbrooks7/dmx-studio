import SwiftUI
import SceneKit
import AVFoundation
import AppKit
import Metal
import UniformTypeIdentifiers

/// Makes a video of a song's light show on the 3D stage, with the song's audio, to show people
/// what the show looks like. Each frame is the show at that moment (the same lights the app sends),
/// drawn on a copy of your venue from a fixed camera. Nothing on the real lights changes.
@MainActor
final class StageVideoExporter: ObservableObject {
    @Published var progress: Double? = nil      // 0…1 while exporting
    @Published var status = ""
    @Published var finishedURL: URL? = nil
    @Published var error: String? = nil
    private var cancelled = false

    enum Quality: String, CaseIterable, Identifiable {
        case hd720 = "720p (faster)", hd1080 = "1080p"
        var id: String { rawValue }
        var size: CGSize { self == .hd720 ? CGSize(width: 1280, height: 720) : CGSize(width: 1920, height: 1080) }
    }

    func cancel() { cancelled = true }

    func export(model: AppModel, songID: UUID, camera: String, quality: Quality, showLabels: Bool, to outURL: URL) async {
        cancelled = false; error = nil; finishedURL = nil
        guard let song = model.song(songID), let a = song.analysis, let show = song.activeShow else {
            error = "Learn this song and make a show for it first."; return
        }
        let fps = 30.0
        let duration = a.duration
        let frames = Int(duration * fps)
        let size = quality.size
        progress = 0; status = "Setting up the stage…"

        // a copy of the venue, drawn off screen
        let stage = Stage3DView.Coordinator(model: model)
        stage.sync()
        stage.setCamera(camera)
        guard let device = MTLCreateSystemDefaultDevice() else { error = "This Mac's graphics can't draw the video."; progress = nil; return }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = stage.scene
        renderer.pointOfView = stage.camera

        let tmpVideo = FileManager.default.temporaryDirectory.appendingPathComponent("dmx-stage-\(UUID().uuidString).mov")
        do {
            let writer = try AVAssetWriter(outputURL: tmpVideo, fileType: .mov)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: quality == .hd720 ? 6_000_000 : 10_000_000]
            ])
            input.expectsMediaDataInRealTime = false
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height)
            ])
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? NSError(domain: "video", code: 1) }
            writer.startSession(atSourceTime: .zero)

            let idleFrame = model.idle.render(fixtures: model.fixtures, time: 0)
            let started = Date()
            for f in 0..<frames {
                if cancelled { writer.cancelWriting(); try? FileManager.default.removeItem(at: tmpVideo); progress = nil; status = "Cancelled"; return }
                let t = Double(f) / fps
                var frame = model.songFrame(songID, show: show.id, at: t, idleFrame: idleFrame) ?? idleFrame
                for i in frame.indices { if let src = model.copySource(of: i), src < frame.count { frame[i] = frame[src] } }
                stage.applyFrame(frame, now: t, master: 1)
                let image = renderer.snapshot(atTime: t, with: size, antialiasingMode: quality == .hd720 ? .multisampling2X : .multisampling4X)
                while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
                if let pool = adaptor.pixelBufferPool, let buf = pixelBuffer(image, pool: pool, size: size,
                                                                              label: showLabels ? label(show, at: t, song: song) : nil) {
                    adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: CMTimeScale(fps)))
                }
                if f % 15 == 0 {
                    let done = Double(f + 1) / Double(frames)
                    progress = done * 0.95
                    let spent = Date().timeIntervalSince(started)
                    let left = done > 0.01 ? spent / done - spent : 0
                    status = "Drawing the show… \(Int(done * 100))%" + (left > 5 ? " · about \(Self.mmss(left)) left" : "")
                    await Task.yield()
                }
            }
            input.markAsFinished()
            await writer.finishWriting()
            if writer.status != .completed { throw writer.error ?? NSError(domain: "video", code: 2) }

            // add the song's audio
            status = "Adding the music…"; progress = 0.96
            let comp = AVMutableComposition()
            let vAsset = AVURLAsset(url: tmpVideo), aAsset = AVURLAsset(url: song.url)
            let range = CMTimeRange(start: .zero, duration: CMTime(seconds: Double(frames) / fps, preferredTimescale: 600))
            if let vt = vAsset.tracks(withMediaType: .video).first,
               let ct = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try ct.insertTimeRange(range, of: vt, at: .zero)
            }
            if let at = aAsset.tracks(withMediaType: .audio).first,
               let ct = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                let aRange = CMTimeRange(start: .zero, duration: min(range.duration, aAsset.duration))
                try ct.insertTimeRange(aRange, of: at, at: .zero)
            }
            try? FileManager.default.removeItem(at: outURL)
            guard let exp = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else {
                throw NSError(domain: "video", code: 3, userInfo: [NSLocalizedDescriptionKey: "Couldn't start the final export"])
            }
            exp.outputURL = outURL
            exp.outputFileType = .mp4
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in exp.exportAsynchronously { c.resume() } }
            try? FileManager.default.removeItem(at: tmpVideo)
            guard exp.status == .completed else { throw exp.error ?? NSError(domain: "video", code: 4) }
            progress = nil; status = "Saved"; finishedURL = outURL
        } catch {
            try? FileManager.default.removeItem(at: tmpVideo)
            progress = nil; self.error = "The video couldn't be made: \(error.localizedDescription)"
        }
    }

    /// "Chorus 2" for the moment t (phrases inside a part count as the part)
    private func label(_ show: LightShow, at t: Double, song: Song) -> String {
        let parts = show.sections.filter { $0.transition == nil && $0.empty != true }
        let cur = parts.last { $0.start <= t + 0.05 }?.name ?? ""
        return (cur.components(separatedBy: "·").first ?? cur).trimmingCharacters(in: .whitespaces)
    }

    private func pixelBuffer(_ image: NSImage, pool: CVPixelBufferPool, size: CGSize, label: String?) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        guard let buf = pb else { return nil }
        CVPixelBufferLockBaseAddress(buf, [])
        defer { CVPixelBufferUnlockBaseAddress(buf, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: Int(size.width), height: Int(size.height),
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        ctx.draw(cg, in: CGRect(origin: .zero, size: size))
        if let label, !label.isEmpty {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            let font = NSFont.systemFont(ofSize: size.height * 0.04, weight: .heavy)
            let text = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.9)])
            let pad = size.height * 0.03
            let ts = text.size()
            NSColor.black.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: NSRect(x: pad, y: pad, width: ts.width + pad, height: ts.height + pad * 0.6),
                         xRadius: pad * 0.4, yRadius: pad * 0.4).fill()
            text.draw(at: NSPoint(x: pad * 1.5, y: pad * 1.3))
            NSGraphicsContext.restoreGraphicsState()
        }
        return buf
    }

    static func mmss(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}

/// The Export Video window: pick the song, the camera and the size, then save an .mp4.
struct StageVideoExportSheet: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var exporter = StageVideoExporter()
    @Environment(\.dismiss) private var dismiss
    @State private var songID: UUID?
    @State private var camera = "Overview"
    @State private var quality: StageVideoExporter.Quality = .hd720
    @State private var labels = true

    private var songs: [Song] { model.songs.filter { $0.analysis != nil && $0.activeShow != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export a Video of the Show").font(.title2.bold())
            Text("Makes an .mp4 of the 3D stage running the song's light show, with the music, to show people what the show looks like. Your real lights aren't touched.")
                .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Form {
                Picker("Song", selection: $songID) {
                    ForEach(songs) { s in Text(s.displayName).tag(Optional(s.id)) }
                }
                Picker("Camera", selection: $camera) {
                    ForEach(["Overview", "Audience", "Close-up", "Side", "Top"], id: \.self) { Text($0).tag($0) }
                }
                Picker("Size", selection: $quality) {
                    ForEach(StageVideoExporter.Quality.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Show the part names (Verse 1, Chorus…) in the corner", isOn: $labels)
            }
            if let p = exporter.progress {
                ProgressView(value: p)
                Text(exporter.status).font(.caption).foregroundColor(.secondary)
            } else if let url = exporter.finishedURL {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Saved \(url.lastPathComponent)").lineLimit(1)
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            }
            if let e = exporter.error { Text(e).font(.caption).foregroundColor(.red) }
            Text("Drawing takes a while on older Macs (often a few minutes for a 3-minute song at 720p). Keep the app open until it's done.")
                .font(.caption).foregroundColor(.secondary)
            HStack {
                Spacer()
                if exporter.progress != nil {
                    Button("Cancel") { exporter.cancel() }
                } else {
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Export…") { save() }.keyboardShortcut(.defaultAction).disabled(songID == nil)
                }
            }
        }
        .padding(22)
        .frame(width: 520)
        .onAppear { songID = model.playingSongID ?? model.selectedSongID ?? songs.first?.id }
    }

    private func save() {
        guard let id = songID, let s = model.song(id) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "\(s.title) - light show.mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await exporter.export(model: model, songID: id, camera: camera, quality: quality, showLabels: labels, to: url) }
    }
}
