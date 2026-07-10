import Foundation

/// Fast LLM fallback when rule-based routing finds no destination.
/// Handles phonetic mistranscriptions like "Claudia" → Claude.
struct AIRoutingResult {
    let destinationId: String
    let stripChars: Int
    let confidence: Float
}

final class AIRoutingProvider {
    static let shared = AIRoutingProvider()

    private var currentTask: URLSessionDataTask?
    private let lock = NSLock()

    func cancel() {
        lock.lock()
        currentTask?.cancel()
        currentTask = nil
        lock.unlock()
    }

    /// Classify a raw transcript against known destinations.
    /// Calls completion on the main queue. Returns nil on timeout/failure.
    func classify(
        rawTranscript: String,
        destinations: [Destination],
        completion: @escaping (AIRoutingResult?) -> Void
    ) {
        cancel()

        let prefs = UserPreferences.shared
        let key = prefs.aiPolishApiKey
        guard !key.isEmpty else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let endpoint = prefs.aiPolishEndpoint.isEmpty
            ? "https://api.openai.com/v1/chat/completions"
            : prefs.aiPolishEndpoint
        guard let url = URL(string: endpoint) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let enabled = destinations.filter(\.enabled)
        let catalog = enabled.map { "- \($0.id): \($0.displayName) (aliases: \($0.allAliases.prefix(6).joined(separator: ", ")))" }
            .joined(separator: "\n")

        let system = """
        You detect routing intent in voice dictation. The user may say "hey Claude", "hey Claudia", "open cursor", etc. at the start of speech.
        Return ONLY valid JSON — no markdown, no commentary.
        Format: {"id":"<destination_id_or_null>","stripChars":<int>,"confidence":<0.0-1.0>}
        - id: match from the catalog below, or null if no routing intent
        - stripChars: number of characters to remove from the START of the transcript (the routing phrase)
        - confidence: how sure you are (0.0-1.0). Only return id when confidence >= 0.75
        If the user is just dictating content with no routing phrase, return {"id":null,"stripChars":0,"confidence":0}
        """

        let user = """
        Catalog:
        \(catalog)

        Transcript:
        \(rawTranscript)
        """

        let model = prefs.aiPolishModel.isEmpty ? "gpt-4o-mini" : prefs.aiPolishModel
        let payload: [String: Any] = [
            "model": model,
            "temperature": 0.0,
            "max_tokens": 80,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 2.5
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("https://cadence.app", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("Cadence", forHTTPHeaderField: "X-Title")
        req.httpBody = body

        var finished = false
        let finish: (AIRoutingResult?) -> Void = { result in
            guard !finished else { return }
            finished = true
            DispatchQueue.main.async { completion(result) }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            finish(nil)
        }

        let task = URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            self?.lock.lock()
            self?.currentTask = nil
            self?.lock.unlock()

            if let error = error as NSError?, error.code == NSURLErrorCancelled { return }
            if error != nil { finish(nil); return }

            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                finish(nil)
                return
            }

            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let jsonData = Self.extractJSON(from: trimmed),
                  let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                finish(nil)
                return
            }

            guard let id = parsed["id"] as? String, !id.isEmpty, id != "null" else {
                finish(nil)
                return
            }

            let confidence = (parsed["confidence"] as? NSNumber)?.floatValue ?? 0
            guard confidence >= 0.75 else {
                finish(nil)
                return
            }

            let stripChars = (parsed["stripChars"] as? NSNumber)?.intValue ?? 0
            finish(AIRoutingResult(destinationId: id, stripChars: max(0, stripChars), confidence: confidence))
        }

        lock.lock()
        currentTask = task
        lock.unlock()
        task.resume()
    }

    private static func extractJSON(from text: String) -> Data? {
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            return String(text[start...end]).data(using: .utf8)
        }
        return text.data(using: .utf8)
    }
}
