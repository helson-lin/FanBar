import AppKit
import FanBarShared
import SwiftUI

/// Keeps the current icon visible; alternative appearances live in a native popover.
struct AppIconPickerRow: View {
    @AppStorage(AppIconChoice.preferenceKey)
    private var selectedRawValue = AppIconChoice.classic.rawValue
    @State private var isShowingPicker = false

    private var selection: AppIconChoice {
        AppIconChoice(rawValue: selectedRawValue) ?? .classic
    }

    var body: some View {
        // The section header names the setting and its footer explains where
        // the icon appears; the row only states the current choice.
        HStack(spacing: 12) {
            SettingsRowText(title: selection.title)
            Spacer(minLength: 0)
            iconButton
        }
        .settingsRow()
        .onDisappear { isShowingPicker = false }
    }

    private var iconButton: some View {
        Button {
            isShowingPicker.toggle()
        } label: {
            HStack(spacing: 6) {
                AppIconPreview(choice: selection, size: 36)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(fanBarText("选择 App 图标", "Choose an app icon"))
        .accessibilityValue(selection.title)
        .help(fanBarText("选择 App 图标", "Choose an app icon"))
        .popover(isPresented: $isShowingPicker, arrowEdge: .top) {
            AppIconPicker(selection: selection) { choice in
                AppIconPreferences.select(choice)
                isShowingPicker = false
            }
            .onExitCommand { isShowingPicker = false }
        }
    }
}

private enum AppIconPickerLayout {
    static let tileWidth: CGFloat = 70
    static let spacing: CGFloat = 8
    static let padding: CGFloat = 16
    static let columns = Array(repeating: GridItem(.fixed(tileWidth), spacing: spacing), count: 4)
}

private struct AppIconPicker: View {
    let selection: AppIconChoice
    let onSelect: (AppIconChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            iconGroup(
                title: fanBarText("质感", "Materials"),
                choices: [.classic, .smartisan, .smartisanRings, .aluminum]
            )
            iconGroup(
                title: fanBarText("风格", "Styles"),
                choices: [.flat, .pixel]
            )
        }
        .padding(AppIconPickerLayout.padding)
        .fixedSize()
        .accessibilityElement(children: .contain)
    }

    private func iconGroup(title: String, choices: [AppIconChoice]) -> some View {
        VStack(alignment: .leading, spacing: AppIconPickerLayout.spacing) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: AppIconPickerLayout.columns, alignment: .leading, spacing: AppIconPickerLayout.spacing) {
                ForEach(choices) { choice in
                    AppIconOption(choice: choice, isSelected: choice == selection) {
                        onSelect(choice)
                    }
                }
            }
        }
    }
}

/// Both the trigger and the choices use the same aspect-preserving image treatment.
private struct AppIconPreview: View {
    let choice: AppIconChoice
    let size: CGFloat

    var body: some View {
        Group {
            if let image = choice.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(choice == .pixel ? .none : .high)
                    .scaledToFit()
            } else {
                Image(systemName: "fan")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Selection is named by VoiceOver and a checkmark as well as the accent outline.
private struct AppIconOption: View {
    let choice: AppIconChoice
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 5) {
                AppIconPreview(choice: choice, size: 44)
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: SettingsChrome.cardCornerRadius, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: SettingsChrome.cardCornerRadius, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )
                    .overlay(
                        Group {
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.accentColor)
                                    .background(Circle().fill(Color(NSColor.windowBackgroundColor)))
                                    .accessibilityHidden(true)
                            }
                        },
                        alignment: .bottomTrailing
                    )

                Text(choice.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: AppIconPickerLayout.tileWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
