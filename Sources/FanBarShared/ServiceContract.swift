/// Values the compatibility service enforces and the client validates with strict equality.
/// They must match contracts/service-constants.json, which the Worker generates from its source;
/// ServiceContractTests fails when either side changes alone.
public enum ServiceContract {
    public enum Compatibility {
        public static let policyVersion = "2026-10-21"
        public static let retentionDays = 90
        public static let maximumReportBytes = 16384
    }

    public enum Diagnostics {
        public static let policyVersion = "diagnostics-2026-10-19-v5"
        public static let retentionDays = 90
        public static let maximumBytes = 262_144
    }
}
