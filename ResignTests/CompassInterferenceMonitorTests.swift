import Foundation
import Testing
@testable import Resign

struct CompassInterferenceMonitorTests {
    private let start = Date(timeIntervalSince1970: 1000)

    @Test func briefSpikeDoesNotWarnButSustainedStrongFieldDoes() {
        var monitor = CompassInterferenceMonitor()
        monitor.add(field: [120, 0, 0], accuracy: 5, at: start)
        #expect(monitor.warning(at: start) == nil)
        monitor.add(field: [50, 0, 0], accuracy: 5, at: start.addingTimeInterval(1))
        #expect(monitor.warning(at: start.addingTimeInterval(1)) == nil)
        for i in 2...4 {
            monitor.add(field: [0, 120, 0], accuracy: 5, at: start.addingTimeInterval(Double(i)))
        }
        #expect(monitor.warning(at: start.addingTimeInterval(4)) == .strongField)
    }

    @Test func thirtyDegreeAccuracyWarnsWithoutClaimingMagnetDetection() {
        var monitor = CompassInterferenceMonitor()
        for i in 0...3 {
            monitor.add(field: [30, 40, 0], accuracy: 30, at: start.addingTimeInterval(Double(i)))
        }
        #expect(monitor.warning(at: start.addingTimeInterval(3)) == .poorAccuracy)
    }

    @Test func recoveryRequiresSustainedGoodReadingsAndStaleWarningsExpire() {
        var monitor = CompassInterferenceMonitor()
        for i in 0...2 {
            monitor.add(field: [120, 0, 0], accuracy: 5, at: start.addingTimeInterval(Double(i)))
        }
        for i in 3...5 {
            monitor.add(field: [50, 0, 0], accuracy: 5, at: start.addingTimeInterval(Double(i)))
        }
        #expect(monitor.warning(at: start.addingTimeInterval(5)) == .strongField)
        monitor.add(field: [50, 0, 0], accuracy: 5, at: start.addingTimeInterval(6))
        #expect(monitor.warning(at: start.addingTimeInterval(6)) == nil)
        for i in 7...9 {
            monitor.add(field: [120, 0, 0], accuracy: 5, at: start.addingTimeInterval(Double(i)))
        }
        #expect(monitor.warning(at: start.addingTimeInterval(13)) == nil)
    }

    @Test func missingOrOutOfOrderSamplesDoNotAccumulateEvidence() {
        var monitor = CompassInterferenceMonitor()
        monitor.add(field: [120, 0, 0], accuracy: 5, at: start)
        monitor.add(field: [120, 0, 0], accuracy: 5, at: start.addingTimeInterval(10))
        monitor.add(field: [120, 0, 0], accuracy: 5, at: start.addingTimeInterval(9))
        #expect(monitor.warning(at: start.addingTimeInterval(10)) == nil)
    }

    @Test func unavailableFieldDoesNotProveAMagnetAndInvalidAccuracyStillWarns() {
        var monitor = CompassInterferenceMonitor()
        for i in 0...3 {
            monitor.add(field: [.nan, 0, 0], accuracy: 5, at: start.addingTimeInterval(Double(i)))
        }
        #expect(monitor.warning(at: start.addingTimeInterval(3)) == nil)
        for i in 4...7 {
            monitor.add(field: [0, 0, 0], accuracy: -1, at: start.addingTimeInterval(Double(i)))
        }
        #expect(monitor.warning(at: start.addingTimeInterval(7)) == .poorAccuracy)
    }
}
