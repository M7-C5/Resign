import Foundation
import UIKit

/// Session-only lighting choices for the room preview. Never persisted.
struct LightingSimulationSettings: Equatable, Sendable {
    var artificialLightsOn = false
    var minuteOfDay = 12 * 60
    var solarContext = SolarSimulationContext()

    var clampedMinute: Int { min(1439, max(0, minuteOfDay)) }
    var hourOfDay: Double { Double(clampedMinute) / 60 }

    var timeLabel: String {
        String(format: "%02d.%02d", clampedMinute / 60, clampedMinute % 60)
    }
}

/// Explicit reference site for the mock room, not the user's measured location.
/// Local -Z faces true north when heading is zero; +X is then east.
struct SolarSimulationContext: Equatable, Sendable {
    var latitude: Double = -6.2088
    var longitude: Double = 106.8456
    var year = 2026
    var month = 10
    var day = 24
    var timeZoneIdentifier = "Asia/Jakarta"
    /// Clockwise true-north bearing of the room's -Z axis.
    var roomHeadingDegrees: Double = 0
    /// Local outward facade bearings for the selected room's detected windows.
    var windowLocalAzimuths: [Double] = [90]

    /// The reference room's window faces local +X, 90° clockwise from its -Z axis.
    var windowBearingDegrees: Double {
        NorthAlignmentCalibration.normalized(roomHeadingDegrees + (windowLocalAzimuths.first ?? 90))
    }

    var windowCompassDirection: String {
        compassDirection(bearing: windowBearingDegrees)
    }

    var naturalLightDescription: String {
        var directions: [String] = []
        for azimuth in windowLocalAzimuths {
            let direction = compassDirection(bearing: NorthAlignmentCalibration.normalized(roomHeadingDegrees + azimuth))
            if !directions.contains(direction) { directions.append(direction) }
        }
        guard !directions.isEmpty else { return "No windows detected in this room" }
        return "Natural light from \(directions.joined(separator: ", ")) \(windowLocalAzimuths.count == 1 ? "window" : "windows")"
    }

    private func compassDirection(bearing: Double) -> String {
        let directions = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
        return directions[Int((bearing + 22.5) / 45) % directions.count]
    }

    func date(minuteOfDay: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        let minute = min(1439, max(0, minuteOfDay))
        let parts = DateComponents(year: year, month: month, day: day,
                                   hour: minute / 60, minute: minute % 60)
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }
}

struct SunState: Equatable, Sendable {
    /// Geometric radians above the horizon, negative at night.
    var elevation: Float
    /// Clockwise azimuth relative to the room's -Z axis.
    var azimuth: Float
    var daylight: Float
    var skylight: Float
    var kelvin: Double

    var rayDirection: SIMD3<Float> {
        -SIMD3<Float>(cos(elevation) * sin(azimuth), sin(elevation),
                      -cos(elevation) * cos(azimuth))
    }
}

extension LightingSimulationSettings {
    var sun: SunState {
        let position = SolarEphemerisEngine().position(
            at: solarContext.date(minuteOfDay: clampedMinute),
            latitude: solarContext.latitude, longitude: solarContext.longitude
        )
        let elevation = position.elevation
        let altitudeDegrees = elevation * 180 / .pi
        // Clear-sky artistic exposure: continuous at the horizon; not calibrated lux.
        let height = max(0, sin(elevation))
        let direct = pow(height, 0.65)
        let twilight = min(1, max(0, (altitudeDegrees + 6) / 12))
        let smoothTwilight = twilight * twilight * (3 - 2 * twilight)
        let sky = smoothTwilight * (0.2 + 0.8 * sqrt(height))
        return SunState(
            elevation: Float(elevation),
            azimuth: Float(position.azimuth - NorthAlignmentCalibration.normalized(solarContext.roomHeadingDegrees) * .pi / 180),
            daylight: Float(direct), skylight: Float(sky),
            kelvin: 2200 + 3500 * min(1, height / 0.65)
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
