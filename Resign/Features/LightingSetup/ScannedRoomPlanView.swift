import SwiftUI

/// Shared scan drawing used by ceiling-light placement.
struct ScannedRoomPlanView: View {
    let room: Room
    let furniture: [Furniture]
    let openings: [RoomOpening]
    let scanPlan: RoomPlanSnapshot?
    var showsAnnotations = true

    private var planBounds: RoomPlanBounds {
        RoomPlanBounds(snapshot: scanPlan, fallbackWidth: room.width, fallbackLength: room.length)
    }

    private var planAspectRatio: CGFloat {
        CGFloat(planBounds.width / planBounds.length)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if scanPlan == nil || scanPlan?.wallSegments.isEmpty == true {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.secondarySystemBackground))
                        .padding(12)
                }

                if let scanPlan, !scanPlan.wallSegments.isEmpty {
                    Canvas { context, size in
                        for wall in scanPlan.wallSegments {
                            var path = Path()
                            path.move(to: planPoint(localX: wall.startX, localZ: wall.startZ, in: size))
                            path.addLine(to: planPoint(localX: wall.endX, localZ: wall.endZ, in: size))
                            context.stroke(
                                path,
                                with: .color(Color.primary.opacity(0.75)),
                                style: StrokeStyle(lineWidth: 5, lineCap: .square)
                            )
                        }
                    }
                    .allowsHitTesting(false)
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.primary.opacity(0.75), lineWidth: 5)
                        .padding(12)
                }

                ForEach(openings) { opening in
                    openingFootprint(opening, in: geometry.size)
                }

                ForEach(furniture) { item in
                    furnitureFootprint(item, in: geometry.size)
                }

            }
        }
        .aspectRatio(planAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .topLeading) {
            let scanW = min(planBounds.width, planBounds.length)
            let scanL = max(planBounds.width, planBounds.length)
            Text(String(format: "Scan · %.2fm (W) × %.2fm (L)", scanW, scanL))
                .opacity(showsAnnotations ? 1 : 0)
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(18)
                .allowsHitTesting(false)
                .opacity(showsAnnotations ? 1 : 0)
        }
        .overlay(alignment: .bottomLeading) {
            if showsAnnotations, openings.contains(where: { $0.type.lowercased() == "window" || $0.type.lowercased() == "door" }) {
                HStack(spacing: 10) {
                    openingLegend(color: .cyan, title: "Window")
                    openingLegend(color: .orange, title: "Door")
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(18)
                .allowsHitTesting(false)
            }
        }
        .accessibilityHint("Scanned room plan with walls, openings, and furniture.")
    }

    private func openingFootprint(_ opening: RoomOpening, in size: CGSize) -> some View {
        let roomWidth = CGFloat(planBounds.width)
        let roomLength = CGFloat(planBounds.length)
        let localPosition = scanPlan?.localCoordinates(worldX: opening.posX, worldZ: opening.posZ)
            ?? SIMD2<Float>(opening.posX, opening.posZ)
        let distanceToXWall = abs(abs(CGFloat(localPosition.x)) - roomWidth / 2)
        let distanceToZWall = abs(abs(CGFloat(localPosition.y)) - roomLength / 2)
        let onVerticalWall = distanceToXWall <= distanceToZWall
        let point = planPoint(localX: localPosition.x, localZ: localPosition.y, in: size)
        let wallLength = CGFloat(opening.width) / (onVerticalWall ? roomLength : roomWidth)
            * (onVerticalWall ? size.height - 34 : size.width - 34)
        let color: Color
        switch opening.type.lowercased() {
        case "window":
            color = .cyan
        case "door":
            color = .orange
        default:
            color = .purple
        }

        return RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.white, lineWidth: 1)
            }
            .frame(
                width: onVerticalWall ? 9 : max(12, wallLength),
                height: onVerticalWall ? max(12, wallLength) : 9
            )
            .position(point)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func openingLegend(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(color)
                .frame(width: 12, height: 5)
            Text(title)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func furnitureFootprint(_ item: Furniture, in size: CGSize) -> some View {
        let roomWidth = CGFloat(planBounds.width)
        let roomLength = CGFloat(planBounds.length)
        let localPosition = scanPlan?.localCoordinates(worldX: item.positionX, worldZ: item.positionZ)
            ?? SIMD2<Float>(item.positionX, item.positionZ)
        let point = planPoint(localX: localPosition.x, localZ: localPosition.y, in: size)
        let width = min(size.width - 34, max(8, CGFloat(item.width) / roomWidth * (size.width - 34)))
        let height = min(size.height - 34, max(8, CGFloat(item.length) / roomLength * (size.height - 34)))

        RoundedRectangle(cornerRadius: 5)
            .fill(Color(.tertiarySystemFill))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(.white.opacity(0.8), lineWidth: 1)
            }
            .overlay {
                if width >= 48, height >= 24 {
                    Text(item.category.capitalized)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .padding(2)
                }
            }
            .frame(width: width, height: height)
            .rotationEffect(.radians(-Double(scanPlan?.localYaw(item.rotationYaw) ?? item.rotationYaw)))
            .position(point)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func planPoint(localX: Float, localZ: Float, in size: CGSize) -> CGPoint {
        let unit = planBounds.unitCoordinates(x: localX, z: localZ)
        return CGPoint(x: 17 + CGFloat(unit.x) * (size.width - 34),
                       y: 17 + CGFloat(unit.y) * (size.height - 34))
    }
}
