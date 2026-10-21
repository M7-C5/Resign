//
//  LightingSetupView.swift
//  Resign
//

import SwiftUI
import SwiftData
import SceneKit

/// The "Add Your Light Source" screen — Phase 4 of the Resign onboarding flow.
///
/// Presents an interactive 5×5 ceiling projection grid where the user:
/// 1. Taps cells to place light fixtures (auto-named "Lighting N").
/// 2. Selects a placed light to adjust Color Temperature (2200–6500 K)
///    and Brightness (500–3000 lm) via sliders in a bottom panel.
/// 3. Deletes fixtures via the trash icon with a confirmation dialog.
/// 4. Confirms "Save & Continue" to persist all drafts into the given `Layout`.
/// 5. Can discard and go back with another confirmation dialog.
///
/// All grid edits operate on transient `LightDraft` value types. SwiftData is
/// only written to when the user confirms "Save & Continue".
///
/// - SeeAlso: `LightingSetupViewModel`
/// - SeeAlso: ADR 0007 — LightDraft Transient Value Type for Ceiling Grid Editing
public struct LightingSetupView: View {

    @Environment(\.modelContext) private var modelContext

    /// The `Layout` record that will receive the saved `Light` objects.
    var layout: Layout

    /// Called after all drafts have been successfully persisted.
    var onSave: () -> Void

    /// Called after the user confirms the "Go Back" discard dialog.
    var onBack: () -> Void

    @State private var viewModel = LightingSetupViewModel()

