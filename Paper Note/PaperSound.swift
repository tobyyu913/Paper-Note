//
//  PaperSound.swift
//  Paper Note
//
//  Runtime sound synthesis — no audio assets. Two sounds:
//   • flip(): a band-limited paper rustle for turning a page.
//   • stud(): a metallic snap for the leather cover's press stud.
//

import AVFoundation

final class PaperSound {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let varispeed = AVAudioUnitVarispeed()
    private var rustles: [AVAudioPCMBuffer] = []
    private var snap: AVAudioPCMBuffer?
    private var started = false

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        engine.attach(player)
        engine.attach(varispeed)
        engine.connect(player, to: varispeed, format: format)
        engine.connect(varispeed, to: engine.mainMixerNode, format: format)
        rustles = (0..<4).map { Self.makeRustle(seed: UInt64($0) &* 2654435761, format: format) }
        snap = Self.makeStud(format: format)
    }

    func flip() {
        guard let buffer = rustles.randomPick() else { return }
        play(buffer, rate: Float.random(in: 0.92...1.08))
    }

    func stud() {
        guard let snap else { return }
        play(snap, rate: Float.random(in: 0.97...1.03))
    }

    private func play(_ buffer: AVAudioPCMBuffer, rate: Float) {
        if !started {
            do { try engine.start(); started = true } catch { return }
        }
        if !player.isPlaying { player.play() }
        varispeed.rate = rate
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    // MARK: - Paper rustle

    private static func makeRustle(seed: UInt64, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * 0.26)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let data = buffer.floatChannelData![0]

        var rng = SplitMix64(seed: seed)
        let n = Int(frameCount)
        var prev: Float = 0
        for i in 0..<n {
            let t = Double(i) / Double(n)
            let attack = min(1.0, t / 0.04)
            let decay = pow(1.0 - t, 1.6)
            var env = Float(attack * decay)
            if rng.nextUnit() > 0.985 { env *= Float.random(in: 1.5...2.6, using: &rng) }
            let white = rng.nextSigned()
            let highpassed = white - prev   // brighten toward a dry "shh"
            prev = white
            data[i] = highpassed * env * 0.45
        }
        return buffer
    }

    // MARK: - Press-stud snap

    private static func makeStud(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * 0.14)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let data = buffer.floatChannelData![0]

        var rng = SplitMix64(seed: 0xBEEF_F00D)
        let n = Int(frameCount)
        // Two sharp transients (the stud popping free) plus a short metallic ring.
        let clickAt = [0, Int(0.018 * sampleRate)]
        for i in 0..<n {
            let t = Double(i) / sampleRate
            var s: Float = 0

            // Metallic ring: a couple of high partials decaying fast.
            let ring = sin(2 * .pi * 2400 * t) * 0.6 + sin(2 * .pi * 3600 * t) * 0.4
            s += Float(ring) * Float(exp(-t / 0.02)) * 0.35

            // Click transients: very short noisy impulses.
            for c in clickAt {
                let d = i - c
                if d >= 0 && d < Int(0.004 * sampleRate) {
                    let local = Double(d) / (0.004 * sampleRate)
                    s += rng.nextSigned() * Float(pow(1 - local, 3)) * 0.8
                }
            }
            data[i] = max(-1, min(1, s))
        }
        return buffer
    }
}

// MARK: - Deterministic RNG

private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func nextUnit() -> Double { Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0) }
    mutating func nextSigned() -> Float { Float(nextUnit() * 2.0 - 1.0) }
}

private extension Array {
    func randomPick() -> Element? { isEmpty ? nil : self[Int.random(in: 0..<count)] }
}
