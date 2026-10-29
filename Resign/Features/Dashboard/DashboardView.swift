//
//  DashboardView.swift
//  Resign
//

import SwiftUI
import SwiftData

public struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Room.updatedAt, order: .reverse) private var rooms: [Room]
    @State private var viewModel = DashboardViewModel()

    @State private var roomToRename: Room?
    @State private var newRoomName = ""
    @State private var roomToDelete: Room?
    @State private var swipedRoomID: UUID?
    @State private var selectedRoom: Room?
    @State private var isShowingRoomCreation = false

    private var room2Room: Room? {
        rooms.first { $0.name == DashboardViewModel.room2Name || $0.name == "Room-2 (Studio)" }
    }

    private var room2Layout: Layout? {
        room2Room?.layouts.first
    }

    private var scannedRooms: [Room] {
        rooms.filter { $0.name != DashboardViewModel.room2Name && $0.name != "Room-2 (Studio)" }
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if swipedRoomID != nil {
                            withAnimation(.smooth) {
                                swipedRoomID = nil
                            }
                        }
                    }

                ScrollView {
                    VStack(spacing: 20) {
                        // Hard-coded Room-2 3D Studio Card
                        room2StudioCard

                        // Scanned Rooms Section
                        scannedRoomsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 80)
                }
                .onTapGesture {
                    if swipedRoomID != nil {
                        withAnimation(.smooth) {
                            swipedRoomID = nil
                        }
                    }
                }
            }

            // Navigation to Layout Details
            .navigationDestination(item: $selectedRoom) { room in
                LayoutDetailsView(room: room)
            }

            // Rename Alert
            .alert(
                "Edit name",
                isPresented: Binding(
                    get: { roomToRename != nil },
                    set: { isPresented in
                        if !isPresented {
                            roomToRename = nil
                            swipedRoomID = nil
                        }
                    }
                )
            ) {
                TextField("Room Name", text: $newRoomName)

                Button("Cancel", role: .cancel) {
                    roomToRename = nil
                    swipedRoomID = nil
                }

                Button("Save") {
                    if let room = roomToRename {
                        viewModel.renameRoom(room, to: newRoomName, context: modelContext)
                    }
                    roomToRename = nil
                    swipedRoomID = nil
                }
            } message: {
                Text("Enter a name for this room.")
            }

            // Delete Alert
            .alert(
                "Are you sure you want to delete?",
                isPresented: Binding(
                    get: { roomToDelete != nil },
                    set: { isPresented in
                        if !isPresented {
                            roomToDelete = nil
                            swipedRoomID = nil
                        }
                    }
                )
            ) {
                Button("Cancel", role: .cancel) {
                    roomToDelete = nil
                    swipedRoomID = nil
                }

                Button("Delete", role: .destructive) {
                    if let room = roomToDelete {
                        viewModel.deleteRoom(room, context: modelContext)
                    }
                    roomToDelete = nil
                    swipedRoomID = nil
                }
            } message: {
                Text("You cannot restore your changes after deletion.")
            }
            .navigationTitle("My Layout")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        Studio3DView(layoutID: room2Layout?.id)
                    } label: {
                        Image(systemName: "sun.max")
                    }
                    .accessibilityLabel("Lighting Simulation")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    isShowingRoomCreation = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(.primary)
                .padding(.trailing, 24)
                .padding(.bottom, 24)
                .accessibilityLabel("Scan new room")
            }
            .fullScreenCover(isPresented: $isShowingRoomCreation) {
                RoomCreationFlowView()
            }
            .onAppear {
                viewModel.ensureRoom2Seeded(context: modelContext)
            }
        }
    }

    // MARK: - Subviews

    private var room2StudioCard: some View {
        NavigationLink {
            Studio3DView(layoutID: room2Layout?.id)
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.12, green: 0.16, blue: 0.28),
                                Color(red: 0.06, green: 0.09, blue: 0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("3D STUDIO DEMO", systemImage: "cube.transparent")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.16), in: Capsule())

                        Spacer()

                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Room-2 Model")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)

                        Text("Interactive furniture rearrangement, collision physics & PBR materials")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(2)
                    }
                }
                .padding(18)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 154)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        }
        .accessibilityLabel("Open Room-2 in 3D Studio")
    }

    @ViewBuilder
    private var scannedRoomsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("My Scanned Rooms")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                if !scannedRooms.isEmpty {
                    Text("\(scannedRooms.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                }
            }

            if scannedRooms.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "camera.metering.matrix")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)

                    Text("No Scanned Rooms Yet")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("Scan your room with LiDAR to create custom 3D layouts and floor plans.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)

                    Button {
                        isShowingRoomCreation = true
                    } label: {
                        Label("Scan a Room", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            } else {
                ForEach(scannedRooms) { room in
                    LayoutCardView(
                        layoutName: room.name,
                        layoutCount: room.layouts.count,
                        isSwiped: Binding(
                            get: { swipedRoomID == room.id },
                            set: { isOpen in
                                if isOpen {
                                    swipedRoomID = room.id
                                } else if swipedRoomID == room.id {
                                    swipedRoomID = nil
                                }
                            }
                        ),
                        onTap: {
                            swipedRoomID = nil
                            selectedRoom = room
                        },
                        onEdit: {
                            newRoomName = room.name
                            roomToRename = room
                        },
                        onDelete: {
                            roomToDelete = room
                        }
                    )
                }
            }
        }
    }
}

#Preview("Dashboard") {
    let container = try! ModelContainer.createInMemoryContainer()
    let viewModel = DashboardViewModel()
    viewModel.ensureRoom2Seeded(context: container.mainContext)
    return DashboardView()
        .modelContainer(container)
}
