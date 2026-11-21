import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation

/// An audio input on this Mac: built-in mic, USB mic / interface, or a loopback device like BlackHole
/// (which is how music playing on the computer can be "heard" on macOS 12).
struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    var isLoopback: Bool {
        let n = name.lowercased()
        return n.contains("blackhole") || n.contains("loopback") || n.contains("soundflower") || n.contains("aggregate")
    }
}

enum AudioInputs {
    static func list() -> [AudioInputDevice] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard inputChannels(id) > 0 else { return nil }
            return AudioInputDevice(id: id, name: name(id) ?? "Input \(id)")
        }
    }

    static func defaultInput() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    private static func name(_ id: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var cf: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &cf) == noErr, let s = cf?.takeRetainedValue() else { return nil }
        return s as String
    }

    private static func inputChannels(_ id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                              mScope: kAudioDevicePropertyScopeInput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

// MARK: - Outputs (where the music plays: headphone / line-out jack, speakers, a USB interface)

struct AudioOutputDevice: Identifiable, Hashable {
    var id: String { uid }
    let uid: String
    let name: String
    let channels: Int
}

enum AudioOutputs {
    static func list() -> [AudioOutputDevice] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            let ch = channels(id)
            guard ch > 0, let uid = string(id, kAudioDevicePropertyDeviceUID, kAudioObjectPropertyScopeGlobal) else { return nil }
            var name = string(id, kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal) ?? "Output"
            if let src = dataSourceName(id) { name += " — " + src }   // e.g. "MacBook Pro Speakers — Headphones"
            return AudioOutputDevice(uid: uid, name: name, channels: ch)
        }
    }

    /// The output macOS is using now (System Settings → Sound)
    static func defaultOutputName() -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        var name = string(id, kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal) ?? "Output"
        if let src = dataSourceName(id) { name += " — " + src }
        return name
    }

    static func exists(_ uid: String) -> Bool { list().contains { $0.uid == uid } }

    private static func string(_ id: AudioDeviceID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var cf: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &cf) == noErr, let s = cf?.takeRetainedValue() else { return nil }
        return s as String
    }

    /// Built-in output on Intel Macs is one device whose "source" switches between speakers and the jack
    private static func dataSourceName(_ id: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDataSource,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        var src: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(id, &addr),
              AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &src) == noErr else { return nil }
        var nameAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDataSourceNameForIDCFString,
                                                  mScope: kAudioDevicePropertyScopeOutput,
                                                  mElement: kAudioObjectPropertyElementMain)
        var cf: Unmanaged<CFString>?
        var translation = AudioValueTranslation(mInputData: &src, mInputDataSize: UInt32(MemoryLayout<UInt32>.size),
                                                mOutputData: &cf, mOutputDataSize: UInt32(MemoryLayout<Unmanaged<CFString>?>.size))
        var tsize = UInt32(MemoryLayout<AudioValueTranslation>.size)
        guard AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &tsize, &translation) == noErr, let s = cf?.takeRetainedValue() else { return nil }
        return s as String
    }

    private static func channels(_ id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    /// A short stereo test: a beep on the left, then a higher beep on the right
    static func stereoTestFile() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dmx-stereo-test.wav")
        let sr = 44100.0
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2) else { return nil }
        let n = AVAudioFrameCount(sr * 2.2)
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n), let ch = buf.floatChannelData else { return nil }
        buf.frameLength = n
        for i in 0..<Int(n) {
            let t = Double(i) / sr
            let env = { (a: Double, b: Double) -> Double in t < a || t > b ? 0 : min(1, (t - a) / 0.02, (b - t) / 0.05) }
            ch[0][i] = Float(sin(2 * .pi * 660 * t) * 0.4 * env(0.1, 0.9))     // left
            ch[1][i] = Float(sin(2 * .pi * 990 * t) * 0.4 * env(1.2, 2.0))     // right
        }
        guard let f = try? AVAudioFile(forWriting: url, settings: fmt.settings) else { return nil }
        try? f.write(from: buf)
        return url
    }
}
