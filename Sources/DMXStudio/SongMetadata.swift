import Foundation
import AVFoundation

/// Reads the song title and artist from an audio file's tags (MP3 ID3, M4A/AAC, AIFF, WAV),
/// falling back to the file name ("Artist - Title.mp3", "01 Title.wav", …).
enum SongMetadata {
    static let supportedExtensions: Set<String> = ["mp3", "wav", "wave", "aif", "aiff", "m4a", "aac", "flac", "caf"]

    static func isAudio(_ url: URL) -> Bool { supportedExtensions.contains(url.pathExtension.lowercased()) }

    static func read(_ url: URL) -> (title: String, artist: String?) {
        var title: String?
        var artist: String?

        let asset = AVURLAsset(url: url)
        var items = asset.commonMetadata
        for format in asset.availableMetadataFormats {
            items += asset.metadata(forFormat: format)
        }
        for item in items {
            guard let value = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { continue }
            let key = (item.commonKey?.rawValue ?? (item.key as? String) ?? "").lowercased()
            let id = (item.identifier?.rawValue ?? "").lowercased()
            if title == nil && (key == "title" || id.hasSuffix("/tit2") || id.hasSuffix("/©nam") || id.contains("inam")) {
                title = value
            }
            if artist == nil && (key == "artist" || id.hasSuffix("/tpe1") || id.hasSuffix("/©art") || id.contains("iart")) {
                artist = value
            }
        }
        if title == nil || artist == nil, let wav = readWavInfo(url) {
            title = title ?? wav.title
            artist = artist ?? wav.artist
        }

        // File-name fallback
        let fromName = parseFileName(url.deletingPathExtension().lastPathComponent)
        let finalArtist = artist ?? fromName.artist
        return (cleanTitle(title ?? fromName.title, artist: finalArtist), finalArtist)
    }

    /// "01 Song (Artist)" -> "Song": drops a leading track number and a trailing repeat of the artist.
    static func cleanTitle(_ raw: String, artist: String?) -> String {
        var t = raw.trimmingCharacters(in: .whitespaces)
        if let r = t.range(of: #"^\s*\d{1,3}\s*[-.)]?\s+"#, options: .regularExpression) { t.removeSubrange(r) }
        if let a = artist, !a.isEmpty {
            for wrap in ["(\(a))", "[\(a)]", "- \(a)", "– \(a)"] where t.lowercased().hasSuffix(wrap.lowercased()) {
                t = String(t.dropLast(wrap.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return t.isEmpty ? raw : t
    }

    /// "Artist - Title", "01 - Title", "01. Title", "Title (Official Audio)"
    static func parseFileName(_ raw: String) -> (title: String, artist: String?) {
        var name = raw.replacingOccurrences(of: "_", with: " ")
        // strip leading track numbers like "01 ", "1. ", "03 - "
        if let r = name.range(of: #"^\s*\d{1,3}\s*[-.)]?\s+"#, options: .regularExpression) {
            name.removeSubrange(r)
        }
        // strip common junk in brackets
        for junk in ["(official audio)", "(official video)", "(official music video)", "(lyrics)", "(audio)", "[official audio]", "(clean)", "(explicit)"] {
            if let r = name.range(of: junk, options: .caseInsensitive) { name.removeSubrange(r) }
        }
        name = name.trimmingCharacters(in: .whitespaces)
        // "LastChristmas" -> "Last Christmas" (only when the name has no spaces at all)
        if !name.contains(" ") {
            var spaced = ""
            for (i, ch) in name.enumerated() {
                if i > 0, ch.isUppercase, let prev = spaced.last, prev.isLowercase || prev.isNumber { spaced.append(" ") }
                spaced.append(ch)
            }
            name = spaced
        }
        for sep in [" - ", " – ", " — "] {
            if let r = name.range(of: sep) {
                let a = String(name[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                let t = String(name[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !a.isEmpty && !t.isEmpty { return (t, a) }
            }
        }
        return (name.isEmpty ? raw : name, nil)
    }

    /// WAV files often keep tags in a RIFF "LIST/INFO" chunk (INAM = title, IART = artist).
    static func readWavInfo(_ url: URL) -> (title: String?, artist: String?)? {
        guard ["wav", "wave"].contains(url.pathExtension.lowercased()),
              let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let header = try? h.read(upToCount: 12), header.count == 12,
              String(decoding: header[0..<4], as: UTF8.self) == "RIFF" else { return nil }
        var title: String?, artist: String?
        var offset: UInt64 = 12
        for _ in 0..<64 {
            try? h.seek(toOffset: offset)
            guard let ch = try? h.read(upToCount: 8), ch.count == 8 else { break }
            let id = String(decoding: ch[0..<4], as: UTF8.self)
            let size = UInt64(ch[4]) | UInt64(ch[5]) << 8 | UInt64(ch[6]) << 16 | UInt64(ch[7]) << 24
            if id == "LIST", size < 1_000_000, let body = try? h.read(upToCount: Int(size)), body.count >= 4,
               String(decoding: body[0..<4], as: UTF8.self) == "INFO" {
                var i = 4
                while i + 8 <= body.count {
                    let sid = String(decoding: body[i..<i+4], as: UTF8.self)
                    let ssz = Int(body[i+4]) | Int(body[i+5]) << 8 | Int(body[i+6]) << 16 | Int(body[i+7]) << 24
                    let start = i + 8, end = min(body.count, start + ssz)
                    let val = String(decoding: body[start..<end], as: UTF8.self)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespaces))
                    if sid == "INAM" && !val.isEmpty { title = val }
                    if sid == "IART" && !val.isEmpty { artist = val }
                    i = start + ssz + (ssz % 2)
                }
            }
            offset += 8 + size + (size % 2)
        }
        return (title == nil && artist == nil) ? nil : (title, artist)
    }
}
