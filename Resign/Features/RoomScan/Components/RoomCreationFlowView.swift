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
                        onContinueToOrientation: { layout in
                            path.append(.orientation(layoutID: layout.id))
                        },
                        onFinish: {
                            dismiss()
                        }
                    )
                    .navigationBarBackButtonHidden(true)

                case .orientation(let layoutID):
                    OrientationContainerView(
                        layoutID: layoutID,
                        onSave: {
                            path.append(.lightingSetup(layoutID: layoutID))
                        },
                        onBack: {
                            if !path.isEmpty {
                                path.removeLast()
                            }
                        }
                    )

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

    @Environment(\.modelContext) private var modelContext
    @State private var layout: Layout?
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if let layout {
                LightingSetupView(
                    layout: layout,
                    onSave: onSave,
                    onBack: onBack
                )
            } else if hasLoaded {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)

                    Text("Could not find room layout")
                        .font(.headline)

                    Button("Go Back", action: onBack)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            } else {
                ProgressView("Loading Layout...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
            }
        }
        .onAppear {
            loadLayout()
        }
    }

    private func loadLayout() {
        let targetId = layoutID
        // 1. Direct fetch by ID
        let descriptor = FetchDescriptor<Layout>(predicate: #Predicate<Layout> { $0.id == targetId })
        if let direct = try? modelContext.fetch(descriptor).first {
            self.layout = direct
            self.hasLoaded = true
            return
        }

        // 2. Fallback: Search all rooms' layouts
        let roomDescriptor = FetchDescriptor<Room>()
        if let rooms = try? modelContext.fetch(roomDescriptor) {
            for room in rooms {
                if let match = room.layouts.first(where: { $0.id == targetId }) {
                    self.layout = match
                    self.hasLoaded = true
                    return
                }
            }
        }

        self.hasLoaded = true
    }
}

/// Loads the scanned layout and its owning room before north alignment.
struct OrientationContainerView: View {
    let layoutID: UUID
    let onSave: () -> Void
    let onBack: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var layout: Layout?
    @State private var room: Room?
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if let layout, let room {
                OrientationView(layout: layout, room: room, onSave: onSave, onBack: onBack)
            } else if hasLoaded {
                ContentUnavailableView("Room Not Found", systemImage: "location.north.circle")
            } else {
                ProgressView("Loading Orientation...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
            }
        }
        .onAppear {
            loadOrientation()
        }
    }

    private func loadOrientation() {
        let targetId = layoutID
        // 1. Direct fetch by ID
        let descriptor = FetchDescriptor<Layout>(predicate: #Predicate<Layout> { $0.id == targetId })
        if let direct = try? modelContext.fetch(descriptor).first {
            self.layout = direct
            if let directRoom = direct.room {
                self.room = directRoom
                self.hasLoaded = true
                return
            }
        }

        // 2. Search all rooms to ensure we get both room and layout
        let roomDescriptor = FetchDescriptor<Room>()
        if let rooms = try? modelContext.fetch(roomDescriptor) {
            for r in rooms {
                if let match = r.layouts.first(where: { $0.id == targetId }) {
                    self.layout = match
                    self.room = r
                    self.hasLoaded = true
                    return
                }
            }
        }

        self.hasLoaded = true
    }
}
