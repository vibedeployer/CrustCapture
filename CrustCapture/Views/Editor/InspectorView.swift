import SwiftUI

struct InspectorView: View {
    @Binding var settings: EffectSettings
    var onSettingsChanged: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Background section
                inspectorSection("Background") {
                    backgroundPicker
                }

                Divider()

                // Appearance section
                inspectorSection("Appearance") {
                    sliderRow("Corner Radius", value: $settings.cornerRadius, range: 0...30, onChange: onSettingsChanged)
                    sliderRow("Padding", value: $settings.padding, range: 0...80, onChange: onSettingsChanged)
                    sliderRow("Shadow", value: $settings.shadowRadius, range: 0...40, onChange: onSettingsChanged)
                    sliderRow("Shadow Opacity", value: Binding(
                        get: { CGFloat(settings.shadowOpacity) },
                        set: { settings.shadowOpacity = Double($0) }
                    ), range: 0...1, onChange: onSettingsChanged)
                }

                Divider()

                // Cursor section
                inspectorSection("Cursor") {
                    Toggle("Cursor Highlight", isOn: Binding(
                        get: { settings.cursorStyle.highlightEnabled },
                        set: { settings.cursorStyle.highlightEnabled = $0; onSettingsChanged() }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    if settings.cursorStyle.highlightEnabled {
                        ColorPicker("Color", selection: Binding(
                            get: { settings.cursorStyle.highlightColor },
                            set: { settings.cursorStyle.highlightColor = $0; onSettingsChanged() }
                        ))
                        .controlSize(.small)

                        sliderRow("Size", value: Binding(
                            get: { settings.cursorStyle.highlightRadius },
                            set: { settings.cursorStyle.highlightRadius = $0 }
                        ), range: 10...60, onChange: onSettingsChanged)

                        Toggle("Click Pulse", isOn: Binding(
                            get: { settings.cursorStyle.clickPulseEnabled },
                            set: { settings.cursorStyle.clickPulseEnabled = $0; onSettingsChanged() }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                }

                Divider()

                // Auto Zoom section
                inspectorSection("Auto Zoom") {
                    Toggle("Enable Auto Zoom", isOn: Binding(
                        get: { settings.autoZoomEnabled },
                        set: { settings.autoZoomEnabled = $0; onSettingsChanged() }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    if settings.autoZoomEnabled {
                        sliderRow("Zoom Level", value: $settings.autoZoomScale, range: 1.2...4.0, onChange: onSettingsChanged)

                        Text("Automatically zooms into click locations for a polished look")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Background Picker

    @State private var customBgColor1 = Color(red: 0.2, green: 0.2, blue: 0.5)
    @State private var customBgColor2 = Color(red: 0.5, green: 0.2, blue: 0.8)

    private var backgroundPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 50, maximum: 60), spacing: 8)
            ], spacing: 8) {
                ForEach(Array(BackgroundStyle.presets.enumerated()), id: \.offset) { _, preset in
                    Button {
                        settings.background = preset.1
                        onSettingsChanged()
                    } label: {
                        backgroundPreview(style: preset.1, name: preset.0)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            Text("Custom")
                .font(.caption)
                .foregroundStyle(.tertiary)

            HStack(spacing: 8) {
                ColorPicker("", selection: $customBgColor1)
                    .labelsHidden()
                    .frame(width: 30)
                ColorPicker("", selection: $customBgColor2)
                    .labelsHidden()
                    .frame(width: 30)

                Button("Apply") {
                    settings.background = .gradient(customBgColor1, customBgColor2, 135)
                    onSettingsChanged()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Solid") {
                    settings.background = .solid(customBgColor1)
                    onSettingsChanged()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func backgroundPreview(style: BackgroundStyle, name: String) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundFill(for: style))
                .frame(height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected(style) ? Color.accentColor : Color.clear, lineWidth: 2)
                )

            Text(name)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func backgroundFill(for style: BackgroundStyle) -> some ShapeStyle {
        switch style {
        case .solid(let color):
            return AnyShapeStyle(color)
        case .gradient(let start, let end, let angle):
            let radians = Angle(degrees: angle)
            return AnyShapeStyle(
                LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        case .wallpaper:
            return AnyShapeStyle(Color.gray)
        }
    }

    private func isSelected(_ style: BackgroundStyle) -> Bool {
        settings.background == style
    }

    // MARK: - Helpers

    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            content()
        }
    }

    private func sliderRow(_ label: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>, onChange: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text(String(format: "%.1f", value.wrappedValue))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Slider(value: value, in: range)
                .controlSize(.small)
                .onChange(of: value.wrappedValue) {
                    onChange()
                }
        }
    }
}
