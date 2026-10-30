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
    @State private var showAllKeywords = false

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
            .onChange(of: viewModel.detectedViolations) { _, violations in
                guard let room = viewModel.currentRoom, let layout = viewModel.activeLayout ?? room.layouts.first else { return }
                let doors = room.openings.filter { $0.type.localizedCaseInsensitiveContains("door") }
                studioViewModel?.setViolations(violations, in: layout, doors: doors)
            }
            .onChange(of: viewModel.highlightedFurnitureIDs) { _, ids in
                studioViewModel?.highlightFurniture(ids: ids)
            }
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
            Text("What's not working in your room?")
                .font(.headline)
            Text("Pick the problems that sound familiar, describe them in your own words, or both.")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Text("Suggested keywords").font(.subheadline)
                Spacer()
                Button(showAllKeywords ? "See less" : "See more") {
                    withAnimation { showAllKeywords.toggle() }
                }
                .font(.caption)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(showAllKeywords ? ProblemKeyword.allCases : ProblemKeyword.suggested) { keyword in
                    let isOn = viewModel.preference.selectedKeywords.contains(keyword)
                    Button {
                        viewModel.toggleKeyword(keyword)
                    } label: {
                        Text(keyword.title)
                            .font(.footnote)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(isOn ? Color.blue : Color(.tertiarySystemFill), in: Capsule())
                            .foregroundStyle(isOn ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Describe in your own words (optional)")
                .font(.subheadline)
            TextEditor(text: $viewModel.userPreference)
                .frame(minHeight: 90)
                .padding(6)
                .scrollContentBackground(.hidden)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            HStack(alignment: .top) {
                if !viewModel.preference.inferredKeywords.isEmpty {
                    Text("Detected: " + viewModel.preference.inferredKeywords.map(\.title).joined(separator: ", "))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(viewModel.preference.freeText.count)/\(RoomPreference.maxFreeTextLength)")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Button {
                guard let room = viewModel.currentRoom, let layout = viewModel.activeLayout ?? room.layouts.first else { return }
                Task {
                    await viewModel.runDiagnosticPipeline(
                        for: room,
                        in: layout,
                        roomPreference: viewModel.preference
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
            VStack(alignment: .leading, spacing: 6) {
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

                // Transparent Engine Source Indicator Badge
                HStack(spacing: 6) {
                    Image(systemName: response.engineSource == .appleIntelligence ? "sparkles" : "cpu")
                        .font(.caption2)
                    Text("Engine: \(response.engineSource.rawValue)")
                        .font(.caption2).bold()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    response.engineSource == .appleIntelligence
                        ? Color.purple.opacity(0.12)
                        : Color.blue.opacity(0.12),
                    in: Capsule()
                )
                .foregroundStyle(
                    response.engineSource == .appleIntelligence
                        ? Color.purple
                        : Color.blue
                )
            }

            ForEach(response.insights) { insight in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(insight.title)
                            .font(.caption).bold()
                        if let severity = insight.severity {
                            Text(severity == .critical ? "Critical" : "Warning")
                                .font(.caption2).bold()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background((severity == .critical ? Color.red : Color.orange).opacity(0.15), in: Capsule())
                                .foregroundStyle(severity == .critical ? Color.red : Color.orange)
                        }
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
                            Text("\(layout.furnitures.count) Furnishings • \((viewModel.layoutInsights[layout.id] ?? []).count) Insights")
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

                    ForEach(viewModel.layoutInsights[layout.id] ?? []) { item in
                        let positive = item.sentiment == "+"
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: positive ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(positive ? Color.green : Color.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.caption).bold()
                                Text(item.detail).font(.caption2).foregroundStyle(.secondary)
                                if !item.addressedProblems.isEmpty {
                                    Text("Helps with: " + item.addressedProblems.map(\.title).joined(separator: ", "))
                                        .font(.caption2).foregroundStyle(.blue)
                                }
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
