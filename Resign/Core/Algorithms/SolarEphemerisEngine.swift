import Foundation

/// Geometric solar position; azimuth runs clockwise from true north.
public struct SolarPosition: Equatable, Sendable {
    public let elevation: Double
    public let azimuth: Double
}

/// NOAA fractional-year approximation, without atmospheric refraction or terrain obstruction.
public struct SolarEphemerisEngine {
    public init() {}

    public func position(at date: Date, latitude: Double, longitude: Double) -> SolarPosition {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let days = calendar.range(of: .day, in: .year, for: date)?.count ?? 365
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let minutes = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) + Double(parts.second ?? 0) / 60
        let gamma = 2 * Double.pi / Double(days) * (Double(day - 1) + (minutes / 60 - 12) / 24)
        let equation = 229.18 * (0.000115 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
            - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
        let declination = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma) + 0.001307 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
        let hourAngle = (minutes + equation + 4 * longitude) / 4 * .pi / 180 - .pi
        let lat = latitude * .pi / 180
        // ENU vector avoids singular azimuth divisions near the zenith and poles.
        let east = -cos(declination) * sin(hourAngle)
        let north = cos(lat) * sin(declination) - sin(lat) * cos(declination) * cos(hourAngle)
        let up = sin(lat) * sin(declination) + cos(lat) * cos(declination) * cos(hourAngle)
        let azimuth = atan2(east, north)
        return SolarPosition(elevation: asin(min(1, max(-1, up))),
                             azimuth: azimuth < 0 ? azimuth + 2 * .pi : azimuth)
    }
}
