import SwiftUI

struct ExportView: View {
    @ObservedObject var project: Project
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ExportViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button {
                    appState.finishExport()
                } label: {
                    Label("Back to Editor", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isExporting)

                Spacer()

                Text("Export")
                    .font(.headline)

                Spacer()

                // Spacer for symmetry
                Color.clear.frame(width: 120)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            Spacer()

            if viewModel.isExporting {
                exportProgress
            } else {
                exportSettings
            }

            Spacer()
        }
    }

    private var exportSettings: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "film")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Export your recording")
                .font(.title2)
                .fontWeight(.semibold)

            // Settings
            VStack(spacing: 16) {
                HStack {
                    Text("Codec")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $viewModel.codec) {
                        ForEach(ExportCodec.allCases, id: \.self) { codec in
                            Text(codec.rawValue).tag(codec)
                        }
                    }
                    .frame(width: 180)
                }

                HStack {
                    Text("Quality")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $viewModel.quality) {
                        ForEach(ExportQuality.allCases, id: \.self) { quality in
                            Text(quality.rawValue).tag(quality)
                        }
                    }
                    .frame(width: 220)
                }

                HStack {
                    Text("Duration")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatDuration(project.trimmedDuration))
                        .foregroundStyle(.primary)
                }

                HStack {
                    Text("Resolution")
                        .foregroundStyle(.secondary)
                    Spacer()
                    let p = project.effectSettings.padding
                    Text("\(project.recording.width + Int(p * 2)) x \(project.recording.height + Int(p * 2))")
                        .foregroundStyle(.primary)
                }
            }
            .padding(20)
            .frame(width: 400)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            // Export button
            Button {
                viewModel.export(project: project)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export MP4")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let error = viewModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var exportProgress: some View {
        VStack(spacing: 20) {
            // Animated icon
            Image(systemName: "gearshape.2")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
                .rotationEffect(.degrees(viewModel.progress * 360))

            Text("Exporting...")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 8) {
                ProgressView(value: viewModel.progress)
                    .frame(width: 300)

                Text("\(Int(viewModel.progress * 100))%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Button("Cancel") {
                viewModel.cancel()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
