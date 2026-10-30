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
                archiveTargetCenter: viewModel.archiveTargetCenter,
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
                onArchiveHover: { isHovering in
                    viewModel.isHoveringArchiveTarget = isHovering
                    if let id = viewModel.selectedFurnitureID {
                        controller.setGhostOpacity(for: id, isGhosted: isHovering)
                    }
                    if isHovering {
                        snapFeedbackTrigger.toggle()
                    }
                },
                onArchiveDrop: { id in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        viewModel.archiveFurniture(id: id, in: selectedLayout, context: modelContext)
                        controller.archiveFurnitureEntity(id: id)
                        snapFeedbackTrigger.toggle()
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

            // Top-Trailing Controls: Viewport Snapping & Lighting Simulation
            HStack(spacing: 12) {
                // Architectural Viewport Snapping Menu
                Menu {
                    ForEach(ViewportPreset.allCases) { preset in
                        if preset == .dollhouse {
                            Divider()
                        }
                        Button {
                            controller.snapToViewport(preset)
                        } label: {
                            Label(preset.title, systemImage: preset.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: "cube.plane.bottom.right.detached")
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("Viewport Presets")

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
            }
            .padding()

            // Bottom Bar: Left Inventory Drawer + Right Contextual Action Bar
            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 12) {
                    InventoryDrawerView(
                        archivedFurnitures: viewModel.archivedFurnitures(in: selectedLayout),
                        isHoveringArchiveTarget: viewModel.isHoveringArchiveTarget,
                        isOpen: viewModel.isInventoryOpen,
                        onToggleOpen: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                if !viewModel.isInventoryOpen && selectedFurniture != nil {
                                    viewModel.deselectFurniture(in: selectedLayout, context: modelContext)
                                    controller.setSelection(furnitureID: nil)
                                }
                                viewModel.isInventoryOpen.toggle()
                            }
                        },
                        onTargetCenterResolved: { center in
                            viewModel.archiveTargetCenter = center
                        },
                        onRestoreItem: { item, screenPoint in
                            restoreFurnitureItem(item, at: screenPoint)
                        }
                    )

                    Spacer(minLength: 0)

                    if let furniture = selectedFurniture, !viewModel.isInventoryOpen {
                        VStack(spacing: 6) {
                            if viewModel.isColliding {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                    Text("Overlapping")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.red)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.red.opacity(0.12), in: Capsule())
                            }

                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(furniture.name)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    let dimW = min(furniture.width, furniture.length)
                                    let dimL = max(furniture.width, furniture.length)
                                    Text("\(String(format: "%.1f", dimW))m (W) × \(String(format: "%.1f", dimL))m (L)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 4)

                                // Archive shortcut button
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                        let id = furniture.id
                                        viewModel.archiveFurniture(id: id, in: selectedLayout, context: modelContext)
                                        controller.archiveFurnitureEntity(id: id)
                                        snapFeedbackTrigger.toggle()
                                    }
                                } label: {
                                    Image(systemName: "archivebox")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 32, height: 32)
                                        .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                                }
                                .accessibilityLabel("Archive furniture")

                                // Done / Revert button
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
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                        .background(viewModel.isColliding ? Color.orange : Color.accentColor, in: Circle())
                                }
                                .accessibilityLabel(viewModel.isColliding ? "Revert collision" : "Done rearranging")
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
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

    private func restoreFurnitureItem(_ furniture: Furniture, at screenPoint: CGPoint?) {
        let floorPos: SIMD2<Float>
        if let screenPoint, let p = controller.projectToFloor(from: screenPoint) {
            floorPos = SIMD2<Float>(p.x, p.z)
        } else {
            floorPos = SIMD2<Float>(0, 0)
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            if let result = viewModel.restoreFurniture(id: furniture.id, to: floorPos, in: selectedLayout, context: modelContext) {
                controller.spawnRestoredFurnitureEntity(for: furniture)
                controller.updateFurnitureTransform(id: furniture.id, position: result.position, yaw: furniture.rotationYaw)
                controller.setSelection(furnitureID: furniture.id, isColliding: result.isColliding)
                viewModel.isInventoryOpen = false
                snapFeedbackTrigger.toggle()
            }
        }
    }
}

#Preview("Studio 3D") {
    Studio3DView()
}
