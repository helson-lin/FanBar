import Darwin
import Foundation
import IOKit

/// One mounted local volume, as shown in the panel's disk list.
struct DiskVolumeUsage: Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var isInternal: Bool
    var usedBytes: UInt64
    var totalBytes: UInt64

    var fraction: Double? {
        totalBytes > 0 ? min(1, Double(usedBytes) / Double(totalBytes)) : nil
    }
}

/// How physical memory is split, using Activity Monitor's categories.
struct MemoryBreakdown: Equatable, Sendable {
    /// App memory plus wired memory: what the system cannot drop.
    var appBytes: UInt64
    /// File-backed and purgeable pages macOS can reclaim on demand.
    var cachedBytes: UInt64
    var compressedBytes: UInt64
    var totalBytes: UInt64
    var swapUsedBytes: UInt64?

    var usedBytes: UInt64 { appBytes + compressedBytes }
    /// Pages not used and not holding cache.
    var freeBytes: UInt64 {
        let occupied = usedBytes + cachedBytes
        return totalBytes > occupied ? totalBytes - occupied : 0
    }
}

/// One sample of whole-system load. A value is nil when its source is not
/// available on this Mac, so the panel shows a dash instead of a false zero.
struct SystemUsage: Equatable, Sendable {
    var cpuFraction: Double?
    /// Per logical core, in the kernel's core order. Empty until the second sample.
    var cpuCoreFractions: [Double] = []
    /// Kind of each core in the same order, from the device tree. Empty on
    /// Intel Macs, where every core is the same kind.
    var cpuCoreKinds: [CPUCoreKind] = []
    /// Cores shown in the panel: physical cores when hyper-threads are merged.
    var cpuCoreCount: Int?
    var loadAverage: Double?
    var memory: MemoryBreakdown?
    var gpuFraction: Double?
    var gpuCoreCount: Int?
    var gpuMemoryInUseBytes: UInt64?
    var disks: [DiskVolumeUsage] = []

    var memoryFraction: Double? {
        guard let memory, memory.totalBytes > 0 else { return nil }
        return min(1, Double(memory.usedBytes) / Double(memory.totalBytes))
    }

    var diskUsedBytes: UInt64? { disks.isEmpty ? nil : disks.reduce(0) { $0 + $1.usedBytes } }
    var diskTotalBytes: UInt64? { disks.isEmpty ? nil : disks.reduce(0) { $0 + $1.totalBytes } }

    /// Capacity-weighted across every listed volume, so a small external drive
    /// cannot dominate the headline number.
    var diskFraction: Double? {
        guard let used = diskUsedBytes, let total = diskTotalBytes, total > 0 else { return nil }
        return min(1, Double(used) / Double(total))
    }
}

/// Apple silicon cluster a logical core belongs to.
enum CPUCoreKind: Equatable, Sendable {
    case performance
    case efficiency
}

/// Cumulative CPU tick counters for one core or for the whole machine.
struct CPUTicks: Equatable, Sendable {
    var user: UInt32
    var system: UInt32
    var idle: UInt32
    var nice: UInt32
}

/// Reads CPU, memory, GPU, and disk usage with public Mach, sysctl, and IOKit
/// calls. These are the same sources exelban/stats (MIT) uses, chosen because
/// they exist on macOS 11 and need no private API or helper process.
final class SystemUsageReader {
    private var previousTicks: CPUTicks?
    private var previousCoreTicks: [CPUTicks] = []
    private var cachedDisks: [DiskVolumeUsage] = []
    private var disksSampledAt: Date?
    private let coreKinds = SystemUsageReader.coreKinds()
    /// Intel Macs with Hyper-Threading report two logical CPUs per core. Like
    /// exelban/stats, the panel shows one bar per physical core instead.
    private let mergesHyperThreads = SystemUsageReader.hasHyperThreading()

    /// Volume capacity changes slowly and "available for important usage" asks the
    /// system to estimate purgeable space, so disks refresh less often than load.
    static let diskRefreshInterval: TimeInterval = 30

    func sample(now: Date = Date()) -> SystemUsage {
        var usage = SystemUsage()

        if let current = Self.cpuTicks() {
            // The first sample has no baseline, so CPU usage stays nil until the second tick.
            usage.cpuFraction = previousTicks.flatMap { Self.cpuFraction(previous: $0, current: current) }
            previousTicks = current
        } else {
            previousTicks = nil
        }

        let coreTicks = Self.coreTicks()
        if coreTicks.count == previousCoreTicks.count {
            let perLogicalCPU = zip(previousCoreTicks, coreTicks).map { previous, current in
                Self.cpuFraction(previous: previous, current: current) ?? 0
            }
            usage.cpuCoreFractions = mergesHyperThreads ? Self.mergingHyperThreadPairs(perLogicalCPU) : perLogicalCPU
        }
        previousCoreTicks = coreTicks
        let logicalCount = coreTicks.isEmpty ? ProcessInfo.processInfo.activeProcessorCount : coreTicks.count
        usage.cpuCoreCount = mergesHyperThreads ? (logicalCount + 1) / 2 : logicalCount

        usage.cpuCoreKinds = coreKinds
        usage.loadAverage = Self.oneMinuteLoadAverage()
        usage.memory = Self.memoryBreakdown()

        let gpu = Self.gpuStatistics()
        usage.gpuFraction = gpu.fraction
        usage.gpuCoreCount = gpu.coreCount
        usage.gpuMemoryInUseBytes = gpu.memoryInUseBytes

        if disksSampledAt.map({ now.timeIntervalSince($0) >= Self.diskRefreshInterval }) ?? true {
            cachedDisks = Self.diskVolumes()
            disksSampledAt = now
        }
        usage.disks = cachedDisks
        return usage
    }

