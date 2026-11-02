//
//  PreferencePageView.swift
//  Resign
//
//  Created by Antigravity on 26/10/26.
//

import SwiftUI

public struct PreferencePageView: View {
    @Bindable public var viewModel: InsightsViewModel
    @Binding public var environmentPreset: Int
    public var showsEnvironmentSwitcher: Bool
    public var onEnvironmentPresetChanged: ((Int) -> Void)?
    public var onContinue: () -> Void
    public var onBack: (() -> Void)?

    @State private var showAllKeywords = false

    public init(
        viewModel: InsightsViewModel,
        environmentPreset: Binding<Int> = .constant(0),
        showsEnvironmentSwitcher: Bool = true,
        onEnvironmentPresetChanged: ((Int) -> Void)? = nil,
        onContinue: @escaping () -> Void,
        onBack: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self._environmentPreset = environmentPreset
        self.showsEnvironmentSwitcher = showsEnvironmentSwitcher
        self.onEnvironmentPresetChanged = onEnvironmentPresetChanged
        self.onContinue = onContinue
        self.onBack = onBack
    }

    private var displayedKeywords: [ProblemKeyword] {
        showAllKeywords ? ProblemKeyword.allCases : ProblemKeyword.allCases.filter(\.isSuggested)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    if showsEnvironmentSwitcher {
                        // Test Room Environment Switcher Card
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Test Room Environment", systemImage: "cube.transparent")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if let room = viewModel.currentRoom {
                                    Text("\(String(format: "%.1f", room.width))m × \(String(format: "%.1f", room.length))m")
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color(.secondarySystemFill), in: Capsule())
                                }
                            }

                            Picker("Test Room", selection: $environmentPreset) {
                                Text("USDZ Mock Room").tag(0)
                                Text("Clashes Demo Room").tag(1)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: environmentPreset) { _, newValue in
                                onEnvironmentPresetChanged?(newValue)
                            }

                            if let room = viewModel.currentRoom, let layout = viewModel.activeLayout ?? room.layouts.first {
                                HStack(spacing: 12) {
                                    Label("\(layout.furnitures.count) Furnishings", systemImage: "sofa.fill")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    Text("•").foregroundStyle(.tertiary)
                                    Label("\(room.openings.count) Openings", systemImage: "door.left.hand.open")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.top, 2)
                            }
                        }
                        .padding(14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                    }

                    // Heading & Subtitle
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What’s Not Working in Your Room?")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)

                        Text("Tell us what feels difficult or frustrating about your space. Choose the problems that sound familiar, describe them in your own words, or both.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                    }
                    .padding(.top, 4)

                    // Suggested Keywords Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Suggested keywords")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)

                            Spacer()

                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showAllKeywords.toggle()
                                }
                            } label: {
                                Text(showAllKeywords ? "See less" : "See more")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                        }

                        // Flowing chips grid
                        FlowLayout(spacing: 8) {
                            ForEach(displayedKeywords) { keyword in
                                let isSelected = viewModel.selectedKeywords.contains(keyword)
                                Button {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                        viewModel.toggleKeyword(keyword)
                                    }
                                } label: {
                                    Text(keyword.title)
                                        .font(.footnote.weight(isSelected ? .semibold : .regular))
                                        .foregroundStyle(isSelected ? .white : Color(.label))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .frame(minHeight: 44)
                                        .background(
                                            Capsule()
                                                .fill(isSelected ? Color(white: 0.38) : Color(.systemGray6))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Describe in Your Own Words
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Describe in your own words (optional)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemGray6).opacity(0.7))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color(.systemGray4).opacity(0.4), lineWidth: 1)
                                )

                            if viewModel.userPreference.isEmpty {
                                Text("My desk feels too cramped, and I need more space to move around.")
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)
                                    .padding(14)
                                    .allowsHitTesting(false)
                            }

                            TextEditor(text: $viewModel.userPreference)
                                .font(.subheadline)
                                .scrollContentBackground(.hidden)
                                .padding(10)
                                .frame(minHeight: 110)
                        }
                        .frame(height: 120)

                        HStack {
                            Spacer()
                            Text("\(viewModel.userPreference.count)/\(RoomPreference.maxFreeTextLength)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 90)
            }

            // Bottom Continue Button
            VStack {
                Button {
                    onContinue()
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isAnalyzing {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(viewModel.isAnalyzing ? "Analyzing Room..." : "Continue")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(white: 0.22), in: Capsule())
                }
                .disabled(viewModel.isAnalyzing)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private var headerBar: some View {
        HStack {
            if let onBack {
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
            } else {
                Spacer().frame(width: 44)
            }

            Spacer()

            Text("Your Preferences")
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            Spacer().frame(width: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - FlowLayout Helper for Wrapping Chips

public struct FlowLayout: SwiftUI.Layout {
    public var spacing: CGFloat

    public init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var maxHeightInRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += maxHeightInRow + spacing
                maxHeightInRow = 0
            }
            maxHeightInRow = max(maxHeightInRow, size.height)
            x += size.width + spacing
        }
        height = y + maxHeightInRow
        return CGSize(width: width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var maxHeightInRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += maxHeightInRow + spacing
                maxHeightInRow = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            maxHeightInRow = max(maxHeightInRow, size.height)
            x += size.width + spacing
        }
    }
}
