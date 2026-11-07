import AppKit
import Combine
import FanBarShared
import SwiftUI

/// The History tab: what the log is for and one switch first, then how
/// detailed to record (three purpose presets), then everything technical
/// folded under Advanced. See docs/design/settings-log.html (v4).
struct TemperatureLogSettingsView: View {
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    @ObservedObject var controller: FanController

    @AppStorage(TemperatureLogPreferences.enabledKey)
    private var enabled = false
    @AppStorage(TemperatureLogPreferences.intervalKey)
    private var intervalSeconds = TemperatureLogPreferences.defaultIntervalSeconds
    @AppStorage(TemperatureLogPreferences.retentionDaysKey)
    private var retentionDays = TemperatureLogPreferences.defaultRetentionDays
    @AppStorage(TemperatureLogPreferences.logTemperaturesKey)
    private var logTemperatures = true
    @AppStorage(TemperatureLogPreferences.logFanSpeedsKey)
    private var logFanSpeeds = true

    @State private var usage: TemperatureLogUsage?
    /// Folder size changes slowly; a periodic scan is enough and never runs per refresh tick.
    private let usageTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var settings: TemperatureLogSettings { TemperatureLogSettings.current() }

    var body: some View {
        Group {
            TemperatureLogOverviewCard(
                controller: controller,
                enabled: $enabled,
                usage: usage,
                directory: settings.directory
            )
            TemperatureLogPresetPicker(
                intervalSeconds: $intervalSeconds,
                retentionDays: $retentionDays,
                columnCount: TemperatureLogFormat.columns(for: settings).count
            )
            .opacity(enabled ? 1 : 0.55)
            .disabled(!enabled)
            TemperatureLogAdvancedCard(
                intervalSeconds: $intervalSeconds,
                retentionDays: $retentionDays,
                logTemperatures: $logTemperatures,
                logFanSpeeds: $logFanSpeeds
            )
            .opacity(enabled ? 1 : 0.55)
            .disabled(!enabled)
        }
        .onAppear(perform: refreshUsage)
        .onReceive(usageTimer) { _ in refreshUsage() }
        .onChange(of: retentionDays) { _ in controller.temperatureLog.requestCleanup() }
        .onChange(of: enabled) { _ in refreshUsage() }
        .environment(\.locale, (FanBarLanguage(rawValue: languageRawValue) ?? .system).locale)
    }

    private func refreshUsage() {
        usage = TemperatureLogUsage.summarize(TemperatureLogRetention.files(in: settings.directory), now: Date())
    }
}

/// Chooses the log folder without blocking the run loop: runModal() would
/// stop the 2-second refresh timer, and with it curve control.
enum TemperatureLogFolderPicker {
    @MainActor
    static func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = fanBarText("选择", "Choose")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            UserDefaults.standard.set(url.path, forKey: TemperatureLogPreferences.directoryKey)
        }
    }
}

/// The one switch, what it is for, and — once on — what has been recorded
/// and where to look, or why recording paused.
private struct TemperatureLogOverviewCard: View {
    @ObservedObject var controller: FanController
    @Binding var enabled: Bool
    let usage: TemperatureLogUsage?
    let directory: URL
    @Environment(\.colorScheme) private var colorScheme

    private var palette: PanelPalette { PanelPalette(colorScheme: colorScheme) }

    var body: some View {
        SettingsChrome.settingsCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor.opacity(0.12)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(fanBarText("记录温度历史", "Record temperature history"))
                        .fontWeight(.semibold)
                    Text(fanBarText(
                        "记下温度和风扇转速，之后可以回看什么时候变热",
                        "Keeps temperatures and fan speeds so you can see when your Mac got hot"
                    ))
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                    Text(enabled
                        ? fanBarText("只存在本机", "Stays on this Mac")
                        : fanBarText(
                            "只存在本机 · 开启后存成表格，可用 Numbers 或 Excel 打开",
                            "Stays on this Mac · Saved as a spreadsheet for Numbers or Excel"
                        ))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Toggle(fanBarText("记录温度历史", "Record temperature history"), isOn: $enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(SettingsChrome.rowHorizontalPadding)

            if enabled {
                SettingsChrome.rowDivider
                statusRow
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch controller.temperatureLog.status {
        case .failed:
            failureRow
        case .recording(let fileName):
            recordingRow(fileName: fileName)
        case .idle:
            HStack(spacing: 8) {
                Circle().fill(Color.secondary).frame(width: 7, height: 7).accessibilityHidden(true)
                Text(fanBarText("等待第一条记录", "Waiting for the first sample"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
            .settingsRow()
        }
    }

    private func recordingRow(fileName: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(palette.accent).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(fanBarText("正在记录", "Recording"))
                .font(.system(size: 12, weight: .medium))
            if let summary = TemperatureLogText.recordedSummary(usage) {
                Text(summary)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            Button(fanBarText("用表格打开", "Open Spreadsheet")) {
                NSWorkspace.shared.open(directory.appendingPathComponent(fileName))
            }
            .help(fanBarText("用 Numbers 或 Excel 打开正在记录的文件", "Opens the current file in Numbers or Excel"))
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([directory.appendingPathComponent(fileName)])
            } label: {
                Image(systemName: "folder")
            }
            .help(fanBarText("在访达中显示", "Reveal in Finder"))
            .accessibilityLabel(fanBarText("在访达中显示", "Reveal in Finder"))
        }
        .settingsRow()
        .accessibilityElement(children: .contain)
    }

    private var failureRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(palette.hot)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(fanBarText("已暂停", "Paused"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(palette.hot)
                Text(TemperatureLogText.failureDetail(retryAt: controller.temperatureLog.retryAt, now: Date()))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(fanBarText("写入失败，请检查文件夹权限。", "Writing failed. Check the folder’s permissions."))
            Button(fanBarText("重试", "Retry")) { controller.temperatureLog.retryNow() }
            Button(fanBarText("更换位置…", "Change Location…")) { TemperatureLogFolderPicker.choose() }
        }
        .settingsRow()
        .background(palette.hot.opacity(0.07))
        .accessibilityElement(children: .contain)
    }
}
