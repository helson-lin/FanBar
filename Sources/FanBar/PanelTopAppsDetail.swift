import AppKit
import FanBarShared
import SwiftUI

/// The CPU cell's detail: apps using the most CPU, opened beneath the grid like the disk list.
/// Rows only say who is busy, so they stay neutral; the CPU cell's color already says how busy.
struct PanelTopAppsDetail: View {
    let snapshot: TopAppsSnapshot?
    let palette: PanelPalette
    let onCollapse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(fanBarText("占用 CPU 最多的应用", "Apps using the most CPU"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(palette.secondaryText)
                Spacer()
                Button(action: onCollapse) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PanelDimButtonStyle())
                .foregroundColor(palette.secondaryText)
                .padding(.trailing, -5)
                .accessibilityLabel(fanBarText("收起应用列表", "Hide app list"))
            }
            if let snapshot, let top = snapshot.apps.first {
                VStack(spacing: 0) {
                    ForEach(snapshot.apps) { app in
                        PanelTopAppRow(app: app, share: app.percent / max(top.percent, 0.01), palette: palette)
                    }
                }
                Text(fanBarFormat(
                    "当前用户的 %d 个进程 · 百分比按单核计算",
                    "%d processes for this user · 100%% is one core",
                    snapshot.processCount
                ))
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(palette.secondaryText)
                .padding(.top, 4)
            } else {
                // The first reading needs two samples half a second apart.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 5).fill(palette.well).frame(width: 20, height: 20)
                            Capsule().fill(palette.well).frame(width: 96, height: 7)
                            Spacer()
                            Capsule().fill(palette.well).frame(width: 30, height: 7)
                        }
                        .frame(height: 32)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(fanBarText("正在统计…", "Measuring…"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PanelTopAppRow: View {
    let app: TopApp
    /// This app's CPU relative to the busiest one.
    let share: Double
    let palette: PanelPalette

    @State private var isHovered = false

    var body: some View {
        Button(action: ActivityMonitorLauncher.open) {
            HStack(spacing: 8) {
                Image(nsImage: AppIconCache.icon(for: app))
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(app.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.well)
                    Capsule().fill(palette.memoryCache)
                        .frame(width: 64 * CGFloat(min(1, max(0.04, share))))
                }
                .frame(width: 64, height: 4)
                Text(Self.format(app.percent))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(.primary)
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.horizontal, 6)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PanelDimButtonStyle())
        .padding(.horizontal, -6)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(fanBarText("在访达中显示", "Show in Finder")) {
                let path = app.bundlePath ?? app.id
                guard FileManager.default.fileExists(atPath: path) else { return }
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(app.name), \(Self.format(app.percent))")
        .accessibilityHint(fanBarText("打开活动监视器", "Opens Activity Monitor"))
        .accessibilityAddTraits(.isButton)
    }

    /// Whole percents from 10% up, one decimal below, like Activity Monitor.
    static func format(_ percent: Double) -> String {
        String(format: percent >= 10 ? "%.0f%%" : "%.1f%%", percent)
    }
}

enum ActivityMonitorLauncher {
    /// There's no public way to select a process in it, so this only opens the app.
    static func open() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else {
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Icons are looked up once per app; processes outside any app share the executable icon.
@MainActor
private enum AppIconCache {
    private static var icons: [String: NSImage] = [:]

    static func icon(for app: TopApp) -> NSImage {
        if let cached = icons[app.id] { return cached }
        let icon: NSImage = if let bundle = app.bundlePath {
            NSWorkspace.shared.icon(forFile: bundle)
        } else {
            NSWorkspace.shared.icon(for: .unixExecutable)
        }
        icons[app.id] = icon
        return icon
    }
}
