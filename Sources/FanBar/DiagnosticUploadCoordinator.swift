import Combine
import FanBarShared
import Foundation

@MainActor
protocol DiagnosticUploadServing {
    var configuration: CompatibilityServiceConfiguration { get }
    func diagnosticPolicy() async throws -> DiagnosticPolicy
    func submitDiagnostic(_ receipt: CompatibilitySavedReceipt) async throws -> CompatibilitySubmissionResponse
    func withdrawDiagnostic(_ receipt: CompatibilitySavedReceipt) async throws
}

extension CompatibilityReportService: DiagnosticUploadServing {}

/// Drives the diagnostic upload sheet. Nothing is sent without consent and a validated policy,
/// the withdrawal credential is saved before any network write, and a withdrawn ID is never reused.
@MainActor
final class DiagnosticUploadCoordinator: ObservableObject {
    @Published private(set) var report: DiagnosticReport?
    @Published private(set) var policy: DiagnosticPolicy?
    @Published private(set) var receipt: CompatibilitySavedReceipt?
    @Published private(set) var history: [CompatibilitySavedReceipt] = []
    @Published var consent = false
    @Published private(set) var busy = false
    @Published private var failure: Failure?

    var error: String? { failure?.message }

    private enum Failure {
        case service(CompatibilityServiceError)
        case export

        var message: String {
            switch self {
            case .service(let error): error.message
            case .export: fanBarText("无法保存报告，请选择其他位置后重试。", "Unable to save. Choose another location and retry.")
            }
        }
    }

    private let collect: @MainActor () async -> DiagnosticReport
    private let makeService: @MainActor (URL?) throws -> any DiagnosticUploadServing
    private let store: any CompatibilityReceiptStoring

    init(
        collect: @escaping @MainActor () async -> DiagnosticReport,
        makeService: @escaping @MainActor (URL?) throws -> any DiagnosticUploadServing = DiagnosticUploadCoordinator.liveService,
        store: any CompatibilityReceiptStoring = CompatibilityReceiptStore(service: "local.fanbar.diagnostics.receipts")
    ) {
        self.collect = collect
        self.makeService = makeService
        self.store = store
    }

    /// History items keep the service they were sent to; new uploads use the configured one.
    static func liveService(for url: URL?) throws -> any DiagnosticUploadServing {
        let configuration = url.flatMap { CompatibilityServiceConfiguration(url: $0) }
            ?? (url == nil ? CompatibilityServiceConfiguration.current : nil)
        guard let configuration else { throw CompatibilityServiceError.notConfigured }
        return CompatibilityReportService(configuration: configuration)
    }

    /// Build reported by a running helper that differs from the one this app bundles: a stale daemon.
    var staleHelperBuild: String? {
        guard let report, let running = report.runningHelper, running.status == "reported",
              let build = running.build, build != report.device.helperVersion else { return nil }
        return build
    }

    var canSubmit: Bool {
        consent && report != nil && policy != nil && !busy && receipt?.response == nil
    }

    func prepare() async {
        let collected = await collect()
        guard !Task.isCancelled else { return }
        report = collected
        loadHistory()
        guard !Task.isCancelled else { return }
        await loadPolicy()
    }

    func loadPolicy() async {
        do {
            policy = try await makeService(nil).diagnosticPolicy()
            failure = nil
        } catch { self.failure = .service(Self.serviceError(for: error, fallback: .network)) }
    }

    func submit() async {
        guard canSubmit, let report else { return }
        do {
            if receipt == nil {
                let service = try makeService(nil)
                let pending = CompatibilitySavedReceipt(
                    reportID: report.diagnosticID, serviceURL: service.configuration.baseURL,
                    deletionToken: try CompatibilitySavedReceipt.makeToken(), reportData: try report.jsonData(),
                    publishReport: false, policyVersion: DiagnosticPolicy.supportedVersion, createdAt: Date()
                )
                try store.save(pending) // Persist the retry/deletion credential before any network write.
                receipt = pending
                history = try store.receipts()
            }
            if let receipt { await send(receipt) }
        } catch { self.failure = .service(Self.serviceError(for: error, fallback: .invalidReport)) }
    }

    func send(_ item: CompatibilitySavedReceipt) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let service = try makeService(item.serviceURL)
            _ = try await service.diagnosticPolicy()
            var updated = item
            updated.response = try await service.submitDiagnostic(item)
            try store.save(updated)
            if receipt?.reportID == item.reportID { receipt = updated }
            history = try store.receipts()
            failure = nil
        } catch { self.failure = .service(Self.serviceError(for: error, fallback: .network)) }
    }

    func withdraw(_ item: CompatibilitySavedReceipt) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await makeService(item.serviceURL).withdrawDiagnostic(item)
            try store.remove(reportID: item.reportID)
            history = try store.receipts()
            // Never reuse a withdrawn ID, including requests that timed out before withdrawal.
            if receipt?.reportID == item.reportID {
                receipt = nil
                report = nil
                consent = false
                report = await collect()
            }
            failure = nil
        } catch { self.failure = .service(Self.serviceError(for: error, fallback: .network)) }
    }

    func exportFailed() {
        failure = .export
    }

    private func loadHistory() {
        do { history = try store.receipts() } catch { self.failure = .service(.credentialStorage) }
    }

    private static func serviceError(for error: Error, fallback: CompatibilityServiceError) -> CompatibilityServiceError {
        error as? CompatibilityServiceError ?? fallback
    }
}
