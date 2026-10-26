//
//  DashboardView.swift
//  Resign
//

import SwiftUI

public struct DashboardView: View {
    
    // Temporary layout data (later will be replaced by actual saved layout data)
    @State private var layouts: [String]
    @State private var layoutToRename: String?
    @State private var newLayoutName = ""
    @State private var layoutToDelete: String?
    @State private var swipedLayout: String?
    @State private var selectedRoom: String?
    
    public init(layouts: [String] = []) {
        _layouts = State(initialValue: layouts)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.white
                    .ignoresSafeArea()
                
                if layouts.isEmpty {
                    // Empty State
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 50))
                            .foregroundStyle(.gray)
                        
                        Text("No Layout Yet.")
                            .font(.headline)
                            .foregroundStyle(.black)
                        
                        Text("Create a layout to start planning\nand arranging your room.\nTap the + button to get started.")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .offset(y: -35)
                    
                } else {
                    // Filled State
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(layouts, id: \.self) { layout in
                                LayoutCardView(
                                    layoutName: layout,
                                    isSwiped: Binding(
                                        get: {
                                            swipedLayout == layout
                                        },
                                        set: { isOpen in
                                            if isOpen {
                                                swipedLayout = layout
                                            } else if swipedLayout == layout {
                                                swipedLayout = nil
                                            }
                                        }
                                    ),
                                    onTap: {
                                        swipedLayout = nil
                                        selectedRoom = layout
                                    },
                                    onEdit: {
                                        newLayoutName = layout
                                        layoutToRename = layout
                                    },
                                    onDelete: {
                                        layoutToDelete = layout
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                }
            }
            
            // Navigation to Layout Details
            .navigationDestination(item: $selectedRoom) { room in
                LayoutDetailsView(roomName: room)
            }
            
            // Rename Alert
            .alert(
                "Edit name",
                isPresented: Binding(
                    get: { layoutToRename != nil },
                    set: { isPresented in
                        if !isPresented {
                            layoutToRename = nil
                            swipedLayout = nil
                        }
                    }
                )
            ) {
                TextField("LayoutName", text: $newLayoutName)
                
                Button("Cancel", role: .cancel) {
                    layoutToRename = nil
                    swipedLayout = nil
                }
                
                Button("Save") {
                    if let oldName = layoutToRename {
                        let trimmedName = newLayoutName.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        
                        if !trimmedName.isEmpty,
                           let index = layouts.firstIndex(of: oldName) {
                            layouts[index] = trimmedName
                        }
                    }
                    
                    layoutToRename = nil
                    swipedLayout = nil
                }
            } message: {
                Text("Enter a name for this layout.")
            }
            
            //Delete Alert
            .alert(
                "Are you sure you want to delete?",
                isPresented: Binding(
                    get: { layoutToDelete != nil },
                    set: { isPresented in
                        if !isPresented {
                            layoutToRename = nil
                            swipedLayout = nil
                        }
                    }
                )
            ) {
                Button("Cancel", role: .cancel) {
                    layoutToDelete = nil
                    swipedLayout = nil
                }

                Button("Delete", role: .destructive) {
                    if let layout = layoutToDelete {
                        layouts.removeAll { $0 == layout }
                    }

                    layoutToDelete = nil
                    swipedLayout = nil
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
                    // Later will be navigated to Scan New Room
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(.black)
                .padding(.trailing, 24)
                .padding(.bottom, 24)
            }
        }
    }
}

#Preview("Empty State") {
    DashboardView(layouts: [])
}

#Preview("Filled State") {
    DashboardView(layouts: [
        "Bedroom 1",
        "Bedroom 2"
    ])
}
