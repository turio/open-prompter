import SwiftUI

struct CaptureStatusModifier: ViewModifier {
    @Environment(AppState.self) private var state
    @AppStorage(PrefKey.recordingFramerate.rawValue) private var fpsRaw = "fps30"

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if state.cameraStore.style != .off {
                    VStack(spacing: 4) {
                        Text("\(captureLabel)   MIC  \(state.audioRouteMonitor.currentRouteName)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        if let warning = state.audioRouteMonitor.inputChangedWarning {
                            Text(warning).font(.system(size: 12, weight: .bold)).foregroundStyle(.yellow)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 62)
                    .allowsHitTesting(false)
                }
            }
            .onChange(of: state.recordingState.isRecording) { _, recording in
                if recording { state.audioRouteMonitor.beginTake() }
                else { state.audioRouteMonitor.endTake() }
            }
    }

    private var captureLabel: String {
        let fps = RecordingFramerate(rawValue: fpsRaw)?.fps ?? 30
        let aspect = (RecordingAspect(rawValue: Prefs.recordingAspect) ?? .default).canonicalShape
        return aspect == .wide ? "4K · \(fps)" : "\(aspect.displayName) · \(fps)"
    }
}
