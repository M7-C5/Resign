import Foundation
import UIKit

/// Session-only lighting choices for the room preview. Never persisted.
struct LightingSimulationSettings: Equatable, Sendable {
    var artificialLightsOn = false
    var minuteOfDay = 12 * 60

    var clampedMinute: Int { min(1439, max(0, minuteOfDay)) }
    var hourOfDay: Double { Double(clampedMinute) / 60 }

    var timeLabel: String {
        String(format: "%02d.%02d", clampedMinute / 60, clampedMinute % 60)
    }
}

/// Mock sun for the east-facing window. This is a simple curve, not a geographic solar model.
struct SunState: Equatable, Sendable {
    /// Radians above the horizon. 0 at night.
    var elevation: Float
    /// Radians. 0 = sun due east of the room, +/- swings slightly north/south during the day.
    var azimuth: Float
    /// 0...1 strength of direct sunlight (0 at night).
    var daylight: Float
    /// 0...1 soft sky light. Also non-zero during dawn and dusk.
    var skylight: Float
    /// Color temperature of the direct sun.
    var kelvin: Double

    /// Direction the sunlight travels: from the sun toward the room.
    var rayDirection: SIMD3<Float> {
        let towardSun = SIMD3<Float>(
            cos(elevation) * cos(azimuth),
            sin(elevation),
            cos(elevation) * sin(azimuth)
        )
        return -towardSun
    }
}

extension LightingSimulationSettings {
    /// Sunrise at 06:00, sunset at 18:00, peak elevation about 60 degrees at noon.
    var sun: SunState {
        let hour = hourOfDay
        let t = (hour - 6) / 12                       // 0 at sunrise, 1 at sunset
        let isDay = t > 0 && t < 1
        let arc: Double = isDay ? sin(t * .pi) : 0    // 0...1 bell curve

        let skyT = (hour - 5) / 14                    // wider window so dawn/dusk are not pitch black
        let sky: Double = (skyT > 0 && skyT < 1) ? pow(sin(skyT * .pi), 1.2) : 0

        return SunState(
            elevation: isDay ? Float(max(0.06, arc * 1.05)) : 0,
            azimuth: isDay ? Float((0.5 - t) * 0.7) : 0,
            daylight: Float(pow(arc, 0.8)),
            skylight: Float(sky),
            kelvin: 2200 + 3400 * pow(arc, 0.7)
        )
    }
}

extension UIColor {
    /// Approximate blackbody color for a temperature in Kelvin.
    convenience init(kelvin: Double) {
        let temp = min(40_000, max(1_000, kelvin)) / 100
        let red: Double
        let green: Double
        let blue: Double

        if temp <= 66 {
            red = 255
            green = 99.4708025861 * log(temp) - 161.1195681661
            if temp >= 66 {
                blue = 255
            } else if temp <= 19 {
                blue = 0
            } else {
                blue = 138.5177312231 * log(temp - 10) - 305.0447927307
            }
        } else {
            red = 329.698727446 * pow(temp - 60, -0.1332047592)
            green = 288.1221695283 * pow(temp - 60, -0.0755148492)
            blue = 255
        }

        func channel(_ value: Double) -> CGFloat {
            CGFloat(min(255, max(0, value)) / 255)
        }
        self.init(red: channel(red), green: channel(green), blue: channel(blue), alpha: 1)
    }
}
