import AppKit
import FanBarShared
import SwiftUI
import UniformTypeIdentifiers

struct CompatibilityReceiptsView: View {
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    @Environment(\.presentationMode) private var presentationMode
    @State private var receipts: [CompatibilitySavedReceipt] = []
    @State private var notice: Notice?
    @State private var busyID: String?
    @State private var withdrawing: CompatibilitySavedReceipt?
    @State private var retrying: CompatibilitySavedReceipt?
    private let store: any CompatibilityReceiptStoring

    private enum Notice {
        case service(CompatibilityServiceError)
        case withdrawn

        var message: String {
            switch self {
            case .service(let error): error.message
            case .withdrawn: fanBarText("报告已撤回，或已经过期。", "Report withdrawn or already expired.")
            }
        }
    }

    init(store: any CompatibilityReceiptStoring = CompatibilityReceiptStore()) {
        self.store = store
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(fanBarText("上报记录与撤回", "Submitted Reports and Withdrawal")).font(.headline)
                Spacer()
                Button(fanBarText("完成", "Done")) { presentationMode.wrappedValue.dismiss() }
                    .keyboardShortcut(.cancelAction).disabled(busyID != nil)
            }
            Text(fanBarText(
                "每份报告使用独立凭证，保存在本机钥匙串。凭证不会出现在公开报告中。",
                "Each report has a separate credential in this Mac’s Keychain. It never appears in public reports."
            ))
                .font(.caption).foregroundColor(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if receipts.isEmpty {
                        Text(fanBarText("本机暂无上报记录。", "No submitted reports on this Mac."))
                            .foregroundColor(.secondary).padding(.vertical, 30)
                    }
                    ForEach(receipts) { receipt in receiptCard(receipt) }
                }
            }
            if let notice { Text(notice.message).font(.caption).foregroundColor(.secondary) }
        }
        .padding(24).frame(width: 510, height: 450)
        .onAppear(perform: reload)
        .sheet(item: $retrying, onDismiss: reload) { receipt in
            CompatibilityReportPreview(
                data: receipt.reportData,
                coordinator: CompatibilityUploadCoordinator(
                    data: receipt.reportData, configuration: receiptConfiguration(receipt),
                    store: store, receipt: receipt
                )
            )
        }
        .alert(item: $withdrawing) { receipt in
            Alert(
                title: Text(fanBarText("撤回这份报告？", "Withdraw this report?")),
                message: Text(fanBarText("在线报告及其社区统计贡献将被删除。", "The online report and its community contribution will be removed.")),
                primaryButton: .destructive(Text(fanBarText("撤回报告", "Withdraw report"))) {
                    Task { await withdraw(receipt) }
                },
                secondaryButton: .cancel()
            )
        }
        .environment(\.locale, (FanBarLanguage(rawValue: languageRawValue) ?? .system).locale)
    }

    private func receiptCard(_ receipt: CompatibilitySavedReceipt) -> some View {
        SettingsChrome.settingsCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(receipt.reportID).font(.system(size: 11, design: .monospaced))
                Text(receipt.serviceURL.absoluteString).font(.caption).foregroundColor(.secondary)
                Text(receipt.response == nil
                    ? fanBarText("提交结果待确认；可以撤回可能已收到的报告。", "Submission unconfirmed; you can withdraw a report that may have arrived.")
                    : fanBarText("报告已收到，公开结果以审核状态为准。", "Report received. Publication depends on review."))
                    .font(.caption).foregroundColor(.secondary)
                Text(receipt.createdAt, style: .date).font(.caption).foregroundColor(.secondary)
                HStack {
                    if receipt.response == nil {
                        Button(fanBarText("重试上报…", "Retry submission…")) { retrying = receipt }
                    }
                    Button(fanBarText("保存撤回凭证…", "Save withdrawal credential…")) { saveCredential(receipt) }
                    Spacer()
                    Button(fanBarText("撤回报告", "Withdraw report")) { withdrawing = receipt }
                }.disabled(busyID != nil)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func reload() {
        do { receipts = try store.receipts() } catch { notice = .service(.credentialStorage) }
    }

    private func withdraw(_ receipt: CompatibilitySavedReceipt) async {
        guard busyID == nil else { return }
        guard let configuration = receiptConfiguration(receipt) else {
            notice = .service(.notConfigured)
            return
        }
        busyID = receipt.reportID
        defer { busyID = nil }
        do {
            try await CompatibilityReportService(configuration: configuration).withdraw(receipt)
            try store.remove(reportID: receipt.reportID)
            reload()
            notice = .withdrawn
        } catch {
            notice = .service(error as? CompatibilityServiceError ?? .server)
        }
    }

    private func receiptConfiguration(_ receipt: CompatibilitySavedReceipt) -> CompatibilityServiceConfiguration? {
        #if DEBUG
        CompatibilityServiceConfiguration(url: receipt.serviceURL, allowsLocalDevelopment: true)
        #else
        CompatibilityServiceConfiguration(url: receipt.serviceURL)
        #endif
    }

    private func saveCredential(_ receipt: CompatibilitySavedReceipt) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "FanBar-withdrawal-\(receipt.reportID).json"
        panel.allowedContentTypes = [.json]
        panel.message = fanBarText("凭证可以删除报告，请妥善保管，不要公开分享。", "This credential can delete the report. Keep it private.")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let credential = WithdrawalCredential(
                    reportID: receipt.reportID, serviceURL: receipt.serviceURL, deletionToken: receipt.deletionToken
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(credential).write(to: url, options: .atomic)
            } catch { notice = .service(.credentialStorage) }
        }
    }

    private struct WithdrawalCredential: Encodable {
        let reportID: String
        let serviceURL: URL
        let deletionToken: String
    }
}
