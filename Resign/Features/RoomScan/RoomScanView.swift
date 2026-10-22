//
//  RoomScanView.swift
//  Resign
//

import SwiftUI
import RoomPlan
import SwiftData

public struct RoomScanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = RoomScanViewModel()

    public var onScanComplete: ((UUID) -> Void)?

    public init(onScanComplete: ((UUID) -> Void)? = nil) {
        self.onScanComplete = onScanComplete
    }

    public var body: some View {
        Group {
            if viewModel.state == .unsupported {
                hardwareRequiredView
            } else {
                scannerView
            }
        }
        .onChange(of: viewModel.state) { _, newState in
            if case .completed(let roomId) = newState {
                onScanComplete?(roomId)
                dismiss()
            }
        }
    }

    private var scannerView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            RoomCaptureViewWrapper(
                captureView: viewModel.captureView,
                onComplete: { capturedRoom in
                    viewModel.process(capturedRoom: capturedRoom, modelContext: modelContext)
                },
                onInstruction: { instruction in
                    viewModel.handleInstruction(instruction)
                },
                onError: { error in
                    viewModel.state = .error(error.localizedDescription)
                }
            )
            .ignoresSafeArea()

            RoomScanOverlayView(
                state: viewModel.state,
                instructionText: viewModel.instructionText,
                onStart: {
                    viewModel.startScanning()
                },
                onFinish: {
                    viewModel.stopScanning()
                },
                onCancel: {
                    dismiss()
                }
            )
        }
    }

    private var hardwareRequiredView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sensor.tag.radiowaves.forward.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("LiDAR Scanner Required")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Resign requires an iPhone Pro (12 Pro or newer) equipped with Apple's LiDAR Scanner to accurately capture real-world room geometry.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button("Dismiss") {
                dismiss()
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}
