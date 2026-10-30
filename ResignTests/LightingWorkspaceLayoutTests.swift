import Foundation
import Testing
import UIKit
import CoreLocation
import RealityKit
import simd
@testable import Resign

@Suite("Lighting workspace adaptation")
struct LightingWorkspaceLayoutTests {
    @Test(arguments: [CGSize(width: 1032, height: 1376), CGSize(width: 1194, height: 834),
                      CGSize(width: 1133, height: 744), CGSize(width: 1024, height: 768)])
    func tabletWindowsKeepPreviewAndControlsVisible(size: CGSize) {
        let layout = LightingWorkspaceLayout(size: size)
        #expect(layout.usesSidePanel)
        #expect(layout.panelWidth >= 320 && layout.panelWidth <= 380)
        #expect(size.width - layout.panelWidth - 48 >= 360)
        #expect(layout.simulationBottomInset(isEditing: true) == 0)
    }

    @Test(arguments: [CGSize(width: 393, height: 852), CGSize(width: 507, height: 1024),
                      CGSize(width: 834, height: 1194),
                      CGSize(width: 744, height: 1133), CGSize(width: 844, height: 390)])
    func narrowAndShortWindowsUseScrollableStack(size: CGSize) {
        let layout = LightingWorkspaceLayout(size: size)
        #expect(!layout.usesSidePanel)
        #expect(layout.simulationBottomInset(isEditing: false) == 0)
        #expect(layout.simulationBottomInset(isEditing: true) <= size.height * 0.45)
    }

    @Test func accessibilityTextUsesStackedControlsEvenOnWideWindow() {
        let layout = LightingWorkspaceLayout(size: CGSize(width: 1194, height: 834), accessibilityText: true)
        #expect(!layout.usesSidePanel)
    }

    @Test @MainActor func narrowViewportFitsRoomWithoutResettingUserOrbitOrZoom() throws {
        let controller = RoomSceneController(fixtures: [])
        controller.setOrbit(yaw: 0.7, pitch: 0.6)
        controller.setDistance(9)
        let camera = try #require(controller.root.children.compactMap { $0 as? PerspectiveCamera }.first)
        let initial = camera.position
        controller.setViewportSize(CGSize(width: 400, height: 1000))
        #expect(simd_distance(camera.position, initial) > controller.distance)
        #expect(controller.yaw == 0.7 && controller.pitch == 0.6 && controller.distance == 9)
        controller.setViewportSize(CGSize(width: 1000, height: 700))
        #expect(simd_distance(camera.position, initial) < 0.001)
    }

    @Test @MainActor func headingReferenceFollowsInterfaceOrientation() {
        #expect(CompassHeadingOrientationReader.headingOrientation(for: .portrait) == .portrait)
        #expect(CompassHeadingOrientationReader.headingOrientation(for: .portraitUpsideDown) == .portraitUpsideDown)
        #expect(CompassHeadingOrientationReader.headingOrientation(for: .landscapeLeft) == .landscapeRight)
        #expect(CompassHeadingOrientationReader.headingOrientation(for: .landscapeRight) == .landscapeLeft)
        #expect(CompassHeadingOrientationReader.headingOrientation(for: .unknown) == nil)
    }

    @Test @MainActor func invalidSensorReadingCancelsHoldAndValidReadingRecovers() {
        let model = OrientationViewModel()
        model.start()
        defer { model.stop() }
        let date = Date()
        model.receiveHeading(0, reference: "Magnetic North", accuracy: 5, at: date)
        #expect(model.isHoldingNorth)
        model.receiveHeading(0, reference: "Magnetic North", accuracy: -1,
                             at: date.addingTimeInterval(1))
        model.tick(at: date.addingTimeInterval(3))
        #expect(!model.isHeadingLocked && model.headingDegrees == nil)
        #expect(model.compassIssue != nil)

        model.receiveHeading(0, reference: "Magnetic North", accuracy: 5,
                             at: date.addingTimeInterval(4))
        #expect(model.compassIssue == nil)
        model.tick(at: date.addingTimeInterval(5))
        #expect(!model.isHeadingLocked)
        model.tick(at: date.addingTimeInterval(6.1))
        #expect(model.isHeadingLocked)
    }

    @Test @MainActor func backgroundTimeDoesNotCountTowardNorthHold() {
        let model = OrientationViewModel()
        model.start()
        defer { model.stop() }
        let date = Date()
        model.receiveHeading(0, reference: "Magnetic North", accuracy: 5, at: date)
        model.stop()
        model.tick(at: date.addingTimeInterval(10))
        #expect(!model.isHeadingLocked && model.headingDegrees == nil)
        model.start()
        model.receiveHeading(0, reference: "Magnetic North", accuracy: 5,
                             at: date.addingTimeInterval(11))
        model.start()
        model.tick(at: date.addingTimeInterval(12))
        #expect(!model.isHeadingLocked)
        model.tick(at: date.addingTimeInterval(13.1))
        #expect(model.isHeadingLocked)
    }

    @Test @MainActor func headingInterferenceIsReportedWithoutLockingAnOldSample() {
        let model = OrientationViewModel()
        model.start()
        defer { model.stop() }
        let date = Date()
        model.receiveHeading(0, reference: "Magnetic North", accuracy: 5, at: date)
        model.locationManager(CLLocationManager(), didFailWithError: CLError(.headingFailure))
        model.tick(at: date.addingTimeInterval(3))
        #expect(model.compassIssue != nil)
        #expect(model.headingDegrees == nil && !model.isHeadingLocked)
        model.retryCompass()
        #expect(model.compassIssue == nil && !model.isHeadingLocked)
    }

    @Test @MainActor func rotatingAfterManualNorthLockPreservesCalibration() {
        let model = OrientationViewModel()
        model.start()
        defer { model.stop() }
        guard model.usesManualHeading else { return }
        let start = Date()
        model.setManualHeading(0, at: start)
        model.tick(at: start.addingTimeInterval(2.1))
        #expect(model.isHeadingLocked)
        model.setHeadingOrientation(.landscapeLeft)
        #expect(model.isHeadingLocked && model.headingDegrees == 0)
    }
}
