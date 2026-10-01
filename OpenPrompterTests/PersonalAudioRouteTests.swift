import XCTest
@testable import OpenPrompter

final class PersonalAudioRouteTests: XCTestCase {
    private let builtin = PreferredAudioInput.Identity(id: "phone-port", name: "iPhone Microphone", isBuiltIn: true)
    private let dji = PreferredAudioInput.Identity(id: "usb-port", name: "DJI Mic Mini", isBuiltIn: false)

    func testExplicitPinPresentAndMissing() {
        XCTAssertEqual(PreferredAudioInput.selectedPort(pin: "usb-port", ports: [builtin, dji]), dji)
        XCTAssertNil(PreferredAudioInput.selectedPort(pin: "usb-port", ports: [builtin]))
        XCTAssertFalse(PreferredAudioInput.routeMatches(pin: "usb-port", selected: dji, active: builtin))
        XCTAssertTrue(PreferredAudioInput.routeMatches(pin: "usb-port", selected: dji, active: dji))
    }

    func testBuiltInAndAuto() {
        XCTAssertEqual(PreferredAudioInput.selectedPort(pin: "builtin", ports: [dji, builtin]), builtin)
        XCTAssertNil(PreferredAudioInput.selectedPort(pin: "auto", ports: [dji, builtin]))
        XCTAssertTrue(PreferredAudioInput.routeMatches(pin: "auto", selected: nil, active: dji))
        XCTAssertFalse(PreferredAudioInput.routeMatches(pin: "auto", selected: nil, active: nil))
    }

    func testCaptureIDBridgeRequiresUniqueExactActiveName() {
        let capture = PreferredAudioInput.Identity(id: "capture-id", name: "DJI Mic Mini", isBuiltIn: false)
        XCTAssertEqual(PreferredAudioInput.captureDevice(active: dji, devices: [capture, builtin]), capture)
        XCTAssertNil(PreferredAudioInput.captureDevice(active: dji, devices: [builtin]))
        XCTAssertNil(PreferredAudioInput.captureDevice(active: dji, devices: [capture, .init(id: "other-id", name: capture.name, isBuiltIn: false)]))
        XCTAssertNil(PreferredAudioInput.captureDevice(active: dji, devices: [.init(id: "wireless", name: "Wireless microphone", isBuiltIn: false)]))
        XCTAssertEqual(PreferredAudioInput.captureDevice(active: dji, devices: [dji, capture]), dji)
    }
}
