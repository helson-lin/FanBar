import AppKit
import FanBarShared
import SwiftUI
import XCTest
@testable import FanBar

/// Presses on the curve editor must select the handle under the pointer,
/// including a handle that is not the last one drawn (#174). On macOS 15 a
/// gesture attached after `position` hit-tests the whole plot, so this test
/// fails there unless the handle owns its own hit circle.
@MainActor
final class FanCurvePointSelectionTests: XCTestCase {
    func testEarlierCurvePointStaysSelectableAfterALaterPointIsSelected() throws {
        let points = [
            FanCurvePoint(celsius: 40, fraction: 0.30),
            FanCurvePoint(celsius: 62, fraction: 0.55),
            FanCurvePoint(celsius: 84, fraction: 0.80)
        ]
        let selection = CurveSelection()
        let canvasSize = CGSize(width: 420, height: 204)
        let host = NSHostingView(rootView: FanCurveCanvas(
            profile: FanCurveProfile(sensor: .maxChip, points: points),
            selectedPointID: Binding(get: { selection.id }, set: { selection.id = $0 }),
            onPointChange: { _, _, _ in }
        ))
        host.frame = NSRect(origin: .zero, size: canvasSize)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: canvasSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))

        try press(points[2], in: window, canvasSize: canvasSize)
        XCTAssertEqual(selection.id, points[2].id)

        try press(points[0], in: window, canvasSize: canvasSize)
        XCTAssertEqual(selection.id, points[0].id)

        try press(points[1], in: window, canvasSize: canvasSize)
        XCTAssertEqual(selection.id, points[1].id)
    }

    private func press(_ point: FanCurvePoint, in window: NSWindow, canvasSize: CGSize) throws {
        let center = handleCenter(of: point, canvasSize: canvasSize)
        // AppKit events use a bottom-left origin; the plot uses the top-left.
        let location = NSPoint(x: center.x, y: canvasSize.height - center.y)
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type,
                location: location,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            ))
        }
        window.sendEvent(try event(.leftMouseDown))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        window.sendEvent(try event(.leftMouseUp))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    /// Same insets and domain as `FanCurveCanvas`. A press has to land on the
    /// handle's center, well clear of the other 14 pt hit circles.
    private func handleCenter(of point: FanCurvePoint, canvasSize: CGSize) -> CGPoint {
        let plot = CGRect(
            x: 36,
            y: 6,
            width: canvasSize.width - 36 - 8,
            height: canvasSize.height - 6 - 22
        )
        let minimumCelsius = FanCurveProfile.minimumCelsius
        let maximumCelsius = FanCurveProfile.maximumCelsius
        let x = plot.minX + CGFloat(
            (point.celsius - minimumCelsius) / (maximumCelsius - minimumCelsius)
        ) * plot.width
        let y = plot.maxY - CGFloat(point.fraction) * plot.height
        return CGPoint(x: x, y: y)
    }
}

private final class CurveSelection {
    var id: UUID?
}
