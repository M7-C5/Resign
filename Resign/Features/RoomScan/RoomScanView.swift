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
    @Environment(\.scenePhase) private var scenePhase
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
            if case .completed = viewModel.state {
                viewModel.reset()
            }
            if viewModel.state == .ready {
                viewModel.startScanning()
            }
        }
        .onDisappear {
            viewModel.pauseScanningIfActive()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.resumeNorthTracking()
            } else {
                viewModel.suspendNorthTracking()
            }
        }
        .onChange(of: viewModel.state) { _, newState in
            switch newState {
            case .completed(let roomId):
                onScanComplete?(roomId)
            case .cancelled:
                onCancel?()
                dismiss()
            default:
                break
            }
        }
        .alert("Are you done scanning?", isPresented: $viewModel.isShowingConfirmationAlert) {
            Button("Keep scanning", role: .cancel) {
                viewModel.dismissConfirmationAlert()
            }
            Button("Finish scan") {
                viewModel.confirmFinishScanning()
            }
        } message: {
            if case .calibrated(let calibration) = viewModel.northCalibrationStatus {
                if calibration.isRefined {
                    Text("Your scan and north calibration will be saved.")
                } else {
                    Text("Your scan and estimated north (±\(Int(calibration.accuracyDegrees.rounded()))°) will be saved. Keep scanning if you want to improve accuracy.")
                }
            } else {
                Text("North has not been calibrated yet. Keep scanning to find north, or finish with north unknown.")
            }
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
                        viewModel.failScanning(error)
                    }
                }
            )
            .ignoresSafeArea()

            RoomScanOverlayView(
                state: viewModel.state,
                northCalibrationStatus: viewModel.northCalibrationStatus,
                compassInterferenceWarning: viewModel.compassInterferenceWarning,
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
                .font(.largeTitle)
                .imageScale(.large)
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
