import FanBarShared
import Foundation

/// One cell of the panel's monitoring area.
enum PanelMonitorModule: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case gpu
    case disk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: fanBarText("内存", "Memory")
        case .gpu: "GPU"
        case .disk: fanBarText("启动盘", "Startup disk")
        }
    }

    /// What the cell shows, for the Add menu where the module isn't visible yet.
    var detail: String {
        switch self {
        case .cpu: fanBarText("总体负载与性能核、能效核", "Overall load, performance and efficiency cores")
        case .memory: fanBarText("应用、压缩与缓存", "App, compressed and cached memory")
        case .gpu: fanBarText("负载与显存", "Load and graphics memory")
        case .disk: fanBarText("剩余空间，可展开查看所有磁盘", "Free space; expand to see every disk")
        }
    }
}

/// Which monitoring modules the panel shows, in order. Zero modules hides the area.
enum PanelMonitorPreferences {
    static let preferenceKey = "fanbar.panelMonitorModules.v1"
    static let defaultModules = PanelMonitorModule.allCases

    /// A missing key means the default set; an empty string means the user cleared it.
    /// Unknown tokens (from a newer build) are skipped and repeats keep their first place.
    static func modules(from rawValue: String?) -> [PanelMonitorModule] {
        guard let rawValue else { return defaultModules }
        var seen = Set<PanelMonitorModule>()
        return rawValue.split(separator: ",").compactMap { token in
            PanelMonitorModule(rawValue: token.trimmingCharacters(in: .whitespaces))
        }.filter { seen.insert($0).inserted }
    }

    /// Reveal a menu-bar target for this presentation without changing saved preferences.
    static func presentedModules(_ modules: [PanelMonitorModule], focusing: PanelMonitorModule?) -> [PanelMonitorModule] {
        guard let focusing, !modules.contains(focusing) else { return modules }
        return modules + [focusing]
    }

    static func rawValue(for modules: [PanelMonitorModule]) -> String {
        modules.map(\.rawValue).joined(separator: ",")
    }

    static func missing(from modules: [PanelMonitorModule]) -> [PanelMonitorModule] {
        PanelMonitorModule.allCases.filter { !modules.contains($0) }
    }

    /// Moves `module` into `target`'s place; the modules in between shift by one.
    static func moving(
        _ module: PanelMonitorModule,
        to target: PanelMonitorModule,
        in modules: [PanelMonitorModule]
    ) -> [PanelMonitorModule] {
        guard module != target,
              let from = modules.firstIndex(of: module),
              let to = modules.firstIndex(of: target) else { return modules }
        var result = modules
        result.remove(at: from)
        result.insert(module, at: to)
        return result
    }

    /// One step up (`-1`) or down (`1`); nil when the module is already at that end.
    static func moving(
        _ module: PanelMonitorModule,
        by offset: Int,
        in modules: [PanelMonitorModule]
    ) -> [PanelMonitorModule]? {
        guard let index = modules.firstIndex(of: module),
              modules.indices.contains(index + offset) else { return nil }
        return moving(module, to: modules[index + offset], in: modules)
    }

    /// Rows of the two-column grid. An odd last module gets a row to itself and spans it.
    static func rows(_ modules: [PanelMonitorModule]) -> [[PanelMonitorModule]] {
        stride(from: 0, to: modules.count, by: 2).map {
            Array(modules[$0..<min($0 + 2, modules.count)])
        }
    }
}
