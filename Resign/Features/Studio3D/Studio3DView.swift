import SwiftUI
import Observation
import SwiftData

public struct Studio3DView: View {
    private let layoutID: UUID?
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = Studio3DViewModel()
    @State private var controller = RoomSceneController()
    @State private var snapFeedbackTrigger = false
    @Query(sort: \Layout.updatedAt, order: .reverse) private var layouts: [Layout]

    public init(layoutID: UUID? = nil) {
        self.layoutID = layoutID
    }

    private var selectedLayout: Layout? {
        if let layoutID {
            return layouts.first { $0.id == layoutID }
        }
        return layouts.first { $0.room?.name == DashboardViewModel.room2Name || $0.name == "Original Layout" } ?? layouts.first
    }

    private var selectedFurniture: Furniture? {
        selectedLayout?.furnitures.first { $0.id == viewModel.selectedFurnitureID }
    }

    private var lightingFixtures: [RoomLightingFixture]? {
        guard let layout = selectedLayout else { return nil }
        let source = RoomSimulationLayout(layout: layout)
        return layout.lights.sorted { $0.name < $1.name }.map {
            RoomLightingFixture(light: $0, layout: source)
        }
    }

    private var sceneLayout: RoomSimulationLayout? {
        selectedLayout.map { RoomSimulationLayout(layout: $0) }
    }

    private var roomHeading: Double {
        selectedLayout?.room?.compass ?? 0
    }

    public var body: some View {
        @Bindable var viewModel = viewModel

        ZStack(alignment: .topTrailing) {
            // Authentic 3D Room Viewport with Sims-style furniture manipulation
            RoomSimulationView(
                controller: controller,
                settings: viewModel.previewLighting,
                fixtures: lightingFixtures,
                onSelectFurniture: { id in
                    withAnimation(.snappy(duration: 0.2)) {
                        viewModel.selectFurniture(id: id, in: selectedLayout)
                        controller.setSelection(furnitureID: id, isColliding: viewModel.isColliding)
                    }
                },
                onMoveFurniture: { id, floorPos in
                    if let result = viewModel.moveSelectedFurniture(to: floorPos, in: selectedLayout, context: modelContext) {
                        controller.updateFurnitureTransform(
                            id: id,
                            position: result.position,
                            yaw: selectedFurniture?.rotationYaw ?? 0
                        )
                        controller.setSelection(furnitureID: id, isColliding: result.isColliding)
                    }
                },
                onRotateFurniture: { id, targetYaw in
                    if let result = viewModel.rotateSelectedFurniture(to: targetYaw, in: selectedLayout, context: modelContext) {
                        controller.updateFurnitureTransform(
                            id: id,
                            position: result.position,
                            yaw: result.yaw
                        )
                        controller.setSelection(furnitureID: id, isColliding: result.isColliding)
                        if result.didSnap {
                            snapFeedbackTrigger.toggle()
                        }
                    }
                },
                onBoundsResolved: { bounds in
                    viewModel.roomHorizontalBounds = bounds
                },
                onReloadScannedRoom: {
                    Task { await controller.reload() }
                },
                onWindowDirectionsResolved: { directions in
                    viewModel.updateWindowDirections(directions)
                }
            )
            .padding(.bottom, viewModel.isLightingPresented ? LightingSimulationSheet.collapsedHeight + 20 : 0)

            // Lighting Simulation Trigger
            Button {
                viewModel.beginLightingEditing()
            } label: {
                Image(systemName: "lightbulb")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel("Lighting Simulation")
            .padding()

            // Contextual Furniture Rearrangement Action Bar
            if let furniture = selectedFurniture {
                VStack {
                    Spacer()
                    VStack(spacing: 8) {
                        if viewModel.isColliding {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                Text("Overlapping with furniture")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.red)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.12), in: Capsule())
                            .transition(.opacity)
                        }

                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(furniture.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("\(String(format: "%.1f", furniture.width))m × \(String(format: "%.1f", furniture.length))m • Drag knob to rotate")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                withAnimation(.snappy(duration: 0.2)) {
                                    if viewModel.isColliding {
                                        if let reverted = viewModel.revertToLastValidPosition(id: furniture.id, in: selectedLayout!, context: modelContext) {
                                            controller.updateFurnitureTransform(id: furniture.id, position: reverted.position, yaw: reverted.yaw)
                                        }
                                    }
                                    viewModel.deselectFurniture(in: selectedLayout, context: modelContext)
                                    controller.setSelection(furnitureID: nil)
                                }
                            } label: {
                                Image(systemName: viewModel.isColliding ? "arrow.uturn.backward" : "checkmark")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(viewModel.isColliding ? Color.orange : Color.accentColor, in: Circle())
                            }
                            .accessibilityLabel(viewModel.isColliding ? "Revert collision" : "Done rearranging")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $viewModel.isLightingPresented, onDismiss: {
            viewModel.sheetDidDismiss()
        }) {
            LightingSimulationSheet(
                settings: $viewModel.lightingDraft,
                onCancel: { viewModel.discardLightingEditing() },
                onConfirm: { viewModel.confirmLightingEditing() }
            )
        }
        .onAppear {
            controller.setRoomAndLayout(room: selectedLayout?.room, layout: selectedLayout)
        }
        .onChange(of: selectedLayout) { _, newLayout in
            controller.setRoomAndLayout(room: newLayout?.room, layout: newLayout)
        }
        .onChange(of: roomHeading, initial: true) { _, newHeading in
            viewModel.updateRoomHeading(newHeading)
        }
        .onChange(of: sceneLayout?.windowAzimuths ?? [90], initial: true) { _, directions in
            viewModel.updateWindowDirections(directions)
        }
        .navigationTitle(selectedLayout?.name ?? "3D Studio")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.impact(weight: .light), trigger: snapFeedbackTrigger)
    }
}

#Preview("Studio 3D") {
    Studio3DView()
}
