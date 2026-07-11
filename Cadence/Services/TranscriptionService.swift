import Foundation
import Speech

/// Result of transcription. Includes the raw text plus optional confidence.
struct TranscriptionResult {
    let text: String
    let confidence: Float
    let provider: String
}

/// Pluggable transcription provider. The MVP uses Apple's on-device Speech
/// framework. Future versions can drop in Whisper or a cloud API behind this
/// same protocol.
protocol TranscriptionProvider: AnyObject {
    var displayName: String { get }
    func transcribe(fileURL: URL, completion: @escaping (Result<TranscriptionResult, Error>) -> Void)
    func cancelCurrent()
}

// MARK: - Vocabulary biasing

/// Collects the brand dictionary, personal dictionary, and currently-enabled
/// destinations into a single string used to bias both Apple Speech
/// (`contextualStrings`) and Whisper (`prompt` field). This is the #1 cheap
/// fix for "the ASR doesn't know my product names" complaints.
enum TranscriptionVocabulary {
    static func contextualStrings() -> [String] {
        var terms: Set<String> = []
        if UserPreferences.shared.brandDictionaryEnabled {
            terms.formUnion(BrandDictionary.canonical)
        }
        terms.formUnion(UserPreferences.shared.personalDictionary)
        for dest in DestinationRegistry.shared.destinations where dest.enabled {
            terms.insert(dest.displayName)
            terms.formUnion(dest.allAliases.prefix(3))
        }
        return Array(terms)
    }

    /// Whisper's prompt field accepts a short comma-separated string of
    /// vocabulary hints. We keep it well under ~200 tokens by truncating
    /// to ~80 terms — Whisper weights the start of the prompt heaviest.
    static func whisperPrompt() -> String {
        let priority: [String] = [
            "Cadence, Wispr Flow, McGill, Claude, Anthropic, ChatGPT, OpenAI, Cursor, Gemini, GitHub, TypeScript, Node.js, Next.js, VS Code, Xcode, macOS, iOS, Formula SAE, Formula Electric",
        ]
        let extras = contextualStrings()
            .sorted { $0.count > $1.count }
            .prefix(60)
        let allTerms = priority + extras
        let joined = allTerms.joined(separator: ", ")
        // Whisper prompt cap: ~896 chars is safe.
        if joined.count > 800 {
            return String(joined.prefix(800))
        }
        return joined
    }
}

// MARK: - Apple Speech

/// Apple Speech framework provider. Prefers on-device recognition when the
/// user explicitly requests it; otherwise uses server-side for long-form quality.
final class AppleSpeechTranscriptionProvider: TranscriptionProvider {
    let displayName = "Apple Speech"

    private let recognizer: SFSpeechRecognizer?
    private var currentTask: SFSpeechRecognitionTask?

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    func cancelCurrent() {
        currentTask?.cancel()
        currentTask = nil
    }

    func transcribe(fileURL: URL, completion: @escaping (Result<TranscriptionResult, Error>) -> Void) {
        cancelCurrent()

        guard let recognizer, recognizer.isAvailable else {
            completion(.failure(DictationError.transcriptionFailed("Speech recognizer is not available.")))
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        request.addsPunctuation = true
        // Bias Apple Speech toward our brand + destination vocabulary so it
        // stops mis-transcribing "McGill", "Cursor", "Anthropic", etc.
        let vocab = TranscriptionVocabulary.contextualStrings()
        if !vocab.isEmpty {
            request.contextualStrings = Array(vocab.prefix(100))
        }
        let preferOnDevice = UserPreferences.shared.preferOnDeviceTranscription
        if preferOnDevice && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else {
            request.requiresOnDeviceRecognition = false
        }

        currentTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let error = error as NSError? {
                if error.domain == "kAFAssistantErrorDomain" && error.code == 1110 {
                    self?.currentTask = nil
                    completion(.failure(DictationError.noSpeechDetected))
                    return
                }
                if (error as NSError).code == 216 { // cancelled
                    self?.currentTask = nil
                    return
                }
                self?.currentTask = nil
                completion(.failure(DictationError.transcriptionFailed(error.localizedDescription)))
                return
            }

            guard let result, result.isFinal else { return }
            self?.currentTask = nil
            let text = result.bestTranscription.formattedString
            let segments = result.bestTranscription.segments
            let avgConfidence = segments.isEmpty
                ? 1.0
                : segments.reduce(0) { $0 + $1.confidence } / Float(segments.count)
            completion(.success(TranscriptionResult(
                text: text,
                confidence: avgConfidence,
                provider: "AppleSpeech"
            )))
        }
    }
}

// MARK: - Multipart body (shared by BYOK + Cloud)

