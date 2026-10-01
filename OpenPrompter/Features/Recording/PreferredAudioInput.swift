import AVFoundation
import Foundation

/// Session port UIDs and capture device IDs are separate namespaces.
enum PreferredAudioInput {
    struct Identity: Equatable, Sendable {
        let id: String
        let name: String
        let isBuiltIn: Bool
    }

    static func selectedPort(pin: String, ports: [Identity]) -> Identity? {
        if pin == "auto" { return nil }
        if pin == "builtin" { return ports.first { $0.isBuiltIn } }
        return ports.first { $0.id == pin }
    }

    /// A name bridge is allowed only for the actual active port, and only
    /// when its exact name identifies a single capture device.
    static func captureDevice(active: Identity, devices: [Identity]) -> Identity? {
        if let exact = devices.first(where: { $0.id == active.id }) { return exact }
        let matches = devices.filter { $0.name == active.name }
        return matches.count == 1 ? matches.first : nil
    }

    static func routeMatches(pin: String, selected: Identity?, active: Identity?) -> Bool {
        if pin == "auto" { return active != nil }
        guard let selected, let active else { return false }
        return selected.id == active.id
    }

    static var savedName: String? {
        get { UserDefaults.standard.string(forKey: "pref.recording.micSourceName") }
        set { UserDefaults.standard.set(newValue, forKey: "pref.recording.micSourceName") }
    }

    static func identity(_ port: AVAudioSessionPortDescription) -> Identity {
        .init(id: port.uid, name: port.portName, isBuiltIn: port.portType == .builtInMic)
    }

    static func missingMessage(pin: String) -> String {
        let label = savedName ?? (pin == "builtin" ? "Built-in Microphone" : "Selected microphone")
        return "\(label) is selected but isn't connected. Reconnect it or choose Built-in Microphone in Camera & Recording settings."
    }

    /// Called before capture configuration or a take. Never substitutes a
    /// disconnected explicit pin; recording preflight verifies the route.
    @MainActor
    static func applyPreference() throws {
        let session = AVAudioSession.sharedInstance()
        let pin = Prefs.recordingMicSource ?? "builtin"
        if pin == "auto" { try session.setPreferredInput(nil); return }
        guard let selected = selectedPort(pin: pin, ports: (session.availableInputs ?? []).map(identity)),
              let port = session.availableInputs?.first(where: { $0.uid == selected.id }) else {
            throw RecordingSessionError.writerSetupFailed(missingMessage(pin: pin))
        }
        try session.setPreferredInput(port)
    }

    @MainActor
    static func validateActiveRoute(captureDevice: AVCaptureDevice?) throws {
        let session = AVAudioSession.sharedInstance()
        let pin = Prefs.recordingMicSource ?? "builtin"
        let selected = selectedPort(pin: pin, ports: (session.availableInputs ?? []).map(identity))
        let active = session.currentRoute.inputs.first.map(identity)
        guard routeMatches(pin: pin, selected: selected, active: active) else {
            throw RecordingSessionError.writerSetupFailed(missingMessage(pin: pin))
        }
        guard let active, let device = captureDevice,
              Self.captureDevice(active: active, devices: [
                .init(id: device.uniqueID, name: device.localizedName, isBuiltIn: false)
              ]) != nil else {
            throw RecordingSessionError.writerSetupFailed("The active microphone couldn't be verified against the capture input. Turn the camera off and on, then reconnect or select your microphone.")
        }
        #if DEBUG
        print("[AudioRoute] session=\(active.name) [\(active.id)] capture=\(device.localizedName) [\(device.uniqueID)]")
        #endif
    }
}
