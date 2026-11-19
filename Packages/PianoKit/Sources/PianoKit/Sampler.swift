import AVFoundation
import QuartzCore
import os

/// The grand piano: Salamander samples, one every minor third A0–C8, pitch-shifted to the
/// nearest note. Own render callback (AVAudioSourceNode) instead of AVAudioUnitSampler: the mp3s carry no root
/// keys, and this way a key press starts within one IO buffer (~5 ms) and the listen mode can schedule a whole
/// lesson ahead on the audio clock. Nothing plays until every sample is loaded (`ready`).
public final class Sampler: @unchecked Sendable {
    public typealias Voice = Int

    public private(set) var ready = false

    /// 16-bit like the source: 7 minutes of stereo samples = 75 MB instead of 150 MB as Float (8 GB Mac).
    private final class Sample {
        let l: [Int16], r: [Int16], rate: Double
        init(l: [Int16], r: [Int16], rate: Double) { self.l = l; self.r = r; self.rate = rate }
    }
    private struct Playing {
        var id: Voice, sample: Sample, pos: Double, step: Double, gain: Float
        var start: Int64, release: Int64, env: Float = 1, decay: Float
    }
    private enum Command {
        case play(Playing)
        case release(Voice, at: Int64, fast: Bool)
        case stopAll
    }

    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var samples: [Int: Sample] = [:]          // root note → sample; read-only once `ready`
    private var outRate: Double = 48_000
    // shared with the render thread, under `lock`
    private var lock = os_unfair_lock()
    private var pending: [Command] = []
    private var pubFrames: Int64 = 0
    private var pubHost: Double = 0
    // render thread only
    private var frames: Int64 = 0
    private var active: [Playing] = []
    private var future: [Playing] = []
    private var nextID = 1

    public init() {}

    /// Decodes every sample in `folder` (`A0.mp3`, `Ds4.mp3`…) and starts the audio engine.
    public func load(folder: URL) async -> Bool {
        let names = ["A0", "C1", "Ds1", "Fs1", "A1", "C2", "Ds2", "Fs2", "A2", "C3", "Ds3", "Fs3", "A3", "C4", "Ds4",
                     "Fs4", "A4", "C5", "Ds5", "Fs5", "A5", "C6", "Ds6", "Fs6", "A6", "C7", "Ds7", "Fs7", "A7", "C8"]
        let base = ["C": 0, "Ds": 3, "Fs": 6, "A": 9]
        let decoded: [(Int, Sample)] = await withTaskGroup(of: (Int, Sample)?.self) { group in
            for n in names {
                group.addTask {
                    let letter = String(n.dropLast()), octave = Int(String(n.last!))!
                    guard let s = Self.decode(folder.appendingPathComponent(n + ".mp3")) else { return nil }
                    return (12 * (octave + 1) + base[letter]!, s)
                }
            }
            var out: [(Int, Sample)] = []
            for await r in group { if let r { out.append(r) } }
            return out
        }
        guard !decoded.isEmpty else { return false }
        samples = Dictionary(uniqueKeysWithValues: decoded)
        do { try start() } catch { return false }
        ready = true
        return true
    }

