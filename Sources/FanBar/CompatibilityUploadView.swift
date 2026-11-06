import AppKit
import FanBarShared
import SwiftUI
import UniformTypeIdentifiers

extension CompatibilityServiceError {
    var message: String {
        switch self {
        case .notConfigured: fanBarText("上报服务尚未配置，可先保存本地报告。", "Reporting is not configured. You can save a local report.")
        case .invalidReport: fanBarText("报告内容无效，请重新检测并生成报告。", "Invalid report. Check this Mac again and create a new report.")
        case .consentRequired: fanBarText("请先确认本次提交。", "Confirm this submission first.")
        case .credentialStorage: fanBarText("无法保存撤回凭证，请检查钥匙串后重试。", "Unable to save the withdrawal credential. Check Keychain and retry.")
        case .policyChanged: fanBarText("服务规则已变化，请更新 FanBar 后再上报。", "Service rules changed. Update FanBar before reporting.")
        case .rateLimited: fanBarText("提交过于频繁，请稍后重试。", "Too many submissions. Please retry later.")
        case .reportConflict: fanBarText("报告编号或提交内容冲突，请生成新报告。", "Report ID or content conflicts. Create a new report.")
        case .network: fanBarText(
            "无法连接服务。提交超时时，报告可能已收到；重试不会重复计数。",
            "Connection failed. A timed-out report may have arrived; retrying does not count it twice."
        )
        case .server: fanBarText("服务暂时无法处理请求，请稍后重试。", "The service cannot process this request right now. Retry later.")
        }
    }
}

struct CompatibilityReportPreview: View {
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    let data: Data
    private let preparesSubmission: Bool
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var upload: CompatibilityUploadCoordinator
    @State private var saveFailed = false
    @State private var consent = false
    @State private var publishReport = false

