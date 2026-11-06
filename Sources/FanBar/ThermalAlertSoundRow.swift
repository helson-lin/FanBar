import FanBarShared
import SwiftUI

/// Mirrors the system alert-sound picker: choosing a sound plays it, and
/// the speaker button replays it without reopening the menu.
struct ThermalAlertSoundRow: View {
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    @ObservedObject var controller: FanController

    var body: some View {
        let sound = controller.highTemperatureAlertSound
        return HStack(spacing: 8) {
            SettingsRowText(
                title: fanBarText("提示音", "Sound"),
                detail: fanBarText(
                    "选择具体声音后，即使系统关闭了通知声音或开启了专注模式也会播放。",
                    "A chosen sound plays even when notification sounds are off or a Focus is on."
                )
            )
            Spacer(minLength: 12)
            Button(action: controller.previewHighTemperatureAlertSound) {
                Image(systemName: "speaker.wave.2")
            }
            .buttonStyle(.borderless)
            .disabled(sound.systemSoundName == nil)
            .help(fanBarText("试听", "Preview"))
            .accessibilityLabel(fanBarText("试听", "Preview"))
            Picker(
                fanBarText("提示音", "Sound"),
                selection: Binding(
                    get: { controller.highTemperatureAlertSound },
                    set: { controller.setHighTemperatureAlertSound($0) }
                )
            ) {
                Text(ThermalAlertSound.notificationDefault.title).tag(ThermalAlertSound.notificationDefault)
                Text(ThermalAlertSound.silent.title).tag(ThermalAlertSound.silent)
                Divider()
                ForEach(ThermalAlertSound.systemSoundNames, id: \.self) { name in
                    Text(name).tag(ThermalAlertSound.system(name))
                }
            }
            .labelsHidden()
            .id(languageRawValue)
            .frame(minWidth: SettingsChrome.trailingControlMinWidth)
            .fixedSize()
        }
        .settingsRow()
        .disabled(!controller.highTemperatureNotificationsEnabled)
        .environment(\.locale, (FanBarLanguage(rawValue: languageRawValue) ?? .system).locale)
    }
}
