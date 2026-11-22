import SwiftUI

// Philips Hue: lights on a Hue Bridge become devices in the show. The bridge's local connection takes
// about 10 commands a second in all, so Hue lights follow colors and moods with short fades (no fast
// strobes); the sender below sends whichever lamp is furthest from its target, ~9 times a second.

struct HueBridge: Codable, Equatable {
    var ip: String
    var username: String?
}

struct HueLight: Identifiable, Hashable {
    var id: String
    var name: String
    var color: Bool
}

enum HueAPI {
    static func url(_ ip: String, _ path: String) -> URL? { URL(string: "http://\(ip)/api\(path)") }

    /// Bridges on this network (Philips' discovery service: the bridge reports its address there)
    static func discover() async -> [String] {
        guard let u = URL(string: "https://discovery.meethue.com") else { return [] }
        var req = URLRequest(url: u); req.timeoutInterval = 8
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return list.compactMap { $0["internalipaddress"] as? String }
    }

    enum PairResult { case paired(String), pressButton, failed(String) }

    /// Ask the bridge for a key. Works only within 30 s after its round link button was pressed.
    static func pair(_ ip: String) async -> PairResult {
        guard let u = url(ip, "") else { return .failed("That address doesn't look right.") }
        var req = URLRequest(url: u); req.httpMethod = "POST"; req.timeoutInterval = 6
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["devicetype": "dmx_studio#mac"])
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], let first = arr.first else {
            return .failed("Couldn't reach a Hue Bridge at \(ip). Check it's on the same network.")
        }
        if let s = first["success"] as? [String: Any], let user = s["username"] as? String { return .paired(user) }
        if let e = first["error"] as? [String: Any], (e["type"] as? Int) == 101 { return .pressButton }
        return .failed("The bridge said: \(((first["error"] as? [String: Any])?["description"] as? String) ?? "unknown error")")
    }

    static func lights(_ b: HueBridge) async -> [HueLight] {
        guard let user = b.username, let u = url(b.ip, "/\(user)/lights") else { return [] }
        var req = URLRequest(url: u); req.timeoutInterval = 6
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return [] }
        return dict.map { id, v in
            let type = (v["type"] as? String ?? "").lowercased()
            return HueLight(id: id, name: v["name"] as? String ?? "Hue \(id)", color: type.contains("color"))
        }
        .sorted { (Int($0.id) ?? 0) < (Int($1.id) ?? 0) }
    }

    static func setState(_ b: HueBridge, light: String, body: [String: Any]) {
        guard let user = b.username, let u = url(b.ip, "/\(user)/lights/\(light)/state") else { return }
        var req = URLRequest(url: u); req.httpMethod = "PUT"; req.timeoutInterval = 2
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req).resume()
    }

    /// sRGB (0…1) → Hue's CIE xy color
    static func xy(_ c: RGB) -> [Double] {
        func lin(_ v: Double) -> Double { v > 0.04045 ? pow((v + 0.055) / 1.055, 2.4) : v / 12.92 }
        let r = lin(c.r), g = lin(c.g), b = lin(c.b)
        let X = r * 0.664511 + g * 0.154324 + b * 0.162028
        let Y = r * 0.283881 + g * 0.668433 + b * 0.047685
        let Z = r * 0.000088 + g * 0.072310 + b * 0.986039
        let s = X + Y + Z
        guard s > 0 else { return [0.3227, 0.329] }
        return [(X / s * 10000).rounded() / 10000, (Y / s * 10000).rounded() / 10000]
    }
}

/// Sends the show's colors to Hue lights, a few commands a second, biggest change first
final class HueOutput {
    static let shared = HueOutput()
    private let key = "hueBridge"
    private let q = DispatchQueue(label: "hue.output")
    private var timer: DispatchSourceTimer?
    private struct Look: Equatable { var on: Bool; var bri: Int; var xy: [Double] }
    private var target: [String: Look] = [:]
    private var sent: [String: Look] = [:]

    var bridge: HueBridge? {
        get { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(HueBridge.self, from: $0) } }
        set {
            if let v = newValue, let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
            q.async { self.sent = [:] }
        }
    }

    /// Called every frame with what each Hue light should show
    func update(light: String, color: RGB, level: Double) {
        let bri = Int((max(0, min(1, level)) * 254).rounded())
        let look = Look(on: bri > 2, bri: max(1, bri), xy: HueAPI.xy(color))
        q.async {
            self.target[light] = look
            if self.timer == nil { self.startTimer() }
        }
    }

    private func startTimer() {
        let t = DispatchSource.makeTimerSource(queue: q)
        t.schedule(deadline: .now(), repeating: 0.11)
        t.setEventHandler { [weak self] in self?.sendOne() }
        t.resume()
        timer = t
    }

    private func difference(_ a: Look, _ b: Look?) -> Double {
        guard let b else { return 10 }
        if a.on != b.on { return 5 }
        if !a.on { return 0 }
        return Double(abs(a.bri - b.bri)) / 254 + abs(a.xy[0] - b.xy[0]) * 4 + abs(a.xy[1] - b.xy[1]) * 4
    }

    private func sendOne() {
        guard let b = bridge, b.username != nil else { return }
        guard let (light, look) = target.max(by: { difference($0.value, sent[$0.key]) < difference($1.value, sent[$1.key]) }),
              difference(look, sent[light]) > 0.03 else { return }
        var body: [String: Any] = ["on": look.on, "transitiontime": 1]   // 0.1 s fade
        if look.on { body["bri"] = look.bri; body["xy"] = look.xy }
        HueAPI.setState(b, light: light, body: body)
        sent[light] = look
    }
}

extension AppModel {
    static func hueLightID(_ fx: Fixture) -> String? {
        guard let k = fx.outputKey, k.hasPrefix("hue:") else { return nil }
        return String(k.dropFirst(4))
    }

