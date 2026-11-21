import SwiftUI
import AppKit

// "Install DMX Studio": a small app that downloads the latest full DMX Studio from the GitHub
// releases, puts it in Applications and opens it (like CapCut's installer).

let repo = "josephbrooks7/dmx-studio"
let appName = "DMX Studio.app"
let appBundleID = "com.redvelvetstudios.dmxstudio"

@main
struct InstallerApp: App {
    @NSApplicationDelegateAdaptor(Delegate.self) var delegate
    var body: some Scene {
        WindowGroup("Install DMX Studio") {
            InstallerView().frame(width: 460, height: 300)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

final class Delegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor
final class Installer: NSObject, ObservableObject, URLSessionDownloadDelegate {
    enum Stage: Equatable { case ready, checking, downloading, installing, done, failed(String) }
    @Published var stage: Stage = .ready
    @Published var progress: Double = 0
    @Published var detail = ""
    @Published var latest: String?
    @Published var installed: String?

    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var resumeData: Data?
    private var assetURL: URL?
    private var totalBytes: Int64 = 0
    private var started = Date()
    private var cont: CheckedContinuation<URL, Error>?

    var target: URL {
        let main = URL(fileURLWithPath: "/Applications")
        return FileManager.default.isWritableFile(atPath: main.path)
            ? main.appendingPathComponent(appName)
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/\(appName)")
    }

    override init() {
        super.init()
        for dir in ["/Applications", NSHomeDirectory() + "/Applications"] {
            let plist = URL(fileURLWithPath: dir).appendingPathComponent("\(appName)/Contents/Info.plist")
            if let d = NSDictionary(contentsOf: plist), let v = d["CFBundleShortVersionString"] as? String { installed = v; break }
        }
        Task { try? await findLatest() }
    }

    /// The newest release and its full DMG
    func findLatest() async throws {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]] else { throw Err("Couldn't reach the download page.") }
        let tag = (json["tag_name"] as? String) ?? ""
        guard let dmg = assets.first(where: { a in
            let n = (a["name"] as? String) ?? ""
            return n.hasSuffix(".dmg") && !n.contains("Installer")
        }), let u = (dmg["browser_download_url"] as? String).flatMap(URL.init(string:)) else {
            throw Err("No download found in the latest release.")
        }
        latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        assetURL = u
        totalBytes = (dmg["size"] as? Int64) ?? Int64((dmg["size"] as? Int) ?? 0)
    }

    func install() {
        Task {
            do {
                stage = .checking; detail = "Finding the latest version…"
                if assetURL == nil { try await findLatest() }
                guard let url = assetURL else { throw Err("No download found.") }
                // room for the download and the installed app
                let free = (try? URL(fileURLWithPath: NSHomeDirectory())
                    .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? nil
                if let free, free < totalBytes * 3 {
                    throw Err("Not enough free space: about \(mb(totalBytes * 3)) is needed.")
                }
                stage = .downloading; progress = 0; started = Date()
                let file = try await download(url)
                stage = .installing; detail = "Installing…"
                try await Task.detached { [target = self.target] in try Installer.put(dmg: file, at: target) }.value
                try? FileManager.default.removeItem(at: file)
                stage = .done; detail = "DMX Studio \(latest ?? "") is installed."
                installed = latest
                NSWorkspace.shared.openApplication(at: target, configuration: .init()) { _, _ in }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSApp.terminate(nil) }
            } catch is CancellationError {
                stage = .ready; detail = ""
            } catch {
                stage = .failed((error as? Err)?.text ?? error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel(byProducingResumeData: { [weak self] data in Task { @MainActor in self?.resumeData = data } })
    }

    private func download(_ url: URL) async throws -> URL {
        let s = session ?? URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        session = s
        return try await withCheckedThrowingContinuation { c in
            cont = c
            // pick up where it stopped if the connection dropped or it was cancelled
            let t = resumeData.map { s.downloadTask(withResumeData: $0) } ?? s.downloadTask(with: url)
            resumeData = nil
            task = t
            t.resume()
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                                totalBytesWritten done: Int64, totalBytesExpectedToWrite total: Int64) {
        Task { @MainActor in
            let all = total > 0 ? total : self.totalBytes
            guard all > 0 else { return }
            self.progress = Double(done) / Double(all)
            let secs = max(1, Date().timeIntervalSince(self.started))
            let rate = Double(done) / secs
            let left = rate > 0 ? Double(all - done) / rate : 0
            self.detail = "\(mb(done)) of \(mb(all))" + (secs > 3 ? " · about \(timeText(left)) left" : "")
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // the temporary file is deleted when this returns: move it somewhere safe first
        let keep = FileManager.default.temporaryDirectory.appendingPathComponent("DMX-Studio-download.dmg")
        try? FileManager.default.removeItem(at: keep)
        let moved = (try? FileManager.default.moveItem(at: location, to: keep)) != nil
        Task { @MainActor in
            if moved { self.cont?.resume(returning: keep) } else { self.cont?.resume(throwing: Err("Couldn't save the download.")) }
            self.cont = nil
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let ns = error as NSError
        let data = ns.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        Task { @MainActor in
            if let data { self.resumeData = data }
            if ns.code == NSURLErrorCancelled { self.cont?.resume(throwing: CancellationError()) }
            else { self.cont?.resume(throwing: Err("The download stopped (\(ns.localizedDescription)). Click Try Again to continue where it left off.")) }
            self.cont = nil
        }
    }

    /// Open the DMG, copy the app into place, close the DMG
    nonisolated static func put(dmg: URL, at target: URL) throws {
        // a running copy has to close before it's replaced
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: appBundleID) {
            app.terminate()
            for _ in 0..<50 where !app.isTerminated { Thread.sleep(forTimeInterval: 0.1) }
            if !app.isTerminated { app.forceTerminate() }
        }
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("dmx-studio-mount-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path])
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]); try? FileManager.default.removeItem(at: mount) }
        let src = mount.appendingPathComponent(appName)
        guard FileManager.default.fileExists(atPath: src.path) else { throw Err("The download didn't contain DMX Studio.") }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = target.deletingLastPathComponent().appendingPathComponent(".DMX Studio installing.app")
        try? FileManager.default.removeItem(at: staging)
        try run("/usr/bin/ditto", [src.path, staging.path])
        // swap the new copy in only once it's fully copied
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.moveItem(at: staging, to: target)
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", target.path])
    }

    @discardableResult
    nonisolated static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out; p.standardError = out
        try p.run(); p.waitUntilExit()
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus != 0 { throw Err("Install step failed: \(text.trimmingCharacters(in: .whitespacesAndNewlines))") }
        return text
    }
}

struct Err: Error { let text: String; init(_ t: String) { text = t } }

func mb(_ b: Int64) -> String {
    b >= 1_000_000_000 ? String(format: "%.1f GB", Double(b) / 1e9) : "\(b / 1_000_000) MB"
}
func timeText(_ s: Double) -> String { s < 60 ? "\(Int(s)) sec" : "\(Int(s / 60) + 1) min" }

struct InstallerView: View {
    @StateObject private var ins = Installer()

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("DMX Studio").font(.title.bold())
                    Text(subtitle).font(.callout).foregroundColor(.secondary)
                }
                Spacer()
            }
            Spacer()
            switch ins.stage {
            case .downloading:
                ProgressView(value: ins.progress)
                Text(ins.detail).font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            case .checking, .installing:
                ProgressView().scaleEffect(0.7)
                Text(ins.detail).font(.caption).foregroundColor(.secondary)
            case .done:
                Label(ins.detail, systemImage: "checkmark.circle.fill").foregroundColor(.green)
            case .failed(let msg):
                Label(msg, systemImage: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            case .ready:
                Text("Downloads the full app (about 550 MB, includes the lyric and stems models so it works offline) and puts it in Applications.")
                    .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            HStack {
                if ins.stage == .downloading { Button("Cancel") { ins.cancel() }.keyboardShortcut(.cancelAction) }
                else { Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut(.cancelAction) }
                Spacer()
                Button(buttonTitle) { ins.install() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(ins.stage == .downloading || ins.stage == .checking || ins.stage == .installing || ins.stage == .done)
            }
        }
        .padding(24)
    }

    var subtitle: String {
        switch (ins.installed, ins.latest) {
        case let (i?, l?) where i == l: return "Version \(l) · already installed"
        case let (i?, l?): return "Installed \(i) · new version \(l)"
        case let (nil, l?): return "Version \(l)"
        default: return "Installer"
        }
    }
    var buttonTitle: String {
        if case .failed = ins.stage { return "Try Again" }
        if let i = ins.installed, let l = ins.latest { return i == l ? "Reinstall" : "Update" }
        return "Install"
    }
}
