//
//  RoomDimensionExtractorTests.swift
//  ResignTests
//

import Testing
import simd
@testable import Resign

@Suite("Room Dimension Extractor Tests")
struct RoomDimensionExtractorTests {

    @Test func extractsExactInnerClearSpanFromPolygonCorners() {
        // Real coordinates from user's RoomPlan LiDAR scan (Room.json)
        let corners: [SIMD3<Float>] = [
            SIMD3<Float>(-2.1428986, -2.0243616, 0),
            SIMD3<Float>(-2.1428993, 2.037253, 0),
            SIMD3<Float>(2.0900986, 2.037253, 0),
            SIMD3<Float>(2.0900986, -2.0243616, 0)
        ]
        let wallHeights: [Float] = [3.21, 3.21, 3.21, 3.21]

        let dims = RoomDimensionExtractor.extractDimensions(
            polygonCorners: corners,
            wallHeights: wallHeights
        )

        // Verifies within millimeter precision of 4.23m and 4.06m
        #expect(abs(dims.width - 4.233) < 0.01)
        #expect(abs(dims.length - 4.062) < 0.01)
        #expect(abs(dims.height - 3.21) < 0.01)
    }

    @Test func extractsNarrowDeepRoomAccurately() {
        // Deep corridor room: 2.5m wide x 6.0m deep
        let corners: [SIMD3<Float>] = [
            SIMD3<Float>(-1.25, -3.0, 0),
            SIMD3<Float>(-1.25, 3.0, 0),
            SIMD3<Float>(1.25, 3.0, 0),
            SIMD3<Float>(1.25, -3.0, 0)
        ]

        let dims = RoomDimensionExtractor.extractDimensions(
            polygonCorners: corners,
            wallHeights: [2.7]
        )

        #expect(abs(dims.width - 2.50) < 0.01)
        #expect(abs(dims.length - 6.00) < 0.01)
        #expect(abs(dims.height - 2.70) < 0.01)
    }

    @Test func fallsBackToOrthogonalWallPairsWhenPolygonCornersAreMissing() {
        let wallLengths: [Float] = [4.23, 4.23, 4.06, 4.06]
        let wallHeights: [Float] = [3.0, 3.0, 3.0, 3.0]

        let dims = RoomDimensionExtractor.extractDimensions(
            polygonCorners: [],
            wallHeights: wallHeights,
            wallLengths: wallLengths
        )

        #expect(abs(dims.width - 4.23) < 0.01)
        #expect(abs(dims.length - 4.06) < 0.01)
        #expect(abs(dims.height - 3.00) < 0.01)
    }

    @Test func handlesSquareRoomFallbackCorrectly() {
        let wallLengths: [Float] = [4.5, 4.5, 4.5, 4.5]

        let dims = RoomDimensionExtractor.extractDimensions(
            polygonCorners: [],
            wallHeights: [2.8],
            wallLengths: wallLengths
        )

        #expect(abs(dims.width - 4.5) < 0.01)
        #expect(abs(dims.length - 4.5) < 0.01)
    }

    @Test func returnsSafeDefaultsWhenCompletelyEmpty() {
        let dims = RoomDimensionExtractor.extractDimensions(polygonCorners: [])

        #expect(dims.width == 4.0)
        #expect(dims.length == 4.0)
        #expect(dims.height == 2.8)
    }

    @Test func extractsMasonryToMasonryClearSpanFromOpposingWallsWithExplicitThickness() {
        // 4 walls placed at structural centerlines:
        // East/West at X = ±2.15m (4.30m centerline span, 0.10m thickness -> 4.20m inner masonry span)
        // North/South at Z = ±2.10m (4.20m centerline span, 0.10m thickness -> 4.10m inner masonry span)
        let walls: [ScannedWallPayload] = [
            ScannedWallPayload(position: [0, 1.6, -2.10], dimensions: [4.30, 3.2, 0.10], rotationYaw: 0),
            ScannedWallPayload(position: [0, 1.6, 2.10], dimensions: [4.30, 3.2, 0.10], rotationYaw: 0),
            ScannedWallPayload(position: [2.15, 1.6, 0], dimensions: [4.20, 3.2, 0.10], rotationYaw: .pi / 2),
            ScannedWallPayload(position: [-2.15, 1.6, 0], dimensions: [4.20, 3.2, 0.10], rotationYaw: .pi / 2)
        ]

        // Floor polygon extending to wall centerlines (4.30m x 4.20m)
        let corners: [SIMD3<Float>] = [
            SIMD3<Float>(-2.15, -2.10, 0),
            SIMD3<Float>(-2.15, 2.10, 0),
            SIMD3<Float>(2.15, 2.10, 0),
            SIMD3<Float>(2.15, -2.10, 0)
        ]

        let dims = RoomDimensionExtractor.extractDimensions(
            polygonCorners: corners,
            walls: walls
        )

        #expect(abs(dims.width - 4.20) < 0.005)
        #expect(abs(dims.length - 4.10) < 0.005)
        #expect(abs(dims.height - 3.20) < 0.005)
    }

