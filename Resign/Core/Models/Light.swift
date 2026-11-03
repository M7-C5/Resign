//
//  Light.swift
//  Resign
//

import Foundation
import SwiftData

@Model
public final class Light {
    public var id: UUID = UUID()
    public var name: String = "Light"
    public var coordinateX: Float = 2.0    // Encoded plan X: normalized * 5 - 0.5 (legacy grid 0...4)
    public var coordinateY: Float = 2.0    // Encoded plan Z: normalized * 5 - 0.5 (legacy grid 0...4)
    public var elevationZ: Float = 2.6
    public var brightness: Float = 800.0   // Lumens (0 - 2000)
    public var colorTemp: Int = 3000       // Kelvin (2200 - 6500)
    public var isOn: Bool = true

    public var layout: Layout?

    public init(
        id: UUID = UUID(),
        name: String = "Light",
        coordinateX: Float = 2.0,
        coordinateY: Float = 2.0,
        elevationZ: Float = 2.6,
        brightness: Float = 800.0,
        colorTemp: Int = 3000,
        isOn: Bool = true
    ) {
        self.id = id
        self.name = name
        self.coordinateX = coordinateX
        self.coordinateY = coordinateY
        self.elevationZ = elevationZ
        self.brightness = brightness
        self.colorTemp = colorTemp
        self.isOn = isOn
    }
}