    public init(
        layout: Layout,
        onSave: @escaping () -> Void = {},
        onBack: @escaping () -> Void = {}
    ) {
        self.layout = layout
        self.onSave = onSave
        self.onBack = onBack
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                headerView
                ScrollView {
                    VStack(spacing: 16) {
                        gridView
                            .frame(maxWidth: geometry.size.height * 0.42 * 5.0 / 4.2)
                            .frame(maxWidth: .infinity)
                        bottomPanel
                    }
                    .padding(.top, 8)
                }
            }
        }
        .background(Color(.systemBackground))
        .navigationBarHidden(true)
        .alert("Are you sure you want to save & continue?", isPresented: $viewModel.showSaveConfirm) {
            Button("No", role: .cancel) {}
            Button("Yes") { performSave() }
        } message: {
            Text("Your changes will be saved.")
        }
        .alert("Are you sure you want to go back?", isPresented: $viewModel.showBackConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Back", role: .destructive) { onBack() }
        } message: {
            Text("Your changes wouldn't be saved.")
        }
        .alert("Are you sure you want to delete this light source?", isPresented: $viewModel.showDeleteConfirm) {
            Button("No", role: .cancel) {}
            Button("Yes", role: .destructive) { viewModel.deleteSelectedDraft() }
        } message: {
            Text("Your changes would not be saved.")
        }
        .alert("Could not save lights", isPresented: Binding(
            get: { viewModel.saveError != nil },
            set: { if !$0 { viewModel.saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.saveError ?? "Unknown error")
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerView: some View {
        ZStack {
            Text("Add Your Light Source")
                .font(.headline)
            HStack {
                Button {
                    viewModel.showBackConfirm = true
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back")
                Spacer()
            }
        }
        .padding(.horizontal, 12)

        Text("Click the coordinates to add a light source.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 4)
    }

    // MARK: - 5×5 Grid

    @ViewBuilder
    private var gridView: some View {
        GeometryReader { geometry in
            ZStack {
                MockRoomLightingBackground()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                // Dim only the room so the light markers and their glow stay vivid.
                Color.black.opacity(0.15)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<5, id: \.self) { col in
                                gridCell(col: col, row: row)
                            }
                        }
                    }
                }
            }
        }
        .aspectRatio(5.0 / 4.2, contentMode: .fit)
        .clipped()
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func gridCell(col: Int, row: Int) -> some View {
        let draft = viewModel.drafts.first(where: { $0.gridColumn == col && $0.gridRow == row })
        let isSelected = draft != nil && draft?.id == viewModel.selectedDraftID

        Button {
            viewModel.tapCell(col: col, row: row)
        } label: {
            ZStack {
                // Keep the full cell tappable without drawing grid lines.
                Color.clear

                if let draft {
                    LightSourceMarker(
                        colorTemp: draft.colorTemp,
                        brightness: draft.brightness,
                        isSelected: isSelected
                    )
                } else {
                    // Empty cell indicator
                    Circle()
                        .fill(Color(white: 0.42))
                        .overlay {
                            Circle().stroke(.white.opacity(0.6), lineWidth: 1)
                        }
                        .frame(width: 8, height: 8)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(5.0 / 4.2, contentMode: .fit)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.spring(duration: 0.2), value: draft?.id)
    }

    // MARK: - Bottom Panel

    @ViewBuilder
    private var bottomPanel: some View {
        VStack(spacing: 0) {
            LightingSettingsCard(
                draft: viewModel.selectedDraft,
                onColorTemperatureChange: { viewModel.updateColorTemp($0) },
                onBrightnessChange: { viewModel.updateBrightness($0) },
                onDelete: { viewModel.showDeleteConfirm = true }
            )
            .padding(.horizontal, 24)

            Button {
                viewModel.showSaveConfirm = true
            } label: {
                Text("Save & Continue")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(viewModel.drafts.isEmpty ? Color.gray.opacity(0.5) : Color.accentColor)
                    .cornerRadius(14)
            }
            .disabled(viewModel.drafts.isEmpty)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }

    }

    // MARK: - Actions

    private func performSave() {
        do {
            try viewModel.saveToLayout(layout, context: modelContext)
            onSave()
        } catch {
            viewModel.saveError = error.localizedDescription
        }
    }
}

// MARK: - Light Source Marker

private struct LightSourceMarker: View {
    let colorTemp: Int
    let brightness: Float
    let isSelected: Bool

    private var intensity: Double {
        Double(min(1, max(0, (brightness - 500) / 2500)))
    }

    private var lightColor: Color {
        // Match the slider's warm, neutral and cool stops for a consistent visual cue.
        let fraction = min(1, max(0, Double(colorTemp - 2200) / 4300))
        let stops: [(position: Double, rgb: SIMD3<Double>)] = [
            (0, SIMD3(1.0, 0.68, 0.26)),
            (0.25, SIMD3(1.0, 0.88, 0.60)),
            (0.55, SIMD3(1.0, 0.98, 0.90)),
            (1, SIMD3(0.82, 0.91, 1.0))
        ]
        for index in 1..<stops.count {
            let lower = stops[index - 1]
            let upper = stops[index]
            if fraction <= upper.position {
                let blend = (fraction - lower.position) / (upper.position - lower.position)
                let rgb = lower.rgb + (upper.rgb - lower.rgb) * blend
                return Color(red: rgb.x, green: rgb.y, blue: rgb.z)
            }
        }
        return Color(red: 0.82, green: 0.91, blue: 1.0)
    }

    var body: some View {
        Circle()
            .fill(lightColor)
            .frame(width: isSelected ? 30 : 22, height: isSelected ? 30 : 22)
            .overlay {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: isSelected ? 12 : 9))
                    .foregroundStyle(.black.opacity(0.65))
            }
            .background {
                // The halo is decorative and cannot expand the cell's tap target or layout.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                lightColor.opacity(0.25 + intensity * 0.6),
                                lightColor.opacity(0.1 + intensity * 0.25),
                                lightColor.opacity(0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 22 + intensity * 30
                        )
                    )
                    .frame(width: 44 + intensity * 60, height: 44 + intensity * 60)
                    .blur(radius: 2 + intensity * 4)
                    .allowsHitTesting(false)
            }
            .shadow(color: lightColor.opacity(0.2 + intensity * 0.65), radius: 2 + intensity * 14)
    }
}

// MARK: - Lighting Settings

/// Keeps the same controls visible before selection without creating a light draft.
private struct LightingSettingsCard: View {
    let draft: LightDraft?
    let onColorTemperatureChange: (Int) -> Void
    let onBrightnessChange: (Float) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let draft {
                HStack {
                    Text(draft.name)
                        .font(.headline)
                    Spacer()
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Delete light source")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Color Temperature")
                    .font(.subheadline)
                Text("\(draft?.colorTemp ?? 5000) K")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                ColorTemperatureSlider(
                    value: draft?.colorTemp ?? 5000,
                    range: 2200...6500
                ) { value in
                    guard draft != nil else { return }
                    onColorTemperatureChange(value)
                }
                .disabled(draft == nil)
                .allowsHitTesting(draft != nil)
                .saturation(draft == nil ? 0 : 1)
                .accessibilityLabel("Color Temperature")
                HStack {
                    Text("2200")
                    Spacer()
                    Text("6500 K")
                }
                .font(.caption)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Brightness")
                    .font(.subheadline)
                Text("\(Int(draft?.brightness ?? 1080)) lm")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                Slider(
                    value: Binding(
                        get: { draft?.brightness ?? 1080 },
                        set: { value in
                            guard draft != nil else { return }
                            onBrightnessChange(value)
                        }
                    ),
                    in: 500...3000,
                    step: 10
                )
                .tint(.gray)
                .disabled(draft == nil)
                .accessibilityLabel("Brightness")
                HStack {
                    Text("500 lm")
                    Spacer()
                    Text("3000 lm")
                }
                .font(.caption)
            }
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
        }
    }
}

