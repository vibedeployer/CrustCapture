import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            switch appState.mode {
            case .setup:
                RecordingSetupView()
                    .transition(.opacity)

            case .recording:
                RecordingOverlayView()
                    .transition(.opacity)

            case .editing:
                if let project = appState.currentProject {
                    EditorView(project: project)
                        .transition(.opacity)
                }

            case .exporting:
                if let project = appState.currentProject {
                    ExportView(project: project)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.mode)
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    func showError(_ message: String) {
        errorMessage = message
        showError = true
    }
}
