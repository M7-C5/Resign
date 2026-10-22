import SwiftUI

/// Edits session-only choices; the presenter owns confirm and discard behavior.
struct LightingSimulationSheet: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var settings: LightingSimulationSettings
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
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

                HStack(spacing: 10) {
                    Text("Off")
                    Toggle("Artificial lights", isOn: $settings.artificialLightsOn)
                        .labelsHidden()
                        .tint(.green)
                    Text("On")
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                LightingTimeSlider(minuteOfDay: $settings.minuteOfDay)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.medium, .large] : [.height(230)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(.regularMaterial)
    }
}

private struct LightingTimeSlider: View {
    @Binding var minuteOfDay: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Text("Day")
                .padding(.bottom, 12)
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    let thumbInset: CGFloat = 16
                    let fraction = CGFloat(minuteOfDay) / 1439
                    Text(LightingSimulationSettings(minuteOfDay: minuteOfDay).timeLabel)
                        .font(.caption)
                        .monospacedDigit()
                        .fixedSize()
                        .position(
                            x: max(24, min(geometry.size.width - 24,
                                thumbInset + fraction * max(0, geometry.size.width - 2 * thumbInset))),
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
                .accessibilityValue(LightingSimulationSettings(minuteOfDay: minuteOfDay).timeLabel)
            }
            Text("Night")
                .padding(.bottom, 12)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
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
