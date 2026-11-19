import CoreMIDI
import Foundation
import Observation

/// Every MIDI source (the V49 over USB, on the iPad through the camera adapter), reconnected whenever a device
/// comes or goes. Messages arrive on the main queue as MIDI 1.0 bytes (status, data1, data2).
@MainActor @Observable
public final class MIDIInput {
    /// Names of the connected sources ("V49"), empty = no keyboard.
    public private(set) var sources: [String] = []
    public private(set) var failure: String?
    @ObservationIgnored public var onMessage: (UInt8, UInt8, UInt8) -> Void = { _, _, _ in }

    @ObservationIgnored private var client = MIDIClientRef()
    @ObservationIgnored private var port = MIDIPortRef()

    public init() {}

    public func start() {
        guard client == 0 else { return }
        var status = MIDIClientCreateWithBlock("Piano" as CFString, &client) { [weak self] note in
            if note.pointee.messageID == .msgSetupChanged { DispatchQueue.main.async { self?.connect() } }
        }
        guard status == noErr else { failure = "CoreMIDI non parte (errore \(status))"; return }
        status = MIDIInputPortCreateWithProtocol(client, "Piano in" as CFString, ._1_0, &port) { [weak self] list, _ in
            var bytes: [(UInt8, UInt8, UInt8)] = []
            for packet in list.unsafeSequence() {
                let words = withUnsafeBytes(of: packet.pointee.words) { Array($0.bindMemory(to: UInt32.self)) }
                for w in words.prefix(Int(packet.pointee.wordCount)) where w >> 28 == 2 {   // MIDI 1.0 channel voice
                    bytes.append((UInt8(w >> 16 & 0xff), UInt8(w >> 8 & 0x7f), UInt8(w & 0x7f)))
                }
            }
            guard !bytes.isEmpty else { return }
            DispatchQueue.main.async { for b in bytes { self?.onMessage(b.0, b.1, b.2) } }
        }
        guard status == noErr else { failure = "CoreMIDI non parte (errore \(status))"; return }
        connect()
    }

    private func connect() {
        var names: [String] = []
        for i in 0..<MIDIGetNumberOfSources() {
            let src = MIDIGetSource(i)
            MIDIPortConnectSource(port, src, nil)        // already connected = harmless no-op
            var name: Unmanaged<CFString>?
            if MIDIObjectGetStringProperty(src, kMIDIPropertyDisplayName, &name) == noErr, let n = name?.takeRetainedValue() {
                let s = n as String
                if !s.contains("Session") { names.append(s) }   // iOS lists the network session as a source
            }
        }
        sources = names
    }
}
