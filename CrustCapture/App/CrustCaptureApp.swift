import SwiftUI

@main
struct CrustCaptureApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var recordingViewModel = RecordingViewModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(recordingViewModel)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    appDelegate.appState = appState
                    appDelegate.recordingViewModel = recordingViewModel
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 750)
        .commands {
            CommandGroup(after: .toolbar) {
                Button(appState.mode == .recording ? "Stop Recording" : "Start Recording") {
                    Task { @MainActor in
                        if appState.mode == .recording {
                            await recordingViewModel.stopRecording(appState: appState)
                        } else if appState.mode == .setup && recordingViewModel.selectedSource != nil {
                            await recordingViewModel.startRecording(appState: appState)
                        }
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

// MARK: - App Delegate for Menu Bar

class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?
    var recordingViewModel: RecordingViewModel?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "CrustCapture")
            button.image?.size = NSSize(width: 16, height: 16)
        }

        updateMenu()

        // Update menu periodically to reflect state changes
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMenu()
        }
    }

    private func updateMenu() {
        let menu = NSMenu()

        Task { @MainActor [weak self] in
            guard let self = self, let appState = self.appState, let vm = self.recordingViewModel else { return }

            if appState.mode == .recording {
                // Update icon to red circle when recording
                self.statusItem?.button?.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")

                let durationItem = NSMenuItem(title: "Recording: \(vm.formattedDuration)", action: nil, keyEquivalent: "")
                durationItem.isEnabled = false
                menu.addItem(durationItem)

                menu.addItem(NSMenuItem.separator())

                let stopItem = NSMenuItem(title: "Stop Recording", action: #selector(self.stopRecording), keyEquivalent: "")
                stopItem.target = self
                menu.addItem(stopItem)
            } else {
                self.statusItem?.button?.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "CrustCapture")

                if vm.selectedSource != nil && appState.mode == .setup {
                    let startItem = NSMenuItem(title: "Start Recording", action: #selector(self.startRecording), keyEquivalent: "")
                    startItem.target = self
                    menu.addItem(startItem)
                } else {
                    let noSourceItem = NSMenuItem(title: "Select a source first", action: nil, keyEquivalent: "")
                    noSourceItem.isEnabled = false
                    menu.addItem(noSourceItem)
                }

                menu.addItem(NSMenuItem.separator())

                let showItem = NSMenuItem(title: "Show Window", action: #selector(self.showWindow), keyEquivalent: "")
                showItem.target = self
                menu.addItem(showItem)
            }

            menu.addItem(NSMenuItem.separator())

            let quitItem = NSMenuItem(title: "Quit CrustCapture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            menu.addItem(quitItem)

            self.statusItem?.menu = menu
        }
    }

    @objc private func startRecording() {
        Task { @MainActor in
            guard let appState = appState, let vm = recordingViewModel else { return }
            await vm.startRecording(appState: appState)
        }
    }

    @objc private func stopRecording() {
        Task { @MainActor in
            guard let appState = appState, let vm = recordingViewModel else { return }
            await vm.stopRecording(appState: appState)
        }
    }

    @objc private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
}
