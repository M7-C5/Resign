import Foundation
import simd

/// A layout light converted to the room simulator's coordinate and intensity units.
struct RoomLightingFixture: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let position: SIMD3<Float>
    let brightness: Float
    let colorTemperatureKelvin: Double
    let isOn: Bool

    /// The 5×5 ceiling grid spans 2.6 m across the room in X and Z.
    init(
        id: UUID,
        name: String,
        gridColumn: Float,
        gridRow: Float,
        elevationZ: Float,
        brightness: Float,
        colorTemp: Int,
        isOn: Bool
    ) {
        let column = min(4, max(0, gridColumn))
        let row = min(4, max(0, gridRow))
        self.id = id
        self.name = name
        self.position = [(column - 2) * 0.65, elevationZ, (row - 2) * 0.65]
        self.brightness = max(0, brightness)
        self.colorTemperatureKelvin = Double(colorTemp)
        self.isOn = isOn
    }

    init(light: Light) {
        self.init(
            id: light.id,
            name: light.name,
            gridColumn: light.coordinateX,
            gridRow: light.coordinateY,
            elevationZ: light.elevationZ,
            brightness: light.brightness,
            colorTemp: light.colorTemp,
            isOn: light.isOn
        )
    }

    /// Grid endpoints stay inside the walls of the selected room.
    init(light: Light, roomWidth: Float, roomLength: Float, roomHeight: Float) {
        self.init(
            id: light.id,
            name: light.name,
            position: [
                ((min(4, max(0, light.coordinateX)) + 0.5) / 5 - 0.5) * max(0.1, roomWidth),
                min(max(0.05, light.elevationZ), max(0.05, roomHeight - 0.08)),
                ((min(4, max(0, light.coordinateY)) + 0.5) / 5 - 0.5) * max(0.1, roomLength)
            ],
            brightness: light.brightness,
            colorTemperatureKelvin: Double(light.colorTemp),
            isOn: light.isOn
        )
    }

    init(
        id: UUID = UUID(),
        name: String,
        position: SIMD3<Float>,
        brightness: Float,
        colorTemperatureKelvin: Double,
        isOn: Bool = true
    ) {
        self.id = id
        self.name = name
        self.position = position
        self.brightness = max(0, brightness)
        self.colorTemperatureKelvin = colorTemperatureKelvin
        self.isOn = isOn
    }
}

/// Immutable scene input. Slider edits do not rebuild or re-read the saved room.
struct RoomSimulationLayout: Hashable, Sendable {
    struct Furnishing: Hashable, Sendable {
        let id: UUID
        let name: String
        let category: String
        let position: SIMD3<Float>
        let dimensions: SIMD3<Float>
        let yaw: Float
        let modelURL: URL?
    }

    struct Aperture: Hashable, Sendable {
        let kind: String
        let position: SIMD3<Float>
        let width: Float
        let height: Float
    }

    let id: UUID
    let modelURL: URL?
    let width: Float
    let length: Float
    let height: Float
    let scanPlan: RoomPlanSnapshot?
    var center: SIMD2<Float>
    var floorLevel: Float
    var inferredWallSegments: [RoomPlanSnapshot.WallSegment] = []
    let furnishings: [Furnishing]
    let apertures: [Aperture]

    @MainActor
    init(layout: Layout) {
        let room = layout.room
        id = layout.id
        modelURL = layout.usdzURL
        width = max(0.5, room?.width ?? 5)
        length = max(0.5, room?.length ?? 4.2)
        height = max(0.5, room?.height ?? 2.6)
        scanPlan = room?.planSnapshotData.flatMap { try? JSONDecoder().decode(RoomPlanSnapshot.self, from: $0) }
        center = [scanPlan?.centerX ?? 0, scanPlan?.centerZ ?? 0]
        let furniture = layout.furnitures.filter { !$0.isArchived }.sorted { $0.id.uuidString < $1.id.uuidString }
        floorLevel = scanPlan?.floorLevel ?? furniture.map(\.positionY).min() ?? 0
        furnishings = furniture.map {
            Furnishing(id: $0.id, name: $0.name, category: $0.category,
                       position: [$0.positionX, $0.positionY, $0.positionZ],
                       dimensions: [$0.width, $0.height, $0.length], yaw: $0.rotationYaw, modelURL: $0.usdzURL)
        }
        apertures = (room?.openings ?? []).sorted { $0.id.uuidString < $1.id.uuidString }.map {
            Aperture(kind: $0.type.lowercased(), position: [$0.posX, $0.posY, $0.posZ],
                     width: max(0.05, $0.width), height: max(0.05, $0.height))
        }
    }

    var yaw: Float { scanPlan?.yawRadians ?? 0 }

    var wallSegments: [RoomPlanSnapshot.WallSegment] {
        let captured = scanPlan?.wallSegments ?? []
        return captured.isEmpty ? inferredWallSegments : captured
    }

    func localPosition(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let dx = point.x - center.x
        let dz = point.z - center.y
        return [dx * cos(yaw) - dz * sin(yaw), point.y - floorLevel,
                dx * sin(yaw) + dz * cos(yaw)]
    }

    func outwardNormal(at point: SIMD3<Float>) -> SIMD3<Float> {
        let walls = wallSegments
        if !walls.isEmpty {
            let p = SIMD2<Float>(point.x, point.z)
            let nearest = walls.min { wallDistance(p, $0) < wallDistance(p, $1) }!
            let tangent = SIMD2<Float>(nearest.endX - nearest.startX, nearest.endZ - nearest.startZ)
            if simd_length(tangent) > 0.001 {
                var normal = simd_normalize(SIMD3<Float>(tangent.y, 0, -tangent.x))
                let midpoint = SIMD3<Float>((nearest.startX + nearest.endX) / 2, 0,
                                           (nearest.startZ + nearest.endZ) / 2)
                if simd_dot(normal, midpoint) < 0 { normal = -normal }
                return normal
            }
        }
        if abs(abs(point.x) - width / 2) < abs(abs(point.z) - length / 2) {
            return [point.x >= 0 ? 1 : -1, 0, 0]
        }
        return [0, 0, point.z >= 0 ? 1 : -1]
    }

    var windows: [WindowOpening] {
        apertures.filter { $0.kind == "window" }.map {
            let position = localPosition($0.position)
            return WindowOpening(center: position, width: $0.width, height: $0.height,
                                 outwardNormal: outwardNormal(at: position))
        }
    }

    var windowAzimuths: [Double] {
        windows.map { Double(atan2($0.outwardNormal.x, -$0.outwardNormal.z)) * 180 / .pi }
    }

    private func wallDistance(_ point: SIMD2<Float>, _ wall: RoomPlanSnapshot.WallSegment) -> Float {
        let start = SIMD2<Float>(wall.startX, wall.startZ)
        let delta = SIMD2<Float>(wall.endX - wall.startX, wall.endZ - wall.startZ)
        let t = min(1, max(0, simd_dot(point - start, delta) / max(0.0001, simd_length_squared(delta))))
        return simd_length_squared(point - start - delta * t)
    }
}
