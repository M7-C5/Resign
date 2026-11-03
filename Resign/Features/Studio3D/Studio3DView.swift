import SwiftUI
import Observation
import SwiftData

public struct Studio3DView: View {
    private let layoutID: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var viewModel = Studio3DViewModel()
    @State private var controller = RoomSceneController()
    @State private var snapFeedbackTrigger = false
    @State private var usesInlineLightingPanel = false
    @State private var rotateDragStartYaw: Float? = nil
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

    private var roomTitle: String {
        selectedLayout?.room?.name ?? selectedLayout?.name ?? "3D Studio"
    }

    public var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            topNavigationHeader

            GeometryReader { geometry in
                let workspace = LightingWorkspaceLayout(
                    size: geometry.size,
                    accessibilityText: dynamicTypeSize.isAccessibilitySize
                )
                HStack(spacing: 0) {
                    ZStack(alignment: .topTrailing) {
                        if layoutID != nil, selectedLayout == nil {
                            ContentUnavailableView("Layout Not Found", systemImage: "cube")
                        } else {
                            viewportLayer
                                .padding(.bottom, workspace.simulationBottomInset(isEditing: viewModel.isLightingPresented))
                        }

                        if let furniture = selectedFurniture,
                           let projected = viewModel.selectedFurnitureScreenPosition,
                           !viewModel.isInventoryOpen {
                            let clamped = FurnitureSimsActionHUD.clampedPosition(
                                projected: projected,
                                in: geometry.size
                            )
                            FurnitureSimsActionHUD(
                                furniture: furniture,
                                isColliding: viewModel.isColliding,
                                onStepRotate: {
                                    handleStepRotate(for: furniture)
                                },
                                onCircularRotate: { deltaAngle in
                                    handleCircularRotate(for: furniture, deltaAngle: deltaAngle)
                                },
                                onDragRotateEnded: {
                                    handleDragRotateEnded(for: furniture)
                                },
                                onArchive: {
                                    handleArchive(for: furniture)
                                }
                            )
                            .position(clamped)
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                            .zIndex(10)
                        }

                        bottomControlsBar
                            .padding(.bottom, workspace.simulationBottomInset(isEditing: viewModel.isLightingPresented))
                    }
                    .frame(maxWidth: .infinity)

                    if workspace.usesSidePanel && viewModel.isLightingPresented {
                        LightingSimulationControls(
                            settings: $viewModel.lightingDraft,
                            onCancel: { viewModel.discardLightingEditing() },
                            onConfirm: { viewModel.confirmLightingEditing() }
                        )
                        .frame(width: workspace.panelWidth)
                        .background(.regularMaterial)
                    }
                }
                .onChange(of: workspace.usesSidePanel, initial: true) { _, usesSidePanel in
                    usesInlineLightingPanel = usesSidePanel
                }
            }
        }
        .background(StudioTheme.canvasBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: Binding(
            get: { viewModel.isLightingPresented && !usesInlineLightingPanel },
            set: { presented in
                if !presented && !usesInlineLightingPanel { viewModel.discardLightingEditing() }
            }
        ), onDismiss: {
            if !usesInlineLightingPanel { viewModel.sheetDidDismiss() }
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
        .sensoryFeedback(.impact(weight: .light), trigger: snapFeedbackTrigger)
    }

    private var viewportLayer: some View {
        RoomSimulationView(
            controller: controller,
            settings: viewModel.previewLighting,
            fixtures: lightingFixtures,
            selectedFurnitureID: viewModel.selectedFurnitureID,
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
            onProjectSelectedFurniture: { screenPoint in
                viewModel.selectedFurnitureScreenPosition = screenPoint
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
            onWallSegmentsResolved: { walls in
                viewModel.roomWallSegments = walls
            },
            onReloadScannedRoom: {
                Task { @MainActor in
                    await controller.reload()
                    if let bounds = controller.roomHorizontalBounds {
                        viewModel.roomHorizontalBounds = bounds
                    }
                    viewModel.roomWallSegments = controller.roomWallSegments
                }
            },
            onWindowDirectionsResolved: { directions in
                viewModel.updateWindowDirections(directions)
            }
        )
    }

    private var topNavigationHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            // Leading: Back Navigation Button
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(StudioTheme.primaryText)
                    .frame(width: 44, height: 44)
                    .background(StudioTheme.buttonBackground, in: Circle())
                    .overlay(Circle().stroke(StudioTheme.buttonStroke, lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer()

            // Trailing Actions (POV, AR, Lighting)
            HStack(spacing: 8) {
                // Point of View Snap Button
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
                    Image(systemName: "rotate.3d")
                        .font(.body)
                        .foregroundStyle(StudioTheme.primaryText)
                        .frame(width: 44, height: 44)
                        .background(StudioTheme.buttonBackground, in: Circle())
                        .overlay(Circle().stroke(StudioTheme.buttonStroke, lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
                }
                .accessibilityLabel("Point of View")

                // AR Button (Placeholder for now)
                Button {
                    snapFeedbackTrigger.toggle()
                } label: {
                    Text("AR")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(StudioTheme.primaryText)
                        .frame(width: 44, height: 44)
                        .background(StudioTheme.buttonBackground, in: Circle())
                        .overlay(Circle().stroke(StudioTheme.buttonStroke, lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Augmented Reality")

                // Lighting Simulation Button
                Button {
                    viewModel.toggleLightingSimulation()
                } label: {
                    Image(systemName: viewModel.isSimulationEnabled ? "lightbulb.fill" : "lightbulb")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(viewModel.isSimulationEnabled ? Color.white : StudioTheme.primaryText)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle().fill(viewModel.isSimulationEnabled ? StudioTheme.primaryText : StudioTheme.buttonBackground)
                        )
                        .overlay(Circle().stroke(StudioTheme.buttonStroke, lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.isSimulationEnabled ? "Disable Lighting Simulation" : "Enable Lighting Simulation")
                .disabled(layoutID != nil && selectedLayout == nil)

                if viewModel.isSimulationEnabled {
                    Button {
                        viewModel.beginLightingEditing()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(StudioTheme.primaryText)
                            .frame(width: 44, height: 44)
                            .background(StudioTheme.buttonBackground, in: Circle())
                            .overlay(Circle().stroke(StudioTheme.buttonStroke, lineWidth: 1))
                            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Lighting Controls")
                    .disabled(viewModel.isLightingPresented)
                }
            }
        }
        .overlay(
            Text(roomTitle)
                .font(StudioTheme.titleFont(size: 22, weight: .bold))
                .foregroundStyle(StudioTheme.primaryText)
                .lineLimit(1)
                .allowsHitTesting(false)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var bottomControlsBar: some View {
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
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private func handleStepRotate(for furniture: Furniture) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
            if let result = viewModel.rotateSelectedFurniture45(in: selectedLayout, context: modelContext) {
                controller.updateFurnitureTransform(
                    id: furniture.id,
                    position: result.position,
                    yaw: result.yaw
                )
                controller.setSelection(furnitureID: furniture.id, isColliding: result.isColliding)
                snapFeedbackTrigger.toggle()
            }
        }
    }

    private func handleCircularRotate(for furniture: Furniture, deltaAngle: Float) {
        let startYaw = rotateDragStartYaw ?? furniture.rotationYaw
        if rotateDragStartYaw == nil {
            rotateDragStartYaw = startYaw
        }
        // Clockwise circular motion on screen (positive deltaAngle) decreases yaw in RealityKit (+Y up)
        let targetYaw = startYaw - deltaAngle
        if let result = viewModel.rotateSelectedFurniture(to: targetYaw, in: selectedLayout, context: modelContext) {
            controller.updateFurnitureTransform(
                id: furniture.id,
                position: result.position,
                yaw: result.yaw
            )
            controller.setSelection(furnitureID: furniture.id, isColliding: result.isColliding)
            if result.didSnap {
                snapFeedbackTrigger.toggle()
            }
        }
    }

    private func handleDragRotateEnded(for furniture: Furniture) {
        rotateDragStartYaw = nil
    }

    private func handleArchive(for furniture: Furniture) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            let id = furniture.id
            viewModel.archiveFurniture(id: id, in: selectedLayout, context: modelContext)
            controller.archiveFurnitureEntity(id: id)
            snapFeedbackTrigger.toggle()
        }
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
