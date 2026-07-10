import Foundation
import AVFoundation
import Combine

/// The output of a recording session: a temp file URL plus the duration.
struct RecordingResult {
    let fileURL: URL
    let duration: TimeInterval
    let averagePower: Float
    /// Loudest level (dB) observed while the key was held. Used to decide
    /// whether the user actually spoke — true silence never sends to the network.
    let peakPower: Float
}

/// Captures microphone audio while the push-to-talk key is held.
/// Writes a temp WAV file that can be fed to a transcription provider.
///
/// Implementation notes
/// --------------------
/// The mic is kept "warm" — the `AVAudioEngine` runs continuously and the
/// tap is always installed. While not recording, each incoming buffer is
/// pushed into a small in-memory ring buffer (`preRollSeconds` of audio).
/// When `startRecording` is called we open the output file and prepend
/// whatever is in the ring buffer, so we capture the user's first words
/// even when they speak the instant they hit the key.
final class AudioRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var currentLevel: Float = 0   // -60…0 dB

    private let engine = AVAudioEngine()
    private var hwFormat: AVAudioFormat?
    private var writeFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var audioFile: AVAudioFile?
    private var startedAt: Date?
    private var maxRecordingTimer: Timer?
    private var levelSamples: [Float] = []
    private var fileURL: URL?

    private let preferredSampleRate: Double = 16_000
    /// How much pre-key-press audio to keep in memory so we never miss
    /// the first half-second of speech.
    private let preRollSeconds: TimeInterval = 0.45

    /// In-memory ring buffer of recent Int16 PCM frames (post-conversion to
    /// the 16 kHz write format). Stored as raw Data segments; on
    /// startRecording we concatenate and write them in order.
    private var preRollChunks: [Data] = []
    private var preRollFrameCount: Int = 0
    private let preRollAccessQueue = DispatchQueue(label: "cadence.audio.preroll")

    private var maxPreRollFrames: Int { Int(preferredSampleRate * preRollSeconds) }

    // MARK: - Lifecycle

    /// Start the underlying audio engine and install the tap. Called once
    /// at app launch — keeps the mic warm so the first keyDown can start
    /// writing audio with zero engine-startup latency.
    func warmUp() {
        guard engine.isRunning == false else { return }
        do {
            try setUpEngine()
            try engine.start()
            Log.audio.info("AudioRecorder: engine warmed up")
        } catch {
            Log.audio.error("AudioRecorder warmUp failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Tear down the engine. Used on app quit.
    func shutDown() {
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
    }

    // MARK: - Public recording API

    func startRecording() throws {
        guard !isRecording else { return }
        levelSamples.removeAll()

        // Make sure the engine is alive. If a device change killed it,
        // rebuild and warm up again right now.
        if !engine.isRunning {
            do {
                try setUpEngine()
                try engine.start()
            } catch {
                throw DictationError.audioCaptureFailed("Failed to (re)start audio engine: \(error.localizedDescription)")
            }
        }

        guard let writeFormat else {
            throw DictationError.audioCaptureFailed("Audio engine not initialized")
        }

        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("cadence-\(UUID().uuidString.prefix(8)).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: preferredSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        do {
            audioFile = try AVAudioFile(
                forWriting: url,
                settings: settings,
                commonFormat: .pcmFormatInt16,
                interleaved: true
            )
        } catch {
            throw DictationError.audioCaptureFailed("Failed to open output file: \(error.localizedDescription)")
        }
        fileURL = url

        // Flush the pre-roll buffer into the new file so the first words are present.
        flushPreRoll(into: audioFile, format: writeFormat)

        startedAt = Date()
        isRecording = true

        let maxSec = max(1, UserPreferences.shared.maximumRecordingSeconds)
        maxRecordingTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(maxSec),
            repeats: false
        ) { [weak self] _ in
            Log.audio.info("Maximum recording duration reached")
            _ = try? self?.stopRecording()
        }
        Log.audio.info("Recording started at \(self.preferredSampleRate, privacy: .public) Hz (with \(self.preRollFrameCount, privacy: .public) pre-roll frames)")
    }

    @discardableResult
    func stopRecording() throws -> RecordingResult? {
        guard isRecording else { return nil }
        maxRecordingTimer?.invalidate()
        maxRecordingTimer = nil

        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        startedAt = nil
        isRecording = false
        currentLevel = 0

        defer {
            audioFile = nil
            fileURL = nil
            // Reset pre-roll AFTER recording stops so the next session starts fresh.
            resetPreRoll()
        }

        guard let url = fileURL else {
            throw DictationError.audioCaptureFailed("Recording finalized with no output file")
        }

        let avg = levelSamples.isEmpty ? -120 : levelSamples.reduce(0, +) / Float(levelSamples.count)
        let peak = levelSamples.max() ?? -120
        Log.audio.info("Recording stopped after \(duration, format: .fixed(precision: 2), privacy: .public)s (peak \(peak, format: .fixed(precision: 1), privacy: .public) dB)")
        return RecordingResult(fileURL: url, duration: duration, averagePower: avg, peakPower: peak)
    }

    func cancel() {
        guard isRecording else { return }
        maxRecordingTimer?.invalidate()
        maxRecordingTimer = nil
        startedAt = nil
        isRecording = false
        currentLevel = 0

        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        audioFile = nil
        fileURL = nil
        resetPreRoll()
        Log.audio.info("Recording cancelled")
    }

    // MARK: - Setup

    private func setUpEngine() throws {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        engine.reset()

        let input = engine.inputNode
        let hw = input.outputFormat(forBus: 0)
        guard hw.sampleRate > 0, hw.channelCount > 0 else {
            throw DictationError.audioCaptureFailed("No microphone input available")
        }
        self.hwFormat = hw

        guard let write = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: preferredSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw DictationError.audioCaptureFailed("Failed to build write format")
        }
        self.writeFormat = write

        guard let conv = AVAudioConverter(from: hw, to: write) else {
            throw DictationError.audioCaptureFailed("Could not create audio converter")
        }
        self.converter = conv

        let bufferSize: AVAudioFrameCount = 1024  // smaller buffers = lower latency
        input.installTap(onBus: 0, bufferSize: bufferSize, format: hw) { [weak self] buffer, _ in
            self?.processIncoming(buffer: buffer)
        }

        engine.prepare()
    }

    // MARK: - Tap processing

    private func processIncoming(buffer: AVAudioPCMBuffer) {
        guard let converter, let writeFormat else { return }

        // 1) Level meter — always live so the indicator can react when warming up.
        if let chData = buffer.floatChannelData?[0] {
            let frameCount = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameCount { sum += chData[i] * chData[i] }
            let rms = sqrtf(sum / Float(max(1, frameCount)))
            let db = 20 * log10f(max(rms, 1e-7))
            DispatchQueue.main.async { [weak self] in self?.currentLevel = db }
            if isRecording {
                levelSamples.append(db)
            }
        }

        // 2) Convert to 16 kHz mono Int16.
        let outFrameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * preferredSampleRate / buffer.format.sampleRate
        )
        guard outFrameCount > 0,
              let outBuffer = AVAudioPCMBuffer(
                  pcmFormat: writeFormat,
                  frameCapacity: outFrameCount + 64
              ) else { return }

        var error: NSError?
        var providedInput = false
        let status = converter.convert(to: outBuffer, error: &error) { _, inputStatus in
            if providedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            providedInput = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error || error != nil {
            Log.audio.error("Audio conversion failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            return
        }

        if isRecording {
            // Append directly to the file.
            do {
                try audioFile?.write(from: outBuffer)
            } catch {
                Log.audio.error("Audio file write failed: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            // Append to the pre-roll ring buffer.
            appendToPreRoll(buffer: outBuffer)
        }
    }

    // MARK: - Pre-roll ring buffer

    private func appendToPreRoll(buffer: AVAudioPCMBuffer) {
        guard let int16Data = buffer.int16ChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        let bytes = frames * MemoryLayout<Int16>.size
        let data = Data(bytes: int16Data, count: bytes)

        preRollAccessQueue.sync {
            preRollChunks.append(data)
            preRollFrameCount += frames

            // Trim from the front while we exceed the cap.
            while preRollFrameCount > maxPreRollFrames, let first = preRollChunks.first {
                let firstFrames = first.count / MemoryLayout<Int16>.size
                if preRollFrameCount - firstFrames >= maxPreRollFrames {
                    preRollChunks.removeFirst()
                    preRollFrameCount -= firstFrames
                } else {
                    // Trim from inside the first chunk.
                    let excess = preRollFrameCount - maxPreRollFrames
                    let dropBytes = excess * MemoryLayout<Int16>.size
                    preRollChunks[0] = first.subdata(in: dropBytes..<first.count)
                    preRollFrameCount -= excess
                    break
                }
            }
        }
    }

    private func flushPreRoll(into file: AVAudioFile?, format: AVAudioFormat) {
        guard let file else { return }
        let snapshot: [Data] = preRollAccessQueue.sync {
            let copy = preRollChunks
            preRollChunks.removeAll(keepingCapacity: true)
            preRollFrameCount = 0
            return copy
        }
        guard !snapshot.isEmpty else { return }

        for data in snapshot {
            let frameCount = data.count / MemoryLayout<Int16>.size
            guard frameCount > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                                frameCapacity: AVAudioFrameCount(frameCount)) else { continue }
            buffer.frameLength = AVAudioFrameCount(frameCount)
            data.withUnsafeBytes { raw in
                guard let src = raw.baseAddress?.assumingMemoryBound(to: Int16.self),
                      let dest = buffer.int16ChannelData?[0] else { return }
                dest.update(from: src, count: frameCount)
            }
            do {
                try file.write(from: buffer)
            } catch {
                Log.audio.error("Pre-roll write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        Log.audio.info("Flushed \(snapshot.count, privacy: .public) pre-roll chunks into file")
    }

    private func resetPreRoll() {
        preRollAccessQueue.sync {
            preRollChunks.removeAll(keepingCapacity: true)
            preRollFrameCount = 0
        }
    }
}
