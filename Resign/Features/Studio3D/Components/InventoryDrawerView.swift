//
//  InventoryDrawerView.swift
//  Resign
//

import SwiftUI

public struct InventoryDrawerView: View {
    public let archivedFurnitures: [Furniture]
    public let isHoveringArchiveTarget: Bool
    public let isOpen: Bool
    public let onToggleOpen: () -> Void
    public let onTargetCenterResolved: (CGPoint) -> Void
    public let onRestoreItem: (Furniture, CGPoint?) -> Void

    public init(
        archivedFurnitures: [Furniture],
        isHoveringArchiveTarget: Bool,
        isOpen: Bool,
        onToggleOpen: @escaping () -> Void,
        onTargetCenterResolved: @escaping (CGPoint) -> Void,
        onRestoreItem: @escaping (Furniture, CGPoint?) -> Void
    ) {
        self.archivedFurnitures = archivedFurnitures
        self.isHoveringArchiveTarget = isHoveringArchiveTarget
        self.isOpen = isOpen
        self.onToggleOpen = onToggleOpen
        self.onTargetCenterResolved = onTargetCenterResolved
        self.onRestoreItem = onRestoreItem
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            // Inventory Icon Trigger
            inventoryButton
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                let frame = geo.frame(in: .global)
                                onTargetCenterResolved(CGPoint(x: frame.midX, y: frame.midY))
                            }
                            .onChange(of: geo.frame(in: .global)) { _, newFrame in
                                onTargetCenterResolved(CGPoint(x: newFrame.midX, y: newFrame.midY))
                            }
                    }
                )

            // Sliding Drawer Cards (to the right of the icon)
            if isOpen {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        if archivedFurnitures.isEmpty {
                            emptyStateCard
                        } else {
                            ForEach(archivedFurnitures) { item in
                                InventoryItemCard(
                                    furniture: item,
                                    onTap: {
                                        onRestoreItem(item, nil)
                                    },
                                    onDragToFloor: { screenPoint in
                                        onRestoreItem(item, screenPoint)
                                    }
                                )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
    }

    private var inventoryButton: some View {
        Button(action: onToggleOpen) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "archivebox.fill")
                    .font(.body)
                    .foregroundStyle(isHoveringArchiveTarget ? Color.orange : Color.primary)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                isHoveringArchiveTarget ? Color.orange : Color.clear,
                                lineWidth: 2.5
                            )
                    )
                    .shadow(
                        color: isHoveringArchiveTarget ? Color.orange.opacity(0.4) : Color.clear,
                        radius: 8
                    )
                    .scaleEffect(isHoveringArchiveTarget ? 1.18 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHoveringArchiveTarget)

                if !archivedFurnitures.isEmpty {
                    Text("\(archivedFurnitures.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                        .offset(x: 4, y: -4)
                }
            }
        }
        .accessibilityLabel(isOpen ? "Close Inventory" : "Open Inventory, \(archivedFurnitures.count) items archived")
    }

    private var emptyStateCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("No archived items\nDrag here to archive")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

public struct InventoryItemCard: View {
    public let furniture: Furniture
    public let onTap: () -> Void
    public let onDragToFloor: (CGPoint) -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isDraggingOut = false

    public var body: some View {
        GeometryReader { geo in
            VStack(spacing: 4) {
                Image(systemName: categorySystemImage(for: furniture.category))
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(height: 24)

                Text(furniture.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                let shorter = min(furniture.width, furniture.length)
                let longer = max(furniture.width, furniture.length)
                Text(String(format: "%.1f×%.1f m", shorter, longer))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 76, height: 86)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 4, y: 2)
            .offset(dragOffset)
            .opacity(isDraggingOut ? 0.4 : 1.0)
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        dragOffset = value.translation
                        if value.translation.height < -15 || abs(value.translation.width) > 25 {
                            isDraggingOut = true
                        }
                    }
                    .onEnded { value in
                        let startFrame = geo.frame(in: .global)
                        let endPoint = CGPoint(
                            x: startFrame.midX + value.translation.width,
                            y: startFrame.midY + value.translation.height
                        )
                        if isDraggingOut || value.translation.height < -15 {
                            onDragToFloor(endPoint)
                        } else {
                            onTap()
                        }
                        dragOffset = .zero
                        isDraggingOut = false
                    }
            )
            .onTapGesture {
                onTap()
            }
        }
        .frame(width: 76, height: 86)
        .accessibilityLabel("\(furniture.name), archived")
    }

    private func categorySystemImage(for category: String) -> String {
        switch category.lowercased() {
        case "bed":
            return "bed.double.fill"
        case "sofa":
            return "sofa.fill"
        case "desk", "table":
            return "table.furniture.fill"
        case "chair":
            return "chair.lounge.fill"
        case "storage", "closet":
            return "cabinet.fill"
        case "television", "tv":
            return "tv.fill"
        default:
            return "shippingbox.fill"
        }
    }
}
