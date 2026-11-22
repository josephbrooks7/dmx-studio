import SwiftUI
import AppKit

/// Updates DMX Studio in place: downloads only the new app (a few MB, no AI models), keeps the
/// lyric and stems models already installed, swaps the app and restarts. Falls back to the full
/// download only when a new version needs a model this copy doesn't have.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    enum State: Equatable {
        case idle, checking, upToDate, available(String), downloading(Double, String), installing(String, Double), failed(String)
    }
    @Published var state: State = .idle
    @Published var showing = false
    @Published var notes = ""
    @Published var stepStarted = Date()
    var isInstalling: Bool { if case .installing = state { return true }; return false }
    private func step(_ text: String, _ f: Double) throws {
        if cancelled { throw CancellationError() }
        state = .installing(text, f); stepStarted = Date()
    }
    /// Cancel works until the old version is being replaced (a few seconds at the end)
    @Published var canCancel = false
    private var cancelled = false
    private var downloadTask: URLSessionDownloadTask?
    func cancel() {
        guard canCancel else { return }
        cancelled = true
        downloadTask?.cancel()
        RunningStep.process?.terminate()
    }

    private let repo = "josephbrooks7/dmx-studio"
    private var latest: String?
    private var updateZip: URL?
    private var fullDMG: URL?
    private var fullSize: Int64 = 0
    private var observer: NSKeyValueObservation?

    var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
    var availableVersion: String? { if case .available(let v) = state { return v }; return nil }

    /// Menu: Check for Updates…
    func checkNow() {
        showing = true
        Task { await check() }
    }

    /// On launch: look once a day, say nothing unless there's an update
    func checkQuietly() {
        let key = "updater.lastCheck"
        let last = UserDefaults.standard.double(forKey: key)
        guard Date().timeIntervalSince1970 - last > 20 * 3600 else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
        Task { await check(); if case .failed = state { state = .idle } }
    }

    func check() async {
        state = .checking
        do {
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 20
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let assets = json["assets"] as? [[String: Any]] else { throw UpdateError("Couldn't reach the update page.") }
            let tag = (json["tag_name"] as? String) ?? ""
            let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            func asset(_ match: (String) -> Bool) -> [String: Any]? { assets.first { match(($0["name"] as? String) ?? "") } }
            updateZip = (asset { $0 == "DMX-Studio-Update.zip" }?["browser_download_url"] as? String).flatMap(URL.init(string:))
            let full = asset { $0.hasSuffix(".dmg") && !$0.contains("Installer") }
            fullDMG = (full?["browser_download_url"] as? String).flatMap(URL.init(string:))
            fullSize = (full?["size"] as? NSNumber)?.int64Value ?? 0
            notes = (json["body"] as? String) ?? ""
            latest = v
            state = Self.newer(v, than: current) ? .available(v) : .upToDate
        } catch {
            state = .failed((error as? UpdateError)?.text ?? "Couldn't check for updates (\(error.localizedDescription)).")
        }
    }

    static func newer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for k in 0..<max(x.count, y.count) {
            let p = k < x.count ? x[k] : 0, q = k < y.count ? y[k] : 0
            if p != q { return p > q }
        }
        return false
    }

    func install() {
        cancelled = false
        canCancel = true
        Task {
            do {
                let app = Bundle.main.bundleURL
                guard FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path),
                      !app.path.hasPrefix("/Volumes/") else {
                    throw UpdateError("DMX Studio is running from the disk image. Drag it into Applications first, then update.")
                }
                let work = FileManager.default.temporaryDirectory.appendingPathComponent("dmx-update-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: work) }

                var newApp: URL?
                var moved: [(from: URL, to: URL)] = []
                // 1. the small download: the app without its AI models
                if let zip = updateZip {
                    let file = try await download(zip, label: "Downloading the update")
                    try step("Step 1 of 4 · Unpacking the update", 0.1)
                    try await Self.shell("/usr/bin/ditto", ["-x", "-k", file.path, work.path], timeout: 120)
                    let candidate = work.appendingPathComponent("DMX Studio.app")
                    try step("Step 2 of 4 · Moving your lyric and stems models into the new version", 0.3)
                    if let m = try Self.reuseModels(from: app, into: candidate) { newApp = candidate; moved = m }
                }
                // 2. a new model is needed (or no small update was published): the full download
                if newApp == nil {
                    guard let dmg = fullDMG else { throw UpdateError("No update download found.") }
                    let file = try await download(dmg, label: "Downloading the full app (it includes a new AI model)")
                    try step("Step 2 of 4 · Copying the new version", 0.3)
                    newApp = try await Self.copyFromDMG(file, into: work)
                }
                guard let fresh = newApp else { throw UpdateError("The update didn't contain DMX Studio.") }
                do {
                    try step("Step 3 of 4 · Checking and signing the new version", 0.55)
                    try await Self.shell("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", fresh.path], timeout: 600)
                    _ = try? await Self.shell("/usr/bin/xattr", ["-dr", "com.apple.quarantine", fresh.path], timeout: 60)

                    // 3. swap: the old copy goes to the Trash, the new one takes its place
                    try step("Step 4 of 4 · Replacing the old version", 0.9)
                    canCancel = false
                    var trashed: NSURL?
                    try FileManager.default.trashItem(at: app, resultingItemURL: &trashed)
                    do { try FileManager.default.moveItem(at: fresh, to: app) }
                    catch {
                        if let t = trashed as URL? { try? FileManager.default.moveItem(at: t, to: app) }
                        throw error
                    }
                } catch {
                    // put the models back so the current version keeps working
                    for m in moved.reversed() { try? FileManager.default.moveItem(at: m.to, to: m.from) }
                    throw error
                }
                try step("Done · restarting", 1)
                Self.relaunch(app)
            } catch {
                canCancel = false
                if cancelled || error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                    state = latest.map { .available($0) } ?? .idle    // nothing changed: back to "Update Now"
                } else {
                    state = .failed((error as? UpdateError)?.text ?? error.localizedDescription)
                }
            }
        }
    }

    // MARK: steps

    private func download(_ url: URL, label: String) async throws -> URL {
        state = .downloading(0, label)
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<URL, Error>) in
            let task = URLSession.shared.downloadTask(with: url) { loc, resp, err in
                if let err { c.resume(throwing: err); return }
                guard let loc, (resp as? HTTPURLResponse)?.statusCode == 200 else {
                    c.resume(throwing: UpdateError("The download failed.")); return
                }
                // keep the file: the temporary one is deleted when this returns
                let keep = FileManager.default.temporaryDirectory.appendingPathComponent("dmx-dl-\(UUID().uuidString)-\(url.lastPathComponent)")
                do { try FileManager.default.moveItem(at: loc, to: keep); c.resume(returning: keep) }
                catch { c.resume(throwing: error) }
            }
            observer = task.progress.observe(\.fractionCompleted) { p, _ in
                let f = p.fractionCompleted
                Task { @MainActor in
                    if case .downloading(_, let l) = self.state { self.state = .downloading(f, l) }
                }
            }
            downloadTask = task
            task.resume()
        }
    }

    /// Move the models this copy already has into the new app (a rename: instant, no copying).
    /// nil if the new version lists a model that isn't here (or that changed size).
    nonisolated static func reuseModels(from old: URL, into new: URL) throws -> [(from: URL, to: URL)]? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: new.path) else { return nil }
        let list = new.appendingPathComponent("Contents/Resources/models.txt")
        guard let text = try? String(contentsOf: list) else { return nil }
        let oldModels = old.appendingPathComponent("Contents/Resources/Models")
        let newModels = new.appendingPathComponent("Contents/Resources/Models")
        var plan: [(from: URL, to: URL)] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            guard parts.count == 2, let size = Int64(parts[1]) else { continue }
            let name = String(parts[0])
            let src = oldModels.appendingPathComponent(name)
            guard fm.fileExists(atPath: src.path), bytes(src) == size else { return nil }
            plan.append((src, newModels.appendingPathComponent(name)))
        }
        try fm.createDirectory(at: newModels, withIntermediateDirectories: true)
        var done: [(from: URL, to: URL)] = []
        do {
            for m in plan {
                // same disk: a move is a rename. Another disk: falls back to a copy
                do { try fm.moveItem(at: m.from, to: m.to) }
                catch { try fm.copyItem(at: m.from, to: m.to); continue }
                done.append(m)
            }
        } catch {
            for m in done.reversed() { try? fm.moveItem(at: m.to, to: m.from) }
            throw error
        }
        return done
    }

    /// Total bytes of a file or folder (a compiled model is a folder)
    nonisolated static func bytes(_ url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return -1 }
        if !isDir.boolValue { return ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? -1 }
        var total: Int64 = 0
        let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        while let f = e?.nextObject() as? URL {
            let v = try? f.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if v?.isRegularFile == true { total += Int64(v?.fileSize ?? 0) }
        }
        return total
    }

    nonisolated static func copyFromDMG(_ dmg: URL, into work: URL) async throws -> URL {
        let mount = work.appendingPathComponent("mount")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try await shell("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path])
        defer { Task { _ = try? await shell("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) } }
        let dst = work.appendingPathComponent("full/DMX Studio.app")
        try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await shell("/usr/bin/ditto", [mount.appendingPathComponent("DMX Studio.app").path, dst.path])
        try? FileManager.default.removeItem(at: dmg)
        return dst
    }

    /// Run a tool and wait for it on a plain background thread (the same way Learn's helper runs):
    /// check every 50 ms whether it's done, with a time limit. No termination callbacks or readability
    /// handlers: those fired after the step was cleaned up and crashed the app during an update.
    @discardableResult
    nonisolated static func shell(_ tool: String, _ args: [String], timeout: Double = 300) async throws -> String {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .utility).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: tool)
                p.arguments = args
                let out = Pipe()
                p.standardOutput = out; p.standardError = out
                var data = Data()
                let reader = DispatchGroup()
                reader.enter()
                DispatchQueue.global(qos: .utility).async { data = out.fileHandleForReading.readDataToEndOfFile(); reader.leave() }
                do { try p.run() } catch {
                    try? out.fileHandleForWriting.close()
                    reader.wait()
                    c.resume(throwing: error); return
                }
                RunningStep.process = p
                let deadline = Date().addingTimeInterval(timeout)
                while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
                let timedOut = p.isRunning
                if timedOut { p.terminate(); Thread.sleep(forTimeInterval: 0.3) }
                if p.isRunning { kill(p.processIdentifier, SIGKILL) }
                reader.wait()
                RunningStep.process = nil
                let name = (tool as NSString).lastPathComponent
                let text = String(decoding: data, as: UTF8.self)
                if timedOut {
                    c.resume(throwing: UpdateError("An update step took too long (\(name)). Nothing was changed: try again, or use the installer."))
                } else if p.terminationStatus != 0 {
                    c.resume(throwing: UpdateError("Update step failed (\(name)): \(text.trimmingCharacters(in: .whitespacesAndNewlines).suffix(300))"))
                } else {
                    c.resume(returning: text)
                }
            }
        }
    }

    /// Quit, and open the new copy once this one has closed
    static func relaunch(_ app: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.3; done; open \"\(app.path)\""]
        try? p.run()
        // A normal quit can be held up (an open sheet, a window that won't close), which left the
        // update stuck on "Done · restarting". Save, then leave directly; the helper opens the new copy.
        Updater.shared.showing = false
        // leave even if shutting down the audio gets stuck (that held up quitting before)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { _exit(0) }
        AppModel.current?.prepareToQuit()
        _exit(0)
    }
}

