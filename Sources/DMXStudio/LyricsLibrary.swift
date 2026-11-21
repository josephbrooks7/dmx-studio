import SwiftUI
import AppKit

/// Your lyrics, one text file per song in Documents/DMX Studio/Lyrics. Saved whenever you paste or edit a
/// song's lyrics, and offered again when a song with the same title is imported (other versions, re-imports).
/// You can also drop .txt files in the folder yourself (file name = song title).
struct LyricsEntry: Identifiable, Hashable {
    var id: String { url.path }
    var title: String
    var text: String
    var url: URL
}

enum LyricsLibrary {
    static var folder: URL { LibraryFiles.folder("Lyrics") }

    /// "05_Battle_Maiden_PERFORMANCE_TRACK_Sparkle_Glitch" and "Battle Maiden" → "battle maiden"
    static func key(_ title: String) -> String {
        var t = title.lowercased().replacingOccurrences(of: "_", with: " ")
        for junk in [#"^\s*\d+\s*[-.]?\s*"#, #"\bperformance track\b.*$"#, #"\b(instrumental|backing track|karaoke|demo|master|final|remix|radio edit|clean|explicit)\b"#,
                     #"\(.*?\)|\[.*?\]"#, #"\bfeat\..*$"#, #"\bft\..*$"#] {
            t = t.replacingOccurrences(of: junk, with: " ", options: .regularExpression)
        }
        return t.filter { $0.isLetter || $0.isNumber || $0 == " " }
            .split(separator: " ").joined(separator: " ")
    }

    static func all() -> [LyricsEntry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "txt" }.compactMap { u in
            guard let text = try? String(contentsOf: u, encoding: .utf8) else { return nil }
            return LyricsEntry(title: u.deletingPathExtension().lastPathComponent, text: text, url: u)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The saved lyrics for a song title, if any
    static func find(title: String) -> LyricsEntry? {
        let k = key(title)
        guard !k.isEmpty else { return nil }
        let entries = all()
        return entries.first { key($0.title) == k }
            ?? entries.first { let e = key($0.title); return e.count >= 4 && (k.hasPrefix(e) || e.hasPrefix(k)) }
    }

    @discardableResult
    static func save(title: String, text: String) -> URL? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let name = find(title: title)?.url.deletingPathExtension().lastPathComponent
            ?? LibraryFiles.safeName(title.trimmingCharacters(in: .whitespaces))
        let u = folder.appendingPathComponent(name).appendingPathExtension("txt")
        try? clean.write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    static func delete(_ e: LyricsEntry) { try? FileManager.default.removeItem(at: e.url) }
}

// MARK: - Window

struct LyricsLibraryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [LyricsEntry] = LyricsLibrary.all()
    @State private var selected: String?
    @State private var title = ""
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Lyrics Library").font(.title2.bold())
                Text("\(entries.count) song\(entries.count == 1 ? "" : "s")").foregroundColor(.secondary)
                Spacer()
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([LyricsLibrary.folder]) }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text("Your songs' real lyrics. They're saved here whenever you paste or edit lyrics, and filled in for you when a song with the same title is imported. Timing isn't needed: the app works it out by listening.")
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 6) {
                    List(entries, selection: $selected) { e in
                        Text(e.title).tag(e.id)
                    }
                    .frame(width: 220)
                    HStack {
                        Button { selected = nil; title = ""; text = "" } label: { Label("New", systemImage: "plus") }
                        Spacer()
                        Button(role: .destructive) {
                            if let e = entries.first(where: { $0.id == selected }) { LyricsLibrary.delete(e); reload(); selected = nil; title = ""; text = "" }
                        } label: { Label("Delete", systemImage: "trash") }
                            .disabled(selected == nil)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Song title", text: $title).textFieldStyle(.roundedBorder)
                    TextEditor(text: $text).font(.body)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.15)))
                    HStack {
                        if let s = model.selectedSongID.flatMap({ model.song($0) }) {
                            Button("Use for \"\(s.title)\"") {
                                model.pasteLyrics(s.id, text: text)
                            }
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || s.analysis == nil)
                            .help("Put these lyrics on the selected song (learn it first)")
                        }
                        Spacer()
                        Button("Save") {
                            if let u = LyricsLibrary.save(title: title, text: text) { reload(); selected = u.path }
                        }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 520)
        .onChange(of: selected) { id in
            if let e = entries.first(where: { $0.id == id }) { title = e.title; text = e.text }
        }
    }

    private func reload() { entries = LyricsLibrary.all() }
}
