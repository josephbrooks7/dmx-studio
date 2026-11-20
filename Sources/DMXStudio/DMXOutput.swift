import Foundation
import Darwin

enum DMXError: LocalizedError {
    case openFailed(String)
    case configFailed(String)
    case socketFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let s): return "Couldn't open port: \(s)"
        case .configFailed(let s): return "Couldn't configure port: \(s)"
        case .socketFailed(let s): return "Network error: \(s)"
        }
    }
}

protocol DMXOutput: AnyObject {
    /// Sends one full universe (512 channel values).
    func send(_ frame: [UInt8]) throws
    func close()
}

// MARK: - Serial helper

final class SerialPort {
    let fd: Int32

    // ioctl request codes (C macros aren't imported into Swift)
    private static let IOSSIOSPEED: UInt = 0x8008_5402   // _IOW('T', 2, speed_t)
    private static let TIOCSBRK: UInt = 0x2000_747B      // _IO('t', 123)
    private static let TIOCCBRK: UInt = 0x2000_747A      // _IO('t', 122)

    init(path: String, baud: Int, twoStopBits: Bool) throws {
        let f = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard f >= 0 else { throw DMXError.openFailed("\(path) — \(String(cString: strerror(errno)))") }
        fd = f
        // back to blocking writes
        _ = fcntl(fd, F_SETFL, 0)

        var t = termios()
        guard tcgetattr(fd, &t) == 0 else { Darwin.close(fd); throw DMXError.configFailed("tcgetattr") }
        cfmakeraw(&t)
        t.c_cflag |= tcflag_t(CLOCAL | CREAD)
        t.c_cflag &= ~tcflag_t(PARENB)
        t.c_cflag &= ~tcflag_t(0x0003_0000) // CRTSCTS: no hardware flow control
        if twoStopBits { t.c_cflag |= tcflag_t(CSTOPB) } else { t.c_cflag &= ~tcflag_t(CSTOPB) }
        cfsetspeed(&t, speed_t(B57600))
        guard tcsetattr(fd, TCSANOW, &t) == 0 else { Darwin.close(fd); throw DMXError.configFailed("tcsetattr") }

        if baud != 57600 {
            var speed = speed_t(baud)
            if ioctl(fd, SerialPort.IOSSIOSPEED, &speed) != 0 {
                Darwin.close(fd)
                throw DMXError.configFailed("baud \(baud) not supported")
            }
        }
        tcflush(fd, TCIOFLUSH)
    }

    func write(_ bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let n = bytes.withUnsafeBytes { buf in
                Darwin.write(fd, buf.baseAddress! + offset, bytes.count - offset)
            }
            if n < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                throw DMXError.configFailed("write failed: \(String(cString: strerror(errno)))")
            }
            offset += n
        }
    }

    func setBreak(_ on: Bool) {
        _ = ioctl(fd, on ? SerialPort.TIOCSBRK : SerialPort.TIOCCBRK)
    }

    func drain() { tcdrain(fd) }

    func close() { Darwin.close(fd) }

    static func availablePorts() -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return items.filter { $0.hasPrefix("cu.") && !$0.contains("Bluetooth") && !$0.contains("debug-console") }
            .sorted()
            .map { "/dev/" + $0 }
    }
}

// MARK: - Enttec DMX USB Pro (and compatibles: DMXking ultraDMX, etc.)

final class EnttecProOutput: DMXOutput {
    private let port: SerialPort

    init(path: String) throws {
        port = try SerialPort(path: path, baud: 57600, twoStopBits: false)
    }

    func send(_ frame: [UInt8]) throws {
        // Label 6 = "Output Only Send DMX Packet Request"
        let dataLen = 513 // start code + 512 channels
        var packet: [UInt8] = [0x7E, 6, UInt8(dataLen & 0xFF), UInt8(dataLen >> 8), 0x00]
        packet.append(contentsOf: frame.prefix(512))
        if frame.count < 512 { packet.append(contentsOf: [UInt8](repeating: 0, count: 512 - frame.count)) }
        packet.append(0xE7)
        try port.write(packet)
    }

    func close() { port.close() }
}

// MARK: - Open DMX (raw FTDI, software-generated DMX timing)

final class OpenDMXOutput: DMXOutput {
    private let port: SerialPort

