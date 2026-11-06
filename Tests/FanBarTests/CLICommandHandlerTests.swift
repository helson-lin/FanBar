import FanBarShared
import Foundation
import Testing
@testable import FanBar

@MainActor
struct CLICommandHandlerTests {
    private let custom = UUID()

    private var presets: [CoolingPresetSummary] {
        FanCoolingPreset.allCases.map {
            CoolingPresetSummary(id: .builtIn($0), title: $0.title, systemImage: $0.systemImage)
        } + [CoolingPresetSummary(id: .custom(custom), title: "Late Night", systemImage: "moon.fill")]
    }

    @Test func builtInKeysWorkInEveryLanguage() {
        #expect(CLICommandHandler.resolvePreset("performance", in: presets) == .builtIn(.performance))
        #expect(CLICommandHandler.resolvePreset("  EXTREME ", in: presets) == .builtIn(.extreme))
    }

    @Test func tokensAndTitlesResolve() {
        #expect(CLICommandHandler.resolvePreset("builtin:0", in: presets) == .builtIn(.silent))
        #expect(CLICommandHandler.resolvePreset("late night", in: presets) == .custom(custom))
        #expect(CLICommandHandler.resolvePreset("custom:\(custom.uuidString)", in: presets) == .custom(custom))
        #expect(CLICommandHandler.resolvePreset(FanCoolingPreset.balanced.title, in: presets) == .builtIn(.balanced))
    }

    @Test func unknownOrDeletedPresetsDoNotResolve() {
        #expect(CLICommandHandler.resolvePreset("turbo", in: presets) == nil)
        #expect(CLICommandHandler.resolvePreset("", in: presets) == nil)
        #expect(CLICommandHandler.resolvePreset("custom:\(UUID().uuidString)", in: presets) == nil)
    }
}
