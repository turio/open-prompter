import XCTest
import CoreGraphics
@testable import OpenPrompter

final class PersonalCaptureTests: XCTestCase {
    func testPersonalDefaultsAndLegacyFPS() throws {
        XCTAssertEqual(RecordingFramerate.default, .fps30)
        XCTAssertEqual(RecordingFramerate.surfacedCases, [.fps30, .fps60])
        XCTAssertEqual(try JSONDecoder().decode(RecordingFramerate.self, from: Data("\"fps24\"".utf8)), .fps24)
        XCTAssertEqual(RecordingAspect.default, .wide)
        XCTAssertEqual(PrefKey.recordingQuality.defaultValue as? String, "high")
    }

    private func format(_ w: Int, _ h: Int, _ fps: Double, dynamic: Bool = false) -> CameraStore.FormatDescriptor {
        .init(width: w, height: h, frameRateRanges: [(min: 24, max: fps)],
              supportsDynamicAspectRatios: dynamic,
              dynamicAspectRatios: dynamic ? ["AVCaptureAspectRatio9x16"] : [])
    }

    func test4K60WinsOverHD60() {
        let result = CameraStore.pickCaptureFormat(descriptors: [format(1920, 1080, 60), format(3840, 2160, 60)], preferredFPS: 60, userAspect: .wide)
        XCTAssertEqual(result?.index, 1)
    }

    func test4K30DoesNotFallBackToHD60() {
        XCTAssertNil(CameraStore.pickCaptureFormat(descriptors: [format(1920, 1080, 60), format(3840, 2160, 30)], preferredFPS: 60, userAspect: .wide))
    }

    func testDynamicPriorityAndLargestCandidateRemainDeterministic() {
        let formats = [format(4096, 3072, 60), format(3840, 2160, 60, dynamic: true), format(4032, 3024, 60, dynamic: true)]
        let result = CameraStore.pickCaptureFormat(descriptors: formats, preferredFPS: 60, userAspect: .wide)
        XCTAssertEqual(result?.index, 2)
        XCTAssertEqual(result?.dynamicAspectRaw, "AVCaptureAspectRatio9x16")
    }

    func testPresentationUsesTransformAndRejectsWrongShapeOrHD() {
        XCTAssertTrue(PersonalCaptureContract.validWidePresentation(width: 3840, height: 2160, transform: .init(rotationAngle: .pi / 2), portrait: true))
        XCTAssertTrue(PersonalCaptureContract.validWidePresentation(width: 2160, height: 3840, transform: .identity, portrait: true))
        XCTAssertFalse(PersonalCaptureContract.validWidePresentation(width: 3840, height: 2160, transform: .identity, portrait: true))
        XCTAssertFalse(PersonalCaptureContract.validWidePresentation(width: 4032, height: 3024, transform: .init(rotationAngle: .pi / 2), portrait: true))
        XCTAssertFalse(PersonalCaptureContract.validWidePresentation(width: 1080, height: 1920, transform: .identity, portrait: true))
    }
}