    init(path: String) throws {
        port = try SerialPort(path: path, baud: 250_000, twoStopBits: true)
    }

    func send(_ frame: [UInt8]) throws {
        port.setBreak(true)
        usleep(110)               // break >= 88µs
        port.setBreak(false)
        usleep(16)                // mark-after-break >= 8µs
        var packet: [UInt8] = [0x00]
        packet.append(contentsOf: frame.prefix(512))
        if frame.count < 512 { packet.append(contentsOf: [UInt8](repeating: 0, count: 512 - frame.count)) }
        try port.write(packet)
        port.drain()
    }

    func close() { port.close() }
}

// MARK: - Art-Net (+ sACN), sent to every universe the node might be listening on

final class ArtNetOutput: DMXOutput {
    private let sock: Int32
    private var addr = sockaddr_in()
    private var sacnAddr = sockaddr_in()
    private let universes: [Int]
    private let sendSACN: Bool
    private var sequence: UInt8 = 1
    private let cid: [UInt8] = Array(withUnsafeBytes(of: UUID().uuid) { Array($0) })
    private(set) var packetsSent = 0

    /// - universes: Art-Net universes to send the same frame on (e.g. [0, 1] when unsure)
    /// - sendSACN: also send sACN (E1.31) universe 1 to the same device
    init(ip: String, universes: [Int], sendSACN: Bool) throws {
        sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { throw DMXError.socketFailed("socket()") }
        var yes: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))

        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(6454).bigEndian
        guard inet_pton(AF_INET, ip, &addr.sin_addr) == 1 else {
            Darwin.close(sock)
            throw DMXError.socketFailed("bad IP address \(ip)")
        }
        sacnAddr = addr
        sacnAddr.sin_port = in_port_t(5568).bigEndian
        self.universes = universes.isEmpty ? [0] : universes
        self.sendSACN = sendSACN
    }

    convenience init(ip: String, universe: Int) throws {
        try self.init(ip: ip, universes: [universe], sendSACN: false)
    }

    func send(_ frame: [UInt8]) throws {
        var data = Array(frame.prefix(512))
        if data.count < 512 { data += [UInt8](repeating: 0, count: 512 - data.count) }
        var failed = false
        for u in universes {
            var p: [UInt8] = Array("Art-Net".utf8) + [0]
            p += [0x00, 0x50]                              // OpOutput / ArtDmx (0x5000, little endian)
            p += [0x00, 14]                                // protocol version 14
            p += [sequence, 0]                             // sequence, physical
            p += [UInt8(u & 0xFF), UInt8((u >> 8) & 0x7F)] // SubUni, Net
            p += [0x02, 0x00]                              // length 512 (big endian)
            p += data
            if !sendPacket(p, to: addr) { failed = true }
        }
        if sendSACN && !sendPacket(sacnPacket(universe: 1, data: data), to: sacnAddr) { failed = true }
        sequence = sequence == 255 ? 1 : sequence + 1
        packetsSent += 1
        if failed { throw DMXError.socketFailed(String(cString: strerror(errno))) }
    }

    private func sendPacket(_ p: [UInt8], to dest: sockaddr_in) -> Bool {
        var d = dest
        let sent = p.withUnsafeBytes { buf -> Int in
            withUnsafePointer(to: &d) { ap in
                ap.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(sock, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        return sent >= 0
    }

    /// sACN / E1.31 data packet (638 bytes for a full universe).
    private func sacnPacket(universe: Int, data: [UInt8]) -> [UInt8] {
        func u16(_ v: Int) -> [UInt8] { [UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
        var p: [UInt8] = []
        // Root layer
        p += u16(0x0010) + u16(0x0000)
        p += [0x41, 0x53, 0x43, 0x2D, 0x45, 0x31, 0x2E, 0x31, 0x37, 0x00, 0x00, 0x00]  // "ASC-E1.17"
        p += u16(0x7000 | (638 - 16))
        p += [0x00, 0x00, 0x00, 0x04]
        p += cid
        // Framing layer
        p += u16(0x7000 | (638 - 38))
        p += [0x00, 0x00, 0x00, 0x02]
        var name = Array("DMX Studio".utf8); name += [UInt8](repeating: 0, count: 64 - name.count)
        p += name
        p += [100]                    // priority
        p += u16(0)                   // sync address
        p += [sequence, 0]            // sequence, options
        p += u16(universe)
        // DMP layer
        p += u16(0x7000 | (638 - 115))
        p += [0x02, 0xA1]
        p += u16(0x0000) + u16(0x0001) + u16(513)
        p += [0x00]                   // start code
        p += data
        return p
    }

    func close() { Darwin.close(sock) }
}

// MARK: - Engine: sends every output's frame ~40 times a second on its own thread

final class DMXEngine {
    static let mainKey = "main"
    private let lock = NSLock()
    private var frames: [String: [UInt8]] = [:]
    private var outputs: [String: DMXOutput] = [:]
    private var extraTargets: [String: String] = [:]   // key -> ip
    private var thread: Thread?
    private var running = false
    var onError: ((String) -> Void)?

    var isConnected: Bool { lock.lock(); defer { lock.unlock() }; return outputs[DMXEngine.mainKey] != nil }

    func connect(_ settings: OutputSettings) throws {
        let out: DMXOutput
        switch settings.kind {
        case .enttecPro: out = try EnttecProOutput(path: settings.serialPath)
        case .openDMX: out = try OpenDMXOutput(path: settings.serialPath)
        case .artNet: out = try ArtNetOutput(ip: settings.artNetIP, universes: settings.sendUniverses,
                                             sendSACN: settings.alsoSendSACN ?? true)
        }
        lock.lock()
        let old = outputs[DMXEngine.mainKey]
        outputs[DMXEngine.mainKey] = out
        lock.unlock()
        old?.close()
        startLoop()
    }

    /// Extra Art-Net devices (universe 0) for lights wired to other wireless boxes.
    func setExtraDevices(_ devices: [(key: String, ip: String)]) {
        lock.lock()
        var stale: [DMXOutput] = []
        let wanted = Dictionary(devices.map { ($0.key, $0.ip) }, uniquingKeysWith: { a, _ in a })
        for (key, ip) in extraTargets where wanted[key] != ip {
            if let o = outputs.removeValue(forKey: key) { stale.append(o) }
            extraTargets[key] = nil
        }
        for (key, ip) in wanted where extraTargets[key] == nil && key != DMXEngine.mainKey {
            if let o = try? ArtNetOutput(ip: ip, universes: [0, 1], sendSACN: true) {
                outputs[key] = o
                extraTargets[key] = ip
            }
        }
        lock.unlock()
        stale.forEach { $0.close() }
        if !wanted.isEmpty { startLoop() }
    }

    private func startLoop() {
        lock.lock()
        let already = running
        running = true
        lock.unlock()
        guard !already else { return }
        let t = Thread { [weak self] in self?.loop() }
        t.qualityOfService = .userInteractive
        t.name = "DMX output"
        thread = t
        t.start()
    }

    func disconnect() {
        lock.lock()
        let out = outputs.removeValue(forKey: DMXEngine.mainKey)
        if outputs.isEmpty { running = false }
        lock.unlock()
        if let out {
            try? out.send([UInt8](repeating: 0, count: 512))
            out.close()
        }
    }

    func shutdown() {
        lock.lock()
        running = false
        let all = Array(outputs.values)
        outputs.removeAll()
        extraTargets.removeAll()
        lock.unlock()
        for o in all { try? o.send([UInt8](repeating: 0, count: 512)); o.close() }
    }

    /// How many frames the main output has sent (for the "is it sending?" readout).
    var mainPacketsSent: Int {
        lock.lock(); defer { lock.unlock() }
        return (outputs[DMXEngine.mainKey] as? ArtNetOutput)?.packetsSent ?? 0
    }

    func setFrames(_ f: [String: [UInt8]]) {
        lock.lock(); frames = f; lock.unlock()
    }

    private func loop() {
        let interval = 1.0 / 40.0
        var next = Date().timeIntervalSinceReferenceDate
        var failures = 0
        let blank = [UInt8](repeating: 0, count: 512)
        while true {
            lock.lock()
            guard running else { lock.unlock(); return }
            let outs = outputs
            let f = frames
            lock.unlock()
            var failed = false
            for (key, out) in outs {
                do { try out.send(f[key] ?? blank) } catch { failed = true; if failures == 20 { report(error) } }
            }
            failures = failed ? failures + 1 : 0
            next += interval
            let wait = next - Date().timeIntervalSinceReferenceDate
            if wait > 0 { Thread.sleep(forTimeInterval: wait) } else { next = Date().timeIntervalSinceReferenceDate }
        }
    }

    private func report(_ error: Error) {
        let msg = error.localizedDescription
        DispatchQueue.main.async { self.onError?(msg) }
    }
}

// MARK: - Art-Net discovery (finds PKnight and other nodes on the network)

struct ArtNetNode: Identifiable, Hashable, Codable {
    var id: String { mac.isEmpty ? ip : mac }
    var ip: String
    var name: String
    var longName: String = ""
    var mac: String = ""
    var lastSeen = Date()
}

enum ArtNetDiscovery {
    /// The Mac's own IPv4 addresses (used to spot a PKnight hotspot network).
    static func localIPv4Addresses() -> [String] {
        var result: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = p {
            if let sa = cur.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    result.append(String(cString: host))
                }
            }
            p = cur.pointee.ifa_next
        }
        return result
    }

    /// PKnight WiFi-DMX EasyNode in hotspot mode: Mac gets 192.168.4.x, the node is 192.168.4.1.
    static var pknightHotspotNode: ArtNetNode? {
        guard localIPv4Addresses().contains(where: { $0.hasPrefix("192.168.4.") && $0 != "192.168.4.1" }) else { return nil }
        return ArtNetNode(ip: "192.168.4.1", name: "PKnight EasyNode (hotspot)", longName: "Found by its Wi-Fi network", mac: "pknight-hotspot")
    }

    /// Broadcasts an ArtPoll and collects ArtPollReply packets for `timeout` seconds. Blocking — call off the main thread.
    static func discover(timeout: Double = 2.0) -> [ArtNetNode] {
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return [] }
        defer { Darwin.close(sock) }

        var yes: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(sock, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var local = sockaddr_in()
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = in_port_t(6454).bigEndian
        local.sin_addr.s_addr = INADDR_ANY
        _ = withUnsafePointer(to: &local) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }

        // ArtPoll packet
        let poll: [UInt8] = Array("Art-Net".utf8) + [0, 0x00, 0x20, 0x00, 14, 0x06, 0x00]
        for target in ["255.255.255.255", "2.255.255.255", "10.255.255.255"] {
            var dest = sockaddr_in()
            dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            dest.sin_family = sa_family_t(AF_INET)
            dest.sin_port = in_port_t(6454).bigEndian
            inet_pton(AF_INET, target, &dest.sin_addr)
            _ = poll.withUnsafeBytes { buf in
                withUnsafePointer(to: &dest) { p in
                    p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(sock, buf.baseAddress, buf.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }

        var found: [String: ArtNetNode] = [:]
        let deadline = Date().addingTimeInterval(timeout)
        var buf = [UInt8](repeating: 0, count: 1024)
        while Date() < deadline {
            let n = buf.withUnsafeMutableBytes { recv(sock, $0.baseAddress, $0.count, 0) }
            guard n >= 26 + 18 else { continue }
            // "Art-Net\0" + OpPollReply (0x2100 little endian)
            guard Array(buf[0..<8]) == Array("Art-Net".utf8) + [0], buf[8] == 0x00, buf[9] == 0x21 else { continue }
            let ip = "\(buf[10]).\(buf[11]).\(buf[12]).\(buf[13])"
            let nameBytes = buf[26..<44].prefix { $0 != 0 }
            let name = String(decoding: nameBytes, as: UTF8.self)
            var longName = ""
            if n >= 108 { longName = String(decoding: buf[44..<108].prefix { $0 != 0 }, as: UTF8.self) }
            var mac = ""
            if n >= 207 { mac = buf[201..<207].map { String(format: "%02X", $0) }.joined(separator: ":") }
            if mac == "00:00:00:00:00:00" { mac = "" }
            let node = ArtNetNode(ip: ip, name: name.isEmpty ? "Art-Net device" : name, longName: longName, mac: mac)
            found[node.id] = node
        }
        // EasyNode may not answer discovery; if we're on its hotspot, list it anyway
        if !found.values.contains(where: { $0.ip == "192.168.4.1" }), let hs = pknightHotspotNode {
            found[hs.id] = hs
        }
        return found.values.sorted { $0.ip < $1.ip }
    }
}
