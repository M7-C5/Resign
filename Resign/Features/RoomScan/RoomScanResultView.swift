//
//  RoomScanResultView.swift
//  Resign
//

import SwiftUI
import RealityKit
import SwiftData
import QuickLook
import UIKit
import simd

public struct RoomScanResultView: View {
    public let roomId: UUID
    public let onScanAgain: () -> Void
    public var onContinueToLighting: ((Layout) -> Void)?
    public var onFinish: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var loadedRoom: Room?
    @State private var quickLookURL: URL? = nil

    public init(
        roomId: UUID,
        onScanAgain: @escaping () -> Void,
        onContinueToLighting: ((Layout) -> Void)? = nil,
        onFinish: (() -> Void)? = nil
    ) {
        self.roomId = roomId
        self.onScanAgain = onScanAgain
        self.onContinueToLighting = onContinueToLighting
        self.onFinish = onFinish
    }

    private var room: Room? {
        loadedRoom
    }

    private var layout: Layout? {
        room?.layouts.first
    }

    public var body: some View {
        ZStack {
            Color(white: 0.10).ignoresSafeArea()

            if let room, let layout {
                VStack(spacing: 0) {
                    // Top Metrics Bar
                    headerBar(room: room)

                    // Interactive 3D RealityKit Dollhouse Viewport
                    Room3DRealityViewport(room: room, layout: layout)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Bottom Details & Action Card
                    bottomCard(room: room, layout: layout)
                }
            } else {
                ProgressView("Loading 3D Room...")
                    .foregroundStyle(.white)
            }
        }
        .onAppear {
            loadRoom()
        }
        .quickLookPreview($quickLookURL)
    }

    private func loadRoom() {
        let targetId = roomId
        let descriptor = FetchDescriptor<Room>(predicate: #Predicate<Room> { $0.id == targetId })
        if let match = try? modelContext.fetch(descriptor).first {
            loadedRoom = match
        }
    }

    private func headerBar(room: Room) -> some View {
        VStack(spacing: 4) {
            Text("Scan Complete")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(.green.opacity(0.15), in: Capsule())

            Text(room.name)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            let shorter = min(room.width, room.length)
            let longer = max(room.width, room.length)
            Text(String(format: "%.2fm (W) × %.2fm (L) • Height: %.2fm", shorter, longer, room.height))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private func bottomCard(room: Room, layout: Layout) -> some View {
        VStack(spacing: 16) {
            // Metrics Summary Row
            HStack(spacing: 12) {
                metricChip(
                    icon: "door.left.hand.open",
                    label: "\(room.openings.count) Openings"
                )

                metricChip(
                    icon: "bed.double.fill",
                    label: "\(layout.furnitures.count) Furnitures"
                )

                Spacer()
            }
            .padding(.horizontal, 20)

            // Detected Furniture Items List
            if !layout.furnitures.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(layout.furnitures) { item in
                            furnitureCard(for: item)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            // QuickLook & Export Actions Row
            if let url = layout.resolvedUSDZURL ?? layout.usdzURL {
                HStack(spacing: 12) {
                    Button {
                        quickLookURL = url
                    } label: {
                        Label("AR QuickLook", systemImage: "arkit")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    }

                    ShareLink(item: url) {
                        Label("Export 3D", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 20)
            }

            // Primary: Open ceiling light placement directly
            if let onContinueToLighting {
                Button {
                    onContinueToLighting(layout)
                } label: {
                    Label("Configure Lighting", systemImage: "lightbulb.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 20)
            }

            // Secondary Actions Row
            HStack(spacing: 12) {
                Button {
                    if let onFinish {
                        onFinish()
                    } else {
                        dismiss()
                    }
                } label: {
                    Label("Save & Finish", systemImage: "checkmark")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                }

                Button(action: onScanAgain) {
                    Label("Scan Again", systemImage: "camera.viewfinder")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .padding(.top, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .ignoresSafeArea(edges: .bottom)
    }

    private func metricChip(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.white.opacity(0.12), in: Capsule())
    }

    private func furnitureCard(for item: Furniture) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.category.capitalized)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(item.name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            let itemW = min(item.width, item.length)
            let itemL = max(item.width, item.length)
            Text(String(format: "%.2fm (W) × %.2fm (L)", itemW, itemL))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(width: 140)
        .padding(12)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
