import Foundation
import OSLog

enum DictatorLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "app.dictator.local"

    static let audio = Logger(subsystem: subsystem, category: "Audio")
    static let dictation = Logger(subsystem: subsystem, category: "Dictation")
    static let insertion = Logger(subsystem: subsystem, category: "Insertion")
    static let transcription = Logger(subsystem: subsystem, category: "Transcription")
}
