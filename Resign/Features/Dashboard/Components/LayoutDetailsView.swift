//
//  LayoutDetailsView.swift
//  Resign
//

import SwiftUI
import SwiftData

public struct LayoutDetailsView: View {
    public var room: Room
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = DashboardViewModel()

    // To track swipe, deletion, creation & selection
    @State private var swipedLayoutID: UUID?
    @State private var layoutToDelete: Layout?
    @State private var selectedLayout: Layout?
    @State private var isShowingNewLayoutAlert = false
    @State private var newLayoutName = ""

    public init(room: Room) {
        self.room = room
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose a layout to view or edit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if room.layouts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.split.2x2")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)

                        Text("No layouts generated yet.")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Button {
                            let created = viewModel.createLayout(named: "Original", in: room, context: modelContext)
                            selectedLayout = created
                        } label: {
                            Label("Create Original Layout", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(room.layouts) { layout in
                        HStack(spacing: 0) {
                            layoutRow(
                                title: layout.name,
                                subtitle: subtitle(for: layout.name),
                                isSelected: selectedLayout?.id == layout.id
                            )
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if swipedLayoutID == layout.id {
                                    withAnimation(.smooth) {
                                        swipedLayoutID = nil
                                    }
                                } else {
                                    withAnimation(.snappy) {
                                        selectedLayout = layout
                                    }
                                }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 20)
                                    .onEnded { value in
                                        if value.translation.width < -40 {
                                            withAnimation(.smooth) {
                                                swipedLayoutID = layout.id
                                            }
                                        } else if value.translation.width > 40 {
                                            withAnimation(.smooth) {
                                                if swipedLayoutID == layout.id {
                                                    swipedLayoutID = nil
                                                }
                                            }
                                        }
                                    }
                            )

                            // Delete Button
                            if swipedLayoutID == layout.id {
                                Button {
                                    layoutToDelete = layout
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.white)
                                        .frame(width: 44, height: 44)
                                        .background(Color.red, in: Circle())
                                }
                                .padding(.leading, 12)
                                .transition(.opacity)
                                .accessibilityLabel("Delete layout")
                            }
                        }
                    }

                    // Open in 3D Button when a layout is selected
                    if let selected = selectedLayout {
                        NavigationLink {
                            Studio3DView()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "cube.transparent")
                                    .font(.headline)
                                Text("Open \"\(selected.name)\" in 3D")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 50)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newLayoutName = ""
                    isShowingNewLayoutAlert = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Layout")
            }
        }
        .alert(
            "New Layout",
            isPresented: $isShowingNewLayoutAlert
        ) {
            TextField("Layout Name", text: $newLayoutName)

            Button("Cancel", role: .cancel) {}

            Button("Create") {
                let created = viewModel.createLayout(
                    named: newLayoutName,
                    in: room,
                    context: modelContext
                )
                selectedLayout = created
            }
        } message: {
            Text("Enter a name for the new room layout.")
        }
        .alert(
            "Delete Layout?",
            isPresented: Binding(
                get: { layoutToDelete != nil },
                set: { isPresented in
                    if !isPresented {
                        layoutToDelete = nil
                        swipedLayoutID = nil
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                layoutToDelete = nil
                swipedLayoutID = nil
            }

            Button("Delete", role: .destructive) {
                if let layout = layoutToDelete {
                    if selectedLayout?.id == layout.id {
                        selectedLayout = nil
                    }
                    viewModel.deleteLayout(layout, from: room, context: modelContext)
                }

                layoutToDelete = nil
                swipedLayoutID = nil
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
            // Thumbnail Placeholder
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: "cube.transparent")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    isSelected
                    ? Color(uiColor: .secondarySystemGroupedBackground)
                    : Color(uiColor: .tertiarySystemGroupedBackground)
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.clear,
                    lineWidth: 2
                )
        }
    }

    private func subtitle(for layoutTitle: String) -> String {
        switch layoutTitle {
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
            return "Custom Layout"
        }
    }
}

#Preview {
    let container = try! ModelContainer.createInMemoryContainer()
    let room = Room(name: "Bedroom 1")
    let layout1 = Layout(name: "Original")
    let layout2 = Layout(name: "Option 1")
    room.layouts.append(layout1)
    room.layouts.append(layout2)
    container.mainContext.insert(room)

    return NavigationStack {
        LayoutDetailsView(room: room)
            .modelContainer(container)
    }
}
