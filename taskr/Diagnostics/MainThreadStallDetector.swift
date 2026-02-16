import Foundation

final class MainThreadStallDetector {
    static let shared = MainThreadStallDetector()

    private let queue = DispatchQueue(label: "com.bone.taskr.diagnostics.stall", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastReportedUptime: TimeInterval = 0

    private init() {}

    func start(interval: TimeInterval = 0.25, threshold: TimeInterval = 0.8, reportCooldown: TimeInterval = 5.0) {
        guard timer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let scheduledAt = ProcessInfo.processInfo.systemUptime
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let delay = ProcessInfo.processInfo.systemUptime - scheduledAt
                guard delay >= threshold else { return }

                let now = ProcessInfo.processInfo.systemUptime
                if now - self.lastReportedUptime >= reportCooldown {
                    self.lastReportedUptime = now
                    TaskrDiagnostics.logMainThreadStall(delaySeconds: delay)
                }
            }
        }
        self.timer = timer
        timer.resume()
    }
}
