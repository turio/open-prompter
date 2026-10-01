import AVFoundation
import CoreGraphics

/// Pure checks shared by format selection, preflight and the actual first frame.
enum PersonalCaptureContract {
    static func is4K(width: Int, height: Int) -> Bool {
        min(width, height) >= 2160 && max(width, height) >= 3840
    }

    static func validWidePresentation(width: Int, height: Int,
                                      transform: CGAffineTransform, portrait: Bool) -> Bool {
        let bounds = CGRect(x: 0, y: 0, width: width, height: height).applying(transform)
        let w = abs(bounds.width).rounded()
        let h = abs(bounds.height).rounded()
        let targetRatio = portrait ? 9.0 / 16.0 : 16.0 / 9.0
        return is4K(width: Int(w), height: Int(h)) && abs(w / h - targetRatio) < 0.01
    }

    static func unavailableMessage(fps: Int) -> String {
        "4K \(fps) isn't available on the current front-camera format. " +
        (fps == 60 ? "Switch to 30 fps." : "Choose a supported front-camera format.")
    }
}

struct CapturePreflightSnapshot: Sendable {
    let cameraName: String
    let cameraID: String
    let rawWidth: Int
    let rawHeight: Int
    let fps: Int
    let aspect: String
    let orientation: String
    let preferredMic: String
    let actualMic: String
    let actualMicID: String
    let actualMicType: String

    var debugDescription: String {
        "camera=\(cameraName) [\(cameraID)] raw=\(rawWidth)x\(rawHeight) fps=\(fps) " +
        "aspect=\(aspect) hold=\(orientation) HEVC Rec.709 SDR " +
        "preferredMic=\(preferredMic) actualMic=\(actualMic) [\(actualMicID)] type=\(actualMicType) " +
        "speech=SFSpeechBackend source=AVCaptureAudioDataOutput shared fork"
    }
}
