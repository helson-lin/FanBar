import Combine
import Foundation

@MainActor
final class CompatibilityUploadCoordinator: ObservableObject {
    @Published private(set) var data: Data
    let configuration: CompatibilityServiceConfiguration?
    private let api: (any CompatibilityReportServing)?
    private let store: any CompatibilityReceiptStoring
    @Published private(set) var policy: CompatibilityServicePolicy?
    @Published private(set) var receipt: CompatibilitySavedReceipt?
    @Published private(set) var isLoading = false
    @Published private(set) var isSending = false
    @Published private(set) var error: CompatibilityServiceError?
    /// Opt-in: send a diagnostic report under its own rules once this report is received.
    @Published var attachDiagnostic = false
    @Published private(set) var diagnosticUpload: DiagnosticUploadCoordinator?
    private let collectDiagnostic: (@MainActor () async -> DiagnosticReport)?
    private let makeDiagnosticUpload: @MainActor (@escaping @MainActor () async -> DiagnosticReport) -> DiagnosticUploadCoordinator

    init(
        data: Data,
        configuration: CompatibilityServiceConfiguration? = .current,
        api: (any CompatibilityReportServing)? = nil,
        store: any CompatibilityReceiptStoring = CompatibilityReceiptStore(),
        receipt: CompatibilitySavedReceipt? = nil,
        collectDiagnostic: (@MainActor () async -> DiagnosticReport)? = nil,
        makeDiagnosticUpload: @escaping @MainActor (@escaping @MainActor () async -> DiagnosticReport)
            -> DiagnosticUploadCoordinator = { DiagnosticUploadCoordinator(collect: $0) }
    ) {
        self.data = data
        self.configuration = configuration
        self.api = api ?? configuration.map { CompatibilityReportService(configuration: $0) }
        self.store = store
        self.receipt = receipt
        self.collectDiagnostic = collectDiagnostic
        self.makeDiagnosticUpload = makeDiagnosticUpload
    }

    var canAttachDiagnostic: Bool { collectDiagnostic != nil }

    func isUserConfirmedWorking(_ capability: CompatibilityCapability) -> Bool {
        (try? JSONDecoder().decode(CompatibilityReport.self, from: data))?
            .capabilities.first { $0.capability == capability }?.userConfirmedWorking == true
    }

    func canConfirmWorking(_ capability: CompatibilityCapability) -> Bool {
        guard [.manualControl, .smartCooling].contains(capability) else { return false }
        return (try? JSONDecoder().decode(CompatibilityReport.self, from: data))?
            .capabilities.first { $0.capability == capability }?.status.acceptsHandsOnConfirmation == true
    }

    func setUserConfirmedWorking(_ capability: CompatibilityCapability, confirmed: Bool) {
        guard receipt == nil, !isSending, !confirmed || canConfirmWorking(capability) else { return }
        do {
            var report = try JSONDecoder().decode(CompatibilityReport.self, from: data)
            guard let index = report.capabilities.firstIndex(where: { $0.capability == capability }) else { return }
            report.capabilities[index].userConfirmedWorking = confirmed ? true : nil
            data = try report.jsonData()
            error = nil
        } catch { self.error = .invalidReport }
    }

    func loadPolicy() async {
        guard let api, let configuration, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let policy = try await api.policy()
            try policy.validate(for: configuration)
            self.policy = policy
            error = nil
        } catch {
            self.policy = nil
            self.error = error as? CompatibilityServiceError ?? .network
        }
    }

    func submit(consent: Bool, publishReport: Bool) async {
        guard consent else { error = .consentRequired; return }
        guard let api, let configuration else { error = .notConfigured; return }
        guard let policy, !isSending, receipt?.response == nil else { return }
        isSending = true
        defer { isSending = false }
        do {
            guard data.count <= policy.maximumReportBytes,
                  let report = try? JSONDecoder().decode(CompatibilityReport.self, from: data) else {
                throw CompatibilityServiceError.invalidReport
            }
            if receipt == nil {
                let pending = CompatibilitySavedReceipt(
                    reportID: report.reportID.uuidString.lowercased(), serviceURL: configuration.baseURL,
                    deletionToken: try CompatibilitySavedReceipt.makeToken(), reportData: data,
                    publishReport: publishReport, policyVersion: policy.version, createdAt: Date()
                )
                // Save BEFORE sending: a lost response must not lose the ability to withdraw.
                try store.save(pending)
                receipt = pending
            }
            guard var pending = receipt else { throw CompatibilityServiceError.credentialStorage }
            pending.response = try await api.submit(pending)
            try store.save(pending)
            receipt = pending
            error = nil
        } catch {
            self.error = error as? CompatibilityServiceError ?? .credentialStorage
            return
        }
        await submitAttachedDiagnostic()
    }

    /// Runs only after the report is received. The diagnostic takes the report's ID so the
    /// two can be read side by side; it keeps its own policy check, receipt and withdrawal.
    func submitAttachedDiagnostic() async {
        guard attachDiagnostic, let collectDiagnostic, let reportID = receipt?.response?.reportID else { return }
        let upload: DiagnosticUploadCoordinator
        if let existing = diagnosticUpload {
            upload = existing // A retry: keep the collected report and its saved receipt.
        } else {
            upload = makeDiagnosticUpload {
                var report = await collectDiagnostic()
                report.diagnosticID = reportID
                return report
            }
            diagnosticUpload = upload
        }
        if upload.report == nil {
            await upload.prepare()
        } else if upload.policy == nil {
            await upload.loadPolicy()
        }
        upload.consent = true
        await upload.submit()
    }
}
