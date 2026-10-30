import Foundation
import Testing
import UIKit
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
}