    /// Busy time as a share of all time since `previous`. Counters wrap at
    /// 32 bits, so the differences use wrapping subtraction.
    static func cpuFraction(previous: CPUTicks, current: CPUTicks) -> Double? {
        let user = current.user &- previous.user
        let system = current.system &- previous.system
        let nice = current.nice &- previous.nice
        let idle = current.idle &- previous.idle

        let busy = UInt64(user) + UInt64(system) + UInt64(nice)
        let total = busy + UInt64(idle)
        guard total > 0 else { return nil }
        return min(1, Double(busy) / Double(total))
    }

    /// Averages sibling hyper-threads into one value per physical core. macOS
    /// numbers the two threads of a core next to each other, which is the
    /// pairing exelban/stats relies on as well.
    static func mergingHyperThreadPairs(_ fractions: [Double]) -> [Double] {
        stride(from: 0, to: fractions.count, by: 2).map { index in
            let pair = fractions[index..<min(index + 2, fractions.count)]
            return pair.reduce(0, +) / Double(pair.count)
        }
    }

    /// Activity Monitor's split: app memory is internal pages minus purgeable,
    /// cached files are external plus purgeable pages.
    static func memoryBreakdown(
        statistics stats: vm_statistics64,
        pageSize: UInt64,
        totalBytes: UInt64,
        swapUsedBytes: UInt64?
    ) -> MemoryBreakdown {
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let appPages = (internalPages > purgeable ? internalPages - purgeable : 0) + UInt64(stats.wire_count)
        let cachedPages = UInt64(stats.external_page_count) + purgeable
        return MemoryBreakdown(
            appBytes: appPages * pageSize,
            cachedBytes: cachedPages * pageSize,
            compressedBytes: UInt64(stats.compressor_page_count) * pageSize,
            totalBytes: totalBytes,
            swapUsedBytes: swapUsedBytes
        )
    }

    // MARK: - CPU

