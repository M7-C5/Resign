//
//  LayoutDetailsView.swift
//  Resign
//

import SwiftUI

struct LayoutDetailsView: View {
    
    let roomName: String
    
    // Temporary Layout Data
    @State private var layouts = [
        "Original",
        "Option 1",
        "Option 2",
        "Option 3",
        "Custom Save 1"
    ]
    
    // To track swipe, deletion, & selection
    @State private var swipedLayout: String?
    @State private var layoutToDelete: String?
    @State private var selectedLayout: String?
    
    var body: some View {
        ScrollView{
            VStack(alignment: .leading, spacing: 16) {
                
                Text("Choose a layout to view or edit.")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                
                ForEach(layouts, id: \.self) { layout in
                    HStack(spacing: 0) {
                        
                        layoutRow(
                            title: layout,
                            subtitle: subtitle(for: layout),
                            isSelected: selectedLayout == layout
                        )
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if swipedLayout == layout {
                                withAnimation(.smooth) {
                                    swipedLayout = nil
                                }
                            } else {
                                selectedLayout = layout
                                // Later will be navigated to Room Preview
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 20)
                                .onEnded { value in
                                    if value.translation.width < -40 {
                                        withAnimation(.smooth) {
                                            swipedLayout = layout
                                        }
                                    } else if value.translation.width > 40 {
                                        withAnimation(.smooth) {
                                            if swipedLayout == layout {
                                                swipedLayout = nil
                                            }
                                        }
                                    }
                                }
                        )
                        
                        // Delete Button (for all layouts)
                        if swipedLayout == layout {
                            Button {
                                layoutToDelete = layout
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(.red, in: Circle())
                            }
                            .padding(.leading, 12)
                            .transition(.opacity)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color.white)
        .navigationTitle(roomName)
        .navigationBarTitleDisplayMode(.inline)
        
        // Native back button is shown automatically when navigating from DashboardView
        
        .alert(
            "Delete Layout?",
            isPresented: Binding (
                get: { layoutToDelete != nil },
                set: { isPresented in
                    if !isPresented {
                        layoutToDelete = nil
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
                    
                    if selectedLayout == layout {
                        selectedLayout = nil
                    }
                }
                
                layoutToDelete = nil
                swipedLayout = nil
            }
        } message: {
            Text("This saved layout will be permanently deleted.")
        }
    }
        
    // Reusable Layout Row
    private func layoutRow(
        title: String,
        subtitle: String,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 12) {
            
            // Temporary Thumbnail Placeholder
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 72, height: 72)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.black)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.subheadline)
                .foregroundStyle(.black)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    isSelected
                    ? Color.white
                    : Color.gray.opacity(0.2)
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isSelected ? Color.blue : Color.clear,
                    lineWidth: 2
                )
        }
    }
    
    // Temporary Subtitles for Data Preview
    private func subtitle(for layout: String) -> String {
        switch layout {
        case "Original":
            return "Original Layout"
        case "Option 1":
            return "Balanced and Spacious"
        case "Option 2":
            return "Open Space"
        case "Option 3":
            return "Meeting Focus"
        case "Custom Save 1":
            return "Custom"
        default:
            return ""
        }
    }
}

#Preview {
    NavigationStack {
        LayoutDetailsView(roomName: "Bedroom 1")
    }
}
