import SwiftUI

/// Edits session-only lighting choices. The presenter decides what confirm and discard do.
struct LightingSimulationSheet: View {
    static let collapsedHeight: CGFloat = 230

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var settings: LightingSimulationSettings
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                artificialLightRow
                TimeOfDaySlider(
                    minuteOfDay: $settings.minuteOfDay,
                    windowDirection: settings.solarContext.windowCompassDirection
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .presentationDetents(
            dynamicTypeSize.isAccessibilitySize ? [.medium, .large] : [.height(Self.collapsedHeight)]
        )
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(.regularMaterial)
        .presentationBackgroundInteraction(.enabled(upThrough: .height(Self.collapsedHeight)))
    }

    private var header: some View {
        HStack {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color(.systemGray5), in: Circle())
            }
            .accessibilityLabel("Discard lighting changes")

            Spacer(minLength: 8)
            Text("Lighting Simulation")
                .font(.headline)
                .multilineTextAlignment(.center)
            Spacer(minLength: 8)

            Button(action: onConfirm) {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.blue, in: Circle())
            }
            .accessibilityLabel("Confirm lighting changes")
        }
        .buttonStyle(.plain)
    }

    private var artificialLightRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Off")
                Toggle("Artificial lights", isOn: $settings.artificialLightsOn)
                    .labelsHidden()
                    .tint(.orange)
                Text("On")
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TimeOfDaySlider: View {
    @Binding var minuteOfDay: Int
    let windowDirection: String

    private var label: String {
        LightingSimulationSettings(minuteOfDay: minuteOfDay).timeLabel
    }

    var body: some View {
        VStack {
            HStack(alignment: .bottom, spacing: 10) {
                Text("Day")
                    .padding(.bottom, 12)

                VStack(spacing: 0) {
                    GeometryReader { geometry in
                        let thumbInset: CGFloat = 16
                        let fraction = CGFloat(minuteOfDay) / 1439
                        let usableWidth = max(0, geometry.size.width - 2 * thumbInset)
                        Text(label)
                            .font(.caption)
                            .monospacedDigit()
                            .fixedSize()
                            .position(
                                x: max(24, min(geometry.size.width - 24, thumbInset + fraction * usableWidth)),
                                y: 8
                            )
                    }
                    .frame(height: 18)

                    Slider(
                        value: Binding(
                            get: { Double(minuteOfDay) },
                            set: { minuteOfDay = Int($0.rounded()) }
                        ),
                        in: 0...1439,
                        step: 1
                    )
                    .tint(.blue)
                    .accessibilityLabel("Time of day")
                    .accessibilityValue(label)
                }

                Text("Night")
                    .padding(.bottom, 12)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("Natural light from \(windowDirection) window")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Lighting Simulation Modal") {
    @Previewable @State var isPresented = true
    @Previewable @State var settings = LightingSimulationSettings()

    Color(.systemBackground)
        .sheet(isPresented: $isPresented) {
            LightingSimulationSheet(
                settings: $settings,
                onCancel: { isPresented = false },
                onConfirm: { isPresented = false }
            )
        }
}
