// Localized alert copy is kept intact for catalog extraction.
// swiftlint:disable line_length
import AppKit
import FanBarShared
import SwiftUI

/// Resizable content for the independent compatibility window.
struct DeviceCompatibilityView: View {
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    @ObservedObject var controller: FanController
    var onClose: () -> Void = {}
    @State private var presentation: CompatibilityPresentation?
    @State private var confirmsControlTest = false
    @State private var reportFailed = false
    private let catalog = CompatibilityCatalog.load()

    var body: some View {
        VStack(spacing: 0) {
            if let snapshot = controller.compatibilitySnapshot {
                deviceHeader(snapshot)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        testNotice
                        helperAction
                        capabilityGroup(snapshot, controls: false)
                        capabilityGroup(snapshot, controls: true)
                        DisclosureGroup(fanBarText("已验证机型记录", "Verified Model Records")) {
                            records(snapshot).padding(.top, 12)
                        }
                        .font(.system(size: 12)).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: 880)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
                reportFooter(snapshot)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "desktopcomputer").font(.system(size: 36)).foregroundColor(.secondary)
                    Text(fanBarText("尚未检测。", "Not yet checked.")).font(.headline)
                    Button(fanBarText("开始检测", "Check now"), action: beginCompatibilityCheck).disabled(controller.isBusy)
                    Button(fanBarText("上传诊断日志…", "Upload diagnostic logs…")) { presentation = .diagnostics }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: SettingsChrome.contentWidth, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .onExitCommand(perform: onClose)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { controller.detectCompatibility() }
        .onDisappear { controller.cancelCompatibilityControlTest() }
        .alert(isPresented: $confirmsControlTest) {
            Alert(
                title: Text(fanBarText("测试风扇控制能力？", "Test fan control?")),
                message: Text(fanBarText("将短暂改变风扇转速，分别测试手动调速和当前温控曲线，然后恢复系统自动控制。可能听到风扇声音变化。",
                    "Fan speed will change briefly to test manual control and the current cooling curve, then return to system automatic control. Fan noise may change.")),
                primaryButton: .default(Text(fanBarText("开始测试",
                    "Start test"))) { controller.detectCompatibility(); controller.testCompatibilityControl() },
                secondaryButton: .cancel()
            )
        }
        .sheet(item: $presentation) { item in
            switch item {
            case .report(let data):
                CompatibilityReportPreview(data: data, preparesSubmission: true) { [controller] in
                    await controller.collectDiagnosticReport()
                }
            case .receipts: CompatibilityReceiptsView()
            case .diagnostics: DiagnosticUploadView(controller: controller)
            }
        }
        .environment(\.locale, (FanBarLanguage(rawValue: languageRawValue) ?? .system).locale)
    }

    private func deviceSymbol(_ name: String) -> String {
        if name.hasPrefix("Mac mini") { return "macmini" }
        if name.hasPrefix("MacBook") { return "laptopcomputer" }
        return "desktopcomputer"
    }

