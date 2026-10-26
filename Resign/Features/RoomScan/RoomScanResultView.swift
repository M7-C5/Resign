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
    public var onContinueToOrientation: ((Layout) -> Void)?
    public var onFinish: (() -> Void)?

    @Query private var rooms: [Room]
    @State private var quickLookURL: URL? = nil

    public init(
        roomId: UUID,
        onScanAgain: @escaping () -> Void,
        onContinueToOrientation: ((Layout) -> Void)? = nil,
        onFinish: (() -> Void)? = nil
    ) {
        self.roomId = roomId
        self.onScanAgain = onScanAgain
        self.onContinueToOrientation = onContinueToOrientation
        self.onFinish = onFinish
        let targetId = roomId
        _rooms = Query(filter: #Predicate<Room> { $0.id == targetId })
    }

    private var room: Room? {
        rooms.first
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
        .quickLookPreview($quickLookURL)
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

            Text(String(format: "%.2fm (W) × %.2fm (L) • Height: %.2fm", room.width, room.length, room.height))
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
            if let url = layout.usdzURL {
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

            // Primary: Calibrate north before placing lights
            if let onContinueToOrientation {
                Button {
                    onContinueToOrientation(layout)
                } label: {
                    Label("Set Room North", systemImage: "location.north.fill")
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
                if let onFinish {
                    Button(action: onFinish) {
                        Label("Save & Finish", systemImage: "checkmark")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    }
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

            Text(String(format: "%.2fm × %.2fm", item.width, item.length))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(width: 140)
        .padding(12)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
