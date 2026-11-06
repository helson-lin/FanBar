import FanBarShared
import Foundation
import Security

struct CompatibilityServiceConfiguration: Equatable {
    let baseURL: URL

    init?(url: URL, allowsLocalDevelopment: Bool = false) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/" else { return nil }
        let local = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
        guard components.scheme == "https" || (allowsLocalDevelopment && local && components.scheme == "http") else { return nil }
        baseURL = url
    }

    static var current: Self? {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["FANBAR_COMPATIBILITY_SERVICE_URL"],
           let url = URL(string: value) {
            return Self(url: url, allowsLocalDevelopment: true)
        }
        #endif
        guard let value = Bundle.main.object(forInfoDictionaryKey: "FanBarCompatibilityServiceURL") as? String,
              let url = URL(string: value) else { return nil }
        return Self(url: url)
    }

    func url(path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }
}

struct CompatibilityServicePolicy: Codable {
    static let supportedVersion = ServiceContract.Compatibility.policyVersion
    let version: String
    let serviceOrigin: String
    let retentionDays: Int
    let maximumReportBytes: Int
    let sourceURL: URL

    func validate(for configuration: CompatibilityServiceConfiguration) throws {
        guard version == Self.supportedVersion,
              retentionDays == ServiceContract.Compatibility.retentionDays,
              maximumReportBytes == ServiceContract.Compatibility.maximumReportBytes,
              let origin = URL(string: serviceOrigin),
              origin.host == configuration.baseURL.host,
              origin.scheme == configuration.baseURL.scheme,
              origin.port == configuration.baseURL.port else { throw CompatibilityServiceError.policyChanged }
    }
}

enum CompatibilityServiceError: Error {
    case notConfigured
    case invalidReport
    case consentRequired
    case credentialStorage
    case policyChanged
    case rateLimited
    case reportConflict
    case network
    case server
}

struct CompatibilitySubmissionResponse: Codable, Equatable {
    let reportID: String
    let status: String
    let receivedAt: String
    let expiresAt: String
    let publishReport: Bool
    let policyVersion: String
}

@MainActor
protocol CompatibilityReportServing {
    func policy() async throws -> CompatibilityServicePolicy
    func submit(_ receipt: CompatibilitySavedReceipt) async throws -> CompatibilitySubmissionResponse
    func withdraw(_ receipt: CompatibilitySavedReceipt) async throws
}

/// No mutable state. Blocks all redirects so neither a body nor a credential can leave the chosen service.
private final class CompatibilityRedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

@MainActor
final class CompatibilityReportService: CompatibilityReportServing {
    let configuration: CompatibilityServiceConfiguration
    private let session: URLSession