struct UpdateError: Error { let text: String; init(_ t: String) { text = t } }

struct UpdateSheet: View {
    @ObservedObject var up = Updater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Software Update").font(.title3.bold())
                    Text("This version: \(up.current)").font(.caption).foregroundColor(.secondary)
                }
            }
            Group {
                switch up.state {
                case .idle, .checking:
                    HStack { ProgressView().scaleEffect(0.6); Text("Checking for updates…") }
                case .upToDate:
                    Label("DMX Studio is up to date.", systemImage: "checkmark.circle.fill").foregroundColor(.green)
                case .available(let v):
                    Text("Version \(v) is available.").font(.headline)
                    Text("Only the app is downloaded (a few MB): your lyric and stems models, songs and shows stay as they are. DMX Studio restarts when it's done.")
                        .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                case .downloading(let f, let label):
                    Text(label + "…")
                    ProgressView(value: f)
                case .installing(let text, let f):
                    InstallStepView(text: text, fraction: f, started: up.stepStarted)
                case .failed(let msg):
                    Label(msg, systemImage: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                if up.canCancel {
                    Button("Cancel") { up.cancel() }.keyboardShortcut(.cancelAction)
                } else {
                    Button(up.availableVersion == nil ? "Close" : "Later") { up.showing = false }
                        .keyboardShortcut(.cancelAction)
                        .disabled(up.isInstalling)
                }
                if up.availableVersion != nil && !up.canCancel {
                    Button("Update Now") { up.install() }.keyboardShortcut(.defaultAction)
                } else if case .failed = up.state {
                    Button("Try Again") { Task { await up.check() } }
                }
            }
        }
        .padding(22)
        .frame(width: 440, height: 230)
    }
}

/// A small button that appears in the header when an update is waiting
struct UpdateBadge: View {
    @ObservedObject var up = Updater.shared
    var body: some View {
        if let v = up.availableVersion {
            Button { up.showing = true } label: {
                Label("Update \(v)", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.selection.opacity(0.35)))
                    .overlay(Capsule().stroke(Theme.selection))
            }
            .buttonStyle(.plain)
            .help("A new version of DMX Studio is ready to install")
        }
    }
}

/// One install step: its name, the overall progress and how long this step has taken
struct InstallStepView: View {
    let text: String
    let fraction: Double
    let started: Date
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
            ProgressView(value: fraction)
            Text("This step: \(elapsed) · DMX Studio restarts when it's done")
                .font(.caption).foregroundColor(.secondary)
        }
        .onReceive(tick) { now = $0 }
    }

    private var elapsed: String {
        let s = max(0, Int(now.timeIntervalSince(started)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// The tool an update step is running right now (so Cancel can stop it)
enum RunningStep { static var process: Process? }
