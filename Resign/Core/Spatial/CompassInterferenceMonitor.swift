import Foundation

public enum CompassInterferenceWarning: Equatable, Sendable {
    case strongField
    case poorAccuracy
}

/// Advisory evidence only: cannot identify a case, magnet, or metal object.
struct CompassInterferenceMonitor: Sendable {
    private var candidate: CompassInterferenceWarning?
    private var candidateSince: Date?
    private var recoverySince: Date?
    private var lastSample: Date?
    private var activeWarning: CompassInterferenceWarning?

    mutating func add(field: SIMD3<Double>, accuracy: Double, at date: Date) {
        guard date.timeIntervalSinceReferenceDate.isFinite,
              lastSample.map({ date > $0 }) ?? true else { return }
        if let lastSample, date.timeIntervalSince(lastSample) > 1.5 {
            candidate = nil
            candidateSince = nil
            recoverySince = nil
            if date.timeIntervalSince(lastSample) > 3 { activeWarning = nil }
        }
        lastSample = date
        let magnitude = hypot(hypot(field.x, field.y), field.z)
        let hasField = magnitude.isFinite && magnitude > 0
        let next: CompassInterferenceWarning?
        if hasField && magnitude >= 100 {
            next = .strongField
        } else if accuracy.isFinite && (accuracy < 0 || accuracy >= 25) {
            next = .poorAccuracy
        } else {
            next = nil
        }
        if let next {
            recoverySince = nil
            if candidate != next {
                candidate = next
                candidateSince = date
            }
            let duration: TimeInterval = next == .strongField ? 2 : 3
            if let candidateSince, date.timeIntervalSince(candidateSince) >= duration {
                // Strong-field evidence stays visible until readings actually recover.
                if activeWarning != .strongField || next == .strongField { activeWarning = next }
            }
        } else {
            candidate = nil
            candidateSince = nil
            let recovered = accuracy.isFinite && (0...20).contains(accuracy)
                && (!hasField || magnitude <= 80)
            if recovered {
                if recoverySince == nil { recoverySince = date }
                if let recoverySince, date.timeIntervalSince(recoverySince) >= 3 { activeWarning = nil }
            } else {
                recoverySince = nil
            }
        }
    }

    func warning(at date: Date) -> CompassInterferenceWarning? {
        guard let lastSample, (0...3).contains(date.timeIntervalSince(lastSample)) else { return nil }
        return activeWarning
    }
}