    private static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        // Tuple slots follow CPU_STATE_USER, CPU_STATE_SYSTEM, CPU_STATE_IDLE, CPU_STATE_NICE.
        return CPUTicks(
            user: info.cpu_ticks.0,
            system: info.cpu_ticks.1,
            idle: info.cpu_ticks.2,
            nice: info.cpu_ticks.3
        )
    }

    private static func coreTicks() -> [CPUTicks] {
        var processorCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &info,
            &infoCount
        )
        guard result == KERN_SUCCESS, let info else { return [] }
        // The kernel allocates this array in our address space; release it after copying.
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: info)),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        let stride = Int(CPU_STATE_MAX)
        return (0..<Int(processorCount)).map { core in
            let base = core * stride
            return CPUTicks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            )
        }
    }

    /// Reads each core's cluster from the device tree ("cluster-type" "E" or
    /// "P", keyed by "logical-cpu-id"), as exelban/stats does. Core order in
    /// host_processor_info follows the logical id, and efficiency cores are not
    /// always first, so the panel must not guess. Intel Macs have no clusters.
    private static func coreKinds() -> [CPUCoreKind] {
        let cpus = IORegistryEntryFromPath(0, "IODeviceTree:/cpus")
        guard cpus != 0 else { return [] }
        defer { IOObjectRelease(cpus) }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(cpus, "IODeviceTree", &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var kinds: [Int: CPUCoreKind] = [:]
        while true {
            let cpu = IOIteratorNext(iterator)
            guard cpu != 0 else { break }
            defer { IOObjectRelease(cpu) }

            guard let cluster = registryProperty(cpu, "cluster-type") as? Data,
                  let index = littleEndianInteger(registryProperty(cpu, "logical-cpu-id")) else { continue }
            let letter = String(bytes: cluster.prefix { $0 != 0 }, encoding: .utf8) ?? ""
            kinds[index] = letter == "E" ? .efficiency : .performance
        }
        // Only trust a complete, gap-free map; otherwise show cores ungrouped.
        let ordered = (0..<kinds.count).compactMap { kinds[$0] }
        return ordered.count == kinds.count ? ordered : []
    }

    /// Device-tree integers arrive as little-endian Data; some keys come back as NSNumber.
    private static func littleEndianInteger(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        guard let data = value as? Data, !data.isEmpty else { return nil }
        return data.prefix(8).enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) }
    }

    private static func hasHyperThreading() -> Bool {
        guard let physical = sysctlInteger("hw.physicalcpu"),
              let logical = sysctlInteger("hw.logicalcpu") else { return false }
        return logical == physical * 2
    }

    private static func sysctlInteger(_ name: String) -> Int? {
        var value: Int32 = 0
        var length = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &length, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    private static func oneMinuteLoadAverage() -> Double? {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) > 0 else { return nil }
        return loads[0]
    }

    // MARK: - Memory

    private static func memoryBreakdown() -> MemoryBreakdown? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS, let total = physicalMemoryBytes() else { return nil }

        return memoryBreakdown(
            statistics: stats,
            pageSize: UInt64(sysconf(_SC_PAGESIZE)),
            totalBytes: total,
            swapUsedBytes: swapUsedBytes()
        )
    }

    private static func physicalMemoryBytes() -> UInt64? {
        var size: UInt64 = 0
        var length = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &size, &length, nil, 0) == 0 else { return nil }
        return size
    }

    private static func swapUsedBytes() -> UInt64? {
        var usage = xsw_usage()
        var length = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &length, nil, 0) == 0 else { return nil }
        return usage.xsu_used
    }

    // MARK: - GPU

    /// Reads the busiest GPU accelerator in the registry. Apple silicon publishes
    /// "Device Utilization %" and "In use system memory"; older drivers use
    /// "GPU Activity(%)" and "vramUsedBytes".
    private static func gpuStatistics() -> GPUStatistics {
        // Passing 0 selects the default master port, the same value as kIOMainPortDefault
        // (which is unavailable on macOS 11 SDK builds).
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(0, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return GPUStatistics()
        }
        defer { IOObjectRelease(iterator) }

        var best = GPUStatistics()
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }

            // A dual-GPU MacBook Pro powers its discrete GPU off when idle; its
            // last statistics are stale then, so skip it as exelban/stats does.
            if let agc = registryProperty(service, "AGCInfo") as? [String: Any],
               (agc["poweredOffByAGC"] as? Int ?? 0) != 0 {
                continue
            }
            guard let stats = registryProperty(service, "PerformanceStatistics") as? [String: Any],
                  let percent = (stats["Device Utilization %"] ?? stats["GPU Activity(%)"]) as? Int else {
                continue
            }
            let fraction = min(1, max(0, Double(percent) / 100))
            guard fraction >= (best.fraction ?? -1) else { continue }

            let memory = (stats["In use system memory"] ?? stats["vramUsedBytes"]) as? NSNumber
            best = GPUStatistics(
                fraction: fraction,
                coreCount: (registryProperty(service, "gpu-core-count") as? NSNumber)?.intValue,
                memoryInUseBytes: memory.map { $0.uint64Value }
            )
        }
        return best
    }

    private struct GPUStatistics {
        var fraction: Double?
        var coreCount: Int?
        var memoryInUseBytes: UInt64?
    }

    private static func registryProperty(_ service: io_object_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    // MARK: - Disks

    /// Local, writable, user-visible volumes. Read-only volumes are skipped so a
    /// mounted installer image does not appear as a disk, except the boot volume and
    /// internal ones: when booted from an external drive, the internal Mac's sealed
    /// system volume is mounted read-only and its Data volume is hidden, so the
    /// system volume is the only place the internal disk shows up.
    private static func diskVolumes() -> [DiskVolumeUsage] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsInternalKey,
            .volumeIsLocalKey,
            .volumeIsReadOnlyKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        let volumes = urls.compactMap { url -> DiskVolumeUsage? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsLocal ?? false,
                  !(values.volumeIsReadOnly ?? false) || url.path == "/" || values.volumeIsInternal == true,
                  let total = values.volumeTotalCapacity, total > 0 else {
                return nil
            }
            // "Important usage" counts purgeable space as available, as Finder does.
            // Read-only volumes report it as 0, which would read as a full disk.
            let important = values.volumeAvailableCapacityForImportantUsage.map { Int($0) }
            let available = important.flatMap { $0 > 0 ? $0 : nil }
                ?? values.volumeAvailableCapacity
                ?? 0
            return DiskVolumeUsage(
                id: url.path,
                name: values.volumeName ?? url.lastPathComponent,
                isInternal: values.volumeIsInternal ?? (url.path == "/"),
                usedBytes: UInt64(max(0, total - available)),
                totalBytes: UInt64(total)
            )
        }
        // The boot volume first, then internal before external.
        return volumes.sorted { lhs, rhs in
            if (lhs.id == "/") != (rhs.id == "/") { return lhs.id == "/" }
            if lhs.isInternal != rhs.isInternal { return lhs.isInternal }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
