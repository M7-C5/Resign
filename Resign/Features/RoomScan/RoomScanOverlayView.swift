//
//  RoomScanOverlayView.swift
//  Resign
//

import SwiftUI
import RoomPlan

public struct RoomScanOverlayView: View {
    public let state: RoomScanViewModel.ScanState
    public let onDone: () -> Void
    public let onCancel: () -> Void

    public init(
        state: RoomScanViewModel.ScanState,
        onDone: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.state = state
        self.onDone = onDone
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Navigation Bar: Cancel (Top Left) — Done (Top Right)
            HStack {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .disabled(state == .processing)

                Spacer()

                if state == .scanning {
                    Button(action: onDone) {
                        Text("Done")
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(Color.blue, in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()

            // Processing / Loading State Overlay
            if state == .processing {
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    Text("Processing room scan...")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))

                Spacer()
            }
        }
    }
}
