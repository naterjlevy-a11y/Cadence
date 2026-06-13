import Foundation

/// One entry in the dictation history list. Stored only when
/// `UserPreferences.saveDictationHistory` is on.
struct DictationHistoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let destinationId: String?
    let destinationDisplayName: String?
    let finalText: String
    let routePhraseDetected: String?
    let pasteSucceeded: Bool
    let errorMessage: String?
}

enum DictationStage: String, Codable, CaseIterable {
    case idle
    case recording
    case cancelling
    case processingAudio
    case transcribing
    case detectingRoute
    case cleaningText
    case resolvingDestination
    case openingDestination
    case waitingForDestination
    case pasting
    case completed
    case failed

    var userFacingDescription: String {
        switch self {
        case .idle: return "Ready"
        case .recording: return "Listening"
        case .cancelling: return "Cancelling"
        case .processingAudio: return "Processing audio"
        case .transcribing: return "Transcribing"
        case .detectingRoute: return "Detecting destination"
        case .cleaningText: return "Cleaning up"
        case .resolvingDestination: return "Resolving destination"
        case .openingDestination: return "Opening destination"
        case .waitingForDestination: return "Waiting for destination"
        case .pasting: return "Pasting"
        case .completed: return "Done"
        case .failed: return "Error"
        }
    }
}

enum DictationError: LocalizedError {
    case microphonePermissionDenied
    case accessibilityPermissionDenied
    case inputMonitoringPermissionDenied
    case audioCaptureFailed(String)
    case transcriptionFailed(String)
    case noSpeechDetected
    case destinationNotResolvable(String)
    case appNotInstalled(String)
    case pasteFailed(String)
    case recordingTooShort
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is required to record your voice."
        case .accessibilityPermissionDenied:
            return "Accessibility access is required to focus apps and paste your dictated text."
        case .inputMonitoringPermissionDenied:
            return "Input Monitoring is required for global push-to-talk."
        case .audioCaptureFailed(let detail):
            return "Audio capture failed. \(detail)"
        case .transcriptionFailed(let detail):
            return "We could not transcribe that recording. \(detail)"
        case .noSpeechDetected:
            return "No speech was detected."
        case .destinationNotResolvable(let name):
            return "I heard \"\(name),\" but it is not set up as a destination yet."
        case .appNotInstalled(let name):
            return "\(name) is not installed."
        case .pasteFailed(let detail):
            return "The text was prepared, but paste did not complete. \(detail)"
        case .recordingTooShort:
            return "That recording was too short."
        case .cancelled:
            return "Dictation cancelled."
        case .unknown(let detail):
            return detail
        }
    }
}
