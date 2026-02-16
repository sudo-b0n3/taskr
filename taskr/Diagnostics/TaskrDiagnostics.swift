import Foundation
import os

enum TaskrDiagnostics {
    static let subsystem = "com.bone.taskr.diagnostics"

    static let expansionLogger = Logger(subsystem: subsystem, category: "expansion")
    static let stallLogger = Logger(subsystem: subsystem, category: "stall")
    static let signpostLog = OSLog(subsystem: subsystem, category: "signpost")

    enum Signpost {
        static let toggleExpansion: StaticString = "ToggleExpansion"
        static let setTaskExpanded: StaticString = "SetTaskExpanded"
        static let setExpandedState: StaticString = "SetExpandedState"
    }

    static func logExpansion(_ message: String) {
        expansionLogger.notice("\(message, privacy: .public)")
    }

    static func logMainThreadStall(delaySeconds: Double) {
        let delayMs = Int(delaySeconds * 1000.0)
        stallLogger.error("Main thread stall detected: \(delayMs, privacy: .public)ms")
    }

    static func signpostBegin(_ name: StaticString, message: String) {
        os_signpost(.begin, log: signpostLog, name: name, "%{public}s", message)
    }

    static func signpostEnd(_ name: StaticString, message: String) {
        os_signpost(.end, log: signpostLog, name: name, "%{public}s", message)
    }
}
