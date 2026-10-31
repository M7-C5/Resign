//
//  YourLayoutResultView.swift
//  Resign
//
//  Created by Antigravity on 26/10/26.
//

import SwiftUI

public struct YourLayoutResultView: View {
    @Bindable public var viewModel: InsightsViewModel
    public var studioViewModel: Studio3DViewModel
    public var onSeeSuggestions: () -> Void
    public var onBack: () -> Void

    public init(
        viewModel: InsightsViewModel,
        studioViewModel: Studio3DViewModel,
        onSeeSuggestions: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.studioViewModel = studioViewModel
        self.onSeeSuggestions = onSeeSuggestions
        self.onBack = onBack
    }

    private var roomWidthText: String {
        guard let room = viewModel.currentRoom else { return "5.2 m" }
        return String(format: "%.1f m", room.width)
    }

    private var roomLengthText: String {
        guard let room = viewModel.currentRoom else { return "4.8 m" }
        return String(format: "%.1f m", room.length)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            // Main Content: Spacious ScrollView with 3D Studio & Diagnostics
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Top: Interactive 3D Studio Canvas with Dimension Overlays
                    VStack(alignment: .leading, spacing: 8) {
                        ZStack(alignment: .top) {
                            Studio3DSuggestionView(viewModel: studioViewModel)
                                .frame(maxWidth: .infinity)
                                .frame(height: 310)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                )

                            // Architectural dimension lines matching reference design
                            dimensionCalloutsOverlay
                        }

                        HStack {
                            Label("Interactive 3D: Drag to orbit, pinch to zoom", systemImage: "hand.draw")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if !studioViewModel.highlightedFurnitureIDs.isEmpty {
                                Button("Clear Highlights") {
                                    viewModel.clearHighlights()
                                    studioViewModel.clearHighlights()
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.blue)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                    // Room Review Card (Panero & Zelnik Violations)
                    roomReviewCard

                    // Spacer to ensure nothing is clipped by the bottom CTA bar
                    Spacer().frame(height: 80)
                }
                .padding(.top, 6)
            }
            .overlay(alignment: .bottom) {
                // Bottom Action Bar
                VStack(spacing: 0) {
                    Divider()
                    Button {
                        onSeeSuggestions()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                            Text("See Layout Suggestions")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.blue, in: Capsule())
                        .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear {
            syncStudioScene()
        }
    }

    private func syncStudioScene() {
        guard let room = viewModel.currentRoom, let layout = viewModel.activeLayout ?? room.layouts.first else { return }
        let doors = room.openings.filter { $0.type.localizedCaseInsensitiveContains("door") }
        studioViewModel.applyLayout(layout, animated: false)
        studioViewModel.setViolations(viewModel.detectedViolations, in: layout, doors: doors)
    }

    // MARK: - Dimension Callouts

    private var dimensionCalloutsOverlay: some View {
        HStack {
            // Width Dimension (Left Top Diagonal)
            HStack(spacing: 4) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 10, weight: .bold))
                Text(roomWidthText)
                    .font(.system(size: 12, weight: .bold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .rotationEffect(.degrees(-32))
            .offset(x: 10, y: 15)

            Spacer()

            // Length Dimension (Right Top Diagonal)
            HStack(spacing: 4) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 10, weight: .bold))
                Text(roomLengthText)
                    .font(.system(size: 12, weight: .bold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .rotationEffect(.degrees(32))
            .offset(x: -10, y: 15)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .allowsHitTesting(false)
    }

    // MARK: - Review Card

    private var roomReviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Clearance Analysis")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)

                    Text(viewModel.detectedViolations.isEmpty ? "All standard clearance tolerances satisfied." : "Measured violations against Panero & Zelnik standards.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !viewModel.detectedViolations.isEmpty {
                    Text("\(viewModel.detectedViolations.count) Issues")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }

            VStack(spacing: 12) {
                if !viewModel.detectedViolations.isEmpty {
                    ForEach(viewModel.detectedViolations) { violation in
                        reviewRow(
                            iconName: violation.severity == .critical ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill",
                            iconColor: violation.severity == .critical ? .red : .orange,
                            title: "\(conciseTitle(for: violation)) Clearance (\(violation.ruleId))",
                            detail: "\(violation.message) Measured: \(String(format: "%.0f", violation.measuredClearanceCm))cm (Req: \(String(format: "%.0f", violation.requiredClearanceCm))cm)"
                        )
                        if violation.id != viewModel.detectedViolations.last?.id {
                            Divider()
                        }
                    }
                } else {
                    reviewRow(
                        iconName: "checkmark.circle.fill",
                        iconColor: .green,
                        title: "Optimal Circulation",
                        detail: "Clearance guidelines satisfy standard ergonomic tolerances."
                    )
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
    }



    private func reviewRow(iconName: String, iconColor: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 20))
                .foregroundStyle(iconColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
    }

    private func conciseTitle(for violation: SpatialViolation) -> String {
        switch violation.ruleId {
        case PaneroZelnikRule.walkwayCritical, PaneroZelnikRule.walkwayRecommended:
            return "Narrow"
        case PaneroZelnikRule.deskRearClearance:
            return "Desk"
        case PaneroZelnikRule.doorSwingUnobstructed:
            return "Door"
        case PaneroZelnikRule.bedOperationalZone, PaneroZelnikRule.bedStorageZone:
            return "Bed"
        default:
            return violation.ruleTitle
        }
    }

    private var headerBar: some View {
        HStack {
            Button {
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }

            Spacer()

            Text("Your Layout")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)

            Spacer()

            Spacer().frame(width: 36)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}