    func addHueLight(_ l: HueLight) {
        guard !fixtures.contains(where: { $0.outputKey == "hue:\(l.id)" }) else { return }
        fixtures.append(Fixture(name: l.name, address: 1, profileName: "Philips Hue",
                                layout: l.color ? "D,R,G,B" : "D", outputKey: "hue:\(l.id)"))
    }

    /// Each frame: send the Hue lights their colors (only when live)
    func sendHue(_ rendered: [RenderedFixture]) {
        guard outputEnabled else { return }
        for (i, fx) in fixtures.enumerated() where i < rendered.count {
            guard let id = AppModel.hueLightID(fx) else { continue }
            let heads = rendered[i].heads
            guard !heads.isEmpty else { continue }
            var c = RGB(r: 0, g: 0, b: 0), level = 0.0
            for h in heads { c.r += h.color.r; c.g += h.color.g; c.b += h.color.b; level += h.intensity }
            let n = Double(heads.count)
            c = RGB(r: c.r / n, g: c.g / n, b: c.b / n)
            let on = fx.isOn && !blackout
            HueOutput.shared.update(light: id, color: c, level: on ? level / n * master : 0)
        }
    }
}

/// Find the bridge, pair, and add Hue lights to the show
struct HueSetupView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var bridge: HueBridge? = HueOutput.shared.bridge
    @State private var found: [String] = []
    @State private var manualIP = ""
    @State private var status = ""
    @State private var busy = false
    @State private var lights: [HueLight] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Philips Hue").font(.title2.bold())
                    Text("Hue lights follow the show's colors and moods with short fades. The bridge takes about 10 changes a second in all, so they don't do fast strobes or beat flashes.")
                        .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            if let b = bridge, b.username != nil {
                HStack {
                    Label("Paired with the bridge at \(b.ip)", systemImage: "checkmark.circle.fill").foregroundColor(Theme.lightOn)
                    Spacer()
                    Button("Forget Bridge") { HueOutput.shared.bridge = nil; bridge = nil; lights = [] }
                        .buttonStyle(PillButtonStyle())
                }
                HStack {
                    Text("Your Hue lights").font(.headline)
                    Spacer()
                    Button("Add All") { lights.forEach { model.addHueLight($0) } }.buttonStyle(PillButtonStyle())
                    Button("Refresh") { Task { await loadLights() } }.buttonStyle(PillButtonStyle())
                }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(lights) { l in
                            HStack {
                                Image(systemName: "lightbulb.fill").foregroundColor(l.color ? .purple : .yellow)
                                Text(l.name)
                                Text(l.color ? "Color" : "White").font(.caption).foregroundColor(.secondary)
                                Spacer()
                                let added = model.fixtures.contains { $0.outputKey == "hue:\(l.id)" }
                                Button("Flash") {
                                    if let b = bridge { HueAPI.setState(b, light: l.id, body: ["alert": "select"]) }
                                }.buttonStyle(PillButtonStyle()).help("Blink this lamp once so you can see which it is")
                                Button(added ? "In the show" : "Add to Show") { model.addHueLight(l) }
                                    .buttonStyle(PillButtonStyle(active: added)).disabled(added)
                            }
                            .padding(.vertical, 6)
                            Divider().opacity(0.3)
                        }
                        if lights.isEmpty { Text(busy ? "Loading…" : "No lights found on the bridge.").foregroundColor(.secondary).padding() }
                    }
                }
            } else {
                Text("1. Find your bridge").font(.headline)
                HStack {
                    Button(busy ? "Looking…" : "Find Bridge") { Task { await find() } }.disabled(busy)
                    ForEach(found, id: \.self) { ip in
                        Button(ip) { manualIP = ip }.buttonStyle(PillButtonStyle(active: manualIP == ip))
                    }
                }
                HStack {
                    Text("Bridge address")
                    TextField("e.g. 192.168.1.20", text: $manualIP).textFieldStyle(.roundedBorder).frame(width: 200)
                    Text("(in the Hue app: Settings → Hue Bridges → ⓘ)").font(.caption).foregroundColor(.secondary)
                }
                Text("2. Press the round button on top of the bridge, then click Pair (within 30 seconds)").font(.headline)
                Button(busy ? "Waiting for the button…" : "Pair") { Task { await pair() } }
                    .disabled(busy || manualIP.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
            }
            if !status.isEmpty { Text(status).font(.caption).foregroundColor(.orange) }
        }
        .padding(20)
        .frame(width: 620, height: 480)
        .task { if bridge?.username != nil { await loadLights() } else { await find() } }
    }

    private func find() async {
        busy = true; status = ""
        found = await HueAPI.discover()
        if manualIP.isEmpty, let f = found.first { manualIP = f }
        if found.isEmpty { status = "No bridge found automatically. Type its address (from the Hue app) instead." }
        busy = false
    }

    private func pair() async {
        let ip = manualIP.trimmingCharacters(in: .whitespaces)
        busy = true; status = ""
        // keep asking for 30 s: the bridge accepts once its button has been pressed
        for _ in 0..<15 {
            switch await HueAPI.pair(ip) {
            case .paired(let user):
                let b = HueBridge(ip: ip, username: user)
                HueOutput.shared.bridge = b; bridge = b
                busy = false
                await loadLights()
                return
            case .pressButton:
                status = "Press the round button on the bridge…"
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            case .failed(let msg):
                status = msg; busy = false; return
            }
        }
        status = "The button wasn't pressed in time. Press it, then click Pair again."
        busy = false
    }

    private func loadLights() async {
        guard let b = bridge else { return }
        busy = true
        lights = await HueAPI.lights(b)
        busy = false
    }
}