    @Test func extractsMasonryToMasonryClearSpanFromRealRoomPlanTelemetry() {
        // Exact telemetry from user's real Indonesian masonry bedroom scan (Room.json)
        let yawU = atan2(Float(0.11366442), Float(0.9935191))
        let yawV = yawU + (.pi / 2.0)

        let walls: [ScannedWallPayload] = [
            ScannedWallPayload(
                position: SIMD3<Float>(-0.7200261, -0.08555431, -2.262815),
                dimensions: SIMD3<Float>(4.232998, 3.2099998, 0),
                rotationYaw: yawU
            ),
            ScannedWallPayload(
                position: SIMD3<Float>(-0.25836477, -0.08555431, 1.7724766),
                dimensions: SIMD3<Float>(4.2329974, 3.2099998, 0),
                rotationYaw: yawU
            ),
            ScannedWallPayload(
                position: SIMD3<Float>(1.6135867, -0.08555431, -0.48573974),
                dimensions: SIMD3<Float>(4.0616145, 3.2099998, 0),
                rotationYaw: yawV
            ),
            ScannedWallPayload(
                position: SIMD3<Float>(-2.5919778, -0.08555431, -0.004598479),
                dimensions: SIMD3<Float>(4.0616145, 3.2099998, 0),
                rotationYaw: yawV
            )
        ]

        let corners: [SIMD3<Float>] = [
            SIMD3<Float>(-2.1428986, -2.0243616, 0),
            SIMD3<Float>(-2.1428993, 2.037253, 0),
            SIMD3<Float>(2.0900986, 2.037253, 0),
            SIMD3<Float>(2.0900986, -2.0243616, 0)
        ]

        let dims = RoomDimensionExtractor.extractDimensions(
            polygonCorners: corners,
            walls: walls
        )

        // Raw opposing wall span is 4.233m x 4.062m; after 3.0cm (2 x 1.5cm) LiDAR masonry skin inset:
        // Width = 4.203m (~4.20m), Length = 4.032m (~4.03m), never overmeasuring!
        #expect(abs(dims.width - 4.203) < 0.005)
        #expect(abs(dims.length - 4.032) < 0.005)
        #expect(dims.width <= 4.21)
    }

    @Test func ignoresDoorwayAlcoveFlareOutWhenOpposingMainWallsArePresent() {
        // Main room is 4.00m x 3.80m clear span, but an entryway alcove stretches polygonCorners to 4.55m
        let walls: [ScannedWallPayload] = [
            ScannedWallPayload(position: [0, 1.5, -1.95], dimensions: [4.10, 3.0, 0.10], rotationYaw: 0),
            ScannedWallPayload(position: [0, 1.5, 1.95], dimensions: [4.10, 3.0, 0.10], rotationYaw: 0),
            ScannedWallPayload(position: [2.05, 1.5, 0], dimensions: [3.90, 3.0, 0.10], rotationYaw: .pi / 2),
            ScannedWallPayload(position: [-2.05, 1.5, 0], dimensions: [3.20, 3.0, 0.10], rotationYaw: .pi / 2),
            // Short 0.70m doorway recess wall pushed out at X = -2.55m
            ScannedWallPayload(position: [-2.55, 1.5, -1.55], dimensions: [0.70, 3.0, 0.10], rotationYaw: .pi / 2)
        ]

        let alcoveCorners: [SIMD3<Float>] = [
            SIMD3<Float>(-2.55, -1.95, 0),
            SIMD3<Float>(-2.05, 1.95, 0),
            SIMD3<Float>(2.05, 1.95, 0),
            SIMD3<Float>(2.05, -1.95, 0)
        ]

        let dims = RoomDimensionExtractor.extractDimensions(
            polygonCorners: alcoveCorners,
            walls: walls
        )

        // Must measure the main opposing masonry walls (4.00m x 3.80m), ignoring the -2.55m doorway recess!
        #expect(abs(dims.width - 4.00) < 0.005)
        #expect(abs(dims.length - 3.80) < 0.005)
    }
}
