import SwiftData
import SwiftUI

/// Calibrates a scanned room to north before users place its light sources.
public struct OrientationView: View {
    @Environment(\.modelContext) private var modelContext

    private let layout: Layout
    private let room: Room
    private let onSave: () -> Void
    private let onBack: () -> Void

    @State private var viewModel = OrientationViewModel()
    @State private var northArrowPlanRotation: Double
    @State private var showBackConfirmation = false
    @State private var saveError: String?

    public init(
        layout: Layout,
        room: Room,
        onSave: @escaping () -> Void = {},
        onBack: @escaping () -> Void = {}
    ) {
        self.layout = layout
        self.room = room
        self.onSave = onSave
        self.onBack = onBack
        _northArrowPlanRotation = State(
            initialValue: NorthAlignmentCalibration.normalized(-room.compass)
        )
    }

    public var body: some View {
        VStack(spacing: 14) {
            header

            VStack(spacing: 4) {
                Text("Set Your North")
                    .font(.headline)
                Text(instruction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            OrientationPlanView(
                room: room,
                furniture: layout.furnitures.filter { !$0.isArchived },
                northArrowPlanRotation: $northArrowPlanRotation
            )
            .frame(maxHeight: 330)
            .accessibilityLabel("Room plan with a rotatable north marker")

            compassSection

            Spacer(minLength: 0)

            Button(action: saveAndContinue) {
                Text("Save & Continue")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(viewModel.isHeadingLocked ? Color.accentColor : Color.gray.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!viewModel.isHeadingLocked)
            .accessibilityHint("Save the room's north direction and continue to add light sources")
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(
            "Discard room orientation?",
            isPresented: $showBackConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard and Go Back", role: .destructive, action: onBack)
            Button("Keep Editing", role: .cancel) {}
        }
        .alert("Could not save room orientation", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "Unknown error")
        }
        .task {
            viewModel.start()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                viewModel.tick()
            }
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    private var header: some View {
        HStack {
            Button {
                showBackConfirmation = true
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel("Back")

            Spacer()
            Text(layout.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
    }

    private var instruction: String {
        if viewModel.isHeadingLocked {
            return "Drag around the person to point it toward north."
        }
        if viewModel.usesManualHeading {
            return "Set the compass heading to north and hold it steady to lock."
        }
        return "Turn with your iPhone until it faces north. Hold steady for 2 seconds to lock."
    }

    private var compassSection: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 18) {
                NorthCompassDial(headingDegrees: viewModel.headingDegrees, isLocked: viewModel.isHeadingLocked)
                    .frame(width: 116, height: 116)

                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.headingDegrees.map {
                        let degrees = Int(NorthAlignmentCalibration.normalized($0).rounded()) % 360
                        return String(format: "%03d°", degrees)
                    } ?? "---°")
                        .font(.title2.monospacedDigit().weight(.semibold))
                    Text(viewModel.headingReference.isEmpty ? "Finding compass…" : viewModel.headingReference)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let accuracy = viewModel.headingAccuracy {
                        Text("Accuracy ±\(Int(accuracy.rounded()))°")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if viewModel.isHeadingLocked {
                        Label("North locked", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    } else if viewModel.needsCompassCalibration {
                        Text("Calibrate compass by moving the phone in a figure eight")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if viewModel.isHoldingNorth {
                        Text("Hold steady to lock")
                            .font(.caption.weight(.medium))
                        ProgressView(value: viewModel.lockProgress)
                            .tint(.blue)
                            .frame(maxWidth: 150)
                    } else {
                        Text("Face the phone toward north")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if viewModel.usesManualHeading, !viewModel.isHeadingLocked {
                VStack(spacing: 2) {
                    Slider(
                        value: Binding(
                            get: { viewModel.headingDegrees ?? 180 },
                            set: { viewModel.setManualHeading($0) }
                        ),
                        in: 0...359,
                        step: 1
                    )
                    .accessibilityLabel("Manual compass heading")
                    Text("Compass sensor unavailable — set the reading manually")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func saveAndContinue() {
        guard viewModel.isHeadingLocked else { return }
        room.compass = NorthAlignmentCalibration.roomHeadingDegrees(
            northArrowPlanRotationDegrees: northArrowPlanRotation
        )
        room.updatedAt = Date()
        layout.updatedAt = Date()

        do {
            try modelContext.save()
            onSave()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct OrientationPlanView: View {
    let room: Room
    let furniture: [Furniture]
    @Binding var northArrowPlanRotation: Double

    @State private var dragStartPointerAngle: Double?
    @State private var dragStartArrowAngle = 0.0

    private var planAspectRatio: CGFloat {
        CGFloat(max(0.5, room.width) / max(0.5, room.length))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.93, green: 0.92, blue: 0.88))
                    .padding(12)

                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(.darkGray), lineWidth: 5)
                    .padding(12)

                ForEach(furniture) { item in
                    furnitureFootprint(item, in: geometry.size)
                }

                northMarker
                    .rotationEffect(.degrees(northArrowPlanRotation))
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .accessibilityLabel("North direction marker")
            }
            .contentShape(Rectangle())
            .gesture(rotationGesture(in: geometry.size))
        }
        .aspectRatio(planAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .top) {
            Text("N")
                .font(.caption.weight(.bold))
                .foregroundStyle(.blue)
                .padding(.top, 16)
                .allowsHitTesting(false)
        }
        .accessibilityHint("Drag anywhere on the plan to rotate the centered person toward north. The room plan does not move.")
    }

    private var northMarker: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.92))
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
            Image(systemName: "figure.stand")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.primary)
                .offset(y: 7)
            Image(systemName: "arrow.up")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.blue)
                .offset(y: -23)
        }
        .frame(width: 84, height: 84)
    }

    @ViewBuilder
    private func furnitureFootprint(_ item: Furniture, in size: CGSize) -> some View {
        let roomWidth = CGFloat(max(0.5, room.width))
        let roomLength = CGFloat(max(0.5, room.length))
        let x = size.width / 2 + CGFloat(item.positionX) / roomWidth * (size.width - 34)
        let y = size.height / 2 + CGFloat(item.positionZ) / roomLength * (size.height - 34)
        let width = min(size.width * 0.42, max(12, CGFloat(item.length) / roomWidth * (size.width - 34)))
        let height = min(size.height * 0.42, max(12, CGFloat(item.width) / roomLength * (size.height - 34)))

        RoundedRectangle(cornerRadius: 5)
            .fill(Color(red: 0.66, green: 0.62, blue: 0.55).opacity(0.78))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(.white.opacity(0.8), lineWidth: 1)
            }
            .frame(width: width, height: height)
            .rotationEffect(.radians(Double(item.rotationYaw)))
            .position(x: x, y: y)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func rotationGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let pointerAngle = clockwiseAngle(from: CGPoint(x: size.width / 2, y: size.height / 2), to: value.location)
                if dragStartPointerAngle == nil {
                    dragStartPointerAngle = pointerAngle
                    dragStartArrowAngle = northArrowPlanRotation
                }
                guard let dragStartPointerAngle else { return }
                let delta = signedAngleDelta(from: dragStartPointerAngle, to: pointerAngle)
                northArrowPlanRotation = NorthAlignmentCalibration.normalized(dragStartArrowAngle + delta)
            }
            .onEnded { _ in
                dragStartPointerAngle = nil
            }
    }

    private func clockwiseAngle(from center: CGPoint, to point: CGPoint) -> Double {
        atan2(Double(point.x - center.x), Double(center.y - point.y)) * 180 / .pi
    }

    private func signedAngleDelta(from start: Double, to current: Double) -> Double {
        let delta = (current - start).truncatingRemainder(dividingBy: 360)
        return delta > 180 ? delta - 360 : (delta < -180 ? delta + 360 : delta)
    }
}

private struct NorthCompassDial: View {
    let headingDegrees: Double?
    let isLocked: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(.systemBackground))
                .overlay { Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1) }

