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
    public var onCancel: (() -> Void)?

    public init(
        onScanComplete: ((UUID) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.onScanComplete = onScanComplete
        self.onCancel = onCancel
    }

    private var isShowingErrorAlert: Binding<Bool> {
        Binding(
            get: {
                if case .error = viewModel.state { return true }
                return false
            },
            set: { newValue in
                if !newValue, case .error = viewModel.state {
                    viewModel.state = .ready
                }
            }
        )
    }

    private var errorMessage: String {
        if case .error(let message) = viewModel.state {
            return message
        }
        return ""
    }

    public var body: some View {
        Group {
            if viewModel.state == .unsupported {
                hardwareRequiredView
            } else {
                scannerView
            }
        }
        .onAppear {
            if viewModel.state == .ready {
                viewModel.startScanning()
            }
        }
        .onChange(of: viewModel.state) { _, newState in
            switch newState {
            case .completed(let roomId):
                onScanComplete?(roomId)
                dismiss()
            case .cancelled:
                onCancel?()
                dismiss()
            default:
                break
            }
        }
        .alert("Are you done scanning?", isPresented: $viewModel.isShowingConfirmationAlert) {
            Button("No", role: .cancel) {
                viewModel.dismissConfirmationAlert()
            }
            Button("Yes") {
                viewModel.confirmFinishScanning()
            }
        } message: {
            Text("Your progress will be processed and you can't go back")
        }
        .alert("Scan Incomplete", isPresented: isShowingErrorAlert) {
            Button("Try Again") {
                viewModel.startScanning()
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelScanning()
            }
        } message: {
            Text(errorMessage)
        }
    }

    private var scannerView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            RoomCaptureViewWrapper(
                captureView: viewModel.captureView,
                isCancelled: viewModel.isCancelled,
                onComplete: { capturedRoom in
                    viewModel.process(capturedRoom: capturedRoom, modelContext: modelContext)
                },
                onError: { error in
                    if !viewModel.isCancelled {
                        viewModel.state = .error(error.localizedDescription)
                    }
                }
            )
            .ignoresSafeArea()

            RoomScanOverlayView(
                state: viewModel.state,
                onDone: {
                    viewModel.requestFinishScanning()
                },
                onCancel: {
                    viewModel.cancelScanning()
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

            #if DEBUG
            Button {
                viewModel.loadMockRoom(modelContext: modelContext)
            } label: {
                Label("Load Sample Room (Simulator)", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            #endif

            Button("Cancel") {
                onCancel?()
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
