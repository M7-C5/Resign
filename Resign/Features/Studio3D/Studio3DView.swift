import SwiftUI

public struct Studio3DView: View {
    @State private var viewModel = Studio3DViewModel()

    public init() {}

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            Text("3D Studio")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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
        .sheet(isPresented: Binding(
            get: { viewModel.isLightingPresented },
            set: { if !$0 { viewModel.discardLightingEditing() } }
        ), onDismiss: {
            viewModel.discardLightingEditing()
        }) {
            LightingSimulationSheet(
                settings: $viewModel.lightingDraft,
                onCancel: { viewModel.discardLightingEditing() },
                onConfirm: { viewModel.confirmLightingEditing() }
            )
        }
    }
}

#Preview("Open lighting simulation") {
    Studio3DView()
}
