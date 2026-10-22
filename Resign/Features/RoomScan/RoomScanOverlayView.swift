//
//  RoomScanOverlayView.swift
//  Resign
//

import SwiftUI
import RoomPlan

public struct RoomScanOverlayView: View {
    public let state: RoomScanViewModel.ScanState
    public let instructionText: String?
    public let onStart: () -> Void
    public let onFinish: () -> Void
    public let onCancel: () -> Void

    public init(
        state: RoomScanViewModel.ScanState,
        instructionText: String? = nil,
        onStart: @escaping () -> Void,
        onFinish: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.state = state
        self.instructionText = instructionText
        self.onStart = onStart
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer()

                Text("Room Scanner")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                // Balancing spacer
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .opacity(0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Instruction Banner
            if let instruction = instructionText, state == .scanning {
                Text(instruction)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 16)
            }

            Spacer()

            // Bottom Actions & State Controls
            VStack(spacing: 16) {
                switch state {
                case .ready:
                    Button(action: onStart) {
                        Label("Start Scanning", systemImage: "camera.viewfinder")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    }

                case .scanning:
                    Button(action: onFinish) {
                        Label("Finish & Orient Room", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    }

                case .processing:
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text("Sanitizing geometry & generating USD...")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

                default:
                    EmptyView()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}
