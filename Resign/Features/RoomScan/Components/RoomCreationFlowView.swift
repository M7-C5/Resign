//
//  RoomCreationFlowView.swift
//  Resign
//

import SwiftUI
import SwiftData

public struct RoomCreationFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [RoomCreationRoute] = []

    public init() {}

    public var body: some View {
        NavigationStack(path: $path) {
            RoomScanView(
                onScanComplete: { roomId in
                    path.append(.result(roomId: roomId))
                },
                onCancel: {
                    dismiss()
                }
            )
            .navigationDestination(for: RoomCreationRoute.self) { route in
                switch route {
                case .result(let roomId):
                    RoomScanResultView(
                        roomId: roomId,
                        onScanAgain: {
                            path.removeAll()
                        },
                        onContinueToLighting: { layout in
                            path.append(.lightingSetup(layoutID: layout.id))
                        },
                        onFinish: {
                            dismiss()
                        }
                    )
                    .navigationBarBackButtonHidden(true)

                case .lightingSetup(let layoutID):
                    LightingSetupContainerView(
                        layoutID: layoutID,
                        onSave: {
                            dismiss()
                        },
                        onBack: {
                            if !path.isEmpty {
                                path.removeLast()
                            }
                        }
                    )
                }
            }
        }
    }
}

struct LightingSetupContainerView: View {
    let layoutID: UUID
    let onSave: () -> Void
    let onBack: () -> Void

    @Query private var layouts: [Layout]

    init(layoutID: UUID, onSave: @escaping () -> Void, onBack: @escaping () -> Void) {
        self.layoutID = layoutID
        self.onSave = onSave
        self.onBack = onBack
        let targetId = layoutID
        _layouts = Query(filter: #Predicate<Layout> { $0.id == targetId })
    }

    var body: some View {
        if let layout = layouts.first {
            LightingSetupView(
                layout: layout,
                onSave: onSave,
                onBack: onBack
            )
        } else {
            ProgressView("Loading Layout...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
        }
    }
}
