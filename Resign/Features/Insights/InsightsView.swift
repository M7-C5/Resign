//
//  InsightsView.swift
//  Resign
//
//  Created by Antigravity on 21/10/26.
//

import SwiftUI
import SwiftData

public struct InsightsView: View {
    @State public var viewModel = InsightsViewModel()
    public var studioViewModel: Studio3DViewModel?

    @Query private var rooms: [Room]

    @State private var environmentPreset: Int = 0

    public init(studioViewModel: Studio3DViewModel? = nil) {
        self.studioViewModel = studioViewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - Room Mode Selector
                    Picker("Room Source", selection: $environmentPreset) {
                        Text("Live USDZ Mock Room").tag(0)
                        Text("Clashes Demo Room").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: environmentPreset) { _, newValue in
                        if newValue == 0 {
                            if let room = try? RoomRepository.loadMockRoomFromUSDZ() {
                                viewModel.loadRoom(room)
                            }
                        } else {
                            let room = RoomRepository.createViolatingMockRoom()
                            viewModel.loadRoom(room)
                        }
                    }

                    // MARK: - Header Room Summary Card
                    roomSummaryCard

                    // MARK: - User Preference & Diagnostic Action
                    diagnosticControlsCard

                    // MARK: - Panero & Zelnik Measured Violations
                    if !viewModel.detectedViolations.isEmpty {
                        violationsSection
                    }

                    // MARK: - AI Human Insights
                    if let response = viewModel.diagnosticResponse, !response.insights.isEmpty {
                        aiInsightsSection(response: response)
                    }

                    // MARK: - Generated 3 Layout Variants
                    if !viewModel.generatedLayouts.isEmpty {
                        layoutVariantsSection
                    }
                }
                .padding()
            }
            .navigationTitle("Spatial Diagnostics")
            .task {
                if viewModel.currentRoom == nil {
                    if let first = rooms.first {
                        viewModel.loadRoom(first)
                    } else if let usdzRoom = try? RoomRepository.loadMockRoomFromUSDZ() {
                        viewModel.loadRoom(usdzRoom)
                    } else {
                        let mock = RoomRepository.createViolatingMockRoom()
                        viewModel.loadRoom(mock)
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private var roomSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Scanned Environment", systemImage: "cube.transparent")
                    .font(.headline)
                Spacer()
                if let room = viewModel.currentRoom {
                    Text("\(String(format: "%.1f", room.width))m × \(String(format: "%.1f", room.length))m")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.secondarySystemFill), in: Capsule())
                }
            }

            if let room = viewModel.currentRoom, let layout = viewModel.activeLayout ?? room.layouts.first {
                HStack(spacing: 16) {
                    VStack(alignment: .leading) {
                        Text("\(layout.furnitures.count)")
                            .font(.title2).bold()
                        Text("Furniture Items")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider().frame(height: 30)
                    VStack(alignment: .leading) {
                        Text("\(room.openings.count)")
                            .font(.title2).bold()
                        Text("Doors & Windows")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider().frame(height: 30)
                    VStack(alignment: .leading) {
                        Text("\(viewModel.highlightedFurnitureIDs.count)")
                            .font(.title2).bold()
                            .foregroundStyle(viewModel.highlightedFurnitureIDs.isEmpty ? Color.primary : Color.orange)
                        Text("3D Highlights")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var diagnosticControlsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Optimization Goal")
                .font(.subheadline).bold()
                .foregroundStyle(.secondary)

            TextField("e.g. Spacious Circulation, Work Focus", text: $viewModel.userPreference)
                .textFieldStyle(.roundedBorder)

            Button {
                guard let room = viewModel.currentRoom, let layout = viewModel.activeLayout ?? room.layouts.first else { return }
                Task {
                    await viewModel.runDiagnosticPipeline(
                        for: room,
                        in: layout,
                        preference: viewModel.userPreference
                    )
                }
            } label: {
                HStack {
                    if viewModel.isAnalyzing {
                        ProgressView()
                            .tint(.white)
                            .padding(.trailing, 6)
                        Text("Analyzing Clearance Geometry...")
                    } else {
                        Image(systemName: "sparkles")
                        Text("Run AI Diagnostics & Solve Layouts")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            }
            .disabled(viewModel.isAnalyzing)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var violationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Panero & Zelnik Rulebook Violations", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Spacer()
                Text("\(viewModel.detectedViolations.count) Detected")
                    .font(.caption).bold()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15), in: Capsule())
            }

            ForEach(viewModel.detectedViolations) { violation in
                HStack(alignment: .top, spacing: 12) {
                    Text(violation.ruleId)
                        .font(.caption).bold()
                        .padding(6)
                        .background(violation.severity == .critical ? Color.red.opacity(0.2) : Color.orange.opacity(0.2))
                        .foregroundStyle(violation.severity == .critical ? Color.red : Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(violation.ruleTitle)
                            .font(.subheadline).bold()
                        Text(violation.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Text("Measured: \(String(format: "%.1f", violation.measuredClearanceCm)) cm")
                            Text("•")
                            Text("Required: \(String(format: "%.1f", violation.requiredClearanceCm)) cm")
                        }
                        .font(.caption2).bold()
                        .foregroundStyle(.primary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func aiInsightsSection(response: AIDiagnosticResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("AI Human Reasoning & Fixes", systemImage: "brain.head.profile")
                    .font(.headline)
                    .foregroundStyle(.purple)
                Spacer()
                if !viewModel.highlightedFurnitureIDs.isEmpty {
                    Button("Clear 3D Rings") {
                        viewModel.clearHighlights()
                    }
                    .font(.caption)
                }
            }

            ForEach(response.insights) { insight in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(insight.ruleId)
                            .font(.caption2).bold()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15), in: Capsule())

                        Text(insight.sentiment == "+" ? "Synergy" : "Clash")
                            .font(.caption2).bold()
                            .foregroundStyle(insight.sentiment == "+" ? .green : .red)

                        Spacer()

                        if !insight.involvedFurnitureIds.isEmpty {
                            Button {
                                viewModel.selectInsight(insight)
                            } label: {
                                Label("Highlight in 3D", systemImage: "ring")
                                    .font(.caption2).bold()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Text(insight.explanation)
                        .font(.subheadline)

                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Text(insight.suggestedFix)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var layoutVariantsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Layout Engine Variants (3)", systemImage: "rectangle.3.group")
                .font(.headline)

            ForEach(viewModel.generatedLayouts) { layout in
                let isSelected = viewModel.selectedLayout?.id == layout.id
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(layout.name)
                                .font(.headline)
                            Text("\(layout.furnitures.count) Furnishings • \(layout.insights.count) Enhancements")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isSelected {
                            Label("Active", systemImage: "checkmark.circle.fill")
                                .font(.caption).bold()
                                .foregroundStyle(.green)
                        } else {
                            Button("Select") {
                                viewModel.selectLayout(layout)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }

                    ForEach(layout.insights) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.caption).bold()
                                Text(item.detail).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected ? Color.blue.opacity(0.1) : Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
