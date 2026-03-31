import SwiftUI

struct RecordingSetupView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: RecordingViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Main content
            ScrollView {
                VStack(spacing: 24) {
                    // Permissions warning — only show after loading finishes with no sources
                    if !viewModel.screenCaptureGranted && !viewModel.isLoadingSources {
                        permissionBanner
                    }

                    // Source picker
                    sourcePickerSection

                    // Options
                    optionsSection
                }
                .padding(24)
            }

            Divider()

            // Footer with record button
            footerView
        }
        .task {
            await viewModel.setup()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
        .overlay {
            if viewModel.isCountingDown {
                CountdownView(value: viewModel.countdownValue)
            }
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("CrustCapture")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Select a screen or window to record")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await viewModel.refreshSources() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .help("Refresh sources")
        }
        .padding(20)
    }

    private var permissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Screen Recording Permission Required")
                    .fontWeight(.medium)
                Text("Allow CrustCapture in the system prompt to get started")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ProgressView()
                .controlSize(.small)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.1))
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private var sourcePickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sources")
                .font(.headline)

            if viewModel.screenCaptureService.availableSources.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        if viewModel.isLoadingSources {
                            ProgressView()
                                .controlSize(.large)
                            Text("Loading sources...")
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "rectangle.dashed")
                                .font(.system(size: 40))
                                .foregroundStyle(.tertiary)
                            Text("No sources available")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(40)
                    Spacer()
                }
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 12)
                ], spacing: 12) {
                    ForEach(viewModel.screenCaptureService.availableSources) { source in
                        SourceCard(
                            source: source,
                            isSelected: viewModel.selectedSource == source
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.selectedSource = source
                            }
                        }
                    }
                }
            }
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Options")
                .font(.headline)

            HStack(spacing: 20) {
                // Frame rate
                HStack(spacing: 8) {
                    Image(systemName: "film")
                        .foregroundStyle(.secondary)
                    Picker("Frame Rate", selection: $viewModel.frameRate) {
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }

                Divider()
                    .frame(height: 20)

                // Microphone
                Toggle(isOn: $viewModel.includeMicrophone) {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.includeMicrophone ? "mic.fill" : "mic.slash")
                            .foregroundStyle(viewModel.includeMicrophone ? Color.accentColor : Color.secondary)
                        Text("Microphone")
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Divider()
                    .frame(height: 20)

                // Hide window
                Toggle(isOn: $viewModel.hideWindowDuringRecording) {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.hideWindowDuringRecording ? "eye.slash" : "eye")
                            .foregroundStyle(viewModel.hideWindowDuringRecording ? Color.accentColor : Color.secondary)
                        Text("Hide Window")
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Divider()
                    .frame(height: 20)

                // Crop title bar
                HStack(spacing: 8) {
                    Toggle(isOn: $viewModel.cropTitleBar) {
                        HStack(spacing: 6) {
                            Image(systemName: "crop")
                                .foregroundStyle(viewModel.cropTitleBar ? Color.accentColor : Color.secondary)
                            Text("Crop Top")
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    if viewModel.cropTitleBar {
                        Stepper("\(viewModel.cropTopAmount)px", value: $viewModel.cropTopAmount, in: 0...200, step: 4)
                            .font(.caption)
                            .frame(width: 100)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    private var footerView: some View {
        HStack {
            if let source = viewModel.selectedSource {
                Label(source.title, systemImage: source.isDisplay ? "display" : "macwindow")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                Task { await viewModel.startRecording(appState: appState) }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                    Text("Start Recording")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(viewModel.selectedSource == nil)
        }
        .padding(20)
    }
}

// MARK: - Source Card

struct SourceCard: View {
    let source: CaptureSource
    let isSelected: Bool
    let action: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Live preview thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .aspectRatio(16/9, contentMode: .fit)

                    if let thumbnail = thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Image(systemName: source.isDisplay ? "display" : "macwindow")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                    }
                }
                .aspectRatio(16/9, contentMode: .fit)
                .task {
                    // Initial load with retry
                    await loadThumbnail()
                    // Refresh every 3 seconds for live preview
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if let image = source.captureThumbnail() {
                            thumbnail = image
                        }
                    }
                }

                // Title
                Text(source.title)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)

                // Dimensions
                Text("\(Int(source.frame.width))x\(Int(source.frame.height))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected
                        ? Color.accentColor.opacity(0.1)
                        : Color(nsColor: .controlBackgroundColor))
                    .stroke(isSelected
                        ? Color.accentColor
                        : Color(nsColor: .separatorColor),
                        lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func loadThumbnail() async {
        // Retry until we get a thumbnail (permission may still be propagating)
        for _ in 1...10 {
            let image = source.captureThumbnail()
            if let image {
                thumbnail = image
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}
