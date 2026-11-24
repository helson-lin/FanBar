import AppKit
import FanBarShared
import SwiftUI
import XCTest
@testable import FanBar

@MainActor
final class PanelResourceDetailSwitchTests: XCTestCase {
    private static let panelWidth: CGFloat = 336
    private static let windowHeight: CGFloat = 480

    func testRevealStyleIsImmediatelyVisibleWhenAnimationsAreOff() {
        XCTAssertFalse(PanelDetailRevealStyle.initialRevealed(animates: true))
        XCTAssertTrue(PanelDetailRevealStyle.initialRevealed(animates: false))

        XCTAssertEqual(
            PanelDetailRevealStyle.values(revealed: false, animates: true),
            PanelDetailRevealStyle(opacity: 0, scale: PanelDetailRevealStyle.hiddenScale)
        )
        XCTAssertEqual(
            PanelDetailRevealStyle.values(revealed: true, animates: true),
            PanelDetailRevealStyle(opacity: 1, scale: 1)
        )
        XCTAssertEqual(
            PanelDetailRevealStyle.values(revealed: false, animates: false),
            PanelDetailRevealStyle(opacity: 1, scale: 1)
        )
        XCTAssertEqual(
            PanelDetailRevealStyle.values(revealed: true, animates: false),
            PanelDetailRevealStyle(opacity: 1, scale: 1)
        )
    }

    func testSwitchingDirectlyBetweenDiskAndCPUDetailsNeverLeavesDetailBlank() throws {
        let defaults = UserDefaults.standard
        let savedLanguage = defaults.object(forKey: FanBarLanguage.preferenceKey)
        defaults.set(FanBarLanguage.english.rawValue, forKey: FanBarLanguage.preferenceKey)
        defer { defaults.set(savedLanguage, forKey: FanBarLanguage.preferenceKey) }

        let usage = makeSampleUsage()
        let topApps = makeSampleTopApps()
        let collapsedHeight = measureCollapsedHeight(usage: usage, topApps: topApps)

        for animates in [true, false] {
            try assertDirectSwitchRendersVisibleDetail(
                animates: animates,
                usage: usage,
                topApps: topApps,
                collapsedHeight: collapsedHeight
            )
        }
    }

