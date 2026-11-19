import AppKit
import Combine

/// A deadline, rather than tick subtraction, keeps the countdown correct after sleep.
@MainActor
final class FocusTimerModel: ObservableObject {
    @Published private(set) var remainingSeconds: TimeInterval = 0
    @Published private(set) var isRunning = false
    @Published private(set) var completed = false
    private var duration: TimeInterval = 0
    private var deadline: Date?
    private var ticker: Timer?
    private let now: () -> Date
    private let didComplete: () -> Void
    var isTimerActive: Bool { remainingSeconds > 0 }
    var progress: Double { duration > 0 ? min(1, max(0, 1 - remainingSeconds / duration)) : 0 }

    init(now: @escaping () -> Date = Date.init, didComplete: @escaping () -> Void = { NSSound.beep() }) {
        self.now = now
        self.didComplete = didComplete
    }

    func start(minutes: Int) {
        ticker?.invalidate()
        duration = TimeInterval(min(180, max(1, minutes)) * 60)
        remainingSeconds = duration
        deadline = now().addingTimeInterval(duration)
        completed = false
        isRunning = true
        scheduleTicks()
    }

    func tick() {
        guard isRunning, let deadline else { return }
        remainingSeconds = max(0, deadline.timeIntervalSince(now()))
        if remainingSeconds == 0 {
            isRunning = false
            self.deadline = nil
            ticker?.invalidate(); ticker = nil
            completed = true
            didComplete()
        }
    }

    func toggleRunning() {
        if isRunning {
            tick()
            guard isRunning else { return }
            deadline = nil
            isRunning = false
            ticker?.invalidate(); ticker = nil
        } else if remainingSeconds > 0 {
            deadline = now().addingTimeInterval(remainingSeconds)
            isRunning = true
            scheduleTicks()
        }
    }

    func reset() {
        invalidate()
        remainingSeconds = 0; duration = 0; completed = false
    }

    func invalidate() {
        ticker?.invalidate(); ticker = nil
        deadline = nil; isRunning = false
    }

    private func scheduleTicks() {
        let ticker = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.ticker = ticker
        RunLoop.main.add(ticker, forMode: .common)
    }
}
