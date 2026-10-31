//
//  LayoutSuggestionsDisplayView.swift
//  Resign
//
//  Created by Antigravity on 26/10/26.
//

import SwiftUI

public struct LayoutSuggestionsDisplayView: View {
    @Bindable public var viewModel: InsightsViewModel
    public var studioViewModel: Studio3DViewModel
    public var onBack: () -> Void
    public var onApply: (() -> Void)?
    public var onStartOver: (() -> Void)?

    @State private var isInsightsExpanded = true
    @State private var selectedIndex: Int = 0

    public init(
        viewModel: InsightsViewModel,
        studioViewModel: Studio3DViewModel,
        onBack: @escaping () -> Void,
        onApply: (() -> Void)? = nil,
        onStartOver: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.studioViewModel = studioViewModel
        self.onBack = onBack
        self.onApply = onApply
        self.onStartOver = onStartOver
    }

    private var activeVariants: [Layout] {
        viewModel.generatedLayouts
    }

    private var currentLayout: Layout? {
        guard !activeVariants.isEmpty, selectedIndex < activeVariants.count else {
            return viewModel.selectedLayout ?? viewModel.activeLayout
        }
        return activeVariants[selectedIndex]
    }

    private var currentInsights: [LayoutInsight] {
        guard let layout = currentLayout else { return [] }
        return viewModel.layoutInsights[layout.id] ?? []
    }

    private var resolvedRoomUSDZURL: URL? {
        currentLayout?.resolvedUSDZURL ?? viewModel.currentRoom?.layouts.first?.resolvedUSDZURL
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    // Option Index & Layout Title
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OPTION \(selectedIndex + 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .tracking(0.5)

                        Text(currentLayout?.name ?? "Balanced & Spacious")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                    // 3D Studio Canvas showing the selected layout
                    Studio3DSuggestionView(
                        viewModel: studioViewModel,
                        usdzURL: resolvedRoomUSDZURL ?? USDZRoomLoader.findBundledMockRoomURL()
                    )
                        .frame(maxWidth: .infinity)
                        .frame(height: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .padding(.horizontal, 16)

                    // Layout Variants Option Selector
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Alternative Solutions")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(activeVariants.enumerated()), id: \.element.id) { index, variant in
                                    let isSelected = index == selectedIndex
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            selectedIndex = index
                                            viewModel.selectLayout(variant)
                                            syncStudioWithSelectedVariant(variant)
                                        }
                                    } label: {
                                        VStack(spacing: 6) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 14)
                                                    .fill(isSelected ? Color.blue.opacity(0.12) : Color(.secondarySystemBackground))

                                                // Isometric room preview representation
                                                Image(systemName: isSelected ? "cube.transparent.fill" : "cube.transparent")
                                                    .font(.title2)
                                                    .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                                            }
                                            .frame(width: 88, height: 74)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14)
                                                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                                            )

                                            Text("Option \(index + 1)")
                                                .font(.caption.weight(isSelected ? .bold : .medium))
                                                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 4)

                    // Dynamic Grounded Layout Insights for Selected Variant
                    if !currentInsights.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isInsightsExpanded.toggle()
                                }
                            } label: {
                                HStack {
                                    Text("Why This Layout Works")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Image(systemName: isInsightsExpanded ? "chevron.up" : "chevron.down")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 20)

                            if isInsightsExpanded {
                                LazyVGrid(
                                    columns: [
                                        GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12)
                                    ],
                                    spacing: 12
                                ) {
                                    ForEach(currentInsights) { insight in
                                        insightCard(for: insight)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }

                    // Bottom Spacing for Floating Action Bar
                    Spacer().frame(height: 90)

                }
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    HStack(spacing: 12) {
                        if let onStartOver {
                            Button {
                                onStartOver()
                            } label: {
                                Text("Start Over")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(height: 50)
                                    .padding(.horizontal, 16)
                                    .background(Color(.secondarySystemBackground), in: Capsule())
                            }
                        }

                        Button {
                            if let layout = currentLayout {
                                viewModel.selectLayout(layout)
                                onApply?()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark")
                                Text("Apply This Layout")
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.blue, in: Capsule())
                            .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                }
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .onAppear {
            if let selected = viewModel.selectedLayout,
               let idx = activeVariants.firstIndex(where: { $0.id == selected.id }) {
                selectedIndex = idx
            }
            if let layout = currentLayout {
                syncStudioWithSelectedVariant(layout)
            }
        }
    }


    private func syncStudioWithSelectedVariant(_ layout: Layout) {
        studioViewModel.applyLayout(layout, animated: true)
        studioViewModel.setRecommendationHighlights(for: layout)
    }

    // MARK: - Insight Card

    private func insightCard(for insight: LayoutInsight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Icon Badge
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(badgeBackgroundColor(for: insight.category))
                    .frame(width: 32, height: 32)

                Image(systemName: iconName(for: insight.category))
                    .font(.subheadline)
                    .foregroundStyle(badgeTint(for: insight.category))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(insight.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .lineSpacing(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground).opacity(0.85))
        )
    }

    private func iconName(for category: LayoutInsightCategory) -> String {
        switch category {
        case .circulation: return "figure.walk"
        case .zoning: return "bed.double.fill"
        case .naturalLight: return "sun.max.fill"
        case .access: return "door.left.hand.open"
        case .privacy: return "lock.shield.fill"
        case .storage: return "archivebox.fill"
        }
    }

    private func badgeTint(for category: LayoutInsightCategory) -> Color {
        switch category {
        case .circulation: return Color.green
        case .zoning: return Color.orange
        case .naturalLight: return Color.yellow
        case .access: return Color.purple
        case .privacy: return Color.blue
        case .storage: return Color.teal
        }
    }

    private func badgeBackgroundColor(for category: LayoutInsightCategory) -> Color {
        badgeTint(for: category).opacity(0.15)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Button {
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back")

            Spacer()

            Text("Layout Suggestions")
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            // Blue checkmark button to apply layout
            Button {
                if let layout = currentLayout {
                    viewModel.selectLayout(layout)
                    onApply?()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 32, height: 32)

                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Apply Layout")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
