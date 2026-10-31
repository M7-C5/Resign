//
//  LightingSetupView.swift
//  Resign
//

import SwiftUI
import SwiftData

/// The "Add Your Light Source" screen — Phase 4 of the Resign onboarding flow.
///
/// Presents adaptive ceiling placement points over the scanned plan where the user:
/// 1. Taps cells to place light fixtures (auto-named "Lighting N").
/// 2. Selects a placed light to adjust Color Temperature (2200–6500 K)
///    and Brightness (500–3000 lm) via sliders in a bottom panel.
/// 3. Deletes fixtures via the trash icon with a confirmation dialog.
/// 4. Confirms "Save & Continue" to persist all drafts into the given `Layout`.
/// 5. Can discard and go back with another confirmation dialog.
///
/// All grid edits operate on transient `LightDraft` value types. SwiftData is
/// only written to when the user confirms "Save & Continue".
///
/// - SeeAlso: `LightingSetupViewModel`
/// - SeeAlso: ADR 0011 — LightDraft Transient Value Type for Ceiling Grid Editing
public struct LightingSetupView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The `Layout` record that will receive the saved `Light` objects.
    var layout: Layout

    /// Called after all drafts have been successfully persisted.
    /// If nil, default `dismiss()` is performed.
    var onSave: (() -> Void)?

    /// Called after the user confirms the "Go Back" discard dialog.
    /// If nil, default `dismiss()` is performed.
    var onBack: (() -> Void)?

    @State private var viewModel = LightingSetupViewModel()

    private var scanPlan: RoomPlanSnapshot? {
        layout.room?.planSnapshotData.flatMap { try? JSONDecoder().decode(RoomPlanSnapshot.self, from: $0) }
    }

    private var planBounds: RoomPlanBounds {
        RoomPlanBounds(snapshot: scanPlan, fallbackWidth: layout.room?.width ?? 5,
                       fallbackLength: layout.room?.length ?? 4.2)
    }

    private var roomAspectRatio: CGFloat { CGFloat(planBounds.width / planBounds.length) }

    private var roomBoundary: CeilingLightPlacementGrid {
        CeilingLightPlacementGrid(bounds: planBounds, walls: scanPlan?.wallSegments ?? [], openings: planOpenings)
    }

    private var planOpenings: [CeilingLightPlacementGrid.Opening] {
        guard let scanPlan else { return [] }
        return (layout.room?.openings ?? []).map {
            .init(center: scanPlan.localCoordinates(worldX: $0.posX, worldZ: $0.posZ), width: $0.width)
        }
    }

    private var outsideDrafts: [LightDraft] {
        viewModel.drafts.filter { !roomBoundary.allowsPlacement(at: $0.unitPosition) }
    }

    public init(
        layout: Layout,
        onSave: (() -> Void)? = nil,
        onBack: (() -> Void)? = nil
    ) {
        self.layout = layout
        self.onSave = onSave
        self.onBack = onBack
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                VStack(spacing: 6) { headerView }
                    .frame(maxWidth: 1280)
                    .frame(maxWidth: .infinity)
                placementWorkspace(in: geometry.size)
            }
        }
        .background(Color(.systemBackground))
        .navigationBarHidden(true)
        .onAppear { viewModel.loadFromLayout(layout) }
        .alert("Are you sure you want to save & continue?", isPresented: $viewModel.showSaveConfirm) {
            Button("No", role: .cancel) {}
            Button("Yes") { performSave() }
        } message: {
            Text("Your changes will be saved.")
        }
        .alert("Are you sure you want to go back?", isPresented: $viewModel.showBackConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Back", role: .destructive) {
                if let onBack {
                    onBack()
                } else {
                    dismiss()
                }
            }
        } message: {
            Text("Your changes wouldn't be saved.")
        }
        .alert("Are you sure you want to delete this light source?", isPresented: $viewModel.showDeleteConfirm) {
            Button("No", role: .cancel) {}
            Button("Yes", role: .destructive) { viewModel.deleteSelectedDraft() }
        } message: {
            Text("Your changes would not be saved.")
        }
        .alert("Could not save lights", isPresented: Binding(
            get: { viewModel.saveError != nil },
            set: { if !$0 { viewModel.saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.saveError ?? "Unknown error")
        }
    }

    @ViewBuilder
    private func placementWorkspace(in size: CGSize) -> some View {
        let workspace = LightingWorkspaceLayout(size: size, accessibilityText: dynamicTypeSize.isAccessibilitySize)
        if workspace.usesSidePanel {
            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    gridView
                        .frame(maxWidth: min(size.width - workspace.panelWidth - 48,
                                             max(240, size.height - 100) * roomAspectRatio))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                ScrollView {
                    VStack(spacing: 16) {
                        if !outsideDrafts.isEmpty { outsideLightsList }
                        bottomPanel
                    }
                    .padding(.top, 16)
                }
                .frame(width: workspace.panelWidth)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24))
            }
            .padding(16)
            .frame(maxWidth: 1440)
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    gridView
                        .frame(maxWidth: min(680, size.height * 0.58 * roomAspectRatio))
                        .frame(maxWidth: .infinity)
                    VStack(spacing: 16) {
                        if !outsideDrafts.isEmpty { outsideLightsList }
                        bottomPanel
                    }
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerView: some View {
        ZStack {
            Text("Add Your Light Source")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 52)
            HStack {
                Button {
                    viewModel.showBackConfirm = true
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back")
                Spacer()
            }
        }
        .padding(.horizontal, 12)

        Text("Tap a point inside your room to add a light source.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 4)
    }

    // MARK: - Adaptive Placement

    @ViewBuilder
    private var gridView: some View {
        GeometryReader { geometry in
            ZStack {
                if let room = layout.room {
                    ScannedRoomPlanView(
                        room: room, furniture: layout.furnitures.filter { !$0.isArchived }, openings: room.openings,
                        scanPlan: scanPlan,
                        showsAnnotations: false
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }

                // Dim only the room so the light markers and their glow stay vivid.
                Color.black.opacity(0.15)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                ForEach(emptyPlacementPoints(in: geometry.size), id: \.self) { point in
                    placementButton(at: point, isCenter: point == SIMD2<Float>(0.5, 0.5))
                        .frame(width: 44, height: 44)
                        .position(screenPoint(point, in: geometry.size))
                        .zIndex(point == SIMD2<Float>(0.5, 0.5) ? 1 : 0)
                }
                ForEach(viewModel.drafts.filter { roomBoundary.allowsPlacement(at: $0.unitPosition) }) { draft in
                    placementButton(at: draft.unitPosition, draft: draft)
                        .frame(width: 44, height: 44)
                        .position(screenPoint(draft.unitPosition, in: geometry.size))
                }
            }
        }
        .aspectRatio(roomAspectRatio, contentMode: .fit)
        .clipped()
        .overlay {
            if !roomBoundary.hasUsableBoundary {
                Text("Room outline incomplete. Scan the room again to place new lights.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding()
            }
        }
        .padding(.horizontal, 12)
    }

    private var outsideLightsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Saved lights outside the placement area")
                .font(.subheadline.weight(.semibold))
            Text("Select a light below to edit or remove it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(outsideDrafts) { draft in
                Button {
                    viewModel.selectedDraftID = draft.id
                } label: {
                    Label(draft.name, systemImage: "lightbulb")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private func screenPoint(_ point: SIMD2<Float>, in size: CGSize) -> CGPoint {
        CGPoint(x: 17 + CGFloat(point.x) * max(1, size.width - 34),
                y: 17 + CGFloat(point.y) * max(1, size.height - 34))
    }

    private func emptyPlacementPoints(in size: CGSize) -> [SIMD2<Float>] {
        let grid = CeilingLightPlacementGrid(
            bounds: planBounds, walls: scanPlan?.wallSegments ?? [],
            openings: planOpenings,
            maxColumns: max(1, Int(max(1, size.width - 34) / 40)),
            maxRows: max(1, Int(max(1, size.height - 34) / 40)),
            wallClearance: max(0.15, 14 * max(planBounds.width / Float(max(1, size.width - 34)),
                                            planBounds.length / Float(max(1, size.height - 34))))
        )
        return grid.points.filter { candidate in
            let point = screenPoint(candidate, in: size)
            return !viewModel.drafts.contains { draft in
                let saved = screenPoint(draft.unitPosition, in: size)
                if candidate == SIMD2<Float>(0.5, 0.5) {
                    // A nearby lamp must not suppress the exact room-center option.
                    return abs(draft.unitPosition.x - 0.5) < 0.0001
                        && abs(draft.unitPosition.y - 0.5) < 0.0001
                }
                // Hide only points covered by the bulb marker, not a whole neighboring cell.
                let dx = saved.x - point.x
                let dy = saved.y - point.y
                return dx * dx + dy * dy < 20 * 20
            }
        }
    }

    private func placementButton(at point: SIMD2<Float>, draft: LightDraft? = nil, isCenter: Bool = false) -> some View {
        let isSelected = draft != nil && draft?.id == viewModel.selectedDraftID
        return Button {
            viewModel.tapPosition(point)
        } label: {
            ZStack {
                Color.clear
                if let draft {
                    LightSourceMarker(colorTemp: draft.colorTemp, brightness: draft.brightness, isSelected: isSelected)
                } else {
                    Circle()
                        .fill(isCenter ? Color.accentColor : Color(white: 0.42))
                        .overlay { Circle().stroke(.white.opacity(0.6), lineWidth: 1) }
                        .frame(width: 8, height: 8)
                        .overlay {
                            if isCenter {
                                Circle().stroke(Color.accentColor, lineWidth: 1.5)
                                    .frame(width: 16, height: 16)
                            }
                        }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(draft.map { "Edit \($0.name)" } ?? (isCenter ? "Add light at room center" : "Add light source"))
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - Bottom Panel

    @ViewBuilder
    private var bottomPanel: some View {
        VStack(spacing: 0) {
            LightingSettingsCard(
                draft: viewModel.selectedDraft,
                onColorTemperatureChange: { viewModel.updateColorTemp($0) },
                onBrightnessChange: { viewModel.updateBrightness($0) },
                onDelete: { viewModel.showDeleteConfirm = true }
            )
            .padding(.horizontal, 24)

            Button {
                viewModel.showSaveConfirm = true
            } label: {
                Text("Save & Continue")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(viewModel.canSave ? Color.accentColor : Color.gray.opacity(0.5))
                    .cornerRadius(14)
            }
            .disabled(!viewModel.canSave)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }

    }

    // MARK: - Actions

    private func performSave() {
        do {
            try viewModel.saveToLayout(layout, context: modelContext)
            if let onSave {
                onSave()
            } else {
                dismiss()
            }
        } catch {
            viewModel.saveError = error.localizedDescription
        }
    }
}

// MARK: - Light Source Marker

private struct LightSourceMarker: View {
    let colorTemp: Int
    let brightness: Float
    let isSelected: Bool

    private var intensity: Double {
        Double(min(1, max(0, (brightness - 500) / 2500)))
    }

    private var lightColor: Color {
        // Match the slider's warm, neutral and cool stops for a consistent visual cue.
        let fraction = min(1, max(0, Double(colorTemp - 2200) / 4300))
        let stops: [(position: Double, rgb: SIMD3<Double>)] = [
            (0, SIMD3(1.0, 0.68, 0.26)),
            (0.25, SIMD3(1.0, 0.88, 0.60)),
            (0.55, SIMD3(1.0, 0.98, 0.90)),
            (1, SIMD3(0.82, 0.91, 1.0))
        ]
        for index in 1..<stops.count {
            let lower = stops[index - 1]
            let upper = stops[index]
            if fraction <= upper.position {
                let blend = (fraction - lower.position) / (upper.position - lower.position)
                let rgb = lower.rgb + (upper.rgb - lower.rgb) * blend
                return Color(red: rgb.x, green: rgb.y, blue: rgb.z)
            }
        }
        return Color(red: 0.82, green: 0.91, blue: 1.0)
    }

    var body: some View {
        Circle()
            .fill(lightColor)
            .frame(width: isSelected ? 30 : 22, height: isSelected ? 30 : 22)
            .overlay {
                Image(systemName: "lightbulb.fill")
                    .font(isSelected ? .caption : .caption2)
                    .foregroundStyle(Color(white: 0.42))
            }
            .background {
                // The halo is decorative and cannot expand the cell's tap target or layout.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                lightColor.opacity(0.25 + intensity * 0.6),
                                lightColor.opacity(0.1 + intensity * 0.25),
                                lightColor.opacity(0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 22 + intensity * 30
                        )
                    )
                    .frame(width: 44 + intensity * 60, height: 44 + intensity * 60)
                    .blur(radius: 2 + intensity * 4)
                    .allowsHitTesting(false)
            }
            .shadow(color: lightColor.opacity(0.2 + intensity * 0.65), radius: 2 + intensity * 14)
    }
}

// MARK: - Lighting Settings

/// Keeps the same controls visible before selection without creating a light draft.
private struct LightingSettingsCard: View {
    let draft: LightDraft?
    let onColorTemperatureChange: (Int) -> Void
    let onBrightnessChange: (Float) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let draft {
                HStack {
                    Text(draft.name)
                        .font(.headline)
                    Spacer()
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Delete light source")
                }
            } else {
                Text("Select a light on the plan to edit it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Color Temperature")
                    .font(.subheadline)
                Text("\(draft?.colorTemp ?? 5000) K")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                LightingGradientSlider(
                    value: draft?.colorTemp ?? 5000,
                    range: 2200...6500
                ) { value in
                    guard draft != nil else { return }
                    onColorTemperatureChange(value)
                }
                .disabled(draft == nil)
                .allowsHitTesting(draft != nil)
                .saturation(draft == nil ? 0 : 1)
                .accessibilityLabel("Color Temperature")
                HStack {
                    Text("2200")
                    Spacer()
                    Text("6500 K")
                }
                .font(.caption)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Brightness")
                    .font(.subheadline)
                Text("\(Int(draft?.brightness ?? 1080)) lm")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                LightingGradientSlider(
                    value: Int(draft?.brightness ?? 1080),
                    range: 500...3000,
                    step: 10,
                    stops: [
                        .init(color: Color(white: 0.25), location: 0),
                        .init(color: Color(white: 0.9), location: 1)
                    ]
                ) { value in
                    guard draft != nil else { return }
                    onBrightnessChange(Float(value))
                }
                .disabled(draft == nil)
                .allowsHitTesting(draft != nil)
                .accessibilityLabel("Brightness")
                HStack {
                    Text("500 lm")
                    Spacer()
                    Text("3000 lm")
                }
                .font(.caption)
            }
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
        }
    }
}

// MARK: - Shared Lighting Slider

/// Both lighting controls share track geometry, thumb styling and interaction.
private struct LightingGradientSlider: View {
    @Environment(\.isEnabled) private var isEnabled

    let value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var stops: [Gradient.Stop] = [
        .init(color: Color(red: 1.0, green: 0.68, blue: 0.26), location: 0),
        .init(color: Color(red: 1.0, green: 0.88, blue: 0.60), location: 0.25),
        .init(color: Color(red: 1.0, green: 0.98, blue: 0.90), location: 0.55),
        .init(color: Color(red: 0.82, green: 0.91, blue: 1.0), location: 1)
    ]
    let onChange: (Int) -> Void

    private var fraction: CGFloat {
        let span = max(1, range.upperBound - range.lowerBound)
        return min(1, max(0, CGFloat(value - range.lowerBound) / CGFloat(span)))
    }

    var body: some View {
        GeometryReader { geometry in
            let thumbDiameter: CGFloat = 22
            let trackWidth = max(1, geometry.size.width - thumbDiameter)

            ZStack(alignment: .leading) {
                LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
                    .frame(width: trackWidth, height: 6)
                    .clipShape(Capsule())
                    .offset(x: thumbDiameter / 2)

                Circle()
                    .fill(isEnabled ? Color.white : Color(white: 0.8))
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .shadow(color: .black.opacity(0.20), radius: 3, x: 0, y: 1)
                    .offset(x: fraction * trackWidth)
            }
            .frame(height: 44)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard isEnabled else { return }
                        let rawFraction = (drag.location.x - thumbDiameter / 2) / trackWidth
                        let clamped = min(1, max(0, rawFraction))
                        let span = CGFloat(range.upperBound - range.lowerBound)
                        let increment = max(1, step)
                        let steps = Int((clamped * span / CGFloat(increment)).rounded())
                        updateValue(range.lowerBound + steps * increment)
                    }
            )
        }
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text("\(value)"))
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            let increment = max(step, (range.upperBound - range.lowerBound) / 100)
            switch direction {
            case .increment: updateValue(value + increment)
            case .decrement: updateValue(value - increment)
            @unknown default: break
            }
        }
    }

    private func updateValue(_ newValue: Int) {
        onChange(min(range.upperBound, max(range.lowerBound, newValue)))
    }
}

// MARK: - Preview

#Preview("Lighting Setup - Interactive") {
    let schema = Schema([
        Room.self,
        RoomOpening.self,
        Layout.self,
        Furniture.self,
        Light.self,
        Insight.self,
    ])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [configuration])
    let layout = Layout(name: "Sample Office Layout")
    let room = Room(name: "Sample Office", length: 4, width: 6)
    room.layouts.append(layout)
    room.openings = [RoomOpening(posX: 3, posY: 1.4, posZ: 0)]
    layout.furnitures = [Furniture(name: "Desk", category: "desk", positionX: -1.5, positionZ: -1,
                                  length: 0.7, width: 1.4, height: 0.75)]
    container.mainContext.insert(room)

    return NavigationStack {
        LightingSetupView(
            layout: layout,
            onSave: {
                print("Preview: Light setup saved!")
            },
            onBack: {
                print("Preview: Go back requested")
            }
        )
    }
    .modelContainer(container)
}
