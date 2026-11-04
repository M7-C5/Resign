import Foundation
import Testing
import simd
@testable import Resign

@Suite("Automatic scan north calibration")
struct ScanNorthCalibrationTests {
    private let start = Date(timeIntervalSince1970: 1000)

    @Test func coarseValidCompassImmediatelyProvidesAnEstimateThenRefines() throws {
        var estimator = ScanNorthEstimator()
        estimator.add(trueHeading: 75, accuracy: 45, cameraReference: [0, 0, -1], at: start)
        let initial = try #require(estimator.estimate(at: start))
        #expect(initial.worldHeadingDegrees == 75)
        #expect(initial.accuracyDegrees == 45)
        #expect(!initial.isRefined)
        for i in 1...6 {
            estimator.add(trueHeading: 80, accuracy: 5, cameraReference: [0, 0, -1],
                          at: start.addingTimeInterval(Double(i)))
        }
        let refined = try #require(estimator.estimate(at: start.addingTimeInterval(6)))
        #expect(refined.isRefined)
        #expect(abs(refined.worldHeadingDegrees - 80) < 0.001)
    }

    @Test func frequentCompassCallbacksStillSpanEnoughTimeToCalibrate() throws {
        var estimator = ScanNorthEstimator()
        for i in 0...400 {
            estimator.add(trueHeading: 90, accuracy: 5, cameraReference: [0, 0, -1],
                          at: start.addingTimeInterval(Double(i) / 100))
        }
        let result = try #require(estimator.estimate(at: start.addingTimeInterval(4)))
        #expect(abs(result.worldHeadingDegrees - 90) < 0.001)
        #expect(result.sampleCount >= 5)
    }

    @Test func referenceUsesHorizontalEdgeForLandscapeAndPortraitScanning() {
        #expect(ScanNorthReference.choose(portraitTop: [1, 0, 0], landscapeTop: [0, 1, 0]) == .portrait)
        #expect(ScanNorthReference.choose(portraitTop: [0, 1, 0], landscapeTop: [1, 0, 0]) == .landscapeLeft)
        // Keep the current reference during small pose changes to avoid restarting calibration.
        #expect(ScanNorthReference.choose(portraitTop: [0.8, 0.6, 0], landscapeTop: [0.6, -0.8, 0], current: .landscapeLeft) == .landscapeLeft)
    }

    @Test func trackingPauseAndAvailabilityFailuresRemainDistinct() {
        #expect(NorthCalibrationStatus.afterStop(discard: true, calibration: nil, previous: .searching) == .paused)
        #expect(NorthCalibrationStatus.afterStop(discard: false, calibration: nil, previous: .searching) == .notCalibrated)
        #expect(NorthCalibrationStatus.afterStop(discard: false, calibration: nil, previous: .permissionRequired) == .permissionRequired)
        #expect(NorthCalibrationStatus.afterStop(discard: false, calibration: nil, previous: .compassUnavailable) == .compassUnavailable)
    }

    @Test func removesCameraRotationAndAppliesPlanYaw() throws {
        var estimator = ScanNorthEstimator()
        for i in 0..<6 {
            let bearing = Double(i * 15)
            let angle = Float(bearing * .pi / 180)
            estimator.add(trueHeading: 90 + bearing, accuracy: 5,
                          cameraReference: [sin(angle), 0, -cos(angle)], at: start.addingTimeInterval(Double(i)))
        }
        let result = try #require(estimator.estimate(at: start.addingTimeInterval(5)))
        #expect(abs(result.worldHeadingDegrees - 90) < 0.001)
        #expect(abs(result.roomHeadingDegrees(planYawRadians: .pi / 2)) < 0.001)
        #expect(abs(result.roomHeadingDegrees(planYawRadians: -.pi / 2) - 180) < 0.001)
    }

    @Test func averagesAcrossNorthWithoutTurningSouth() throws {
        var estimator = ScanNorthEstimator()
        for (i, heading) in [359.0, 1, 359, 1, 0].enumerated() {
            estimator.add(trueHeading: heading, accuracy: 5, cameraReference: [0, 0, -1],
                          at: start.addingTimeInterval(Double(i)))
        }
        let result = try #require(estimator.estimate(at: start.addingTimeInterval(4)))
        #expect(min(result.worldHeadingDegrees, 360 - result.worldHeadingDegrees) < 0.01)
        #expect(estimator.estimate(at: start.addingTimeInterval(20)) == nil)
    }

    @Test func rejectsUnreliableAndVerticalReadings() {
        var estimator = ScanNorthEstimator()
        for i in 0..<6 {
            let date = start.addingTimeInterval(Double(i))
            estimator.add(trueHeading: -1, accuracy: 5, cameraReference: [0, 0, -1], at: date)
            estimator.add(trueHeading: 90, accuracy: -1, cameraReference: [0, 0, -1], at: date)
            estimator.add(trueHeading: 90, accuracy: 5, cameraReference: [0, 1, 0], at: date)
        }
        #expect(estimator.estimate(at: start.addingTimeInterval(5)) == nil)
    }

    @Test func inconsistentWorldBearingsRemainProvisional() {
        var estimator = ScanNorthEstimator()
        for i in 0..<6 {
            estimator.add(trueHeading: Double(i * 60), accuracy: 5, cameraReference: [0, 0, -1],
                          at: start.addingTimeInterval(Double(i)))
        }
        let result = estimator.estimate(at: start.addingTimeInterval(5))
        #expect(result != nil)
        #expect(result?.isRefined == false)
    }

    @Test(arguments: [5.0, 45.0]) @MainActor func mapperPersistsCalibrationInRoomFrameAndLegacySnapshotsStillDecode(accuracy: Double) throws {
        let north = ScanNorthCalibration(worldHeadingDegrees: 120, accuracyDegrees: accuracy,
                                        sampleCount: accuracy <= 20 ? 6 : 1, calibratedAt: start)
        let walls = [ScannedWallPayload(position: [0, 1, 0], dimensions: [5, 2, 0], rotationYaw: .pi / 2)]
        let payload = CapturedRoomPayload(roomLength: 4, roomWidth: 5, roomHeight: 2, walls: walls, openings: [], objects: [])
        let room = RoomCaptureMapper().mapToRoom(payload: payload, northCalibration: north)
        #expect(abs(room.compass - 30) < 0.001)
        let data = try #require(room.planSnapshotData)
        let snapshot = try JSONDecoder().decode(RoomPlanSnapshot.self, from: data)
        #expect(snapshot.northCalibration == north)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "northCalibration")
        let legacy = try JSONDecoder().decode(RoomPlanSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.northCalibration == nil)
    }
}
