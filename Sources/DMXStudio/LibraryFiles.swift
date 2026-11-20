import Foundation
import AppKit

/// Your work as real files in Documents/DMX Studio, so everything you make is saved where you can see it:
///
///     DMX Studio/
///       Sessions/    one .json per session (lights, presets, set lists, stage, idle look)
///       Presets/     one .json per preset you made or changed
///       Set Lists/   one .json per set list (with the song names in order)
///       Songs/       the imported audio files + one .song.json each (what Learn found + the light shows)
///
/// A session can also be exported as one shareable .dmxsession file that carries its songs along,
/// and imported on another computer.
enum LibraryFiles {
    static let sessionExtension = "dmxsession"

    static var root: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("DMX Studio", isDirectory: true)
    }

    static func folder(_ name: String) -> URL {
        let u = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// A name that's safe as a file name.
    static func safeName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = s.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        let short = String(cleaned.prefix(80))
        return short.isEmpty ? "Untitled" : short
    }

    // MARK: - Songs: keep a copy of each imported audio file in the library

    /// Copies an audio file into Songs/ (once) and returns where it lives now.
    static func adopt(audio url: URL) -> URL {
        let songsDir = folder("Songs")
        if url.standardizedFileURL.path.hasPrefix(songsDir.standardizedFileURL.path) { return url }
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        var dest = songsDir.appendingPathComponent(url.lastPathComponent)
        if fm.fileExists(atPath: dest.path) {
            if size(of: dest) == size(of: url) { return dest }          // already copied
            let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
            var n = 2
            repeat { dest = songsDir.appendingPathComponent("\(base) \(n).\(ext)"); n += 1 } while fm.fileExists(atPath: dest.path)
        }
        do { try fm.copyItem(at: url, to: dest); return dest } catch { return url }
    }

    private static func size(of u: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int) ?? -1
    }

    // MARK: - Mirror the library into folders (called after every save, off the main thread)

    private static let mirrorLock = NSLock()
    private static var lastWritten: [String: Int] = [:]     // file path → hash of what we wrote

    static func mirror(sessions: [Session], songs: [Song], userPresets: [LookPreset], lineups: [Lineup]) {
        mirrorLock.lock(); defer { mirrorLock.unlock() }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601

        func writeAll<T: Encodable>(_ items: [T], folderName: String, name: (T) -> String, ext: String = "json") {
            let dir = folder(folderName)
            var used = Set<String>()
            var keep: [String] = []
            for item in items {
                var file = safeName(name(item))
                var n = 2
                while used.contains(file.lowercased()) { file = "\(safeName(name(item))) \(n)"; n += 1 }
                used.insert(file.lowercased())
                let url = dir.appendingPathComponent("\(file).\(ext)")
                keep.append(url.lastPathComponent)
                guard let data = try? enc.encode(item) else { continue }
                let h = data.hashValue
                if lastWritten[url.path] == h, FileManager.default.fileExists(atPath: url.path) { continue }
                if (try? data.write(to: url, options: .atomic)) != nil { lastWritten[url.path] = h }
            }
            // Remove files this app wrote before that no longer exist (renamed or deleted in the app).
            // Files you put there yourself are never touched.
            let key = "writtenFiles.\(folderName)"
            let before = UserDefaults.standard.stringArray(forKey: key) ?? []
            for old in before where !keep.contains(old) {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(old))
            }
            UserDefaults.standard.set(keep, forKey: key)
        }

        writeAll(sessions, folderName: "Sessions", name: { $0.name })
        writeAll(userPresets, folderName: "Presets", name: { $0.name })
        let titles = Dictionary(songs.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        let sets = lineups.map { SetListFile(setList: $0, songs: $0.entries.map { titles[$0.songID] ?? "?" }) }
        writeAll(sets, folderName: "Set Lists", name: { $0.setList.name })
        writeAll(songs, folderName: "Songs", name: { $0.displayName }, ext: "song.json")
    }

    struct SetListFile: Codable {
        var setList: Lineup
        var songs: [String]      // readable song names, in order
    }

    // MARK: - Export / import a whole session as one file

    struct SessionPackage: Codable {
        var format = 1
        var app = "DMX Studio"
        var session: Session
        var songs: [Song]        // paths are relative ("Songs/<file>") inside the package
    }

    /// Writes `session` plus the songs its set lists use (audio, what Learn found, light shows) into one .dmxsession file.
    static func exportSession(_ session: Session, songs allSongs: [Song], to dest: URL) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("dmx-export-\(UUID().uuidString)")
        let pkg = work.appendingPathComponent("package")
        let songsDir = pkg.appendingPathComponent("Songs")
        try fm.createDirectory(at: songsDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let used = Set(session.lineups.flatMap { $0.entries.map(\.songID) })
        var packed: [Song] = []
        var names = Set<String>()
        for var song in allSongs where used.contains(song.id) {
            var file = song.url.lastPathComponent
            var n = 2
            while names.contains(file.lowercased()) { file = "\(n)-\(song.url.lastPathComponent)"; n += 1 }
            names.insert(file.lowercased())
            if fm.fileExists(atPath: song.path) {
                try fm.copyItem(at: song.url, to: songsDir.appendingPathComponent(file))
                song.path = "Songs/\(file)"
            } else {
                song.path = ""      // audio missing on this computer; shows still travel
            }
            packed.append(song)
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(SessionPackage(session: session, songs: packed)).write(to: pkg.appendingPathComponent("session.json"))

        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try runDitto(["-c", "-k", "--sequesterRsrc", pkg.path, dest.path])
    }

    /// Reads a .dmxsession file. Songs' audio is copied into Songs/ and their paths point there.
    static func importSession(from url: URL) throws -> (Session, [Song]) {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("dmx-import-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        try runDitto(["-x", "-k", url.path, work.path])

        // The package may be at the top or one folder down
        var base = work
        if !fm.fileExists(atPath: base.appendingPathComponent("session.json").path),
           let sub = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil).first(where: {
               fm.fileExists(atPath: $0.appendingPathComponent("session.json").path) }) {
            base = sub
        }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: base.appendingPathComponent("session.json"))
        let pkg = try dec.decode(SessionPackage.self, from: data)
        var songs = pkg.songs
        for i in songs.indices where !songs[i].path.isEmpty {
            let src = base.appendingPathComponent(songs[i].path)
            if fm.fileExists(atPath: src.path) { songs[i].path = adopt(audio: src).path }
        }
        return (pkg.session, songs)
    }

    private static func runDitto(_ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = args
        let err = Pipe()
        p.standardError = err
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw NSError(domain: "DMXStudio", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "Couldn't pack or unpack the session file." : msg])
        }
    }
}
