import Foundation

/// Locks the device's north reference only after it stays near north continuously.
struct NorthAlignmentCalibration: Equatable {
    static let lockDuration: TimeInterval = 2
    static let northToleranceDegrees = 8.0

    private(set) var alignedSince: Date?
    private(set) var isLocked = false

    @discardableResult
    mutating func update(
        headingDegrees: Double,
        accuracyDegrees: Double? = nil,
        at date: Date
    ) -> Bool {
        guard !isLocked else { return true }

        if let accuracyDegrees, accuracyDegrees > Self.northToleranceDegrees {
            alignedSince = nil
            return false
        }

        guard angularDistance(from: Self.normalized(headingDegrees), to: 0) <= Self.northToleranceDegrees else {
            alignedSince = nil
            return false
        }

        if alignedSince == nil {
            alignedSince = date
            return false
        }

        guard let alignedSince else { return false }
        if date.timeIntervalSince(alignedSince) >= Self.lockDuration {
            isLocked = true
        }
        return isLocked
    }

    func progress(at date: Date) -> Double {
        guard !isLocked, let alignedSince else { return isLocked ? 1 : 0 }
        return min(1, max(0, date.timeIntervalSince(alignedSince) / Self.lockDuration))
    }

    /// The avatar points toward north in the plan; room heading is the bearing of its -Z axis.
    static func roomHeadingDegrees(northArrowPlanRotationDegrees: Double) -> Double {
        normalized(-northArrowPlanRotationDegrees)
    }

    static func normalized(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }

    private func angularDistance(from first: Double, to second: Double) -> Double {
        let difference = abs(Self.normalized(first) - Self.normalized(second))
        return min(difference, 360 - difference)
    }
}
