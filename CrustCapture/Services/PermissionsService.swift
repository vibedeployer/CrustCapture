import ScreenCaptureKit
import AVFoundation
import AppKit

@MainActor
class PermissionsService: ObservableObject {
    @Published var screenCaptureGranted = false
    @Published var microphoneGranted = false

    func checkPermissions() {
        screenCaptureGranted = CGPreflightScreenCaptureAccess()
        checkMicrophonePermission()
    }

    func requestScreenCapture() {
        // Open Screen Recording privacy settings directly
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func requestMicrophone() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneGranted = granted
    }

    private func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneGranted = true
        default:
            microphoneGranted = false
        }
    }
}
