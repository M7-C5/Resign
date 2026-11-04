//
//  RoomScanOverlayView.swift
//  Resign
//

import SwiftUI
import RoomPlan
import UIKit

public struct RoomScanOverlayView: View {
    @Environment(\.openURL) private var openURL
    public let state: RoomScanViewModel.ScanState
    public let northCalibrationStatus: NorthCalibrationStatus
    public let compassInterferenceWarning: CompassInterferenceWarning?
    public let onDone: () -> Void
    public let onCancel: () -> Void

    public init(
        state: RoomScanViewModel.ScanState,
        northCalibrationStatus: NorthCalibrationStatus = .searching,
        compassInterferenceWarning: CompassInterferenceWarning? = nil,
        onDone: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.state = state
        self.northCalibrationStatus = northCalibrationStatus
        self.compassInterferenceWarning = compassInterferenceWarning
        self.onDone = onDone
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Navigation Bar
            HStack {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
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
                            .frame(minHeight: 44)
                            .background(Color.blue, in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            if state == .scanning || state == .processing {
                Group {
                    if northCalibrationStatus == .permissionRequired {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        } label: {
                            northStatusBadge
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens app Settings to allow location access.")
                    } else {
                        northStatusBadge
                    }
                }
                .padding(.top, 10)
            }

            if state == .scanning, let compassInterferenceWarning {
                interferenceBanner(compassInterferenceWarning)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

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

    private var northStatusBadge: some View {
        let title: String
        let symbol: String
        let tint: Color
        switch northCalibrationStatus {
        case .searching:
            title = "Finding north"
            symbol = "location.north"
            tint = .orange
        case .waitingForTrueNorth:
            title = "Waiting for location to resolve north"
            symbol = "location"
            tint = .orange
        case .improvingAccuracy:
            title = "Compass reading invalid · move device slowly"
            symbol = "location.north"
            tint = .orange
        case .collecting(let count):
            title = "Finding north · \(count) readings"
            symbol = "location.north"
            tint = .orange
        case .calibrated(let calibration):
            let quality = calibration.isRefined ? "North found" : "North estimated"
            title = "\(quality) · ±\(Int(calibration.accuracyDegrees.rounded()))°"
            symbol = calibration.isRefined ? "checkmark.seal.fill" : "location.north.fill"
            tint = calibration.isRefined ? .green : .orange
        case .paused:
            title = "North paused"
            symbol = "pause.circle"
            tint = .secondary
        case .permissionRequired:
            title = "Allow Location for north"
            symbol = "location.slash"
            tint = .orange
        case .compassUnavailable:
            title = "Compass unavailable"
            symbol = "location.slash"
            tint = .secondary
        case .notCalibrated:
            title = "North not calibrated"
            symbol = "location.slash"
            tint = .secondary
        }

        return HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(title)
                .foregroundStyle(.primary)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private func interferenceBanner(_ warning: CompassInterferenceWarning) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(warning == .strongField ? "Possible magnetic interference" : "Compass accuracy is low")
                    .font(.subheadline.weight(.semibold))
                Text("A magnetic case, accessory, or nearby metal may affect north. Remove magnetic accessories or move away from metal objects and keep scanning.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.primary)
        }
        .padding(12)
        .frame(maxWidth: 520, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .allowsHitTesting(false)
    }
}
