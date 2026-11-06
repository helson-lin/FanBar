import CoreImage
import XCTest
@testable import FanBar

@MainActor
final class MenuBarIconRotorTests: XCTestCase {
    /// Regression (issue #63): a CIImage input made Core Animation build an
    /// in-process Core Image Metal context, about 180 MB of footprint.
    func testEraserFilterHasNoImageInputs() {
        let filter = MenuBarIconRotor.makeEraserFilter()
        for key in filter.inputKeys {
            XCTAssertFalse(filter.value(forKey: key) is CIImage, "\(key) is a CIImage")
        }
    }

    func testEraserFilterClearsTheBackdrop() throws {
        let filter = MenuBarIconRotor.makeEraserFilter()
        filter.setValue(CIImage(color: CIColor.red).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4)),
                        forKey: kCIInputImageKey)
        let output = try XCTUnwrap(filter.outputImage)
        var pixel = [UInt8](repeating: 255, count: 4)
        CIContext(options: [.useSoftwareRenderer: true]).render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 1, y: 1, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        XCTAssertEqual(pixel, [0, 0, 0, 0])
    }
}
