import AppKit
import FanBarShared

/// User-selectable app icons. `classic` is the bundle's own `FanBar.icns`;
/// the others ship as PNGs in `Contents/Resources/AppIcons`.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case classic
    case smartisan
    case smartisanRings = "smartisan-rings"
    case aluminum
    case flat
    case pixel

    static let preferenceKey = "fanbar.appIcon"

    var id: String { rawValue }

    static var current: AppIconChoice {
        UserDefaults.standard.string(forKey: preferenceKey).flatMap(AppIconChoice.init) ?? .classic
    }

    var title: String {
        switch self {
        case .classic: return fanBarText("经典", "Classic")
        case .smartisan: return fanBarText("陶瓷", "Ceramic")
        case .smartisanRings: return fanBarText("陶瓷·纹理", "Ceramic Lined")
        case .aluminum: return fanBarText("铝合金", "Aluminum")
        case .flat: return fanBarText("深色", "Dark")
        case .pixel: return fanBarText("像素", "Pixel")
        }
    }

    var image: NSImage? {
        switch self {
        case .classic:
            return Bundle.main.image(forResource: "FanBar")
        default:
            return Bundle.main.url(forResource: rawValue, withExtension: "png", subdirectory: "AppIcons")
                .flatMap(NSImage.init(contentsOf:))
        }
    }
}

@MainActor
enum AppIconPreferences {
    static func select(_ choice: AppIconChoice) {
        UserDefaults.standard.set(choice.rawValue, forKey: AppIconChoice.preferenceKey)
        apply(choice)
    }

    /// Re-applied at launch because a Sparkle update replaces the bundle and
    /// with it the custom Finder icon.
    static func applyAtLaunch() {
        let choice = AppIconChoice.current
        guard choice != .classic else { return }
        apply(choice)
    }

    private static func apply(_ choice: AppIconChoice) {
        let customImage = choice == .classic ? nil : choice.image
        // `nil` restores the bundle icon for in-app surfaces (menu panel header, alerts).
        // Those draw at 64pt at most, and FanBar has no Dock tile, so a
        // decoded 1024px icon would hold ~4 MB for nothing.
        NSApplication.shared.applicationIconImage = customImage.map(inAppIcon(from:))
        // Finder, Launchpad and Spotlight read the icon from disk. Only touch a
        // real app bundle; `swift run` executables have nothing to decorate.
        let bundlePath = Bundle.main.bundlePath
        guard bundlePath.hasSuffix(".app") else { return }
        NSWorkspace.shared.setIcon(customImage, forFile: bundlePath, options: [])
    }

    /// Largest in-app use is the 64pt alert icon; 128pt @2x leaves headroom.
    private static let inAppIconPointSize: CGFloat = 128

    private static func inAppIcon(from image: NSImage) -> NSImage {
        let pointSize = NSSize(width: inAppIconPointSize, height: inAppIconPointSize)
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pointSize.width * 2),
            pixelsHigh: Int(pointSize.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return image }
        representation.size = pointSize
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: representation) else { return image }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: pointSize))
        let scaled = NSImage(size: pointSize)
        scaled.addRepresentation(representation)
        return scaled
    }
}
