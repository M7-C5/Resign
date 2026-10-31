//
//  SpatialJourneyFlowView.swift
//  Resign
//
//  Created by Antigravity on 26/10/26.
//

import SwiftUI
import SwiftData

public enum SpatialJourneyStep: Hashable {
    case preferences
    case yourLayout
    case suggestions
}

public struct SpatialJourneyFlowView: View {
    @State public var viewModel = InsightsViewModel()
    @State public var studioViewModel = Studio3DViewModel()
    @State public var currentStep: SpatialJourneyStep = .preferences
    @State public var environmentPreset: Int = 0

    @Query private var rooms: [Room]

    public init() {}

    public var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            switch currentStep {
            case .preferences:
                PreferencePageView(
                    viewModel: viewModel,
                    environmentPreset: $environmentPreset,
                    onEnvironmentPresetChanged: { newPreset in
                        switchEnvironmentPreset(to: newPreset)
                    },
                    onContinue: {
                        Task {
                            await proceedToDiagnostics()
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

            case .yourLayout:
                YourLayoutResultView(
                    viewModel: viewModel,
                    studioViewModel: studioViewModel,
                    onSeeSuggestions: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentStep = .suggestions
                        }
                    },
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentStep = .preferences
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

            case .suggestions:
                LayoutSuggestionsDisplayView(
                    viewModel: viewModel,
                    studioViewModel: studioViewModel,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentStep = .yourLayout
                        }
                    },
                    onApply: {
                        if let selected = viewModel.selectedLayout {
                            viewModel.activeLayout = selected
                        }
                    },
                    onStartOver: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentStep = .preferences
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: currentStep)
        .task {
            ensureRoomLoaded()
        }
        .onChange(of: viewModel.highlightedFurnitureIDs) { _, ids in
            studioViewModel.highlightFurniture(ids: ids)
        }
    }

    // MARK: - Preset Room Management


    public func switchEnvironmentPreset(to preset: Int) {
        environmentPreset = preset
        studioViewModel.clearHighlights()
        studioViewModel.clearViolations()

        if preset == 0 {
            if let usdzRoom = try? RoomRepository.loadMockRoomFromUSDZ() {
                viewModel.loadRoom(usdzRoom)
            }
        } else {
            let mock = RoomRepository.createViolatingMockRoom()
            viewModel.loadRoom(mock)
        }

        if let room = viewModel.currentRoom, let layout = viewModel.activeLayout ?? room.layouts.first {
            let doors = room.openings.filter { $0.type.localizedCaseInsensitiveContains("door") }
            studioViewModel.setViolations(viewModel.detectedViolations, in: layout, doors: doors)
        }
    }

    private func ensureRoomLoaded() {
        guard viewModel.currentRoom == nil else { return }
        if environmentPreset == 0, let usdzRoom = try? RoomRepository.loadMockRoomFromUSDZ() {
            viewModel.loadRoom(usdzRoom)
        } else if let first = rooms.first {
            viewModel.loadRoom(first)
        } else {
            let mock = RoomRepository.createViolatingMockRoom()
            viewModel.loadRoom(mock)
        }
    }

    private func proceedToDiagnostics() async {
        ensureRoomLoaded()
        guard let room = viewModel.currentRoom, let layout = viewModel.activeLayout ?? room.layouts.first else { return }

        await viewModel.runDiagnosticPipeline(for: room, in: layout)

        let doors = room.openings.filter { $0.type.localizedCaseInsensitiveContains("door") }
        studioViewModel.setViolations(viewModel.detectedViolations, in: layout, doors: doors)

        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = .yourLayout
        }
    }
}