    private static func decode(_ url: URL) -> Sample? {
        guard let file = try? AVAudioFile(forReading: url),
              let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buf)) != nil, let ch = buf.floatChannelData else { return nil }
        let n = Int(buf.frameLength)
        func pcm(_ p: UnsafeMutablePointer<Float>) -> [Int16] {
            UnsafeBufferPointer(start: p, count: n).map { Int16(max(-1, min(1, $0)) * 32767) }
        }
        let l = pcm(ch[0])
        let r = buf.format.channelCount > 1 ? pcm(ch[1]) : l
        return Sample(l: l, r: r, rate: file.processingFormat.sampleRate)
    }

    private func start() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try? session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                               queue: .main) { [weak self] _ in try? self?.engine.start() }
        #endif
        outRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        if outRate <= 0 { outRate = 48_000 }
        let format = AVAudioFormat(standardFormatWithSampleRate: outRate, channels: 2)!
        let node = AVAudioSourceNode(format: format) { [unowned self] _, ts, count, abl in
            self.render(Int(count), host: ts.pointee.mHostTime, abl)
            return noErr
        }
        self.node = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                               queue: .main) { [weak self] _ in try? self?.engine.start() }
        try engine.start()
    }

    // MARK: clock

    private static let hostToSec: Double = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return Double(tb.numer) / Double(tb.denom) / 1e9
    }()

    /// Seconds on the audio clock (frames rendered, interpolated between buffers with the host clock).
    public var now: Double {
        os_unfair_lock_lock(&lock)
        let f = pubFrames, h = pubHost
        os_unfair_lock_unlock(&lock)
        let since = h > 0 ? max(0, min(0.05, CACurrentMediaTime() - h)) : 0
        return Double(f) / outRate + since
    }

    private func frame(_ t: Double) -> Int64 { Int64((t * outRate).rounded()) }

    // MARK: playing

    /// Plays MIDI note `m` at `when` (audio-clock seconds, see `now`); `dur` nil = until `stop`.
    @discardableResult
    public func note(_ m: Int, at when: Double, dur: Double? = nil, vel: Double = 0.8) -> Voice {
        guard ready, let root = samples.keys.min(by: { abs($0 - m) < abs($1 - m) }), let s = samples[root] else { return 0 }
        os_unfair_lock_lock(&lock)
        let id = nextID
        nextID += 1
        os_unfair_lock_unlock(&lock)
        let start = frame(when)
        let step = pow(2, Double(m - root) / 12) * s.rate / outRate
        let v = Playing(id: id, sample: s, pos: 0, step: step, gain: Float(pow(vel, 1.6) * 1.1 * 0.9),
                        start: start, release: dur.map { start + frame($0) } ?? .max, decay: Self.decay(0.12, outRate))
        send(.play(v))
        return id
    }

    public func stop(_ v: Voice, at when: Double? = nil) {
        guard v != 0 else { return }
        send(.release(v, at: frame(when ?? now), fast: false))
    }

    /// Stops everything playing or scheduled (Stop / lesson change), with a 20 ms fade.
    public func stopAll() { send(.stopAll) }

    /// Count-in beat on the piano: a soft high A on beat 1, E on the others.
    public func click(at when: Double, accent: Bool) {
        note(accent ? 93 : 88, at: when, dur: 0.15, vel: accent ? 0.5 : 0.35)
    }

    private static func decay(_ tau: Double, _ rate: Double) -> Float { Float(exp(-1 / (tau * rate))) }

    private func send(_ c: Command) {
        os_unfair_lock_lock(&lock)
        pending.append(c)
        os_unfair_lock_unlock(&lock)
    }

    // MARK: render thread

    private func render(_ n: Int, host: UInt64, _ abl: UnsafeMutablePointer<AudioBufferList>) {
        let bufs = UnsafeMutableAudioBufferListPointer(abl)
        guard bufs.count >= 2, let lp = bufs[0].mData?.assumingMemoryBound(to: Float.self),
              let rp = bufs[1].mData?.assumingMemoryBound(to: Float.self) else { return }
        lp.update(repeating: 0, count: n)
        rp.update(repeating: 0, count: n)
        var cmds: [Command] = []
        if os_unfair_lock_trylock(&lock) {
            if !pending.isEmpty { cmds = pending; pending.removeAll(keepingCapacity: true) }
            pubFrames = frames
            pubHost = host > 0 ? Double(host) * Self.hostToSec : CACurrentMediaTime()
            os_unfair_lock_unlock(&lock)
        }
        let fast = Self.decay(0.02, outRate)
        for c in cmds {
            switch c {
            case .play(let v):
                future.append(v)
            case .release(let id, let at, let quick):
                if let i = active.firstIndex(where: { $0.id == id }) {
                    active[i].release = min(active[i].release, at)
                    if quick { active[i].decay = fast }
                } else if let i = future.firstIndex(where: { $0.id == id }) {
                    future[i].release = min(future[i].release, at)
                }
            case .stopAll:
                future.removeAll()
                for i in active.indices { active[i].release = min(active[i].release, frames); active[i].decay = fast }
            }
        }
        let end = frames + Int64(n)
        if !future.isEmpty {
            var keep: [Playing] = []
            for v in future { if v.start < end { active.append(v) } else { keep.append(v) } }
            future = keep
            if active.count > 64 { active.removeFirst(active.count - 64) }   // voice stealing: oldest first
        }
        var i = 0
        while i < active.count {
            var v = active[i]
            let len = v.sample.l.count
            var dead = false
            let first = max(0, Int(v.start - frames))
            v.sample.l.withUnsafeBufferPointer { sl in
                v.sample.r.withUnsafeBufferPointer { sr in
                    for k in first..<n {
                        let f = frames + Int64(k)
                        if f >= v.release {
                            v.env *= v.decay
                            if v.env < 1e-4 || f - v.release > Int64(outRate * 1.2) { dead = true; break }
                        }
                        let idx = Int(v.pos)
                        if idx + 1 >= len { dead = true; break }
                        let frac = Float(v.pos - Double(idx)), g = v.gain * v.env / 32767
                        let l0 = Float(sl[idx]), r0 = Float(sr[idx])
                        lp[k] += (l0 + (Float(sl[idx + 1]) - l0) * frac) * g
                        rp[k] += (r0 + (Float(sr[idx + 1]) - r0) * frac) * g
                        v.pos += v.step
                    }
                }
            }
            if dead { active.remove(at: i) } else { active[i] = v; i += 1 }
        }
        for k in 0..<n {                                  // soft limit instead of a compressor
            if abs(lp[k]) > 0.8 { lp[k] = tanhf(lp[k]) }
            if abs(rp[k]) > 0.8 { rp[k] = tanhf(rp[k]) }
        }
        frames = end
    }
}
