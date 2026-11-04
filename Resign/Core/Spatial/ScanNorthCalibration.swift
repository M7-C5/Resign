import Foundation
import simd

/// Select a device edge with a reliable horizontal projection while scanning upright.
enum ScanNorthReference: Sendable {
    case portrait
    case landscapeLeft

    static func choose(portraitTop: SIMD3<Float>, landscapeTop: SIMD3<Float>, current: Self? = nil) -> Self {
        let portrait = hypot(portraitTop.x, portraitTop.z)
        let landscape = hypot(landscapeTop.x, landscapeTop.z)
        if let current, (current == .portrait ? portrait : landscape) >= 0.5 { return current }
        return portrait >= landscape ? .portrait : .landscapeLeft
    }
}

/// True-north bearing of AR world's -Z, before the saved plan's yaw is applied.
public struct ScanNorthCalibration: Codable, Sendable, Hashable {
    public let worldHeadingDegrees: Double
    public let accuracyDegrees: Double
    public let sampleCount: Int
    public let calibratedAt: Date
    /// Provisional estimates contain one reading; refined estimates passed the stability window.
    public var isRefined: Bool { sampleCount >= 5 && accuracyDegrees <= 20 }

    public init(worldHeadingDegrees: Double, accuracyDegrees: Double, sampleCount: Int, calibratedAt: Date) {
        self.worldHeadingDegrees = NorthAlignmentCalibration.normalized(worldHeadingDegrees)
        self.accuracyDegrees = accuracyDegrees
        self.sampleCount = sampleCount
        self.calibratedAt = calibratedAt
    }

    func roomHeadingDegrees(planYawRadians: Float) -> Double {
        NorthAlignmentCalibration.normalized(worldHeadingDegrees - Double(planYawRadians) * 180 / .pi)
    }
}

public enum NorthCalibrationStatus: Equatable, Sendable {
    case searching
    case waitingForTrueNorth
    case improvingAccuracy
    case collecting(sampleCount: Int)
    case calibrated(ScanNorthCalibration)
    case paused
    case permissionRequired
    case compassUnavailable
    case notCalibrated

    static func afterStop(
        discard: Bool,
        calibration: ScanNorthCalibration?,
        previous: Self
    ) -> Self {
        if let calibration { return .calibrated(calibration) }
        if previous == .compassUnavailable || previous == .permissionRequired { return previous }
        return discard ? .paused : .notCalibrated
    }
}

/// Pure circular estimator. The reference vector and compass heading must describe
/// the same physical device edge at the same time, selected by the sensor adapter.
struct ScanNorthEstimator: Sendable {
    private struct Sample: Sendable {
        let bearing: Double
        let accuracy: Double
        let date: Date
    }
    private var samples: [Sample] = []
    var sampleCount: Int { samples.count }

    mutating func add(trueHeading: Double, accuracy: Double, cameraReference: SIMD3<Float>, at date: Date) {
        guard trueHeading.isFinite, (0..<360).contains(trueHeading),
              accuracy.isFinite, accuracy >= 0,
              cameraReference.x.isFinite, cameraReference.y.isFinite, cameraReference.z.isFinite,
              hypot(cameraReference.x, cameraReference.z) >= 0.35,
              samples.last.map({ date.timeIntervalSince($0.date) >= 0.2 }) ?? true else { return }
        let referenceBearing = atan2(Double(cameraReference.x), -Double(cameraReference.z)) * 180 / .pi
        let bearing = NorthAlignmentCalibration.normalized(trueHeading - referenceBearing)
        samples.append(Sample(bearing: bearing, accuracy: accuracy, date: date))
        samples = Array(samples.filter { date.timeIntervalSince($0.date) <= 10 }.suffix(60))
    }

    func estimate(at date: Date) -> ScanNorthCalibration? {
        let recent = samples.filter { (0...10).contains(date.timeIntervalSince($0.date)) }
        guard let latest = recent.last, date.timeIntervalSince(latest.date) <= 3 else { return nil }
        let provisional = ScanNorthCalibration(worldHeadingDegrees: latest.bearing,
            accuracyDegrees: latest.accuracy, sampleCount: 1, calibratedAt: latest.date)
        let accurate = recent.filter { $0.accuracy <= 20 }
        guard accurate.count >= 5, let first = accurate.first, let last = accurate.last,
              last.date.timeIntervalSince(first.date) >= 2,
              date.timeIntervalSince(last.date) <= 3 else { return provisional }
        var x = 0.0, y = 0.0, total = 0.0
        for sample in accurate {
            let weight = 1 / pow(max(1, sample.accuracy), 2)
            let radians = sample.bearing * .pi / 180
            x += cos(radians) * weight
            y += sin(radians) * weight
            total += weight
        }
        guard hypot(x, y) / total >= 0.98 else { return provisional }
        return ScanNorthCalibration(
            worldHeadingDegrees: NorthAlignmentCalibration.normalized(atan2(y, x) * 180 / .pi),
            accuracyDegrees: accurate.map(\.accuracy).max() ?? 20,
            sampleCount: accurate.count, calibratedAt: last.date
        )
    }
}