// MARK: - Mock Room Background

/// A fixed ceiling projection of the bundled reference room, matching the grid bounds.
private struct MockRoomLightingBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .secondarySystemBackground
        view.isUserInteractionEnabled = false

        do {
            guard let url = Bundle.main.url(forResource: "MockRoom", withExtension: "usdz") else {
                throw CocoaError(.fileNoSuchFile)
            }
            let scene = try SCNScene(url: url)
            scene.rootNode.childNode(withName: "Ceiling", recursively: true)?.isHidden = true

            let camera = SCNCamera()
            camera.usesOrthographicProjection = true
            // Half the 4.2 m depth; the 5:4.2 viewport also fits the room width.
            camera.orthographicScale = 2.1
            camera.zNear = 0.1
            camera.zFar = 100

            let viewpoint = SCNNode()
            viewpoint.camera = camera
            viewpoint.position = SCNVector3(0, 10, 0)
            // North (-Z) at the top, east (+X) at the right.
            viewpoint.eulerAngles.x = -.pi / 2
            scene.rootNode.addChildNode(viewpoint)
            // Render the fixed 3D viewpoint once; grid edits do not need a render loop.
            let renderer = SCNRenderer(device: nil, options: nil)
            renderer.scene = scene
            renderer.pointOfView = viewpoint
            renderer.autoenablesDefaultLighting = true
            view.image = renderer.snapshot(
                atTime: 0,
                with: CGSize(width: 1000, height: 840),
                antialiasingMode: .multisampling4X
            )
        } catch {
            let label = UILabel()
            label.text = String(localized: "Room preview unavailable")
            label.textAlignment = .center
            label.font = .preferredFont(forTextStyle: .caption1)
            label.textColor = .secondaryLabel
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }
        return view
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}

// MARK: - Color Temperature Slider

/// A custom gradient-track slider for selecting Kelvin color temperature.
/// The track renders a warm-orange → neutral-white → cool-blue gradient
/// matching the visual language of the design mockup.
private struct ColorTemperatureSlider: View {

    var value: Int
    var range: ClosedRange<Int>
    var onChange: (Int) -> Void

    private var fraction: CGFloat {
        CGFloat(value - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)
    }

    var body: some View {
        GeometryReader { geo in
            let thumbDiameter: CGFloat = 22
            let trackWidth = geo.size.width - thumbDiameter

            ZStack(alignment: .leading) {
                // Gradient track
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 1.0, green: 0.68, blue: 0.26), location: 0.0),   // 2200 K candlelight
                        .init(color: Color(red: 1.0, green: 0.88, blue: 0.60), location: 0.25),  // 3500 K warm white
                        .init(color: Color(red: 1.0, green: 0.98, blue: 0.90), location: 0.55),  // 5000 K neutral
                        .init(color: Color(red: 0.82, green: 0.91, blue: 1.0), location: 1.0),   // 6500 K daylight
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 6)
                .cornerRadius(3)
                .offset(x: thumbDiameter / 2)
                .frame(width: geo.size.width - thumbDiameter / 2)

                // Thumb
                Circle()
                    .fill(.white)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .shadow(color: .black.opacity(0.20), radius: 3, x: 0, y: 1)
                    .offset(x: fraction * trackWidth)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let rawFraction = (drag.location.x - thumbDiameter / 2) / trackWidth
                        let clamped = max(0.0, min(1.0, rawFraction))
                        let kelvin = range.lowerBound + Int(clamped * CGFloat(range.upperBound - range.lowerBound))
                        onChange(kelvin)
                    }
            )
        }
        .frame(height: 22)
    }
}

// MARK: - Preview

#Preview("Lighting Setup - Interactive") {
    let schema = Schema([
        Room.self,
        RoomOpening.self,
        Layout.self,
        Furniture.self,
        Light.self,
        Insight.self,
    ])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [configuration])
    let layout = Layout(name: "Sample Office Layout")
    container.mainContext.insert(layout)

    return NavigationStack {
        LightingSetupView(
            layout: layout,
            onSave: {
                print("Preview: Light setup saved!")
            },
            onBack: {
                print("Preview: Go back requested")
            }
        )
    }
    .modelContainer(container)
}
