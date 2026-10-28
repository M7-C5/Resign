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
    @State private var didRotatePersonToMarkNorth = false
    @State private var roomPlanSnapshot: RoomPlanSnapshot?
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
        _roomPlanSnapshot = State(initialValue: room.planSnapshotData.flatMap {
            try? JSONDecoder().decode(RoomPlanSnapshot.self, from: $0)
        })
        _northArrowPlanRotation = State(
            initialValue: NorthAlignmentCalibration.normalized(-room.compass)
        )
    }

    public var body: some View {
        VStack(spacing: 14) {
            header

            VStack(spacing: 6) {
                Text(viewModel.isHeadingLocked ? "North Detected" : "Set Your North")
                    .font(.headline)
                    .foregroundStyle(viewModel.isHeadingLocked ? .green : .primary)

                if viewModel.isHeadingLocked {
                    Label(
                        "Rotate the person in the center so its N arrow shows which way north lies in the scanned room.",
                        systemImage: "hand.draw"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.blue)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 310)
                } else {
                    Text(instruction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
            }

            ScannedRoomPlanView(
                room: room,
                furniture: layout.furnitures.filter { !$0.isArchived },
                openings: room.openings,
                scanPlan: roomPlanSnapshot,
                northArrowPlanRotation: $northArrowPlanRotation,
                isNorthLocked: viewModel.isHeadingLocked,
                didRotatePersonToMarkNorth: $didRotatePersonToMarkNorth
            )
            .frame(maxHeight: 330)
            .accessibilityLabel("Room plan with a rotatable north marker")

            compassSection

            Spacer(minLength: 0)

            Button(action: saveAndContinue) {
                Text(continueButtonTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(canContinue ? Color.accentColor : Color.gray.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!canContinue)
            .accessibilityHint("After north locks, rotate the person in the plan to mark north, then save and continue")
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
        if viewModel.usesManualHeading {
            return "Set the compass to 000° and hold it steady for 2 seconds."
        }
        return "Turn the iPhone until the compass reads 000°, then hold steady for 2 seconds."
    }

    private var canContinue: Bool {
        viewModel.isHeadingLocked && didRotatePersonToMarkNorth
    }

    private var displayedHeadingDegrees: Double? {
        guard let heading = viewModel.headingDegrees else {
            return viewModel.isHeadingLocked ? 0 : nil
        }
        let normalized = NorthAlignmentCalibration.normalized(heading)
        let distanceFromNorth = min(normalized, 360 - normalized)
        return viewModel.isHeadingLocked || distanceFromNorth <= NorthAlignmentCalibration.automaticLockToleranceDegrees
            ? 0
            : normalized
    }

    private var continueButtonTitle: String {
        guard viewModel.isHeadingLocked else { return "Hold Facing North to Lock" }
        return didRotatePersonToMarkNorth ? "Save & Continue" : "Rotate Person to Set North"
    }

    private var compassSection: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 18) {
                NorthCompassDial(headingDegrees: displayedHeadingDegrees, isLocked: viewModel.isHeadingLocked)
                    .frame(width: 116, height: 116)

                VStack(alignment: .leading, spacing: 6) {
                    Text(displayedHeadingDegrees.map {
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
                    } else if viewModel.isHoldingNorth {
                        Text("Hold steady to lock")
                            .font(.caption.weight(.medium))
                        ProgressView(value: viewModel.lockProgress)
                            .tint(.blue)
                            .frame(maxWidth: 150)
                        if viewModel.needsCompassCalibration {
                            Text("Low compass accuracy — move the phone in a figure eight for a better reading")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else if viewModel.needsCompassCalibration {
                        Text("Compass accuracy is low — move the phone in a figure eight, then face north")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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

struct ScannedRoomPlanView: View {
    let room: Room
    let furniture: [Furniture]
    let openings: [RoomOpening]
    let scanPlan: RoomPlanSnapshot?
    @Binding var northArrowPlanRotation: Double
    let isNorthLocked: Bool
    @Binding var didRotatePersonToMarkNorth: Bool
    var showsNorthMarker = true
    var showsAnnotations = true

    @State private var dragStartPointerAngle: Double?
    @State private var dragStartArrowAngle = 0.0

    private var planAspectRatio: CGFloat {
        CGFloat(max(0.5, room.width) / max(0.5, room.length))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if scanPlan == nil || scanPlan?.wallSegments.isEmpty == true {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(red: 0.93, green: 0.92, blue: 0.88))
                        .padding(12)
                }

                if let scanPlan, !scanPlan.wallSegments.isEmpty {
                    Canvas { context, size in
                        for wall in scanPlan.wallSegments {
                            var path = Path()
                            path.move(to: planPoint(localX: wall.startX, localZ: wall.startZ, in: size))
                            path.addLine(to: planPoint(localX: wall.endX, localZ: wall.endZ, in: size))
                            context.stroke(
                                path,
                                with: .color(Color(.darkGray)),
                                style: StrokeStyle(lineWidth: 5, lineCap: .square)
                            )
                        }
                    }
                    .allowsHitTesting(false)
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(.darkGray), lineWidth: 5)
                        .padding(12)
                }

                ForEach(openings) { opening in
                    openingFootprint(opening, in: geometry.size)
                }

                ForEach(furniture) { item in
                    furnitureFootprint(item, in: geometry.size)
                }

                if showsNorthMarker {
                    northMarker
                        .rotationEffect(.degrees(northArrowPlanRotation))
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        .contentShape(Circle())
                        .gesture(rotationGesture(in: geometry.size))
                        .accessibilityLabel("North direction marker")
                }
            }
            .coordinateSpace(name: "orientation-plan")
        }
        .aspectRatio(planAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .topLeading) {
            Text(String(format: "Scan · %.2f × %.2f m", room.width, room.length))
                .opacity(showsAnnotations ? 1 : 0)
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(18)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomLeading) {
            if showsAnnotations, openings.contains(where: { $0.type.lowercased() == "window" || $0.type.lowercased() == "door" }) {
                HStack(spacing: 10) {
                    openingLegend(color: .cyan, title: "Window")
                    openingLegend(color: .orange, title: "Door")
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(18)
                .allowsHitTesting(false)
            }
        }
        .accessibilityHint("After the compass locks, drag the person in the center to point its N arrow toward the room's north direction. The scanned room plan stays fixed.")
    }

    private var northMarker: some View {
        ZStack {
            if isNorthLocked {
                Circle()
                    .stroke(
                        Color.blue.opacity(0.8),
                        style: StrokeStyle(lineWidth: 2, dash: [5, 4])
                    )
                    .frame(width: 104, height: 104)

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.blue)
                    .offset(y: -55)
            }

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
            Text("N")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(.blue)
                .offset(y: -36)
        }
        .frame(width: 110, height: 110)
    }

    private func openingFootprint(_ opening: RoomOpening, in size: CGSize) -> some View {
        let roomWidth = CGFloat(max(0.5, room.width))
        let roomLength = CGFloat(max(0.5, room.length))
        let localPosition = scanPlan?.localCoordinates(worldX: opening.posX, worldZ: opening.posZ)
            ?? SIMD2<Float>(opening.posX, opening.posZ)
        let distanceToXWall = abs(abs(CGFloat(localPosition.x)) - roomWidth / 2)
        let distanceToZWall = abs(abs(CGFloat(localPosition.y)) - roomLength / 2)
        let onVerticalWall = distanceToXWall <= distanceToZWall
        let x = size.width / 2 + CGFloat(localPosition.x) / roomWidth * (size.width - 34)
        let y = size.height / 2 + CGFloat(localPosition.y) / roomLength * (size.height - 34)
        let wallLength = CGFloat(opening.width) / (onVerticalWall ? roomLength : roomWidth)
            * (onVerticalWall ? size.height - 34 : size.width - 34)
        let color: Color
        switch opening.type.lowercased() {
        case "window":
            color = .cyan
        case "door":
            color = .orange
        default:
            color = .purple
        }

        return RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.white, lineWidth: 1)
            }
            .frame(
                width: onVerticalWall ? 9 : max(12, wallLength),
                height: onVerticalWall ? max(12, wallLength) : 9
            )
            .position(x: x, y: y)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func openingLegend(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(color)
                .frame(width: 12, height: 5)
            Text(title)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func furnitureFootprint(_ item: Furniture, in size: CGSize) -> some View {
        let roomWidth = CGFloat(max(0.5, room.width))
        let roomLength = CGFloat(max(0.5, room.length))
        let localPosition = scanPlan?.localCoordinates(worldX: item.positionX, worldZ: item.positionZ)
            ?? SIMD2<Float>(item.positionX, item.positionZ)
        let x = size.width / 2 + CGFloat(localPosition.x) / roomWidth * (size.width - 34)
        let y = size.height / 2 + CGFloat(localPosition.y) / roomLength * (size.height - 34)
        let width = min(size.width - 34, max(8, CGFloat(item.width) / roomWidth * (size.width - 34)))
        let height = min(size.height - 34, max(8, CGFloat(item.length) / roomLength * (size.height - 34)))

        RoundedRectangle(cornerRadius: 5)
            .fill(Color(red: 0.66, green: 0.62, blue: 0.55).opacity(0.78))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(.white.opacity(0.8), lineWidth: 1)
            }
            .overlay {
                if width >= 48, height >= 24 {
                    Text(item.category.capitalized)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .padding(2)
                }
            }
            .frame(width: width, height: height)
            .rotationEffect(.radians(-Double(scanPlan?.localYaw(item.rotationYaw) ?? item.rotationYaw)))
            .position(x: x, y: y)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func rotationGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("orientation-plan"))
            .onChanged { value in
                let pointerAngle = clockwiseAngle(from: CGPoint(x: size.width / 2, y: size.height / 2), to: value.location)
                if dragStartPointerAngle == nil {
                    dragStartPointerAngle = pointerAngle
                    dragStartArrowAngle = northArrowPlanRotation
                }
                guard let dragStartPointerAngle else { return }
                let delta = signedAngleDelta(from: dragStartPointerAngle, to: pointerAngle)
                let updatedRotation = NorthAlignmentCalibration.normalized(dragStartArrowAngle + delta)
                if isNorthLocked,
                   abs(signedAngleDelta(from: northArrowPlanRotation, to: updatedRotation)) >= 4 {
                    didRotatePersonToMarkNorth = true
                }
                northArrowPlanRotation = updatedRotation
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

    private func planPoint(localX: Float, localZ: Float, in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width / 2 + CGFloat(localX / max(0.5, room.width)) * (size.width - 34),
            y: size.height / 2 + CGFloat(localZ / max(0.5, room.length)) * (size.height - 34)
        )
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

#Preview("Compass States") {
    HStack(spacing: 24) {
        VStack(spacing: 8) {
            NorthCompassDial(headingDegrees: 0, isLocked: true)
                .frame(width: 116, height: 116)
            Text("North locked")
                .font(.caption)
        }

        VStack(spacing: 8) {
            NorthCompassDial(headingDegrees: 135, isLocked: false)
                .frame(width: 116, height: 116)
            Text("Reading heading")
                .font(.caption)
        }
    }
    .padding(24)
    .background(Color(.systemBackground))
}

#Preview("Orientation Setup — Full Screen") {
    let container = try! ModelContainer.createInMemoryContainer()
    let room = Room(name: "Sample Bedroom")
    let layout = Layout(name: "Bedroom Layout")
    let walls = [
        ScannedWallPayload(position: [0, 1.3, -2.1], dimensions: [5.0, 2.6, 0.1], rotationYaw: 0),
        ScannedWallPayload(position: [0, 1.3, 2.1], dimensions: [5.0, 2.6, 0.1], rotationYaw: .pi),
        ScannedWallPayload(position: [2.5, 1.3, 0], dimensions: [4.2, 2.6, 0.1], rotationYaw: .pi / 2),
        ScannedWallPayload(position: [-2.5, 1.3, 0], dimensions: [4.2, 2.6, 0.1], rotationYaw: -.pi / 2)
    ]
    room.planSnapshotData = try? JSONEncoder().encode(RoomPlanSnapshot(walls: walls, floorLevel: 0))
    room.openings = [
        RoomOpening(type: "window", posX: room.width / 2, posY: 1.4, posZ: -0.5, width: 1.3, height: 1.2),
        RoomOpening(type: "door", posX: 0.5, posY: 1.0, posZ: room.length / 2, width: 0.9, height: 2.0)
    ]
    room.layouts.append(layout)
    layout.furnitures = [
        Furniture(
            name: "Bed",
            category: "bed",
            positionX: -0.7,
            positionZ: -0.55,
            length: 1.8,
            width: 2.0
        ),
        Furniture(
            name: "Desk",
            category: "desk",
            positionX: 0.9,
            positionZ: -1.0,
            length: 1.3,
            width: 0.65
        ),
        Furniture(
            name: "Sofa",
            category: "sofa",
            positionX: 0.8,
            positionZ: 1.15,
            length: 1.7,
            width: 0.8
        )
    ]
    container.mainContext.insert(room)

    return OrientationView(layout: layout, room: room)
        .modelContainer(container)
}
