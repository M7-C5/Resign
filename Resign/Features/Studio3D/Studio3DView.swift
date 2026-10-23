import SwiftUI
import Observation

public struct Studio3DView: View {
    @State private var viewModel = Studio3DViewModel()

    public init() {}

    public var body: some View {
        @Bindable var viewModel = viewModel

        ZStack(alignment: .topTrailing) {
            // Shrink the room while the sheet is open so it stays visible above it.
            RoomSimulationView(settings: viewModel.previewLighting)
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

/// Holds the confirmed lighting and the draft being edited in the sheet.
@Observable
@MainActor
public final class Studio3DViewModel {
    private(set) var lightingSettings = LightingSimulationSettings()
    var lightingDraft = LightingSimulationSettings()
    var isLightingPresented = false

    /// While the sheet is open the room previews the draft; otherwise the confirmed settings.
    var previewLighting: LightingSimulationSettings {
        isLightingPresented ? lightingDraft : lightingSettings
    }

    public init() {}

    func beginLightingEditing() {
        lightingDraft = lightingSettings
        isLightingPresented = true
    }

    func confirmLightingEditing() {
        guard isLightingPresented else { return }
        lightingSettings = lightingDraft
        isLightingPresented = false
    }

    func discardLightingEditing() {
        lightingDraft = lightingSettings
        isLightingPresented = false
    }

    /// Called after any dismissal, including swipe down. The draft never outlives the sheet.
    func sheetDidDismiss() {
        lightingDraft = lightingSettings
    }
}

#Preview("Studio 3D") {
    Studio3DView()
}








//import SwiftUI
//
//public struct Studio3DView: View {
//    @State private var viewModel = Studio3DViewModel()
//
//    public init() {}
//
//    public var body: some View {
//        ZStack(alignment: .topTrailing) {
//            GeometryReader { geometry in
//                MockRoomSimulationView(settings: viewModel.previewLighting)
//                    .frame(
//                        width: geometry.size.width,
//                        height: max(180, geometry.size.height - (viewModel.isLightingPresented ? 250 : 0))
//                    )
//            }
//
//            Button {
//                viewModel.beginLightingEditing()
//            } label: {
//                Image(systemName: "lightbulb")
//                    .font(.body)
//                    .foregroundStyle(.primary)
//                    .frame(width: 44, height: 44)
//                    .background(.regularMaterial, in: Circle())
//            }
//            .accessibilityLabel("Lighting Simulation")
//            .padding()
//        }
//        .sheet(isPresented: Binding(
//            get: { viewModel.isLightingPresented },
//            set: { if !$0 { viewModel.discardLightingEditing() } }
//        ), onDismiss: {
//            viewModel.discardLightingEditing()
//        }) {
//            LightingSimulationSheet(
//                settings: $viewModel.lightingDraft,
//                onCancel: { viewModel.discardLightingEditing() },
//                onConfirm: { viewModel.confirmLightingEditing() }
//            )
//        }
//    }
//}
//
//#Preview("Open lighting simulation") {
//    Studio3DView()
//}
