import SwiftUI

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct EditorView: View {
    @ObservedObject var project: Project
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = EditorViewModel()
    @StateObject private var exportViewModel = ExportViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            editorToolbar

            Divider()

            // Main content: Preview + Inspector
            HSplitView {
                // Preview area
                previewArea
                    .frame(minWidth: 500)

                // Inspector sidebar
                InspectorView(
                    settings: $project.effectSettings,
                    onSettingsChanged: {
                        project.saveState()
                        viewModel.regenerateZoomKeyframes()
                    }
                )
                .frame(width: 280)
            }

            Divider()

            // Timeline
            timelineArea
        }
        .onAppear {
            viewModel.loadProject(project)
        }
        .overlay {
            if exportViewModel.isExporting {
                exportOverlay
            }
        }
        .sheet(item: $exportViewModel.exportedURL) { url in
            exportCompleteSheet(url: url)
        }
        .onCommand(#selector(UndoManager.undo)) {
            if project.canUndo {
                project.undo()
                viewModel.regenerateZoomKeyframes()
            }
        }
        .onCommand(#selector(UndoManager.redo)) {
            if project.canRedo {
                project.redo()
                viewModel.regenerateZoomKeyframes()
            }
        }
    }

    private var exportOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView(value: exportViewModel.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 300)

                Text("Exporting... \(Int(exportViewModel.progress * 100))%")
                    .font(.headline)
                    .foregroundStyle(.white)

                Button("Cancel") {
                    exportViewModel.cancel()
                }
                .buttonStyle(.bordered)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
        }
    }

    private func exportCompleteSheet(url: URL) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Export Complete")
                .font(.title2)
                .fontWeight(.semibold)

            Text(url.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Show in Finder") {
                    exportViewModel.revealInFinder(url: url)
                    exportViewModel.exportedURL = nil
                }
                .buttonStyle(.borderedProminent)

                Button("Done") {
                    exportViewModel.exportedURL = nil
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(32)
    }

    private var editorToolbar: some View {
        HStack {
            Button {
                appState.backToSetup()
            } label: {
                Label("New Recording", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)

            Spacer()

            // Playback controls
            HStack(spacing: 16) {
                Button {
                    viewModel.seek(to: project.trimRange.startSeconds)
                } label: {
                    Image(systemName: "backward.end.fill")
                }
                .buttonStyle(.borderless)

                Button {
                    viewModel.togglePlayback()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.space, modifiers: [])

                Button {
                    viewModel.seek(to: project.trimRange.endSeconds)
                } label: {
                    Image(systemName: "forward.end.fill")
                }
                .buttonStyle(.borderless)
            }

            Spacer()

            HStack(spacing: 8) {
                Picker("", selection: $exportViewModel.format) {
                    ForEach(ExportFormat.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 100)

                Picker("", selection: $exportViewModel.resolution) {
                    ForEach(ExportResolution.allCases, id: \.self) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .frame(width: 90)

                Button {
                    exportViewModel.export(project: project)
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var previewArea: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor).opacity(0.3)

            if let image = viewModel.previewImage {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(20)
                    .shadow(radius: 10)
            } else {
                ProgressView()
                    .scaleEffect(1.5)
            }
        }
    }

    private var timelineArea: some View {
        VStack(spacing: 8) {
            // Time display
            HStack {
                Text(formatTime(viewModel.currentTime - project.trimRange.startSeconds))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(formatTime(project.trimmedDuration))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Thumbnails strip
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Thumbnail strip
                    HStack(spacing: 1) {
                        ForEach(Array(viewModel.thumbnails.enumerated()), id: \.offset) { _, thumb in
                            Image(decorative: thumb, scale: 1.0)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 50)
                                .clipped()
                        }
                    }
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    // Trim handles
                    trimHandles(width: geometry.size.width)

                    // Playhead
                    playhead(width: geometry.size.width)
                }
                .frame(height: 50)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = max(0, min(1, value.location.x / geometry.size.width))
                            viewModel.scrub(fraction: fraction)
                        }
                )
            }
            .frame(height: 50)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func trimHandles(width: CGFloat) -> some View {
        let duration = project.recording.durationSeconds
        let startFraction = project.trimRange.startSeconds / duration
        let endFraction = project.trimRange.endSeconds / duration

        return ZStack(alignment: .leading) {
            // Dimmed areas outside trim range
            Rectangle()
                .fill(.black.opacity(0.5))
                .frame(width: CGFloat(startFraction) * width)

            Rectangle()
                .fill(.black.opacity(0.5))
                .frame(width: (1.0 - CGFloat(endFraction)) * width)
                .offset(x: CGFloat(endFraction) * width)

            // Start handle
            RoundedRectangle(cornerRadius: 2)
                .fill(.yellow)
                .frame(width: 4, height: 50)
                .offset(x: CGFloat(startFraction) * width)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let fraction = max(0, min(value.location.x / width, project.trimRange.endSeconds / duration - 0.01))
                            project.trimRange.startSeconds = fraction * duration
                            viewModel.seek(to: project.trimRange.startSeconds)
                        }
                )

            // End handle
            RoundedRectangle(cornerRadius: 2)
                .fill(.yellow)
                .frame(width: 4, height: 50)
                .offset(x: CGFloat(endFraction) * width - 4)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let fraction = max(project.trimRange.startSeconds / duration + 0.01, min(1.0, value.location.x / width))
                            project.trimRange.endSeconds = fraction * duration
                        }
                )
        }
    }

    private func playhead(width: CGFloat) -> some View {
        let duration = project.recording.durationSeconds
        let fraction = viewModel.currentTime / duration

        return Rectangle()
            .fill(.white)
            .frame(width: 2, height: 56)
            .shadow(color: .black.opacity(0.5), radius: 2)
            .offset(x: CGFloat(fraction) * width)
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
