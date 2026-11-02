import Darwin
import Foundation

/// One app in the CPU detail list, with its helper processes folded in.
struct TopApp: Equatable, Identifiable, Sendable {
    /// The `.app` bundle path, or the executable path for a process outside any app.
    var id: String
    var name: String
    var bundlePath: String?
    /// Activity Monitor's scale: 100 is one full core, so busy apps exceed 100.
    var percent: Double
}

struct TopAppsSnapshot: Equatable, Sendable {
    var apps: [TopApp]
    /// Processes the current user can read; system processes owned by root are not.
    var processCount: Int
}

/// Samples per-process CPU time and ranks apps by their share since the last sample.
/// Only runs while the panel's CPU detail is open, so its cost is paid on demand.
/// Not thread-safe: the controller confines each reader to one serial queue.
final class TopAppsReader: @unchecked Sendable {
    static let limit = 5

    private struct Process {
        var key: String
        var name: String
        var bundlePath: String?
    }

    private var previousCPU: [pid_t: UInt64] = [:]
    private var previousTime: UInt64?
    /// Paths rarely change for a living pid, so they're looked up once.
    private var processes: [pid_t: Process] = [:]
    private let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    func reset() {
        previousCPU = [:]
        previousTime = nil
        processes = [:]
    }

    /// nil on the first call, which only records the baseline.
    func sample(now: UInt64 = DispatchTime.now().uptimeNanoseconds) -> TopAppsSnapshot? {
        var cpu: [pid_t: UInt64] = [:]
        for pid in Self.allPIDs() {
            guard let nanoseconds = cpuNanoseconds(pid) else { continue }
            cpu[pid] = nanoseconds
        }
        processes = processes.filter { cpu[$0.key] != nil }

        defer {
            previousCPU = cpu
            previousTime = now
        }
        guard let previousTime, now > previousTime else { return nil }
        let elapsed = Double(now - previousTime)

        var byApp: [String: TopApp] = [:]
        for (pid, total) in cpu {
            guard let before = previousCPU[pid], total >= before else { continue }
            let percent = Double(total - before) / elapsed * 100
            guard percent > 0 else { continue }
            let process = process(for: pid)
            byApp[process.key, default: TopApp(
                id: process.key, name: process.name, bundlePath: process.bundlePath, percent: 0
            )].percent += percent
        }
        let ranked = byApp.values.sorted { $0.percent > $1.percent }
        return TopAppsSnapshot(apps: Array(ranked.prefix(Self.limit)), processCount: cpu.count)
    }

    // MARK: Grouping

    /// The outermost `.app` in an executable path, so helpers nested inside an app's
    /// frameworks (Chrome's renderer helpers, Xcode's tools) count toward that app.
    static func bundlePath(forExecutable path: String) -> String? {
        guard let range = path.range(of: ".app/") else {
            return path.hasSuffix(".app") ? path : nil
        }
        return String(path[..<range.lowerBound]) + ".app"
    }

    private func process(for pid: pid_t) -> Process {
        if let cached = processes[pid] { return cached }
        // Count a process toward whoever launched it on the user's behalf, as Activity
        // Monitor does, so WebKit's web content and GPU processes join their app.
        let owner = Self.responsiblePID(pid)
        let path = (owner != pid ? Self.executablePath(owner) : nil) ?? Self.executablePath(pid)
        let process: Process
        if let path, let bundle = Self.bundlePath(forExecutable: path) {
            let name = (FileManager.default.displayName(atPath: bundle) as NSString).deletingPathExtension
            process = Process(key: bundle, name: name, bundlePath: bundle)
        } else {
            let name = path.map { ($0 as NSString).lastPathComponent } ?? Self.shortName(pid) ?? "\(pid)"
            process = Process(key: path ?? "pid:\(pid)", name: name, bundlePath: nil)
        }
        processes[pid] = process
        return process
    }

    // MARK: libproc

    private typealias ResponsibleFunction = @convention(c) (pid_t) -> pid_t

    /// Private but long-standing; looked up at run time so its absence only loses grouping.
    private static let responsibleFunction: ResponsibleFunction? = {
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let symbol = dlsym(defaultHandle, "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: ResponsibleFunction.self)
    }()

    private static func responsiblePID(_ pid: pid_t) -> pid_t {
        guard let responsibleFunction else { return pid }
        let owner = responsibleFunction(pid)
        return owner > 0 ? owner : pid
    }

    private func cpuNanoseconds(_ pid: pid_t) -> UInt64? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        // Apple silicon reports Mach ticks, Intel nanoseconds; the timebase covers both.
        let ticks = info.pti_total_user + info.pti_total_system
        return ticks * UInt64(timebase.numer) / UInt64(max(timebase.denom, 1))
    }

    private static func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return count > 0 ? Array(pids.prefix(Int(count))) : []
    }

    private static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func shortName(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 64)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}
