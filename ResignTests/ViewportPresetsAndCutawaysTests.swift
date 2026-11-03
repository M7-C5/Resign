//
//  ViewportPresetsAndCutawaysTests.swift
//  ResignTests
//

import Testing
import RealityKit
import Foundation
import simd
@testable import Resign

@Suite("Viewport Presets and Wall Cutaways")
struct ViewportPresetsAndCutawaysTests {

    @Test @MainActor func viewportPresetAnglesMatchArchitecturalContracts() {
        #expect(abs(ViewportPreset.top.targetPitch - 1.55) < 0.01)
        #expect(abs(ViewportPreset.front.targetYaw - 0.0) < 0.01)
        #expect(abs(ViewportPreset.front.targetPitch - 0.15) < 0.01)
        #expect(abs(ViewportPreset.back.targetYaw - .pi) < 0.01)
        #expect(abs(ViewportPreset.back.targetPitch - 0.15) < 0.01)
        #expect(abs(ViewportPreset.left.targetYaw - (-.pi / 2.0)) < 0.01)
        #expect(abs(ViewportPreset.right.targetYaw - (.pi / 2.0)) < 0.01)
        #expect(abs(ViewportPreset.dollhouse.targetYaw - (-0.73)) < 0.01)
        #expect(abs(ViewportPreset.dollhouse.targetPitch - 0.62) < 0.01)
    }

    @Test @MainActor func snapToViewportUpdatesOrbitDirectlyWhenUnanimated() {
        let controller = RoomSceneController()
        controller.snapToViewport(.front, animated: false)
        #expect(abs(controller.yaw - ViewportPreset.front.targetYaw) < 0.01)
        #expect(abs(controller.pitch - ViewportPreset.front.targetPitch) < 0.01)

        controller.snapToViewport(.right, animated: false)
        #expect(abs(controller.yaw - ViewportPreset.right.targetYaw) < 0.01)
        #expect(abs(controller.pitch - ViewportPreset.right.targetPitch) < 0.01)
    }

    @Test @MainActor func topViewKeepsAllPerimeterWallsVisible() async throws {
        let controller = RoomSceneController()
        await controller.load()

        controller.snapToViewport(.top, animated: false)
        #expect(controller.pitch >= 1.05)

        // In Top view, all walls remain enabled
        for item in controller.wallCutaways {
            #expect(item.entity.isEnabled == true)
        }
    }

    @Test @MainActor func frontViewCutsAwaySouthFacingWallsOnly() async throws {
        let controller = RoomSceneController()
        await controller.load()

        // Front view looks from South (+Z) looking toward North (-Z)
        controller.snapToViewport(.front, animated: false)

        for item in controller.wallCutaways {
            let isSouthWall = item.outwardNormal.y > 0.8
            let isNorthWall = item.outwardNormal.y < -0.8
            if isSouthWall {
                #expect(item.entity.isEnabled == false)
            } else if isNorthWall {
                #expect(item.entity.isEnabled == true)
            }
        }
    }

    @Test @MainActor func backViewCutsAwayNorthFacingWallsOnly() async throws {
        let controller = RoomSceneController()
        await controller.load()

        // Back view looks from North (-Z) looking toward South (+Z)
        controller.snapToViewport(.back, animated: false)

        for item in controller.wallCutaways {
            let isNorthWall = item.outwardNormal.y < -0.8
            let isSouthWall = item.outwardNormal.y > 0.8
            if isNorthWall {
                #expect(item.entity.isEnabled == false)
            } else if isSouthWall {
                #expect(item.entity.isEnabled == true)
            }
        }
    }

    @Test @MainActor func rightViewCutsAwayEastFacingWallsOnly() async throws {
        let controller = RoomSceneController()
        await controller.load()

        // Right view looks from East (+X) looking toward West (-X)
        controller.snapToViewport(.right, animated: false)

        for item in controller.wallCutaways {
            let isEastWall = item.outwardNormal.x > 0.8
            let isWestWall = item.outwardNormal.x < -0.8
            if isEastWall {
                #expect(item.entity.isEnabled == false)
            } else if isWestWall {
                #expect(item.entity.isEnabled == true)
            }
        }
    }

    @Test @MainActor func leftViewCutsAwayWestFacingWallsOnly() async throws {
        let controller = RoomSceneController()
        await controller.load()

        // Left view looks from West (-X) looking toward East (+X)
        controller.snapToViewport(.left, animated: false)

        for item in controller.wallCutaways {
            let isWestWall = item.outwardNormal.x < -0.8
            let isEastWall = item.outwardNormal.x > 0.8
            if isWestWall {
                #expect(item.entity.isEnabled == false)
            } else if isEastWall {
                #expect(item.entity.isEnabled == true)
            }
        }
    }

    @Test @MainActor func isometricCornerCutsAwayAtMostTwoFrontFacingWalls() async throws {
        let controller = RoomSceneController()
        await controller.load()

        // Standard dollhouse angle (-0.73 rad, South-West quadrant)
        controller.snapToViewport(.dollhouse, animated: false)

        let hiddenWalls = controller.wallCutaways.filter { !$0.entity.isEnabled }
        let visibleWalls = controller.wallCutaways.filter { $0.entity.isEnabled }

        // Up to 2 wall directions facing camera are cut away, and far walls remain visible
        let hiddenDirections = Set(hiddenWalls.map {
            "\($0.outwardNormal.x > 0.5 ? "E" : ($0.outwardNormal.x < -0.5 ? "W" : ""))\(($0.outwardNormal.y > 0.5 ? "S" : ($0.outwardNormal.y < -0.5 ? "N" : "")))"
        })
        #expect(hiddenDirections.count <= 2)
        #expect(visibleWalls.count >= 2)
    }
}
