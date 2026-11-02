import AppKit
import FanBarShared
import SwiftUI
import XCTest
@testable import FanBar

@MainActor
final class PanelCardLayoutTests: XCTestCase {
    func testDenseHardwareAndExpandedDetailsFitPanelWidthInBothAppearances() {
        var usage = SystemUsage()
        usage.cpuFraction = 0.42
        usage.cpuCoreFractions = Array(repeating: 0.42, count: 32)
        usage.cpuCoreKinds = Array(repeating: .performance, count: 24) + Array(repeating: .efficiency, count: 8)
        usage.cpuCoreCount = 32
        usage.gpuFraction = 0.28
        usage.gpuCoreCount = 80
        usage.disks = (0..<6).map { index in
            DiskVolumeUsage(id: "disk-\(index)", name: "Work archive volume \(index)",
                            isInternal: index == 0, usedBytes: 512_000_000_000, totalBytes: 1_024_000_000_000)
        }
        for scheme in [ColorScheme.light, .dark] {
            for expanded in [nil, PanelResourceList.Resource.cpu, .memory, .gpu, .disk] {
                let view = PanelResourceList(
                    usage: usage, thermal: nil, cpuHistory: [0.1, 0.42], gpuHistory: [0.1, 0.28],
                    animates: false, expanded: .constant(expanded)
                )
                .frame(width: 336)
                .environment(\.colorScheme, scheme)
                let host = NSHostingView(rootView: view)
                let size = host.fittingSize
                XCTAssertEqual(size.width, 336, accuracy: 0.5)
                XCTAssertTrue(size.height.isFinite)
                XCTAssertGreaterThan(size.height, 60)
                XCTAssertLessThan(size.height, 1000)
            }
        }
    }

    func testOnlyDiskAndCPUCanExpand() {
        var usage = SystemUsage()
        usage.gpuCoreCount = 80
        usage.gpuMemoryInUseBytes = 64 * 1_073_741_824
        for scheme in [ColorScheme.light, .dark] {
            func height(expanded: PanelResourceList.Resource?) -> CGFloat {
                let host = NSHostingView(rootView: PanelResourceList(
                    usage: usage, thermal: nil, cpuHistory: [], gpuHistory: [0.2, 0.3],
                    animates: false, expanded: .constant(expanded)
                ).frame(width: 336).environment(\.colorScheme, scheme))
                return host.fittingSize.height
            }
            let collapsed = height(expanded: nil)
            for resource in [PanelResourceList.Resource.memory, .gpu] {
                XCTAssertEqual(height(expanded: resource), collapsed, accuracy: 0.5)
            }
            XCTAssertGreaterThan(height(expanded: .disk), collapsed)
            // Before the first reading the CPU detail shows placeholder rows.
            XCTAssertGreaterThan(height(expanded: .cpu), collapsed)
        }
    }

    func testConfiguredModulesSetRowCountAndHiddenDiskNeverExpands() {
        var usage = SystemUsage()
        usage.cpuFraction = 0.3
        usage.disks = [DiskVolumeUsage(id: "/", name: "Macintosh HD", isInternal: true,
                                       usedBytes: 400_000_000_000, totalBytes: 1_000_000_000_000)]
        func height(_ modules: [PanelMonitorModule], expanded: PanelResourceList.Resource? = nil) -> CGFloat {
            let host = NSHostingView(rootView: PanelResourceList(
                usage: usage, thermal: nil, cpuHistory: [], gpuHistory: [],
                animates: false, modules: modules, expanded: .constant(expanded)
            ).frame(width: 336))
            XCTAssertEqual(host.fittingSize.width, 336, accuracy: 0.5)
            return host.fittingSize.height
        }
        let oneRow = height([.memory, .gpu])
        XCTAssertEqual(height([.memory]), oneRow, accuracy: 12)
        XCTAssertGreaterThan(height([.memory, .gpu, .disk]), oneRow + 40)
        XCTAssertEqual(height([.cpu, .memory], expanded: .disk), height([.cpu, .memory]), accuracy: 0.5)
        XCTAssertGreaterThan(height([.disk], expanded: .disk), height([.disk]))
    }

    /// Modules can be paired in any order, so each one must share the same vertical rhythm.
    func testEveryModuleCellHasTheSameHeightSoAnyPairLinesUp() {
        var usage = SystemUsage()
        usage.cpuFraction = 0.35
        usage.cpuCoreFractions = Array(repeating: 0.3, count: 12)
        usage.cpuCoreKinds = Array(repeating: .performance, count: 8) + Array(repeating: .efficiency, count: 4)
        usage.memory = MemoryBreakdown(appBytes: 16_000_000_000, cachedBytes: 6_000_000_000,
                                       compressedBytes: 4_000_000_000, totalBytes: 34_359_738_368,
                                       swapUsedBytes: nil)
        usage.gpuFraction = 0.71
        usage.gpuCoreCount = 38
        usage.gpuMemoryInUseBytes = 1_900_000_000
        usage.disks = [DiskVolumeUsage(id: "/", name: "Macintosh HD", isInternal: true,
                                       usedBytes: 870_000_000_000, totalBytes: 926_000_000_000)]
        let heights = PanelMonitorModule.allCases.map { module in
            NSHostingView(rootView: PanelResourceList(
                usage: usage, thermal: nil, cpuHistory: [], gpuHistory: [],
                animates: false, modules: [module], expanded: .constant(nil)
            ).frame(width: 336)).fittingSize.height
        }
        for height in heights {
            XCTAssertEqual(height, heights[0], accuracy: 1, "cell heights: \(heights)")
        }
    }

    func testPanelFitsScreenWithoutChangingFanControl() throws {
        let controller = FanController(
            notificationCenter: nil, widgetSnapshotDestination: .disabled,
            makeReadingSource: { FakeFanReadingSource() }
        )
        for scheme in [ColorScheme.light, .dark] {
            let host = NSHostingView(rootView: FanMenu(controller: controller).environment(\.colorScheme, scheme))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: FanMenu.panelWidth, height: 580),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            host.frame = NSRect(x: 0, y: 0, width: FanMenu.panelWidth, height: 580)
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            let size = host.fittingSize
            XCTAssertEqual(size.width, FanMenu.panelWidth, accuracy: 0.5)
            XCTAssertLessThanOrEqual(size.height, max(240, (NSScreen.main?.visibleFrame.height ?? 800) - 70))
            XCTAssertEqual(controller.mode, .automatic)
            if let destination = ProcessInfo.processInfo.environment["FANBAR_CARD_CAPTURE_PATH"] {
                host.frame = NSRect(origin: .zero, size: size)
                host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let image = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                let name = scheme == .dark ? "panel-dark.png" : "panel-light.png"
                try image.write(to: URL(fileURLWithPath: destination).appendingPathComponent(name))
            }
        }
    }
}
