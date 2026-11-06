import AppKit
import FanBarShared
import SwiftUI

/// Recording options and file management for the local CSV temperature log.
struct TemperatureLogSettingsView: View {
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    @ObservedObject var controller: FanController

    @AppStorage(TemperatureLogPreferences.enabledKey)
    private var enabled = false
    @AppStorage(TemperatureLogPreferences.intervalKey)
    private var intervalSeconds = TemperatureLogPreferences.defaultIntervalSeconds
    @AppStorage(TemperatureLogPreferences.directoryKey)
    private var directoryPath = ""
    @AppStorage(TemperatureLogPreferences.newLogPolicyKey)
    private var newLogPolicyRawValue = TemperatureLogPreferences.defaultPolicy.rawValue
    @AppStorage(TemperatureLogPreferences.logTemperaturesKey)
    private var logTemperatures = true
    @AppStorage(TemperatureLogPreferences.logFanSpeedsKey)
    private var logFanSpeeds = true

    private var settings: TemperatureLogSettings { TemperatureLogSettings.current() }

    private var newLogPolicy: Binding<TemperatureLogPreferences.NewLogPolicy> {
        Binding(
            get: { TemperatureLogPreferences.NewLogPolicy(rawValue: newLogPolicyRawValue) ?? TemperatureLogPreferences.defaultPolicy },
            set: { newLogPolicyRawValue = $0.rawValue }
        )
    }

    var body: some View {
        Group {
            recordingSection
            fileSection
        }
        .environment(\.locale, (FanBarLanguage(rawValue: languageRawValue) ?? .system).locale)
    }

    private var recordingSection: some View {
        SettingsSection(
            title: fanBarText("温度日志", "Temperature Log"),
            footer: fanBarText(
                "CPU 日志和高温提醒使用平均温度；菜单栏和温度曲线显示最高温度。数据只保存在本机。",
                "CPU logs and alerts use average temperature; the menu bar and chart show the highest. Data stays on this Mac."
            )
        ) {
            Toggle(isOn: $enabled) {
                SettingsRowText(title: fanBarText("启用日志", "Enable logging"), detail: statusText)
            }
            .toggleStyle(.switch)
            .settingsRow()

            SettingsChrome.rowDivider

            HStack(spacing: SettingsChrome.rowHorizontalPadding) {
                SettingsRowText(
                    title: fanBarText("采样间隔", "Sampling interval"),
                    detail: fanBarText("间隔越短，文件越大。", "Shorter intervals make larger files.")
                )
                Spacer(minLength: 8)
                Picker(fanBarText("采样间隔", "Sampling interval"), selection: $intervalSeconds) {
                    ForEach(TemperatureLogPreferences.intervalOptions, id: \.self) { seconds in
                        Text(fanBarFormat("%d 秒", "%d s", seconds)).tag(seconds)
                    }
                }
                .labelsHidden()
                .id(languageRawValue)
                .frame(width: SettingsChrome.trailingControlMinWidth)
            }
            .settingsRow()

            SettingsChrome.rowDivider

            VStack(alignment: .leading, spacing: SettingsChrome.headerToCardSpacing) {
                Text(fanBarText("记录内容", "Logged Data"))
                HStack(alignment: .top, spacing: SettingsChrome.rowHorizontalPadding) {
                    Toggle(isOn: $logTemperatures) {
                        Text(fanBarText("温度", "Temperatures"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Toggle(isOn: $logFanSpeeds) {
                        Text(fanBarText("风扇转速和模式", "Fan speeds and mode"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.checkbox)
            }
            .settingsRow()
        }
    }

    private var fileSection: some View {
        SettingsSection(
            title: fanBarText("日志文件", "Log Files"),
            footer: fanBarText(
                "更改记录内容时，若表头不匹配，会另建文件，避免混用数据列。",
                "Changing the logged data creates a separate file when the header differs, keeping each file's columns consistent."
            )
        ) {
            VStack(alignment: .leading, spacing: SettingsChrome.rowVerticalPadding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(fanBarText("文件位置", "Location"))
                    Text(locationText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(locationText)
                }

                HStack(spacing: SettingsChrome.headerToCardSpacing) {
                    Spacer(minLength: 0)
                    Button(fanBarText("在访达中显示", "Reveal in Finder"), action: revealInFinder)
                    Button(fanBarText("选择文件夹…", "Choose Folder…"), action: chooseFolder)
                }
            }
            .settingsRow()

            SettingsChrome.rowDivider

            VStack(alignment: .leading, spacing: SettingsChrome.headerToCardSpacing) {
                Text(fanBarText("新建日志", "Create New Log"))
                Picker(fanBarText("新建日志", "Create New Log"), selection: newLogPolicy) {
                    Text(fanBarText("从不（持续追加到同一文件）", "Never (keep appending to one file)"))
                        .tag(TemperatureLogPreferences.NewLogPolicy.never)
                    Text(fanBarText("每次启动应用", "On app startup"))
                        .tag(TemperatureLogPreferences.NewLogPolicy.onStartup)
                    Text(fanBarText("每天午夜（每天一个文件）", "Every day at midnight (one file per day)"))
                        .tag(TemperatureLogPreferences.NewLogPolicy.daily)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .id(languageRawValue)
            }
            .settingsRow()
        }
    }

    private var statusText: String {
        guard enabled else { return fanBarText("已关闭", "Off") }
        switch controller.temperatureLog.status {
        case .idle:
            return fanBarText("等待第一条记录", "Waiting for the first sample")
        case .recording(let fileName):
            return fanBarFormat("正在写入：%@", "Writing to %@", fileName)
        case .failed:
            return fanBarText("写入失败，请检查文件夹权限。", "Writing failed. Check the folder’s permissions.")
        }
    }

    private var locationText: String {
        let directory = settings.directory
        let folder = (directory.path as NSString).abbreviatingWithTildeInPath
        if case .recording(let fileName) = controller.temperatureLog.status {
            return "\(folder)/\(fileName)"
        }
        return folder
    }

    private func revealInFinder() {
        if case .recording(let fileName) = controller.temperatureLog.status {
            let file = settings.directory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: file.path) {
                NSWorkspace.shared.activateFileViewerSelecting([file])
                return
            }
        }
        NSWorkspace.shared.open(settings.directory)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = fanBarText("选择", "Choose")
        // Non-modal: runModal() would stop the 2-second refresh timer, and with it curve control,
        // for as long as the panel stays open.
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            directoryPath = url.path
        }
    }
}
