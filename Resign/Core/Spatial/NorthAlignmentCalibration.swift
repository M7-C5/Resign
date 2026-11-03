import Foundation

/// Angle conversion retained for saved room bearings and lighting simulation.
struct NorthAlignmentCalibration: Equatable {
    /// The avatar points toward north in the plan; room heading is the bearing of its -Z axis.
    static func roomHeadingDegrees(northArrowPlanRotationDegrees: Double) -> Double {
        normalized(-northArrowPlanRotationDegrees)
    }

    static func normalized(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }
}
