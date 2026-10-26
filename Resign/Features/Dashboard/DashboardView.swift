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

                if rooms.isEmpty {
                    // Empty State
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 50))
                            .foregroundStyle(.secondary)

                        Text("No Layout Yet.")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("Create a layout to start planning\nand arranging your room.\nTap the + button to get started.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button {
                            isShowingRoomCreation = true
                        } label: {
                            Label("Scan a Room", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                    .offset(y: -35)

                } else {
                    // Filled State
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(rooms) { room in
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
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
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
                        Studio3DView()
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
        }
    }
}

#Preview("Empty State") {
    let container = try! ModelContainer.createInMemoryContainer()
    DashboardView()
        .modelContainer(container)
}

#Preview("Filled State") {
    let container = try! ModelContainer.createInMemoryContainer()
    let room1 = Room(name: "Bedroom 1")
    let room2 = Room(name: "Living Room")
    let layout = Layout(name: "Original")
    room1.layouts.append(layout)
    container.mainContext.insert(room1)
    container.mainContext.insert(room2)

    return DashboardView()
        .modelContainer(container)
}
