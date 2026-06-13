import Foundation
import AVFoundation

/// Wispr-Flow-style start / send / fail sounds. Buffers are synthesized at
/// launch so we ship no audio assets. Gated by `UserPreferences.playSounds`.
final class SoundService {
    static let shared = SoundService()

    private var startPlayer: AVAudioPlayer?
    private var sendPlayer: AVAudioPlayer?
    private var failPlayer: AVAudioPlayer?

    private init() {
        startPlayer = makePlayer(frequency: 880, duration: 0.08, volume: 0.28)
        sendPlayer = makeArpeggioPlayer(frequencies: [1320, 990], duration: 0.12, volume: 0.32)
        failPlayer = makePlayer(frequency: 220, duration: 0.06, volume: 0.22)
    }

    func playStart() {
        play(startPlayer)
    }

    func playSend() {
        play(sendPlayer)
    }

    func playFail() {
        play(failPlayer)
    }

    private func play(_ player: AVAudioPlayer?) {
        guard UserPreferences.shared.playSounds else { return }
        guard let player else { return }
        player.volume = Float(UserPreferences.shared.soundVolume)
        player.currentTime = 0
        player.play()
    }

    private func makePlayer(frequency: Double, duration: Double, volume: Double) -> AVAudioPlayer? {
        guard let buffer = synthesizeTone(frequency: frequency, duration: duration) else { return nil }
        return player(from: buffer, volume: volume)
    }

    private func makeArpeggioPlayer(frequencies: [Double], duration: Double, volume: Double) -> AVAudioPlayer? {
        guard let buffer = synthesizeArpeggio(frequencies: frequencies, duration: duration) else { return nil }
        return player(from: buffer, volume: volume)
    }

    private func player(from buffer: AVAudioPCMBuffer, volume: Double) -> AVAudioPlayer? {
        guard let data = pcmData(from: buffer) else { return nil }
        do {
            let player = try AVAudioPlayer(data: data, fileTypeHint: "WAVE")
            player.prepareToPlay()
            player.volume = Float(volume)
            return player
        } catch {
            Log.app.error("SoundService: failed to create player — \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func synthesizeTone(frequency: Double, duration: Double, sampleRate: Double = 44_100) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        guard let samples = buffer.floatChannelData?[0] else { return nil }
        let total = Int(frameCount)
        for i in 0..<total {
            let t = Double(i) / sampleRate
            let envelope = min(1.0, t / 0.012) * min(1.0, (duration - t) / 0.025)
            samples[i] = Float(sin(2 * .pi * frequency * t) * envelope * 0.85)
        }
        return buffer
    }

    private func synthesizeArpeggio(frequencies: [Double], duration: Double, sampleRate: Double = 44_100) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        guard let samples = buffer.floatChannelData?[0] else { return nil }
        let total = Int(frameCount)
        let noteDuration = duration / Double(max(1, frequencies.count))
        for i in 0..<total {
            let t = Double(i) / sampleRate
            let noteIndex = min(frequencies.count - 1, Int(t / noteDuration))
            let localT = t - Double(noteIndex) * noteDuration
            let freq = frequencies[noteIndex]
            let envelope = min(1.0, localT / 0.008) * min(1.0, (noteDuration - localT) / 0.02)
            samples[i] = Float(sin(2 * .pi * freq * localT) * envelope * 0.85)
        }
        return buffer
    }

    /// Pack PCM float buffer into a minimal WAV for AVAudioPlayer.
    private func pcmData(from buffer: AVAudioPCMBuffer) -> Data? {
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        let frames = Int(buffer.frameLength)
        var pcm = Data(capacity: frames * 2)
        for i in 0..<frames {
            let sample = Int16(max(-1, min(1, channel[i])) * Float(Int16.max))
            var le = sample.littleEndian
            pcm.append(Data(bytes: &le, count: 2))
        }
        return wrapWAV(pcm: pcm, sampleRate: Int(buffer.format.sampleRate), channels: 1)
    }

    private func wrapWAV(pcm: Data, sampleRate: Int, channels: Int) -> Data {
        var data = Data()
        let byteRate = sampleRate * channels * 2
        let blockAlign = channels * 2
        let chunkSize = 36 + pcm.count
        data.append(contentsOf: "RIFF".utf8)
        data.append(uint32LE(UInt32(chunkSize)))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(uint32LE(16))
        data.append(uint16LE(1)) // PCM
        data.append(uint16LE(UInt16(channels)))
        data.append(uint32LE(UInt32(sampleRate)))
        data.append(uint32LE(UInt32(byteRate)))
        data.append(uint16LE(UInt16(blockAlign)))
        data.append(uint16LE(16))
        data.append(contentsOf: "data".utf8)
        data.append(uint32LE(UInt32(pcm.count)))
        data.append(pcm)
        return data
    }

    private func uint16LE(_ v: UInt16) -> Data {
        var le = v.littleEndian
        return Data(bytes: &le, count: 2)
    }

    private func uint32LE(_ v: UInt32) -> Data {
        var le = v.littleEndian
        return Data(bytes: &le, count: 4)
    }
}
