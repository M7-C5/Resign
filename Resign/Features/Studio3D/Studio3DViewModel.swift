//import Foundation
//import Observation
//
///// Preview choices for the current viewer session, independent of persisted lights.
//struct LightingSimulationSettings: Equatable {
//    var artificialLightsOn = false
//    var minuteOfDay = 720
//
//    /// Simple solar approximation for an east-facing window (MockRoom).
//    /// Models sunrise/sunset around 06:00–18:00 with realistic altitude/color.
//    var hourOfDay: Double {
//        Double(min(1439, max(0, minuteOfDay))) / 60.0
//    }
//
//    /// Solar altitude in radians (0 at horizon, ~π/2 around noon)
//    var solarAltitudeRadians: Double {
//        let h = hourOfDay
//        // Peak around solar noon ~12:00, span ~12 hours daylight
//        let normalized = (h - 6.0) / 12.0 // 0 at 06:00, 1 at 18:00
//        if normalized < 0 || normalized > 1 {
//            return -0.1 // below horizon
//        }
//        // Smooth curve, slightly higher around mid-day
//        return sin(normalized * .pi) * (.pi / 3.2) // up to ~56 degrees
//    }
//
//    var solarAltitudeDegrees: Double {
//        solarAltitudeRadians * 180.0 / .pi
//    }
//
//    /// East-facing room: sun crosses east in morning, more overhead later? 
//    /// Approximate azimuth relative to room (0 = pointing into room from east window)
//    var sunAzimuthOffsetRadians: Double {
//        let h = hourOfDay
//        if h < 6.0 || h > 18.0 {
//            return 0
//        }
//        // Morning: sun comes more obliquely from north side? Keep simple - mostly eastward
//        // Shift slightly as day progresses
//        let t = (h - 6.0) / 12.0 // 0-1
//        return sin(t * .pi) * 0.25 // small lateral shift
//    }
//
//    /// Daylight factor based on solar altitude
//    var daylightFactor: Double {
//        if hourOfDay < 6.0 || hourOfDay > 18.0 {
//            return 0
//        }
//        let alt = max(0, sin(solarAltitudeRadians))
//        // More realistic falloff near horizon
//        return pow(alt, 0.8)
//    }
//
//    /// Color temperature in Kelvin based on time of day
//    var colorTemperatureKelvin: Double {
//        if hourOfDay < 6.0 || hourOfDay > 18.0 {
//            return 1800 // very warm twilight/night
//        }
//        if hourOfDay < 7.0 {
//            // Golden hour sunrise
//            let t = (hourOfDay - 6.0) / 1.0
//            return 2000 + t * 1500 // 2000-3500K
//        }
//        if hourOfDay > 17.0 {
//            // Golden hour sunset
//            let t = (18.0 - hourOfDay) / 1.0
//            return 2000 + t * 1500
//        }
//        if hourOfDay < 9.0 || hourOfDay > 15.0 {
//            return 4000 // mid-morning/late afternoon
//        }
//        return 5500 // midday neutral daylight
//    }
//
//    var ambientIntensity: Double { 40 }
//    var daylightIntensity: Double { 1200 * daylightFactor }
//    var artificialIntensity: Double { artificialLightsOn ? 650 : 0 }
//
//    var timeLabel: String {
//        String(format: "%02d.%02d", minuteOfDay / 60, minuteOfDay % 60)
//    }
//}
//
//@Observable
//@MainActor
//public final class Studio3DViewModel {
//    private(set) var lightingSettings = LightingSimulationSettings()
//    var lightingDraft = LightingSimulationSettings()
//    private(set) var isLightingPresented = false
//
//    var previewLighting: LightingSimulationSettings {
//        isLightingPresented ? lightingDraft : lightingSettings
//    }
//
//    public init() {}
//
//    func beginLightingEditing() {
//        lightingDraft = lightingSettings
//        isLightingPresented = true
//    }
//
//    func confirmLightingEditing() {
//        guard isLightingPresented else { return }
//        lightingSettings = lightingDraft
//        isLightingPresented = false
//    }
//
//    func discardLightingEditing() {
//        lightingDraft = lightingSettings
//        isLightingPresented = false
//    }
//}
