import Foundation

enum CharacterCaptureRequests {
    private struct Request: Decodable {
        let id: UUID
        let character: String
        let build: String
        let created_at: String
        let expires_at: String
    }

    private static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatter.date(from: value) { return parsed }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    @MainActor
    static func processOne(enabled: Bool, playing: Bool) throws -> Bool {
        guard enabled, !playing,
              let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else { return false }
        let root = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("DMX Studio/DiagnosticPreviews", isDirectory: true)
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: root.path),
              attrs[.type] as? FileAttributeType == .typeDirectory,
              let mode = attrs[.posixPermissions] as? NSNumber, mode.intValue & 0o077 == 0 else { return false }
        let files = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        for file in files.prefix(64) where file.lastPathComponent.hasSuffix(".request.json") {
            guard let attrs = try? fm.attributesOfItem(atPath: file.path),
                  attrs[.type] as? FileAttributeType == .typeRegular,
                  let size = attrs[.size] as? NSNumber, size.intValue <= 2048,
                  let mode = attrs[.posixPermissions] as? NSNumber, mode.intValue & 0o077 == 0,
                  let data = try? Data(contentsOf: file), data.count <= 2048,
                  let request = try? JSONDecoder().decode(Request.self, from: data),
                  file.lastPathComponent == request.id.uuidString.lowercased() + ".request.json",
                  request.build == build, ["male", "female"].contains(request.character),
                  let created = date(request.created_at), let expiry = date(request.expires_at),
                  created <= Date(), Date() < expiry else { continue }
            let manifest = root.appendingPathComponent(request.id.uuidString.lowercased() + ".json")
            if fm.fileExists(atPath: manifest.path) { continue }
            var appearance = PerformerAppearance()
            appearance.bodyStyle = request.character == "male" ? "Masculine" : "Feminine"
            _ = try CharacterDiagnosticCapture.export(appearance: appearance, requestID: request.id,
                character: request.character, enabled: enabled)
            return true
        }
        return false
    }
}
