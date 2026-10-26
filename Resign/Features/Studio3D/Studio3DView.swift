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

    private var lightingFixtures: [RoomLightingFixture]? {
        let layout: Layout?
        if let layoutID {
            layout = layouts.first { $0.id == layoutID }
        } else {
            layout = layouts.first
        }
        return layout?.lights
            .sorted { $0.name < $1.name }
            .map { RoomLightingFixture(light: $0) }
    }

    public var body: some View {
        @Bindable var viewModel = viewModel

        ZStack(alignment: .topTrailing) {
            // Shrink the room while the sheet is open so it stays visible above it.
            RoomSimulationView(settings: viewModel.previewLighting, fixtures: lightingFixtures)
                .padding(.bottom, viewModel.isLightingPresented ? LightingSimulationSheet.collapsedHeight + 20 : 0)

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
    }
}

#Preview("Studio 3D") {
    Studio3DView()
}
