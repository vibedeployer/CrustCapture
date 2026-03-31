import SwiftUI

struct RecordingOverlayView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: RecordingViewModel

    @State private var pulseAnimation = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Recording indicator
            VStack(spacing: 16) {
                // Pulsing red dot
                ZStack {
                    Circle()
                        .fill(.red.opacity(0.2))
                        .frame(width: 80, height: 80)
                        .scaleEffect(pulseAnimation ? 1.3 : 1.0)

                    Circle()
                        .fill(.red.opacity(0.4))
                        .frame(width: 50, height: 50)
                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)

                    Circle()
                        .fill(.red)
                        .frame(width: 24, height: 24)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        pulseAnimation = true
                    }
                }

                Text("Recording")
                    .font(.title)
                    .fontWeight(.semibold)

                Text(viewModel.formattedDuration)
                    .font(.system(size: 48, weight: .light, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            Spacer()

            // Stop button
            Button {
                Task { await viewModel.stopRecording(appState: appState) }
            } label: {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white)
                        .frame(width: 16, height: 16)

                    Text("Stop Recording")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)

            // Keyboard shortcut hint
            Text("or press \u{2318}+Shift+R")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
