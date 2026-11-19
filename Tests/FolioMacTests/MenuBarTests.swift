import XCTest
@testable import FolioMac

final class MenuBarTests: XCTestCase {
    func testReferenceDurationScaleAndBounds() {
        for (distance, minutes) in [(0.0, 0), (11, 0), (12, 1), (57, 5), (172, 25), (332, 60), (532, 180), (1000, 180)] {
            XCTAssertEqual(PullTimerDurationCalculator.calculateDuration(dragDistanceY: distance), minutes)
        }
    }

    func testPullReturnAndPrecisionMatchReference() {
        var gesture = PullTimerGesture(origin: CGPoint(x: -500, y: 900))
        gesture.update(to: CGPoint(x: -500, y: 728), fineMode: false)
        XCTAssertEqual(gesture.end(), .start(minutes: 25))
        gesture.update(to: CGPoint(x: -500, y: 728), fineMode: true)
        XCTAssertEqual(gesture.minutes, 25, "Shift must not jump the value")
        gesture.update(to: CGPoint(x: -500, y: 710), fineMode: true)
        XCTAssertEqual(gesture.end(), .start(minutes: 28))
        gesture.update(to: CGPoint(x: -500, y: 895), fineMode: false)
        XCTAssertEqual(gesture.end(), .cancel)
    }

    func testClickAndNonDownwardMotion() {
        var gesture = PullTimerGesture(origin: CGPoint(x: 100, y: 900))
        gesture.update(to: CGPoint(x: 102, y: 899), fineMode: false)
        XCTAssertEqual(gesture.end(), .click)
        gesture.update(to: CGPoint(x: 150, y: 910), fineMode: false)
        XCTAssertEqual(gesture.end(), .cancel)
    }

    @MainActor func testDeadlinePauseResumeAndCompletionAfterSleep() {
        var now = Date(timeIntervalSince1970: 1000)
        var completions = 0
        let timer = FocusTimerModel(now: { now }, didComplete: { completions += 1 })
        defer { timer.invalidate() }
        timer.start(minutes: 25)
        now += 10
        timer.toggleRunning()
        XCTAssertEqual(timer.remainingSeconds, 1490, accuracy: 0.001)
        now += 300
        timer.tick()
        XCTAssertEqual(timer.remainingSeconds, 1490, accuracy: 0.001)
        timer.toggleRunning()
        now += 1489
        timer.tick()
        XCTAssertEqual(timer.remainingSeconds, 1, accuracy: 0.001)
        now += 500 // Missed ticks/sleep still complete at the deadline.
        timer.tick(); timer.tick()
        XCTAssertTrue(timer.completed)
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(completions, 1)
        timer.start(minutes: 5)
        XCTAssertFalse(timer.completed)
        timer.reset()
        now += 1000; timer.tick()
        XCTAssertFalse(timer.isTimerActive)
        XCTAssertEqual(completions, 1)
    }

    @MainActor func testSystemHostedPressStartsTimerAndSuppressesTrailingClick() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = MenuBarController(workspace: Workspace(libraryRoot: root), openWindow: {})
        defer { controller.invalidate() }
        var pointer = MenuBarController.PointerState(location: CGPoint(x: 400, y: 900), isLeftButtonDown: true, isShiftDown: false)
        controller.pointerProvider = { pointer }
        controller.handleExternalPress(source: .globalMonitor)
        pointer.location.y -= 172
        controller.pollPointer()
        pointer.isLeftButtonDown = false
        controller.pollPointer()
        XCTAssertEqual(controller.focusTimer.remainingSeconds, 1500, accuracy: 1)
        XCTAssertTrue(controller.focusTimer.isRunning)
        XCTAssertFalse(controller.isPanelVisible)
        controller.handleExternalPress(source: .buttonAction)
        XCTAssertFalse(controller.isPanelVisible, "Late button action must not open a panel after starting the timer")
    }

    @MainActor func testCancelledPullPreservesExistingTimer() {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = MenuBarController(workspace: Workspace(libraryRoot: root), openWindow: {})
        defer { controller.invalidate() }
        controller.focusTimer.start(minutes: 15)
        var pointer = MenuBarController.PointerState(location: CGPoint(x: 400, y: 900), isLeftButtonDown: true, isShiftDown: false)
        controller.pointerProvider = { pointer }
        controller.handleExternalPress(source: .buttonAction)
        pointer.location.y -= 172; controller.pollPointer()
        pointer.location.y = 899; controller.pollPointer()
        pointer.isLeftButtonDown = false; controller.pollPointer()
        XCTAssertEqual(controller.focusTimer.remainingSeconds, 900, accuracy: 1)
        XCTAssertTrue(controller.focusTimer.isRunning)
        XCTAssertFalse(controller.isPanelVisible)
    }
    @MainActor func testCaptureViewDeliversRealDragStream() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = MenuBarController(workspace: Workspace(libraryRoot: root), openWindow: {})
        defer { controller.invalidate() }
        let button = try XCTUnwrap(controller.statusButton)
        let window = try XCTUnwrap(button.window)
        let capture = try XCTUnwrap(button.subviews.last)
        let origin = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        func event(_ type: NSEvent.EventType, distance: CGFloat) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: origin.x, y: origin.y - distance),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        capture.mouseDown(with: try event(.leftMouseDown, distance: 0))
        capture.mouseDragged(with: try event(.leftMouseDragged, distance: 172))
        capture.mouseUp(with: try event(.leftMouseUp, distance: 172))
        XCTAssertTrue(controller.focusTimer.isRunning)
        XCTAssertEqual(controller.focusTimer.remainingSeconds, 1500, accuracy: 1)
    }

}
