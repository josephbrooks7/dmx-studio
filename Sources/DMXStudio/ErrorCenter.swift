import Foundation
import AppKit
import Darwin

// MARK: - Problems the app shows (and lets you report) instead of crashing

struct AppProblem: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var area: String        // e.g. "Wi-Fi scan", "Learn", "Playback"
    var message: String     // plain-language summary
    var details: String     // technical details for fixing it
    var reported = false
}

final class ErrorCenter: ObservableObject {
    static let shared = ErrorCenter()
    static let repo = "josephbrooks7/dmx-studio"

    @Published var problems: [AppProblem] = []
    @Published var current: AppProblem?        // shown as an alert

    func report(area: String, message: String, details: String = "", show: Bool = true) {
        let p = AppProblem(area: area, message: message, details: details)
        let work = {
            self.problems.insert(p, at: 0)
            if self.problems.count > 100 { self.problems.removeLast() }
            if show { self.current = p }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    static var systemSummary: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        var sys = utsname(); uname(&sys)
        let machine = withUnsafeBytes(of: &sys.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let app = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return "DMX Studio \(app) · macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion) · \(machine)"
    }

    /// Opens a pre-filled GitHub issue for this problem, and copies the full text to the clipboard.
    func sendReport(_ p: AppProblem) {
        let full = """
        **What happened:** \(p.message)
        **Where:** \(p.area)
        **When:** \(p.date)
        **System:** \(Self.systemSummary)

        **Details**
        ```
        \(p.details.isEmpty ? "(none)" : p.details)
        ```
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(full, forType: .string)

        let body = full.count > 6000 ? String(full.prefix(6000)) + "\n…(full report copied to clipboard — paste it here)" : full
        var c = URLComponents(string: "https://github.com/\(Self.repo)/issues/new")!
        c.queryItems = [URLQueryItem(name: "title", value: "[\(p.area)] \(p.message)".prefix(120).description),
                        URLQueryItem(name: "body", value: body),
                        URLQueryItem(name: "labels", value: p.area == "Lyrics report" ? "lyrics" : "bug")]
        if let url = c.url { NSWorkspace.shared.open(url) }
        if let i = problems.firstIndex(where: { $0.id == p.id }) { problems[i].reported = true }
    }
}

// MARK: - Crash catcher: if the app itself crashes, save a report for next launch

enum CrashGuard {
    static var reportURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DMX Studio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("last-crash.txt")
    }

    /// What the app was doing (shown in crash reports). Kept short.
    private static var crumbLock = NSLock()
    private static var crumb = "Starting up"
    static func breadcrumb(_ s: String) { crumbLock.lock(); crumb = s; crumbLock.unlock() }
    static var currentCrumb: String { crumbLock.lock(); defer { crumbLock.unlock() }; return crumb }

    private static var toStderr = false

    /// - Parameter writeToStderr: helper processes print the crash for the main app instead of saving a file.
    static func install(writeToStderr: Bool = false) {
        toStderr = writeToStderr
        NSSetUncaughtExceptionHandler { e in
            CrashGuard.write("Exception: \(e.name.rawValue) \(e.reason ?? "")\n" + e.callStackSymbols.joined(separator: "\n"))
        }
        for sig in [SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGABRT, SIGFPE] {
            signal(sig) { s in
                CrashGuard.write("Signal \(s) (\(CrashGuard.signalName(s)))\n" + Thread.callStackSymbols.joined(separator: "\n"))
                signal(s, SIG_DFL)
                raise(s)
            }
        }
    }

    static func signalName(_ s: Int32) -> String {
        switch s {
        case SIGSEGV: return "bad memory access"
        case SIGBUS: return "bus error"
        case SIGILL, SIGTRAP: return "Swift runtime check failed"
        case SIGABRT: return "abort"
        case SIGFPE: return "math error"
        default: return "signal"
        }
    }

    fileprivate static func write(_ text: String) {
        let report = "While: \(currentCrumb)\n\(ErrorCenter.systemSummary)\n\n\(text)\n"
        if toStderr {
            FileHandle.standardError.write(report.data(using: .utf8) ?? Data())
        } else {
            try? report.write(to: reportURL, atomically: true, encoding: .utf8)
        }
    }

    /// A crash report from the last run, if there was one (and clears it).
    static func takePendingReport() -> String? {
        guard let s = try? String(contentsOf: reportURL, encoding: .utf8), !s.isEmpty else { return nil }
        try? FileManager.default.removeItem(at: reportURL)
        return s
    }
}

// MARK: - Run risky work in a separate process so a failure can't take the app down

enum Helper {
    struct Result {
        var status: Int32
        var crashed: Bool
        var stdout: Data
        var stderr: String
    }

    /// Runs this same app binary with `args` (a hidden helper mode) and waits for it.
    static func run(_ args: [String], timeout: Double, progress: ((Double) -> Void)? = nil, onStart: ((Process) -> Void)? = nil) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
        p.arguments = args
        p.qualityOfService = .utility        // background work: lights, playback and the screen come first
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter(); DispatchQueue.global().async {
            // read as it comes, passing on "progress=0.42" lines
            var pending = ""
            while true {
                let chunk = out.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                outData.append(chunk)
                guard let progress else { continue }
                pending += String(decoding: chunk, as: UTF8.self)
                while let nl = pending.firstIndex(of: "\n") {
                    let line = String(pending[..<nl]); pending = String(pending[pending.index(after: nl)...])
                    if line.hasPrefix("progress="), let v = Double(line.dropFirst(9)) { progress(v) }
                }
            }
            group.leave()
        }
        group.enter(); DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        do {
            try p.run()
            onStart?(p)
        } catch {
            return Result(status: -1, crashed: true, stdout: Data(), stderr: "Couldn't start helper: \(error.localizedDescription)")
        }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        var timedOut = false
        if p.isRunning { timedOut = true; p.terminate() }
        p.waitUntilExit()
        group.wait()
        var stderrText = String(decoding: errData, as: UTF8.self)
        if timedOut { stderrText = "Timed out after \(Int(timeout)) s\n" + stderrText }
        let crashed = timedOut || p.terminationReason == .uncaughtSignal
        return Result(status: p.terminationStatus, crashed: crashed, stdout: outData, stderr: stderrText)
    }
}
