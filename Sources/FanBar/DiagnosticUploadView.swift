// Localization keys and user-facing paragraphs remain intact for catalog extraction.
// swiftlint:disable line_length
import AppKit
import FanBarShared
import SwiftUI

@MainActor
struct DiagnosticUploadView: View {
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var model: DiagnosticUploadCoordinator
    @State private var preparationTask: Task<Void, Never>?

    init(controller: FanController, model: DiagnosticUploadCoordinator? = nil) {
        _model = StateObject(wrappedValue: model ?? DiagnosticUploadCoordinator(
            collect: { [controller] in await controller.collectDiagnosticReport() }
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(fanBarText("上传诊断日志", "Upload diagnostic logs")).font(.title2.weight(.semibold))
                Text(fanBarText("帮助排查温度缺失和传感器读取问题。收集过程只读取信息，不会调整风扇。",
                    "Help investigate missing temperatures and sensor failures. Collection only reads information and does not adjust fans."))
                    .font(.subheadline).foregroundColor(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let report = model.report {
                        SettingsChrome.settingsCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(report.device.displayName).font(.headline)
                                Text("\(report.device.modelIdentifier) · macOS \(report.device.macOSVersion)")
                                Text("FanBar \(report.device.appVersion) · Helper \(report.device.helperVersion)")
                                if let running = model.staleHelperBuild {
                                    Text(fanBarFormat("正在运行的 Helper 是旧版本（build %@）。请在设置中重新授权 Helper 或重启 Mac，然后重新收集。",
                                        "The running Helper is an older build (%@). Reauthorize the Helper in Settings or restart your Mac, then collect again.",
                                        running))
                                        .foregroundColor(.orange)
                                }
                                Text(fanBarText("包含：设备版本、最近一分钟采样、传感器探测、数据格式与原始字节、备用来源结果和错误码。",
                                    "Includes device versions, recent samples (up to one minute), sensor probes, data formats and raw bytes, fallback results, and error codes."))
                                Text(fanBarText("不包含：序列号、用户名、文件路径、进程列表或系统日志。",
                                    "Excludes serial numbers, usernames, file paths, process lists, and system logs."))
                                    .foregroundColor(.secondary)
                            }.font(.caption).padding(16)
                        }
                        Text(fanBarText("还包含最近 24 小时内有界保留的启动、授权、XPC 与控制事件，以及脱敏崩溃摘要。确认上传前，文件仅保存在本机。",
                            "Also includes bounded launch, approval, XPC, and control events from the last 24 hours and sanitized crash summaries. Files stay local until you confirm upload."))
                            .font(.caption).foregroundColor(.secondary)
                        Text(fanBarText("FanBar 无法打开时，可运行附带的 FanBar-Diagnostics.command，无需启动应用即可导出诊断。",
                            "If FanBar cannot open, run the supplied FanBar-Diagnostics.command to export diagnostics without starting the app."))
                            .font(.caption).foregroundColor(.secondary)
                        DisclosureGroup(fanBarText("查看日志详情", "View log details")) {
                            Text((try? report.jsonData()).flatMap { String(data: $0, encoding: .utf8) } ?? "")
                                .font(.system(size: 10, design: .monospaced)).fanBarSelectableText()
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                        }.font(.caption)
                    } else {
                        ProgressView(fanBarText("正在收集诊断信息…", "Collecting diagnostics…"))
                    }
                    if let response = model.receipt?.response {
                        Text(fanBarText("上传成功，请将诊断编号提供给开发者。", "Uploaded. Share the diagnostic ID with the developer.")).font(.headline)
                        Text(response.reportID).font(.system(.caption, design: .monospaced)).fanBarSelectableText()
                        Button(fanBarText("复制诊断编号", "Copy diagnostic ID")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(response.reportID, forType: .string)
                        }
                    } else {
                        Text(fanBarText("日志仅管理员可见，不会公开或计入兼容性统计；在线保留 90 天，可在下方撤回。",
                            "Logs are visible only to administrators, excluded from public compatibility statistics, and retained online for 90 days. Withdraw them below."))
                            .font(.caption).foregroundColor(.secondary)
                        Text(fanBarText("云平台历史恢复点最长还可能保留 30 天；Cloudflare 会处理传输所需的网络元数据。",
                            "Cloud restore points may retain data for up to 30 more days. Cloudflare processes network metadata to deliver the service."))
                            .font(.caption).foregroundColor(.secondary)
                        if let configuration = CompatibilityServiceConfiguration.current {
                            Link(fanBarText("收集与处理规则", "Collection and processing rules"),
                                destination: configuration.url(path: "privacy.html"))
                                .font(.caption)
                        }
                        Toggle(fanBarText("我同意上传本次诊断日志供排查问题",
                            "I agree to upload these diagnostic logs for troubleshooting"),
                            isOn: $model.consent)
                            .font(.caption).disabled(model.busy)
                        if model.policy == nil {
                            Button(fanBarText("获取上传规则", "Fetch upload rules")) { Task { await model.loadPolicy() } }.disabled(model.busy)
                        }
                    }
                    if !model.history.isEmpty {
                        DisclosureGroup(fanBarText("诊断上传记录与撤回", "Diagnostic history and withdrawal")) {
                            ForEach(model.history) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.reportID).font(.system(.caption, design: .monospaced)).fanBarSelectableText()
                                    HStack {
                                        Text(item.createdAt, style: .date).font(.caption).foregroundColor(.secondary)
                                        Spacer()
                                        if item.response == nil {
                                            Button(fanBarText("重试上传", "Retry upload")) { Task { await model.send(item) } }
                                        }
                                        Button(fanBarText("撤回", "Withdraw")) { Task { await model.withdraw(item) } }
                                    }
                                }.padding(.vertical, 8)
                            }
                        }.font(.caption).disabled(model.busy)
                    }
                    if let error = model.error { Text(error).font(.caption).foregroundColor(.orange) }
                }
            }
            Divider()
            HStack {
                Button(fanBarText("导出日志…", "Export logs…"), action: export).disabled(model.report == nil || model.busy)
                Spacer()
                Button(fanBarText("关闭", "Close")) { presentationMode.wrappedValue.dismiss() }
                    .keyboardShortcut(.cancelAction).disabled(model.busy)
                if model.receipt?.response == nil {
                    Button(model.busy ? fanBarText("正在上传…", "Uploading…") : fanBarText("确认上传", "Confirm upload")) {
                        Task { await model.submit() }
                    }.disabled(!model.canSubmit)
                }
            }
        }
        .padding(24).frame(width: 560, height: 600)
        .fanBarInteractiveDismissDisabled(model.busy)
        .onAppear {
            guard preparationTask == nil else { return }
            preparationTask = Task { await model.prepare() }
        }
        .onDisappear {
            preparationTask?.cancel()
            preparationTask = nil
        }
        .environment(\.locale, (FanBarLanguage(rawValue: languageRawValue) ?? .system).locale)
    }

    private func export() {
        guard let report = model.report, let data = try? report.jsonData() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "FanBar-diagnostics-\(report.diagnosticID).json"
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try data.write(to: url, options: .atomic) } catch { model.exportFailed() }
        }
    }
}

// swiftlint:enable line_length
