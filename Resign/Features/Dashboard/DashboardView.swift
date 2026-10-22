//
//  DashboardView.swift
//  Resign
//

import SwiftUI
import SwiftData

public struct DashboardView: View {
    @Query(sort: \Room.updatedAt, order: .reverse) private var rooms: [Room]
    @State private var isPresentingScanner = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if rooms.isEmpty {
                    emptyStateView
                } else {
                    roomListView
                }
            }
            .navigationTitle("My Rooms")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingScanner = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fullScreenCover(isPresented: $isPresentingScanner) {
                RoomScanView { roomId in
                    // Scan completed and saved to SwiftData
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "cube.transparent")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No Rooms Scanned")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Use Apple's LiDAR Scanner to capture your room geometry, windows, and furniture.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button {
                isPresentingScanner = true
            } label: {
                Label("Scan Your Room", systemImage: "camera.viewfinder")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private var roomListView: some View {
        List(rooms) { room in
            VStack(alignment: .leading, spacing: 6) {
                Text(room.name)
                    .font(.headline)

                HStack(spacing: 12) {
                    Text(String(format: "%.2fm × %.2fm", room.width, room.length))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let layout = room.layouts.first {
                        Text("\(layout.furnitures.count) items")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}
