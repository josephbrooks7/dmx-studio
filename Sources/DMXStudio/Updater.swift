import SwiftUI
import AppKit
import Security

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

    @Published var automaticUpdates = UserDefaults.standard.bool(forKey: "updater.automatic") {
        didSet {
            UserDefaults.standard.set(automaticUpdates, forKey: "updater.automatic")
            if automaticUpdates { startAutomaticChecks() }
        }
    }
    @Published var remoteUpdates = UserDefaults.standard.bool(forKey: "updater.remote") {
        didSet {
            UserDefaults.standard.set(remoteUpdates, forKey: "updater.remote")
            if remoteUpdates { startAutomaticChecks() }
        }
    }
    @Published var remoteStatus = "No remote request pending"
    @Published var statusReporting = UserDefaults.standard.bool(forKey: "updater.statusReporting") {
        didSet {
            UserDefaults.standard.set(statusReporting, forKey: "updater.statusReporting")
            if statusReporting { startAutomaticChecks() }
        }
    }
    @Published var statusReportMessage = "Not connected"
    private var lastStatusReport = Date.distantPast
    private var lastStatusBody = ""
    private var statusRequestRunning = false
    private let statusService = "com.redvelvetstudios.dmxstudio.remote-status"

    // Credentials are local to this Mac, never embedded in the application or repository.
    func saveStatusToken(_ token: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: statusService, kSecAttrAccount as String: "github"]
        SecItemDelete(query as CFDictionary)
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusReporting = false; statusReportMessage = "Token removed"; return
        }
        var item = query
        item[kSecValueData as String] = Data(token.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let result = SecItemAdd(item as CFDictionary, nil)
        statusReportMessage = result == errSecSuccess ? "Token saved" : "Could not save token in Keychain"
        if result == errSecSuccess {
            lastStatusReport = .distantPast
            statusReporting = true
            Task { await reportMacStatus() }
        }
    }
    private func statusToken() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: statusService, kSecAttrAccount as String: "github",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private func reportMacStatus() async {
        guard statusReporting, !statusRequestRunning else { return }
        let phase: String
        switch state {
        case .downloading(let f, _): phase = "Downloading " + String(Int(max(0,min(1,f))*100)) + "%"
        case .installing(_, let f): phase = "Installing " + String(Int(max(0,min(1,f))*100)) + "%"
        case .checking: phase = "Checking for updates"
        case .available(let v): phase = "Update " + v + " available"
        case .failed: phase = "Update failed"
        default: phase = safeToUpdate ? "Idle" : "Busy"
        }
        let body = "DMX Studio status: installed " + current + " | " + phase
        guard Date().timeIntervalSince(lastStatusReport) >= 300 ||
            (body != lastStatusBody && Date().timeIntervalSince(lastStatusReport) >= 60) else { return }
        guard let token = statusToken() else { statusReportMessage = "Enter a GitHub token first"; return }
        statusRequestRunning = true
        defer { statusRequestRunning = false }
        lastStatusReport = Date()
        // Status is published only to the explicitly configured private repository.
        let destination = UserDefaults.standard.string(forKey: "updater.statusRepo") ?? ""
        let parts = destination.split(separator: "/")
        guard parts.count == 2, parts.allSatisfy({ $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) } }) else {
            statusReportMessage = "Set a private owner/repository"; return
        }
        do {
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(destination)")!)
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 15
            let (info, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: info) as? [String: Any],
                  json["private"] as? Bool == true else {
                statusReportMessage = "Status repository must be private and accessible"; return
            }
            let issue = UserDefaults.standard.integer(forKey: "updater.statusIssue")
            guard issue > 0 else { statusReportMessage = "Set a status issue number"; return }
            req.url = URL(string: "https://api.github.com/repos/\(destination)/issues/\(issue)")
            req.httpMethod = "PATCH"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["body": body + "\nReported at: " + ISO8601DateFormatter().string(from: Date())])
            let (_, result) = try await URLSession.shared.data(for: req)
            guard (result as? HTTPURLResponse)?.statusCode == 200 else { statusReportMessage = "Status report rejected"; return }
            lastStatusBody = body
            statusReportMessage = "Status reported successfully"
        } catch { statusReportMessage = "Status connection unavailable" }
    }

    private var lastRemoteCheck = Date.distantPast
    private var remoteCheckRunning = false
    // Avoid hammering the shared unauthenticated GitHub API quota on failure.
    private var remoteRetryAfter = Date.distantPast
    private var releaseRetryAfter = Date.distantPast

    private static func rateLimitDeadline(_ response: HTTPURLResponse) -> Date {
        if let retry = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = TimeInterval(retry), seconds > 0 {
            return Date().addingTimeInterval(min(seconds, 86400))
        }
        if let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
           let timestamp = TimeInterval(reset), timestamp > Date().timeIntervalSince1970 {
            return Date(timeIntervalSince1970: timestamp).addingTimeInterval(5)
        }
        return Date().addingTimeInterval(900)
    }
    private static func isRateLimited(_ response: HTTPURLResponse) -> Bool {
        response.statusCode == 429 ||
            (response.statusCode == 403 && response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0")
    }
    private var remoteRequest: Int?
    private var remoteInstalling = false

    // Only exact, recent requests authored by the repository owner's authenticated
    // GitHub identity are accepted. No arbitrary URLs, commands, or versions.
    private func pollRemoteRequest() async {
        guard remoteUpdates, !remoteCheckRunning, Date() >= remoteRetryAfter, Date().timeIntervalSince(lastRemoteCheck) >= 900 else { return }
        remoteCheckRunning = true
        defer { remoteCheckRunning = false }
        lastRemoteCheck = Date()
        do {
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/issues?state=open&sort=created&direction=desc&per_page=30")!)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { remoteStatus = "Remote check: invalid response"; return }
            guard http.statusCode == 200 else {
                if Self.isRateLimited(http) { remoteRetryAfter = Self.rateLimitDeadline(http) }
                remoteStatus = Self.isRateLimited(http) ? "GitHub rate limit reached — remote check will retry later" : "Remote check unavailable (HTTP \(http.statusCode)) — will retry"
                return
            }
            guard let issues = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { remoteStatus = "Remote check: invalid issue data"; return }
            if remoteRequest == nil { remoteStatus = "No remote request pending" }
            let consumed = UserDefaults.standard.integer(forKey: "updater.remoteConsumed")
            let fmt = ISO8601DateFormatter()
            for issue in issues {
                guard issue["pull_request"] == nil, issue["title"] as? String == "DMX Studio: Update this Mac",
                    let user = issue["user"] as? [String: Any], (user["id"] as? NSNumber)?.intValue == 113914577,
                    let number = (issue["number"] as? NSNumber)?.intValue, number > consumed,
                    let stamp = issue["created_at"] as? String, let date = fmt.date(from: stamp),
                    Date().timeIntervalSince(date) >= -60, Date().timeIntervalSince(date) < 86400 else { continue }
                remoteRequest = number
                remoteStatus = "Remote update requested — waiting for idle"
                return
            }
        } catch { remoteStatus = "Remote check unavailable — will retry" }
    }

    private var automaticTimer: Timer?
    private var idleSince: Date?
    private var lastAutomaticCheck = Date.distantPast
    private var automaticAttempt: String?
    private var installingAutomatically = false
    private var safeToUpdate: Bool {
        guard let m = AppModel.current else { return false }
        return !m.outputEnabled && !m.isPlaying && m.activePresetID == nil &&
            m.activeBlock == nil && m.cuedEntry == nil && !m.inGap && m.learning.isEmpty
    }

    private func startAutomaticChecks() {
        guard automaticTimer == nil else { return }
        automaticTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.automaticTick() }
        }
        Task { await automaticTick() }
    }

    private func automaticTick() async {
        guard automaticUpdates || remoteUpdates || statusReporting else { idleSince = nil; return }
        await reportMacStatus()
        await pollRemoteRequest()
        guard safeToUpdate else { idleSince = nil; return }
        guard automaticUpdates || (remoteUpdates && remoteRequest != nil) else { return }
        if idleSince == nil { idleSince = Date() }
        guard Date().timeIntervalSince(idleSince ?? Date()) >= 60, !canCancel, !isInstalling else { return }
        if case .checking = state { return }
        if case .downloading = state { return }
        if Date().timeIntervalSince(lastAutomaticCheck) >= 300 {
            lastAutomaticCheck = Date()
            await check()
        }
        guard safeToUpdate, automaticUpdates || (remoteUpdates && remoteRequest != nil) else { return }
        if case .upToDate = state, let number = remoteRequest {
            UserDefaults.standard.set(number, forKey: "updater.remoteConsumed")
            remoteRequest = nil
            remoteStatus = "Already up to date"
        }
        guard let version = availableVersion, automaticAttempt != version else { return }
        automaticAttempt = version
        installingAutomatically = true
        remoteInstalling = remoteUpdates && remoteRequest != nil
        if remoteInstalling { remoteStatus = "Installing requested update" }
        showing = true
        install()
    }

    /// On launch: look once a day, say nothing unless there's an update
    func checkQuietly() {
        if automaticUpdates || remoteUpdates || statusReporting { startAutomaticChecks(); return }
        let key = "updater.lastCheck"
        let last = UserDefaults.standard.double(forKey: key)
        guard Date().timeIntervalSince1970 - last > 20 * 3600 else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
        Task { await check(); if case .failed = state { state = .idle } }
    }

    // The public latest-release redirect does not consume REST API quota.
    private func checkPublicRelease() async throws {
        var request = URLRequest(url: URL(string: "https://github.com/\(repo)/releases/latest")!)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let url = http.url, url.scheme == "https", url.host == "github.com",
              url.path.hasPrefix("/\(repo)/releases/tag/") else {
            throw UpdateError("Public release check unavailable.")
        }
        let tag = url.lastPathComponent
        let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let parts = v.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ Int($0) != nil && !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else {
            throw UpdateError("Invalid public release version.")
        }
        let base = URL(string: "https://github.com/\(repo)/releases/download/")!.appendingPathComponent(tag)
        updateZip = base.appendingPathComponent("DMX-Studio-Update.zip")
        fullDMG = base.appendingPathComponent("DMX-Studio-\(v).dmg")
        fullSize = 0
        notes = "Release notes: https://github.com/\(repo)/releases/tag/\(tag)"
        latest = v
        state = Self.newer(v, than: current) ? .available(v) : .upToDate
    }

    func check() async {
        if case .checking = state { return }
        if case .downloading = state { return }
        guard !isInstalling, !canCancel else { return }
        state = .checking
        if Date() < releaseRetryAfter {
            do { try await checkPublicRelease() }
            catch { state = .failed("GitHub API rate limited; public release check also unavailable.") }
            return
        }
        do {
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 20
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw UpdateError("Invalid update server response.") }
            guard http.statusCode == 200 else {
                let limited = Self.isRateLimited(http)
                if limited {
                    releaseRetryAfter = Self.rateLimitDeadline(http)
                    try await checkPublicRelease()
                    return
                }
                throw UpdateError(limited ? "GitHub update checks are rate limited. Please retry later." : "Update server returned HTTP \(http.statusCode).")
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let assets = json["assets"] as? [[String: Any]] else { throw UpdateError("Invalid release metadata.") }
            guard let tag = json["tag_name"] as? String, !tag.isEmpty else { throw UpdateError("Release version is missing.") }
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
        guard !canCancel, !isInstalling else { return }
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

                    // Recheck after downloads/signing: never replace the app if a show began meanwhile.
                    if installingAutomatically && ((!automaticUpdates && !(remoteInstalling && remoteUpdates)) || !safeToUpdate) {
                        automaticAttempt = nil
                        throw CancellationError()
                    }
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
                if remoteInstalling, let number = remoteRequest {
                    UserDefaults.standard.set(number, forKey: "updater.remoteConsumed")
                    remoteRequest = nil
                    remoteStatus = "Remote update installed"
                }
                try step("Done · restarting", 1)
                Self.relaunch(app)
            } catch {
                installingAutomatically = false
                remoteInstalling = false
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
                let data = UpdateOutputBuffer()
                let reader = DispatchGroup()
                reader.enter()
                DispatchQueue.global(qos: .utility).async { data.store(out.fileHandleForReading.readDataToEndOfFile()); reader.leave() }
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
                let text = String(decoding: data.load(), as: UTF8.self)
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
    @State private var statusToken = ""
    @AppStorage("updater.statusRepo") private var statusRepo = ""
    @AppStorage("updater.statusIssue") private var statusIssue = 0

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
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What’s new").font(.headline)
                        ScrollView {
                            Text((try? AttributedString(markdown: up.notes, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(up.notes.isEmpty ? "No release notes were provided." : up.notes))
                                .font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        }.frame(minHeight: 110, maxHeight: 260)
                        Link("View all release notes", destination: URL(string: "https://github.com/josephbrooks7/dmx-studio/releases")!)
                            .font(.caption)
                    }
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
            DisclosureGroup("Installed components") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(["Character Studio", "Venue Studio", "Lighting Engine", "Audio Engine", "Show Control", "Core Application"], id: \.self) { component in
                        HStack {
                            Text(component)
                            Spacer()
                            Text("Bundled • " + up.current).foregroundColor(.secondary)
                        }.font(.caption)
                    }
                    Text("Components currently update together. Independent packages will appear here when supported.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            Toggle("Automatically install updates when idle", isOn: $up.automaticUpdates)
                .disabled(up.canCancel || up.isInstalling)
            Text("Checks every five minutes. Updates only with physical output off and no active show or song analysis.")
                .font(.caption).foregroundColor(.secondary)
            Toggle("Allow remote update requests from my GitHub account", isOn: $up.remoteUpdates)
                .disabled(up.canCancel || up.isInstalling)
            if up.remoteUpdates {
                Text(up.remoteStatus).font(.caption).foregroundColor(.secondary)
                Link("Request an update from another device", destination: URL(string: "https://github.com/josephbrooks7/dmx-studio/issues/new?title=DMX%20Studio%3A%20Update%20this%20Mac")!)
                    .font(.caption)
            }
            DisclosureGroup("Private remote version reporting") {
                Text("Reports version and update progress to a private GitHub issue. Use a fine-grained token with Issues write access to that repository only.")
                    .font(.caption).foregroundColor(.secondary)
                TextField("Private repository (owner/name)", text: $statusRepo)
                TextField("Dedicated status issue number", value: $statusIssue, formatter: NumberFormatter())
                SecureField("Fine-grained GitHub token", text: $statusToken)
                HStack {
                    Button("Save token") { up.saveStatusToken(statusToken); statusToken = "" }
                    Button("Remove token") { up.saveStatusToken("") }
                    Toggle("Report status", isOn: $up.statusReporting)
                }
                Text(up.statusReportMessage).font(.caption).foregroundColor(.secondary)
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
        .frame(width: 560, height: up.availableVersion == nil ? 560 : 760)
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

// Synchronize the background pipe reader with the update worker.
private final class UpdateOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    func store(_ value: Data) { lock.lock(); defer { lock.unlock() }; bytes = value }
    func load() -> Data { lock.lock(); defer { lock.unlock() }; return bytes }
}
