import SwiftUI
import Observation
import SwiftData

public struct Studio3DView: View {
    private let layoutID: UUID?
    @State private var viewModel = Studio3DViewModel()
    @Query(sort: \Layout.updatedAt, order: .reverse) private var layouts: [Layout]

    public init(layoutID: UUID? = nil) {
        self.layoutID = layoutID
    }

    private var selectedLayout: Layout? {
        if let layoutID {
            return layouts.first { $0.id == layoutID }
        }
        return layouts.first
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
            // Shrink the room while the sheet is open so it stays visible above it.
            if layoutID != nil, selectedLayout == nil {
                ContentUnavailableView("Layout Not Found", systemImage: "cube")
            } else {
                RoomSimulationView(settings: viewModel.previewLighting, fixtures: lightingFixtures, layout: sceneLayout,
                                   onWindowDirectionsResolved: { viewModel.updateWindowDirections($0) })
                    .id(sceneLayout)
                    .padding(.bottom, viewModel.isLightingPresented ? LightingSimulationSheet.collapsedHeight + 20 : 0)
            }

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
        .onChange(of: roomHeading, initial: true) { _, newHeading in
            viewModel.updateRoomHeading(newHeading)
        }
        .onChange(of: sceneLayout?.windowAzimuths ?? [90], initial: true) { _, directions in
            viewModel.updateWindowDirections(directions)
        }
    }
}

#Preview("Studio 3D") {
    Studio3DView()
}
