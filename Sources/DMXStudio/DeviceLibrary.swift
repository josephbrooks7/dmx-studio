import SwiftUI

/// Every device you've set up, kept across sessions, so you can add it to any show with its settings
/// (model, channel mode, address, how it moves) already done.
enum DeviceLibrary {
    private static let key = "deviceLibrary"

    static func load() -> [Fixture] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Fixture].self, from: data) else { return [] }
        return list
    }

    static func save(_ list: [Fixture]) {
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// Same device: same name and model
    static func same(_ a: Fixture, _ b: Fixture) -> Bool {
        a.name.caseInsensitiveCompare(b.name) == .orderedSame && a.profileName == b.profileName
    }
}

extension AppModel {
    /// Keep the library up to date with the devices in this session (called whenever they change)
    func rememberDevices() {
        var lib = deviceLibrary
        var changed = false
        for fx in fixtures {
            var entry = fx
            entry.off = nil          // on/off is per show, not part of the device
            if let k = lib.firstIndex(where: { DeviceLibrary.same($0, fx) }) {
                entry.id = lib[k].id
                if lib[k] != entry { lib[k] = entry; changed = true }
            } else {
                entry.id = UUID()
                lib.append(entry); changed = true
            }
        }
        if changed { deviceLibrary = lib; DeviceLibrary.save(lib) }
    }

    func inSession(_ device: Fixture) -> Bool { fixtures.contains { DeviceLibrary.same($0, device) } }

    /// Put a saved device into this session (a fresh copy; moved to a free address if its own is taken)
    func addFromLibrary(_ device: Fixture) {
        var fx = device
        fx.id = UUID()
        fx.off = nil
        if inSession(device) {
            var n = 2
            while fixtures.contains(where: { $0.name == "\(device.name) \(n)" }) { n += 1 }
            fx.name = "\(device.name) \(n)"
        }
        if !addressConflicts(for: fx).isEmpty { fx.address = min(nextFreeAddress, 512) }
        fixtures.append(fx)
    }

    func forgetDevice(_ id: UUID) {
        deviceLibrary.removeAll { $0.id == id }
        DeviceLibrary.save(deviceLibrary)
    }
}

/// The Device Library window: add saved devices to this session, or delete them from the library
struct DeviceLibraryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var forgetting: Fixture?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Device Library").font(.title2.bold())
                    Text("Every device you've set up, ready to add to any show with its settings.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            if model.deviceLibrary.isEmpty {
                Text("No devices yet. Devices you add with Add Device are saved here.")
                    .foregroundColor(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.deviceLibrary) { d in
                            HStack(spacing: 12) {
                                Image(systemName: d.headCount > 1 ? "rectangle.split.3x1" : "lightbulb.fill").foregroundColor(Theme.lightOn)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.name).font(.body.weight(.semibold))
                                    Text("\(d.profileName) · \(d.modeLabel) · address \(d.address)")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if model.inSession(d) {
                                    Text("In this show").font(.caption).foregroundColor(Theme.lightOn)
                                }
                                Button(model.inSession(d) ? "Add Another" : "Add to Show") { model.addFromLibrary(d) }
                                    .buttonStyle(PillButtonStyle())
                                Button { forgetting = d } label: { Image(systemName: "trash") }
                                    .buttonStyle(PillButtonStyle())
                                    .help("Delete from the library (doesn't change any show)")
                            }
                            .padding(.vertical, 8)
                            Divider().opacity(0.3)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 640, height: 460)
        .alert("Delete \(forgetting?.name ?? "this device") from the library?",
               isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } })) {
            Button("Delete", role: .destructive) { if let d = forgetting { model.forgetDevice(d.id) }; forgetting = nil }
            Button("Cancel", role: .cancel) { forgetting = nil }
        } message: { Text("Shows that already use it keep it. You can set it up again with Add Device.") }
    }
}
