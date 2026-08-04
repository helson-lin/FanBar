import AppKit
import FanBarShared
import Foundation
import ServiceManagement

@MainActor
final class FanController: ObservableObject {
    enum Mode: Equatable {
        case automatic
        case fixed(Int)
        case extreme
    }

    enum HelperState: Equatable {
        case enabled
        case requiresApproval
        case notRegistered
        case unavailable

        var title: String {
            switch self {
            case .enabled: "控制服务已启用"
            case .requiresApproval: "等待系统批准控制服务"
            case .notRegistered: "尚未启用控制服务"
            case .unavailable: "应用包缺少控制服务"
            }
        }
    }

    @Published private(set) var fans: [FanReading] = []
    @Published private(set) var mode: Mode = .automatic
    @Published private(set) var message = "正在读取风扇…"
    @Published private(set) var isAvailable = false
    @Published private(set) var isBusy = false
    @Published private(set) var helperState: HelperState = .notRegistered
    @Published private(set) var temperatureHistory: [ThermalReading] = []
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginRequiresApproval = false

    private var localClient: SMCClient?
    private let helperClient = HelperClient()
    private let helperService = SMAppService.daemon(plistName: FanBarService.helperPlistName)
    private let loginItemService = SMAppService.mainApp
    private var refreshTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private let maximumTemperatureSamples = 90

    var statusIcon: String {
        mode == .automatic ? "fan" : "fan.fill"
    }

    init() {
        refreshHelperStatus()
        refreshLaunchAtLoginStatus()
        connectAndRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                switch self.mode {
                case .automatic:
                    break
                case .fixed(let rpm):
                    self.setFixedRPM(rpm)
                case .extreme:
                    self.setExtreme()
                }
            }
        }
    }

    func refresh() {
        refreshHelperStatus()
        refreshLaunchAtLoginStatus()
        guard let localClient else { connectAndRefresh(); return }
        do {
            fans = try localClient.fans()
            appendTemperature(localClient.thermalReading())
            isAvailable = true
            if mode == .automatic {
                // Permission state has its own actionable row; keep the header focused on fan mode.
                message = "由 macOS 自动管理"
            }
        } catch {
            isAvailable = false
            message = error.localizedDescription
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try loginItemService.register()
            } else {
                try loginItemService.unregister()
            }
            refreshLaunchAtLoginStatus()
            if launchAtLoginRequiresApproval {
                message = "请在“登录项与扩展”中允许 FanBar"
            }
        } catch {
            refreshLaunchAtLoginStatus()
            message = "无法更新登录项：\(error.localizedDescription)"
        }
    }

    func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func enableHelper() {
        do {
            try helperService.register()
            refreshHelperStatus()
            if helperState == .requiresApproval {
                message = "请在“登录项与扩展”中允许 FanBar"
                SMAppService.openSystemSettingsLoginItems()
            } else {
                message = helperState.title
            }
        } catch {
            refreshHelperStatus()
            message = "无法注册控制服务：\(error.localizedDescription)"
            if helperState == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
    }

    func openHelperSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func setFixedRPM(_ rpm: Int) {
        guard helperState == .enabled, !isBusy else {
            message = "请先启用并批准控制服务"
            return
        }
        isBusy = true
        message = "正在切换到 \(rpm) RPM…"
        Task {
            do {
                try await helperClient.setAllFans(rpm: rpm)
                mode = .fixed(rpm)
                message = "固定目标：\(rpm) RPM"
                if let readings = try? await helperClient.fans() {
                    fans = readings
                }
            } catch {
                message = "控制失败：\(error.localizedDescription)"
            }
            isBusy = false
        }
    }

    func setExtreme() {
        guard helperState == .enabled, !isBusy else {
            message = "请先启用并批准控制服务"
            return
        }
        isBusy = true
        message = "正在切换到极速模式…"
        Task {
            do {
                try await helperClient.setAllFansToEightyPercent()
                mode = .extreme
                message = "极速模式：各风扇最大转速的 80%"
                if let readings = try? await helperClient.fans() {
                    fans = readings
                }
            } catch {
                message = "控制失败：\(error.localizedDescription)"
            }
            isBusy = false
        }
    }

    func setAutomatic() {
        guard helperState == .enabled, !isBusy else {
            mode = .automatic
            message = helperState.title
            return
        }
        isBusy = true
        message = "正在恢复自动控制…"
        Task {
            do {
                try await helperClient.restoreAutomatic()
                mode = .automatic
                message = "已恢复 macOS 自动控制"
                if let readings = try? await helperClient.fans() {
                    fans = readings
                }
            } catch {
                message = "恢复失败：\(error.localizedDescription)"
            }
            isBusy = false
        }
    }

    func quit() {
        Task {
            if helperState == .enabled {
                try? await helperClient.restoreAutomatic()
            }
            NSApplication.shared.terminate(nil)
        }
    }

    private func connectAndRefresh() {
        do {
            localClient = try SMCClient()
            refresh()
        } catch {
            isAvailable = false
            message = error.localizedDescription
        }
    }

    private func refreshHelperStatus() {
        switch helperService.status {
        case .enabled:
            helperState = .enabled
        case .requiresApproval:
            helperState = .requiresApproval
        case .notRegistered:
            helperState = .notRegistered
        case .notFound:
            // SMAppService reports notFound before the bundled daemon's first registration.
            helperState = .notRegistered
        @unknown default:
            helperState = .unavailable
        }
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLoginEnabled = loginItemService.status == .enabled
        launchAtLoginRequiresApproval = loginItemService.status == .requiresApproval
    }

    private func appendTemperature(_ reading: ThermalReading) {
        guard reading.cpuCelsius != nil || reading.gpuCelsius != nil else { return }
        temperatureHistory.append(reading)
        if temperatureHistory.count > maximumTemperatureSamples {
            temperatureHistory.removeFirst(temperatureHistory.count - maximumTemperatureSamples)
        }
    }
}