    private func assertDirectSwitchRendersVisibleDetail(
        animates: Bool,
        usage: SystemUsage,
        topApps: TopAppsSnapshot,
        collapsedHeight: CGFloat
    ) throws {
        let state = ExpansionBox()
        let rootView = ResourceListHarness(usage: usage, topApps: topApps, animates: animates, state: state)
            .frame(width: Self.panelWidth, height: Self.windowHeight, alignment: .top)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: rootView)
        host.frame = NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.windowHeight)
        let window = makeWindow(for: host)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        let cpuPoint = NSPoint(x: Self.panelWidth * 0.25, y: Self.windowHeight - collapsedHeight * 0.25)
        let diskPoint = NSPoint(x: Self.panelWidth * 0.75, y: Self.windowHeight - collapsedHeight * 0.75)

        try click(at: diskPoint, in: window, settleFor: 0.05)
        XCTAssertEqual(state.expanded, .disk, "animates=\(animates)")
        let diskOpenPixels = try waitForVisibleDetailPixels(in: host, below: collapsedHeight)
        XCTAssertGreaterThan(diskOpenPixels, 100, "disk open animates=\(animates)")

        try click(at: cpuPoint, in: window, settleFor: 0.05)
        XCTAssertEqual(state.expanded, .cpu, "animates=\(animates)")
        let cpuPixels = try waitForVisibleDetailPixels(in: host, below: collapsedHeight)
        XCTAssertGreaterThan(cpuPixels, 100, "disk -> cpu animates=\(animates)")

        try click(at: diskPoint, in: window, settleFor: 0.05)
        XCTAssertEqual(state.expanded, .disk, "animates=\(animates)")
        let diskPixels = try waitForVisibleDetailPixels(in: host, below: collapsedHeight)
        XCTAssertGreaterThan(diskPixels, 100, "cpu -> disk animates=\(animates)")

        try click(at: cpuPoint, in: window, settleFor: 0.02)
        try click(at: diskPoint, in: window, settleFor: 0.02)
        try click(at: cpuPoint, in: window, settleFor: 0.05)
        XCTAssertEqual(state.expanded, .cpu, "animates=\(animates)")
        let rapidPixels = try waitForVisibleDetailPixels(in: host, below: collapsedHeight)
        XCTAssertGreaterThan(rapidPixels, 100, "rapid switch animates=\(animates)")

        try click(at: cpuPoint, in: window, settleFor: 0.1)
        XCTAssertNil(state.expanded, "animates=\(animates)")
        XCTAssertEqual(try visibleDetailPixelCount(in: host, below: collapsedHeight), 0, "collapsed animates=\(animates)")
    }

    private func waitForVisibleDetailPixels(
        in host: NSView,
        below collapsedHeight: CGFloat,
        minimum: Int = 100,
        timeout: TimeInterval = 2.0
    ) throws -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        var count = try visibleDetailPixelCount(in: host, below: collapsedHeight)
        while count <= minimum, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            count = try visibleDetailPixelCount(in: host, below: collapsedHeight)
        }
        return count
    }

    private func makeWindow(for host: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.windowHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        return window
    }

    private func measureCollapsedHeight(usage: SystemUsage, topApps: TopAppsSnapshot) -> CGFloat {
        let view = PanelResourceList(
            usage: usage,
            thermal: nil,
            cpuHistory: [0.2, 0.3],
            gpuHistory: [0.1, 0.2],
            animates: false,
            modules: [.cpu, .memory, .gpu, .disk],
            topApps: topApps,
            expanded: .constant(nil)
        )
        .frame(width: Self.panelWidth)
        return NSHostingView(rootView: view).fittingSize.height
    }

    private func click(at location: NSPoint, in window: NSWindow, settleFor duration: TimeInterval) throws {
        func makeEvent(_ type: NSEvent.EventType) throws -> NSEvent {
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
        window.sendEvent(try makeEvent(.leftMouseDown))
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        window.sendEvent(try makeEvent(.leftMouseUp))
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func visibleDetailPixelCount(in host: NSView, below collapsedHeight: CGFloat) throws -> Int {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scaleY = CGFloat(bitmap.pixelsHigh) / max(host.bounds.height, 1)
        let startY = max(0, Int(((collapsedHeight + 12) * scaleY).rounded()))
        let endY = min(bitmap.pixelsHigh, Int(((collapsedHeight + 84) * scaleY).rounded()))
        var visibleCount = 0
        for y in startY..<endY {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if max(color.redComponent, max(color.greenComponent, color.blueComponent)) > 0.08 {
                    visibleCount += 1
                }
            }
        }
        return visibleCount
    }

    private func makeSampleUsage() -> SystemUsage {
        var usage = SystemUsage()
        usage.cpuFraction = 0.32
        usage.cpuCoreFractions = Array(repeating: 0.3, count: 8)
        usage.cpuCoreKinds = Array(repeating: .performance, count: 4) + Array(repeating: .efficiency, count: 4)
        usage.cpuCoreCount = 8
        usage.memory = MemoryBreakdown(
            appBytes: 8_000_000_000,
            cachedBytes: 2_000_000_000,
            compressedBytes: 1_000_000_000,
            totalBytes: 17_179_869_184,
            swapUsedBytes: nil
        )
        usage.gpuFraction = 0.18
        usage.gpuCoreCount = 10
        usage.disks = [
            DiskVolumeUsage(
                id: "/",
                name: "Macintosh HD",
                isInternal: true,
                usedBytes: 400_000_000_000,
                totalBytes: 1_000_000_000_000
            )
        ]
        return usage
    }

    private func makeSampleTopApps() -> TopAppsSnapshot {
        TopAppsSnapshot(
            apps: [
                TopApp(id: "/Applications/Safari.app", name: "Safari", bundlePath: nil, percent: 42.5),
                TopApp(id: "/usr/bin/swift", name: "swift", bundlePath: nil, percent: 18.0),
            ],
            processCount: 180
        )
    }
}

private final class ExpansionBox: ObservableObject {
    @Published var expanded: PanelResourceList.Resource?
}

private struct ResourceListHarness: View {
    let usage: SystemUsage
    let topApps: TopAppsSnapshot
    let animates: Bool
    @ObservedObject var state: ExpansionBox

    var body: some View {
        PanelResourceList(
            usage: usage,
            thermal: nil,
            cpuHistory: [0.2, 0.32],
            gpuHistory: [0.1, 0.18],
            animates: animates,
            modules: [.cpu, .memory, .gpu, .disk],
            topApps: topApps,
            expanded: $state.expanded
        )
        .frame(width: 336)
    }
}