    init(
        data: Data, preparesSubmission: Bool = false, coordinator: CompatibilityUploadCoordinator? = nil,
        collectDiagnostic: (@MainActor () async -> DiagnosticReport)? = nil
    ) {
        self.data = data
        self.preparesSubmission = preparesSubmission
        _upload = StateObject(wrappedValue: coordinator
            ?? CompatibilityUploadCoordinator(data: data, collectDiagnostic: collectDiagnostic))
        _publishReport = State(initialValue: coordinator?.receipt?.publishReport ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(fanBarText("兼容性报告预览", "Compatibility Report Preview"))
                .font(.headline).padding(.bottom, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // swiftlint:disable line_length
                    Text(fanBarText(
                        "仅包含机型、处理器、系统与软件版本、能力状态、控制失败时的失败码和随机报告编号。不包含序列号、设备唯一标识、用户名、文件路径、进程列表、温度历史或错误描述文本。",
                        "Only model, chip, versions, capability states, failure codes for failed controls, and report ID. No personal identifiers, logs, temperatures or error text."
                    ))
                    // swiftlint:enable line_length
                    .font(.caption).foregroundColor(.secondary)
                    reportSummary
                    uploadOptions
                    if let error = upload.error { Text(error.message).font(.caption).foregroundColor(.orange) }
                    if saveFailed {
                        Text(fanBarText("无法保存报告，请选择其他位置后重试。", "Unable to save. Choose another location and retry."))
                            .font(.caption).foregroundColor(.orange)
                    }
                }
            }
            Divider().padding(.vertical, 14)
            HStack(spacing: 12) {
                Button(fanBarText("完成", "Done")) { presentationMode.wrappedValue.dismiss() }
                    .keyboardShortcut(.cancelAction).disabled(upload.isSending)
                Spacer()
                Button(fanBarText("保存到本地…", "Save locally…"), action: saveLocally)
                if upload.configuration != nil, upload.receipt?.response == nil {
                    Button(upload.isSending
                        ? fanBarText("正在上报…", "Submitting…")
                        : fanBarText("确认上报", "Confirm submission")) {
                        Task { await upload.submit(consent: consent, publishReport: publishReport) }
                    }
                    .disabled(!consent || upload.policy == nil || upload.isSending)
                }
            }
        }
        .padding(24).frame(width: 510, height: 550)
        .onAppear {
            if preparesSubmission, upload.policy == nil, upload.receipt?.response == nil {
                Task { await upload.loadPolicy() }
            }
        }
        .environment(\.locale, (FanBarLanguage(rawValue: languageRawValue) ?? .system).locale)
    }

    @ViewBuilder
    private var reportSummary: some View {
        if let report = try? JSONDecoder().decode(CompatibilityReport.self, from: upload.data) {
            SettingsChrome.settingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(report.device.displayName).font(.headline)
                    Text(report.device.modelIdentifier).font(.caption).foregroundColor(.secondary)
                    Text(report.device.processor).font(.caption).foregroundColor(.secondary)
                    Text("macOS \(report.device.macOSVersion) · FanBar \(report.device.appVersion) · Helper \(report.device.helperVersion)")
                        .font(.caption).foregroundColor(.secondary)
                    Divider()
                    ForEach(report.capabilities) { result in
                        HStack(alignment: .firstTextBaseline) {
                            Text(result.capability.title).font(.caption)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(result.userConfirmedWorking == true
                                    ? fanBarText("本机实测可用（用户确认）", "Works on this Mac (user confirmed)")
                                    : result.status.title)
                                    .font(.caption)
                                    .foregroundColor(result.userConfirmedWorking == true ? .green : result.status.tint)
                                if let failure = result.failure {
                                    // Exactly what is uploaded: a fixed code, not the error text.
                                    Text(failure.code.rawValue)
                                        .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }.padding(14)
            }
        }
    }

    private var confirmableCapabilities: [CompatibilityCapability] {
        [.manualControl, .smartCooling].filter(upload.canConfirmWorking)
    }

    private var allHandsOnConfirmed: Bool {
        !confirmableCapabilities.isEmpty && confirmableCapabilities.allSatisfy(upload.isUserConfirmedWorking)
    }

    private var userConfirmations: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(fanBarText("本机实测确认（可选）", "Local hands-on confirmation (optional)"))
                    .font(.subheadline).fontWeight(.semibold)
                Spacer()
                Button(allHandsOnConfirmed
                    ? fanBarText("取消全选", "Deselect all")
                    : fanBarText("全选实测项", "Select all tested features")) {
                    let selected = !allHandsOnConfirmed
                    for capability in confirmableCapabilities {
                        upload.setUserConfirmedWorking(capability, confirmed: selected)
                    }
                }
                .font(.caption).disabled(upload.isSending || upload.receipt != nil || confirmableCapabilities.isEmpty)
            }
            // swiftlint:disable line_length
            Text(fanBarText("仅在你实际使用并确认功能正常时勾选。会作为用户确认上传，自动检测结果保持原样。",
                "Select only if you have actually used the feature and confirmed it works. Uploaded as user confirmation; automatic results stay unchanged."))
            // swiftlint:enable line_length
                .font(.caption).foregroundColor(.secondary)
            ForEach([CompatibilityCapability.manualControl, .smartCooling]) { capability in
                Toggle(isOn: Binding(
                    get: { upload.isUserConfirmedWorking(capability) },
                    set: { upload.setUserConfirmedWorking(capability, confirmed: $0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fanBarFormat("我已在本机实际使用%@并确认可用", "I have used %@ on this Mac and confirmed it works", capability.title))
                        if !upload.canConfirmWorking(capability) {
                            Text(fanBarText("自动检测显示该功能无法在本机运行，不能确认。",
                                "Not available: the automatic check shows this control could not run on this Mac."))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .font(.caption).disabled(upload.isSending || upload.receipt != nil || !upload.canConfirmWorking(capability))
            }
        }
    }

    @ViewBuilder
    private var uploadOptions: some View {
        if let response = upload.receipt?.response {
            VStack(alignment: .leading, spacing: 5) {
                Label(fanBarText("报告已收到，公开结果以审核状态为准。", "Report received. Publication depends on review."), systemImage: "checkmark.circle")
                    .foregroundColor(.green)
                Text(response.reportID).font(.system(size: 11, design: .monospaced))
                Text(fanBarText(
                    "撤回凭证已保存在本机钥匙串，可在上报记录中撤回。",
                    "The withdrawal credential is in this Mac’s Keychain. Withdraw from submitted reports."
                ))
                    .font(.caption).foregroundColor(.secondary)
            }
        } else if let configuration = upload.configuration {
            VStack(alignment: .leading, spacing: 10) {
                Text(configuration.baseURL.absoluteString).font(.caption).foregroundColor(.secondary)
                if let policy = upload.policy {
                    Text(fanBarText(
                        "报告在线保留 90 天。审核后贡献公开统计；原始报告默认私有。Cloudflare 会处理传输所需的网络元数据。",
                        "90 days online. Reviewed reports feed public counts; raw reports stay private. Cloudflare handles network data."
                    ))
                    .font(.caption).foregroundColor(.secondary)
                    HStack {
                        Link(fanBarText("收集与处理规则", "Collection and processing rules"), destination: configuration.url(path: "privacy.html"))
                        Text(policy.version).foregroundColor(.secondary)
                    }.font(.caption)
                    Text(fanBarText("罕见机型与版本组合可能具有辨识度。", "Rare model and version combinations may be identifiable."))
                        .font(.caption2).foregroundColor(.secondary)
                    SettingsChrome.settingsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            userConfirmations
                            Divider()
                            Toggle(fanBarText("同时公开这份报告，审核后供其他用户查阅", "Also publish this report after review"), isOn: $publishReport)
                                .font(.caption).disabled(upload.isSending || upload.receipt != nil)
                            if upload.canAttachDiagnostic { diagnosticOption }
                            Toggle(fanBarText("我同意按以上规则提交本次报告", "I agree to submit this report under these rules"), isOn: $consent)
                                .font(.caption).disabled(upload.isSending)
                        }.padding(14)
                    }
                } else {
                    Text(fanBarText(
                        "检测和本地保存不联网。准备上报时，只连接服务获取规则，不发送设备信息。",
                        "Detection and local saving stay offline. Preparing submission fetches rules without sending device information."
                    ))
                        .font(.caption).foregroundColor(.secondary)
                    Button(upload.isLoading
                        ? fanBarText("正在获取规则…", "Fetching rules…")
                        : fanBarText("准备上报 · 查看规则", "Prepare submission · review rules")) {
                        Task { await upload.loadPolicy() }
                    }.disabled(upload.isLoading)
                }
            }
        } else {
            Text(CompatibilityServiceError.notConfigured.message).font(.caption).foregroundColor(.secondary)
        }
        if let diagnostic = upload.diagnosticUpload {
            AttachedDiagnosticStatus(model: diagnostic) { Task { await upload.submitAttachedDiagnostic() } }
        }
    }

    private var hasFailedControl: Bool {
        (try? JSONDecoder().decode(CompatibilityReport.self, from: upload.data))?
            .capabilities.contains { $0.status == .requestFailed } == true
    }

    private var diagnosticOption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(fanBarText("同时上传诊断日志，仅管理员可见", "Also upload diagnostic logs (administrators only)"),
                isOn: $upload.attachDiagnostic)
                .font(.caption).disabled(upload.isSending || upload.receipt != nil)
            // swiftlint:disable line_length
            Text(fanBarText(
                "诊断日志按其单独的规则处理：包含传感器探测、最近的控制事件和错误码，使用与本报告相同的编号以便对照，不公开、不计入统计，可单独撤回。",
                "Diagnostic logs follow their own rules: sensor probes, recent control events and error codes, filed under this report’s ID so both can be read together. Never published or counted; withdraw them separately."
            ))
            // swiftlint:enable line_length
                .font(.caption2).foregroundColor(.secondary)
            if hasFailedControl {
                Text(fanBarText("控制测试失败，附带诊断日志能帮助定位原因。", "A control check failed. Attaching diagnostic logs helps find the cause."))
                    .font(.caption2).foregroundColor(.orange)
            }
        }
    }

    private func saveLocally() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "FanBar-compatibility.json"
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try upload.data.write(to: url, options: .atomic)
            } catch {
                saveFailed = true
            }
        }
    }
}

/// Progress of the diagnostic sent along with a compatibility report.
struct AttachedDiagnosticStatus: View {
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    @ObservedObject var model: DiagnosticUploadCoordinator
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if model.receipt?.response != nil {
                Label(fanBarText("诊断日志已上传。", "Diagnostic logs uploaded."), systemImage: "checkmark.circle")
                    .foregroundColor(.green)
            } else if model.busy || (model.error == nil && model.receipt == nil) {
                ProgressView(fanBarText("正在上传诊断日志…", "Uploading diagnostic logs…")).controlSize(.small)
            } else {
                if let error = model.error { Text(error).foregroundColor(.orange) }
                Button(fanBarText("重试上传诊断日志", "Retry diagnostic upload"), action: retry)
            }
        }
        .font(.caption)
        .environment(\.locale, (FanBarLanguage(rawValue: languageRawValue) ?? .system).locale)
    }
}
