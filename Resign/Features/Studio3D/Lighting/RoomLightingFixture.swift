import Foundation

/// A layout light converted to the room simulator's coordinate and intensity units.
struct RoomLightingFixture: Identifiable, Equatable, Sendable {
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