    private func deviceHeader(_ snapshot: CompatibilitySnapshot) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: deviceSymbol(snapshot.device.displayName))
                .font(.system(size: 30, weight: .light))
                .foregroundColor(.secondary)
                .frame(width: 60, height: 60)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.device.displayName).font(.system(size: 23, weight: .semibold))
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(snapshot.device.modelIdentifier) · macOS \(snapshot.device.macOSVersion)")
                    Text("FanBar \(snapshot.device.appVersion) · Helper \(snapshot.device.helperVersion)")
                }
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Text(snapshot.summary).font(.system(size: 12)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(action: beginCompatibilityCheck) {
                Label(fanBarText("重新检测", "Check again"), systemImage: "arrow.clockwise")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(controller.isBusy || controller.mode != .automatic || controller.compatibilityControlNeedsRestore)
        }
        .padding(24)
    }

    @ViewBuilder
    private var testNotice: some View {
        if controller.isTestingCompatibilityControl || controller.compatibilityControlMessage != nil || controller.mode != .automatic {
            let warning = controller.compatibilityControlNeedsRestore || controller.mode != .automatic
                || controller.manualControlEvidence == .requestFailed || controller.curveControlEvidence == .requestFailed
            HStack(alignment: .center, spacing: 12) {
                if controller.isTestingCompatibilityControl {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: warning ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundColor(warning ? .orange : .secondary)
                }
                Text(controller.compatibilityControlMessage ?? fanBarText("请先切换到系统自动控制，再开始测试。",
                    "Switch to system automatic control before testing."))
                    .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if controller.mode != .automatic || controller.compatibilityControlNeedsRestore {
                    Button(fanBarText("恢复系统控制", "Restore system control"), action: controller.setAutomatic)
                        .disabled(controller.isBusy)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(controller.compatibilityControlNeedsRestore ? Color.orange.opacity(0.08) : Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain)
        }
    }

    private func capabilityGroup(_ snapshot: CompatibilitySnapshot, controls: Bool) -> some View {
        let rows = snapshot.results.filter { [.manualControl, .smartCooling].contains($0.capability) == controls }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(controls ? fanBarText("风扇控制", "Fan Control") : fanBarText("温度与传感器", "Temperatures and Sensors"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if !controls {
                    Text(snapshot.checkedAt, style: .time).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                }
            }
            SettingsChrome.settingsCard {
                ForEach(rows) { result in
                    if result.id != rows.first?.id { Divider().padding(.leading, 52) }
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: capabilitySymbol(result.capability))
                            .font(.system(size: 16)).foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(result.capability.title).font(.system(size: 13, weight: .medium))
                                Spacer(minLength: 8)
                                Label(result.status.title, systemImage: result.status.symbol)
                                    .font(.system(size: 11, weight: .medium)).foregroundColor(result.status.tint)
                                    .multilineTextAlignment(.trailing)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if controls || result.status != .available {
                                Text(result.detail).font(.system(size: 11)).foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    .accessibilityElement(children: .combine)
                }
            }
            if controls {
                HStack(alignment: .top, spacing: 16) {
                    Label(snapshot.curveSensor.title, systemImage: "thermometer").font(.system(size: 11))
                    Spacer(minLength: 4)
                    if let recordedAt = controller.controlEvidenceRecordedAt {
                        HStack(spacing: 4) {
                            Text(fanBarText("控制结果记录于", "Control results recorded"))
                            Text(recordedAt, style: .date)
                        }.font(.system(size: 11))
                    }
                }.foregroundColor(.secondary)
                Text(fanBarText("控制测试后恢复系统自动控制。结果保存在本机，版本变化后需重新测试。",
                    "Control tests restore system automatic control. Results are saved locally; retest after version changes."))
                    .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func capabilitySymbol(_ capability: CompatibilityCapability) -> String {
        switch capability {
        case .cpuTemperature: "cpu"
        case .gpuTemperature: "rectangle.3.offgrid"
        case .ssdTemperature: "internaldrive"
        case .batteryTemperature: "battery.100"
        case .fanReadings: "wind"
        case .manualControl: "slider.horizontal.3"
        case .smartCooling: "thermometer"
        }
    }

    private func reportFooter(_ snapshot: CompatibilitySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Menu {
                        Button(fanBarText("上报记录与撤回…", "Submitted reports and withdrawal…")) { presentation = .receipts }
                        if let configuration = CompatibilityServiceConfiguration.current {
                            Link(fanBarText("公开记录", "Public records"), destination: configuration.baseURL)
                                .help(fanBarText("查看公开兼容性记录", "View public compatibility records"))
                        }
                    } label: {
                        Label(fanBarText("更多", "More"), systemImage: "ellipsis.circle")
                    }
                    .fixedSize()
                    Spacer(minLength: 12)
                    Button(fanBarText("上传诊断日志…", "Upload diagnostic logs…")) { presentation = .diagnostics }
                        .disabled(controller.isBusy).fixedSize()
                    Button(fanBarText("上传报告…", "Upload report…")) { previewReport(snapshot) }
                        .fanBarPrimaryButton()
                        .disabled(controller.isBusy).fixedSize()
                }
                .controlSize(.regular)
                Text(fanBarText("检测在本机完成，不会自动上传设备信息。", "Checks run locally. Device information is not automatically uploaded."))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if reportFailed {
                    Text(fanBarText("无法生成报告，请重试。", "Unable to create the report. Please retry."))
                        .font(.caption).foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
    }

    private func beginCompatibilityCheck() {
        controller.detectCompatibility()
        if controller.helperState == .enabled, controller.mode == .automatic,
           !controller.compatibilityControlNeedsRestore {
            confirmsControlTest = true
        }
    }

    @ViewBuilder
    private var helperAction: some View {
        if controller.helperState != .enabled {
            SettingsChrome.settingsCard {
                HStack(spacing: 12) {
                    Image(systemName: controller.helperState.symbolName).foregroundColor(controller.helperState.tint)
                    SettingsRowText(title: controller.helperState.noticeTitle, detail: controller.helperState.noticeDetail)
                    Spacer()
                    if let title = controller.helperState.actionTitle {
                        Button(title, action: controller.performHelperAction)
                    }
                }
                .settingsRow()
            }
        }
    }

    private func records(_ snapshot: CompatibilitySnapshot) -> some View {
        let matching = catalog.matching(snapshot.device)
        return VStack(alignment: .leading, spacing: 10) {
            SettingsChrome.settingsCard {
            if matching.isEmpty {
                SettingsRowText(
                    title: fanBarText("此版本组合暂无已验证记录", "No verified record for this version combination"),
                    detail: fanBarText("没有记录不代表不支持，请参考本机检测结果。", "No record does not mean unsupported. Refer to this Mac’s results.")
                ).settingsRow()
            } else {
                ForEach(Array(matching.enumerated()), id: \.offset) { _, record in
                    SettingsRowText(title: record.notes, detail: "\(record.source) · \(record.verifiedOn)").settingsRow()
                }
            }
            }
            Text(fanBarText("列表随应用提供，在本机匹配，不发送机型查询。", "The catalog ships with the app and is matched locally."))
                .font(.system(size: 11)).foregroundColor(.secondary)
        }
    }

    private func previewReport(_ snapshot: CompatibilitySnapshot) {
        guard !controller.isBusy else { return }
        do {
            presentation = .report(try CompatibilityReport(snapshot: snapshot).jsonData())
            reportFailed = false
        } catch {
            reportFailed = true
        }
    }
}

private enum CompatibilityPresentation: Identifiable {
    case report(Data)
    case receipts
    case diagnostics
    var id: String {
        switch self {
        case .report: "report"
        case .receipts: "receipts"
        case .diagnostics: "diagnostics"
        }
    }
}

// swiftlint:enable line_length
