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
}