            ForEach(0..<36, id: \.self) { tick in
                Capsule()
                    .fill(tick.isMultiple(of: 3) ? Color.primary.opacity(0.55) : Color.secondary.opacity(0.3))
                    .frame(width: 2, height: tick.isMultiple(of: 3) ? 8 : 4)
                    .offset(y: -49)
                    .rotationEffect(.degrees(Double(tick) * 10 - (headingDegrees ?? 0)))
            }

            compassLabel("N", bearing: 0)
            compassLabel("E", bearing: 90)
            compassLabel("S", bearing: 180)
            compassLabel("W", bearing: 270)

            Circle()
                .fill(isLocked ? Color.green : Color.blue)
                .frame(width: 7, height: 7)
        }
        .padding(4)
        .overlay(alignment: .top) {
            Image(systemName: "triangle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isLocked ? .green : .blue)
                .offset(y: -1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Compass")
        .accessibilityValue(headingDegrees.map {
            let degrees = Int(NorthAlignmentCalibration.normalized($0).rounded()) % 360
            return "\(degrees) degrees"
        } ?? "Unavailable")
    }

    private func compassLabel(_ title: String, bearing: Double) -> some View {
        let angle = (bearing - (headingDegrees ?? 0)) * .pi / 180
        let center: CGFloat = 58
        let radius: CGFloat = 38
        return Text(title)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(title == "N" ? .red : .secondary)
            .frame(width: 16, height: 16)
            .position(
                x: center + radius * CGFloat(sin(angle)),
                y: center - radius * CGFloat(cos(angle))
            )
    }
}