    init(configuration: CompatibilityServiceConfiguration) {
        self.configuration = configuration
        let settings = URLSessionConfiguration.ephemeral
        settings.httpCookieStorage = nil
        settings.httpShouldSetCookies = false
        settings.urlCache = nil
        settings.timeoutIntervalForRequest = 15
        settings.timeoutIntervalForResource = 20
        settings.httpAdditionalHeaders = ["User-Agent": "FanBar-Compatibility/1"]
        session = URLSession(configuration: settings, delegate: CompatibilityRedirectBlocker(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func policy() async throws -> CompatibilityServicePolicy {
        // Without a version the service answers with the rules older clients require.
        var components = URLComponents(url: configuration.url(path: "api/policy"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "version", value: CompatibilityServicePolicy.supportedVersion)]
        guard let url = components?.url else { throw CompatibilityServiceError.notConfigured }
        let data = try await perform(URLRequest(url: url))
        let policy = try JSONDecoder().decode(CompatibilityServicePolicy.self, from: data)
        try policy.validate(for: configuration)
        return policy
    }

    func submit(_ receipt: CompatibilitySavedReceipt) async throws -> CompatibilitySubmissionResponse {
        guard receipt.serviceURL == configuration.baseURL else { throw CompatibilityServiceError.notConfigured }
        var request = Self.submissionRequest(receipt)
        request.url = configuration.url(path: "api/reports")
        let data = try await perform(request)
        let result = try JSONDecoder().decode(CompatibilitySubmissionResponse.self, from: data)
        guard result.reportID.lowercased() == receipt.reportID.lowercased(),
              result.publishReport == receipt.publishReport,
              result.policyVersion == receipt.policyVersion else { throw CompatibilityServiceError.server }
        return result
    }

    func diagnosticPolicy() async throws -> DiagnosticPolicy {
        let data = try await perform(URLRequest(url: configuration.url(path: "api/diagnostics/policy")))
        let policy = try JSONDecoder().decode(DiagnosticPolicy.self, from: data)
        let origin = configuration.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard policy.version == DiagnosticPolicy.supportedVersion,
              policy.retentionDays == ServiceContract.Diagnostics.retentionDays,
              policy.maximumBytes == ServiceContract.Diagnostics.maximumBytes, policy.serviceOrigin == origin
        else { throw CompatibilityServiceError.policyChanged }
        return policy
    }

    func submitDiagnostic(_ receipt: CompatibilitySavedReceipt) async throws -> CompatibilitySubmissionResponse {
        guard receipt.serviceURL == configuration.baseURL else { throw CompatibilityServiceError.notConfigured }
        var request = Self.submissionRequest(receipt)
        request.url = configuration.url(path: "api/diagnostics")
        let data = try await perform(request)
        let result = try JSONDecoder().decode(CompatibilitySubmissionResponse.self, from: data)
        guard result.reportID.lowercased() == receipt.reportID.lowercased(), !result.publishReport,
              result.policyVersion == DiagnosticPolicy.supportedVersion else { throw CompatibilityServiceError.server }
        return result
    }

    func withdrawDiagnostic(_ receipt: CompatibilitySavedReceipt) async throws {
        guard receipt.serviceURL == configuration.baseURL else { throw CompatibilityServiceError.notConfigured }
        var request = URLRequest(url: configuration.url(path: "api/diagnostics/\(receipt.reportID)"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(receipt.deletionToken)", forHTTPHeaderField: "Authorization")
        _ = try await perform(request)
    }

    static func submissionRequest(_ receipt: CompatibilitySavedReceipt) -> URLRequest {
        var request = URLRequest(url: receipt.serviceURL.appendingPathComponent("api/reports"))
        request.httpMethod = "POST"
        request.httpBody = receipt.reportData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(receipt.deletionToken)", forHTTPHeaderField: "Authorization")
        request.setValue(receipt.policyVersion, forHTTPHeaderField: "X-FanBar-Policy-Version")
        request.setValue(receipt.publishReport ? "1" : "0", forHTTPHeaderField: "X-FanBar-Publish-Report")
        return request
    }

    func withdraw(_ receipt: CompatibilitySavedReceipt) async throws {
        guard receipt.serviceURL == configuration.baseURL else { throw CompatibilityServiceError.notConfigured }
        var request = URLRequest(url: configuration.url(path: "api/reports/\(receipt.reportID)"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(receipt.deletionToken)", forHTTPHeaderField: "Authorization")
        _ = try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                guard error == nil, let data, let response else {
                    continuation.resume(throwing: CompatibilityServiceError.network)
                    return
                }
                continuation.resume(returning: (data, response))
            }.resume()
        }
        guard let response = response as? HTTPURLResponse, data.count <= 131072 else { throw CompatibilityServiceError.server }
        switch response.statusCode {
        case 200, 201, 204: return data
        case 400, 413: throw CompatibilityServiceError.invalidReport
        case 429: throw CompatibilityServiceError.rateLimited
        case 409:
            let error = try? JSONDecoder().decode(ServiceErrorBody.self, from: data)
            throw error?.error.code == "POLICY_CHANGED" ? CompatibilityServiceError.policyChanged : .reportConflict
        default: throw CompatibilityServiceError.server
        }
    }

    private struct ServiceErrorBody: Decodable {
        struct Detail: Decodable { let code: String }
        let error: Detail
    }
}

struct CompatibilitySavedReceipt: Codable, Equatable, Identifiable {
    let reportID: String
    let serviceURL: URL
    let deletionToken: String
    let reportData: Data
    let publishReport: Bool
    let policyVersion: String
    let createdAt: Date
    var response: CompatibilitySubmissionResponse?
    var id: String { reportID }

    static func makeToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CompatibilityServiceError.credentialStorage
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct DiagnosticPolicy: Decodable {
    static let supportedVersion = ServiceContract.Diagnostics.policyVersion
    let version: String
    let serviceOrigin: String
    let retentionDays: Int
    let maximumBytes: Int
}
