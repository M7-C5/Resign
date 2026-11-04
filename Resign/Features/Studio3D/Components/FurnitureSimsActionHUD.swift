import SwiftUI

/// Projected floating action cluster positioned directly over a selected 3D furniture entity,
/// reminiscent of architectural life simulators ("The Sims").
/// Features a circular halo dial, circular motion rotation tracking around the furniture centroid,
/// and instant archival to the inventory drawer.
public struct FurnitureSimsActionHUD: View {
    public let furniture: Furniture
    public let isColliding: Bool
    public let onStepRotate: () -> Void
    public let onCircularRotate: (Float) -> Void
    public let onDragRotateEnded: () -> Void
    public let onArchive: () -> Void

    @State private var dragStartLocation: CGPoint? = nil
    @State private var previousLocation: CGPoint? = nil
    @State private var accumulatedAngle: Float = 0
    @State private var isDraggingRotate: Bool = false
    @State private var currentDragAngle: CGFloat? = nil

    private let dialRadius: CGFloat = 88
    private let buttonRadius: CGFloat = 23
    private let defaultRotateAngle: CGFloat = -.pi * 0.94 // ~ -170° (bottom-left)
    private let defaultArchiveAngle: CGFloat = -.pi * 0.69 // ~ -125° (top-left)

    public init(
        furniture: Furniture,
        isColliding: Bool,
        onStepRotate: @escaping () -> Void,
        onCircularRotate: @escaping (Float) -> Void,
        onDragRotateEnded: @escaping () -> Void,
        onArchive: @escaping () -> Void
    ) {
        self.furniture = furniture
        self.isColliding = isColliding
        self.onStepRotate = onStepRotate
        self.onCircularRotate = onCircularRotate
        self.onDragRotateEnded = onDragRotateEnded
        self.onArchive = onArchive
    }

    private var dialDiameter: CGFloat {
        dialRadius * 2
    }

    private var centerPoint: CGPoint {
        CGPoint(x: dialRadius, y: dialRadius)
    }

    public var body: some View {
        ZStack {
            // 1. Translucent Circular Halo / Dial
            // Hit-testing disabled so 3D furniture underneath remains directly selectable and draggable
            Circle()
                .fill(Color.white.opacity(0.48))
                .overlay(
                    Circle()
                        .stroke(isColliding ? Color.red.opacity(0.65) : Color.white.opacity(0.55), lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
                .frame(width: dialDiameter, height: dialDiameter)
                .allowsHitTesting(false)

            // 2. Archive Button (Fixed on rim at top-left)
            Button {
                onArchive()
            } label: {
                actionButtonContent(systemName: "archivebox.fill")
            }
            .buttonStyle(.plain)
            .frame(width: 48, height: 48)
            .contentShape(Circle())
            .offset(
                x: dialRadius * cos(defaultArchiveAngle),
                y: dialRadius * sin(defaultArchiveAngle)
            )
            .accessibilityLabel("Archive furniture to inventory")

            // 3. Rotate Button (Draggable along rim, strictly catches touches on the 48x48 button)
            let activeRotateAngle = currentDragAngle ?? defaultRotateAngle
            actionButtonContent(systemName: "arrow.clockwise")
                .frame(width: 48, height: 48)
                .contentShape(Circle())
                .offset(
                    x: dialRadius * cos(activeRotateAngle),
                    y: dialRadius * sin(activeRotateAngle)
                )
                .accessibilityLabel("Rotate 45 degrees or drag to turn circularly")
                .gesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .named("SimsHUDCoordinateSpace"))
                        .onChanged { value in
                            handleRotateGestureChanged(value: value)
                        }
                        .onEnded { value in
                            handleRotateGestureEnded(value: value)
                        }
                )
        }
        .frame(width: dialDiameter, height: dialDiameter)
        .coordinateSpace(name: "SimsHUDCoordinateSpace")
    }

    private func actionButtonContent(systemName: String) -> some View {
        ZStack {
            Circle()
                .fill(StudioTheme.primaryText)
                .frame(width: buttonRadius * 2, height: buttonRadius * 2)
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.22), radius: 5, x: 0, y: 2)

            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.white)
        }
        .frame(width: 48, height: 48)
    }

    private func handleRotateGestureChanged(value: DragGesture.Value) {
        let center = centerPoint
        if dragStartLocation == nil {
            dragStartLocation = value.startLocation
            previousLocation = value.startLocation
            accumulatedAngle = 0
            isDraggingRotate = false
        }

        let dist = hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y)
        if dist >= 4 {
            isDraggingRotate = true
            let touchAngle = atan2(value.location.y - center.y, value.location.x - center.x)
            currentDragAngle = touchAngle
        }

        if isDraggingRotate, let prev = previousLocation {
            let delta = SpatialClearanceEngine.circularAngleDelta(
                center: center,
                previous: prev,
                current: value.location
            )
            accumulatedAngle += delta
            previousLocation = value.location
            onCircularRotate(accumulatedAngle)
        }
    }

    private func handleRotateGestureEnded(value: DragGesture.Value) {
        let wasDrag = isDraggingRotate
        dragStartLocation = nil
        previousLocation = nil
        isDraggingRotate = false
        accumulatedAngle = 0

        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
            currentDragAngle = nil
        }

        if wasDrag {
            onDragRotateEnded()
        } else {
            onStepRotate()
        }
    }

    /// Clamps projected 3D coordinates safely within the visible screen frame.
    public static func clampedPosition(
        projected: CGPoint,
        in screenSize: CGSize,
        verticalOffset: CGFloat = 0
    ) -> CGPoint {
        let marginX: CGFloat = 60
        let minX = marginX
        let maxX = max(minX, screenSize.width - marginX)
        let clampedX = min(maxX, max(minX, projected.x))

        let minY: CGFloat = 60
        let maxY = max(minY, screenSize.height - 80)
        let rawY = projected.y - verticalOffset
        let clampedY = min(maxY, max(minY, rawY))

        return CGPoint(x: clampedX, y: clampedY)
    }
}