private enum WhisperMultipart {
    static func buildBody(fileURL: URL, model: String, prompt: String) throws -> (Data, String) {
        guard let audioData = try? Data(contentsOf: fileURL) else {
            throw DictationError.transcriptionFailed("Couldn't read audio file.")
        }
        let boundary = "----CadenceBoundary\(UUID().uuidString)"
        var body = Data()
        func append(_ string: String) {
            if let data = string.data(using: .utf8) { body.append(data) }
        }
        let filename = fileURL.lastPathComponent
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        append("\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append(model)
        append("\r\n")
        if !prompt.isEmpty {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
            append(prompt)
            append("\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
        append("en")
        append("\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        append("json")
        append("\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"temperature\"\r\n\r\n")
        append("0")
        append("\r\n--\(boundary)--\r\n")
        return (body, boundary)
    }
}

// MARK: - Cadence Cloud (Groq via your proxy)

/// Sends audio to your Cloudflare Worker; the server holds the Groq key.
final class CadenceCloudTranscriptionProvider: TranscriptionProvider {
    let displayName = "Cadence Cloud"

    private var currentTask: URLSessionDataTask?
    private let lock = NSLock()

    func cancelCurrent() {
        lock.lock()
        currentTask?.cancel()
        currentTask = nil
        lock.unlock()
    }

    func transcribe(fileURL: URL, completion: @escaping (Result<TranscriptionResult, Error>) -> Void) {
        cancelCurrent()

        guard let endpoint = CloudConfig.shared.transcribeURL else {
            completion(.failure(DictationError.transcriptionFailed("Cadence Cloud is not configured.")))
            return
        }
        // Always refresh the token first — an expired cloud token would 401.
        AuthService.shared.withFreshToken { [weak self] freshToken in
            guard let self else { return }
            guard let token = freshToken, !token.isEmpty else {
                completion(.failure(DictationError.transcriptionFailed("Sign in to Cadence Cloud in Settings → Account, or use your own Groq key.")))
                return
            }
            self.performCloudTranscription(fileURL: fileURL, endpoint: endpoint, token: token, completion: completion)
        }
    }

    private func performCloudTranscription(fileURL: URL, endpoint: URL, token: String,
                                           completion: @escaping (Result<TranscriptionResult, Error>) -> Void) {

        let prefs = UserPreferences.shared
        let model = prefs.groqWhisperModel.isEmpty ? "whisper-large-v3-turbo" : prefs.groqWhisperModel
        let prompt = TranscriptionVocabulary.whisperPrompt()

        let built: (Data, String)
        do {
            built = try WhisperMultipart.buildBody(fileURL: fileURL, model: model, prompt: prompt)
        } catch {
            completion(.failure(error))
            return
        }
        let (body, boundary) = built

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 25.0
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let start = CFAbsoluteTimeGetCurrent()
        let task = URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            self?.lock.lock()
            self?.currentTask = nil
            self?.lock.unlock()

            if let error = error as NSError?, error.code == NSURLErrorCancelled { return }
            if let error {
                completion(.failure(DictationError.transcriptionFailed(error.localizedDescription)))
                return
            }

            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let bodyString = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

            if status == 429 {
                completion(.failure(DictationError.transcriptionFailed("Monthly Cadence Cloud limit reached. Upgrade or add your own Groq key in Settings.")))
                return
            }
            if status >= 400 {
                completion(.failure(DictationError.transcriptionFailed("Cloud transcription failed (HTTP \(status)).")))
                return
            }

            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = obj["text"] as? String else {
                completion(.failure(DictationError.transcriptionFailed("Unexpected cloud response.")))
                return
            }

            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            Log.transcription.info("Cadence Cloud ok in \(elapsedMs, privacy: .public)ms")
            completion(.success(TranscriptionResult(text: cleaned, confidence: 1.0, provider: "CadenceCloud")))
        }
        lock.lock()
        currentTask = task
        lock.unlock()
        task.resume()
    }
}

// MARK: - Groq Whisper (BYOK)

/// Direct Groq API — user supplies their own key.
final class GroqWhisperTranscriptionProvider: TranscriptionProvider {
    let displayName = "Groq Whisper (your key)"

    private let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    private var currentTask: URLSessionDataTask?
    private let lock = NSLock()

    func cancelCurrent() {
        lock.lock()
        currentTask?.cancel()
        currentTask = nil
        lock.unlock()
    }

    func transcribe(fileURL: URL, completion: @escaping (Result<TranscriptionResult, Error>) -> Void) {
        cancelCurrent()

        let prefs = UserPreferences.shared
        let apiKey = SecretStore.shared.groqApiKey
        guard !apiKey.isEmpty else {
            completion(.failure(DictationError.transcriptionFailed("Groq API key not set. Add one in Settings → Privacy → Transcription, or set GROQ_API_KEY in your environment.")))
            return
        }

        let model = prefs.groqWhisperModel.isEmpty ? "whisper-large-v3-turbo" : prefs.groqWhisperModel
        let prompt = TranscriptionVocabulary.whisperPrompt()

        let built: (Data, String)
        do {
            built = try WhisperMultipart.buildBody(fileURL: fileURL, model: model, prompt: prompt)
        } catch {
            completion(.failure(error))
            return
        }
        let (body, boundary) = built

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 20.0
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let start = CFAbsoluteTimeGetCurrent()
        let task = URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            self?.lock.lock()
            self?.currentTask = nil
            self?.lock.unlock()

            if let error = error as NSError?, error.code == NSURLErrorCancelled {
                return
            }
            if let error {
                Log.transcription.error("Groq Whisper network error: \(error.localizedDescription, privacy: .public)")
                completion(.failure(DictationError.transcriptionFailed(error.localizedDescription)))
                return
            }

            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let bodyString = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

            if status >= 400 {
                let snippet = String(bodyString.prefix(220))
                Log.transcription.error("Groq Whisper HTTP \(status, privacy: .public): \(snippet, privacy: .public)")
                let message: String
                switch status {
                case 401: message = "Groq rejected the API key. Re-check it in Settings."
                case 413: message = "Audio file too large for Groq."
                case 429: message = "Groq rate limit hit — try again in a moment."
                default:  message = "Groq returned HTTP \(status)."
                }
                completion(.failure(DictationError.transcriptionFailed(message)))
                return
            }

            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = obj["text"] as? String else {
                completion(.failure(DictationError.transcriptionFailed("Groq returned an unexpected response.")))
                return
            }

            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            Log.transcription.info("Groq Whisper ok in \(elapsedMs, privacy: .public)ms (\(cleaned.count, privacy: .public) chars)")
            completion(.success(TranscriptionResult(
                text: cleaned,
                confidence: 1.0,
                provider: "GroqWhisper"
            )))
        }

        lock.lock()
        currentTask = task
        lock.unlock()
        task.resume()
    }
}

// MARK: - Service (chooses + falls back)

/// Routes audio to the configured transcription provider, with optional
/// fallback when the cloud provider fails (no key, network down, rate limit).
final class TranscriptionService {
    static let shared = TranscriptionService()

    private let appleProvider = AppleSpeechTranscriptionProvider()
    private let cloudProvider = CadenceCloudTranscriptionProvider()
    private let groqProvider = GroqWhisperTranscriptionProvider()

    func cancelCurrent() {
        appleProvider.cancelCurrent()
        cloudProvider.cancelCurrent()
        groqProvider.cancelCurrent()
    }

    func transcribe(fileURL: URL, completion: @escaping (Result<TranscriptionResult, Error>) -> Void) {
        let prefs = UserPreferences.shared

        let run = { [weak self] in
            guard let self else { return }
            let provider = self.resolvePrimary(prefs: prefs)
            Log.transcription.info("Transcribing via \(provider.displayName, privacy: .public)")

            provider.transcribe(fileURL: fileURL) { outcome in
                switch outcome {
                case .success(let result):
                    completion(.success(result))
                case .failure(let error):
                    if prefs.transcriptionFallbackToApple,
                       provider !== self.appleProvider {
                        Log.transcription.warning("Primary \(provider.displayName, privacy: .public) failed — falling back to Apple Speech: \(error.localizedDescription, privacy: .public)")
                        self.appleProvider.transcribe(fileURL: fileURL, completion: completion)
                    } else {
                        completion(.failure(error))
                    }
                }
            }
        }

        // Cloud Groq needs a bearer token before we pick the provider — otherwise
        // resolveGroqProvider silently falls through to Apple Speech.
        let needsCloudSession = prefs.transcriptionProvider == "groq"
            && prefs.transcriptionAuthMode != "byok"
            && CloudConfig.shared.isCloudEnabled
            && SecretStore.shared.groqApiKey.isEmpty

        if needsCloudSession {
            AuthService.shared.ensureCloudSessionReady { _ in
                run()
            }
        } else {
            run()
        }
    }

    /// Resolve the primary provider based on prefs, cloud session, and BYOK key.
    private func resolvePrimary(prefs: UserPreferences) -> TranscriptionProvider {
        switch prefs.transcriptionProvider {
        case "groq":
            return resolveGroqProvider(prefs: prefs)
        default:
            return appleProvider
        }
    }

    private func resolveGroqProvider(prefs: UserPreferences) -> TranscriptionProvider {
        let hasBYOK = !SecretStore.shared.groqApiKey.isEmpty
        let cloudToken = AuthService.shared.accessToken ?? ""
        let canCloud = CloudConfig.shared.isCloudEnabled && !cloudToken.isEmpty

        switch prefs.transcriptionAuthMode {
        case "cloud":
            if canCloud { return cloudProvider }
            if hasBYOK { return groqProvider }
            return appleProvider
        case "byok":
            if hasBYOK { return groqProvider }
            return appleProvider
        default: // auto
            if canCloud { return cloudProvider }
            if hasBYOK { return groqProvider }
            return appleProvider
        }
    }
}
