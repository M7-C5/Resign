//
//  RoomDimensionExtractor.swift
//  Resign
//

import Foundation
import simd

public struct RoomDimensions: Sendable, Equatable {
    public let width: Float
    public let length: Float
    public let height: Float

    public init(width: Float, length: Float, height: Float) {
        self.width = width
        self.length = length
        self.height = height
    }
}

public enum RoomDimensionExtractor {

    /// Standard LiDAR Time-of-Flight surface penetration inset per masonry wall (1.5 cm per wall = 3.0 cm per span)
    /// when RoomPlan surfaces report zero explicit thickness (`dimensions.z == 0`).
    private static let lidarMasonrySkinInset: Float = 0.015

    /// Extracts exact architectural room dimensions (width, length, height)
    /// prioritizing opposing parallel wall inner-face (masonry-to-masonry) clear spans,
    /// with fallbacks to floor polygon coordinates and orthogonal wall lengths.
    public static func extractDimensions(
        polygonCorners: [SIMD3<Float>] = [],
        walls: [ScannedWallPayload] = [],
        wallHeights: [Float] = [],
        wallLengths: [Float] = []
    ) -> RoomDimensions {
        let resolvedHeights = wallHeights.isEmpty ? walls.map(\.dimensions.y) : wallHeights
        let height = resolvedHeights.max().map { max($0, 2.2) } ?? 2.8

        let polygonSpan = extractPolygonSpan(from: polygonCorners)

        // 1. Primary Source of Truth: Opposing Wall Masonry-to-Masonry Clear Span
        if let masonrySpan = extractOpposingWallMasonrySpan(from: walls) {
            if let poly = polygonSpan {
                // Clamp against floor polygon span so doorway/alcove recesses never inflate dimensions
                return RoomDimensions(
                    width: min(masonrySpan.width, poly.width),
                    length: min(masonrySpan.length, poly.length),
                    height: height
                )
            }
            return RoomDimensions(
                width: masonrySpan.width,
                length: masonrySpan.length,
                height: height
            )
        }

        // 2. Secondary Source: RoomPlan Floor Surface Polygon Corners
        if let poly = polygonSpan {
            return RoomDimensions(width: poly.width, length: poly.length, height: height)
        }

        // 3. Fallback: Orthogonal Wall Length Pairs
        let resolvedLengths = wallLengths.isEmpty ? walls.map(\.dimensions.x) : wallLengths
        if !resolvedLengths.isEmpty {
            let sorted = resolvedLengths.sorted(by: >)
            let w = sorted.first ?? 4.0
            // Match the perpendicular wall with distinctly different length if non-square
            let l = sorted.first(where: { abs($0 - w) > 0.05 }) ?? w
            return RoomDimensions(width: w, length: l, height: height)
        }

        // 4. Safe Default
        return RoomDimensions(width: 4.0, length: 4.0, height: height)
    }

    private static func extractPolygonSpan(from polygonCorners: [SIMD3<Float>]) -> (width: Float, length: Float)? {
        guard polygonCorners.count >= 3 else { return nil }
        let xs = polygonCorners.map(\.x)
        let ys = polygonCorners.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else {
            return nil
        }
        let w = maxX - minX
        let l = maxY - minY
        guard w > 0.5 && l > 0.5 else { return nil }
        return (width: w, length: l)
    }

    private static func extractOpposingWallMasonrySpan(from walls: [ScannedWallPayload]) -> (width: Float, length: Float)? {
        let validWalls = walls.filter { $0.dimensions.x > 0.40 }
        guard validWalls.count >= 2 else { return nil }

        let sortedByLength = validWalls.sorted { $0.dimensions.x > $1.dimensions.x }
        let primaryWall = sortedByLength[0]

        // Dominant room axes in the horizontal (X, Z) plane
        let u = SIMD2<Float>(cos(primaryWall.rotationYaw), -sin(primaryWall.rotationYaw))
        let v = SIMD2<Float>(sin(primaryWall.rotationYaw), cos(primaryWall.rotationYaw))

        var parallelWalls: [ScannedWallPayload] = []
        var perpendicularWalls: [ScannedWallPayload] = []

        for wall in validWalls {
            let dir = SIMD2<Float>(cos(wall.rotationYaw), -sin(wall.rotationYaw))
            if abs(dot(dir, u)) >= abs(dot(dir, v)) {
                parallelWalls.append(wall)
            } else {
                perpendicularWalls.append(wall)
            }
        }

        // Width is the span along axis u (bounded by perpendicularWalls on East/West)
        // Length is the span along axis v (bounded by parallelWalls on North/South)
        guard let widthSpan = opposingMasonryDistance(for: perpendicularWalls, along: u),
              let lengthSpan = opposingMasonryDistance(for: parallelWalls, along: v) else {
            return nil
        }

        return (width: widthSpan, length: lengthSpan)
    }

    private static func opposingMasonryDistance(
        for wallGroup: [ScannedWallPayload],
        along axis: SIMD2<Float>
    ) -> Float? {
        guard wallGroup.count >= 2 else { return nil }

        let projections = wallGroup.map { wall -> (wall: ScannedWallPayload, proj: Float) in
            let p2D = SIMD2<Float>(wall.position.x, wall.position.z)
            return (wall, dot(p2D, axis))
        }

        guard let minProj = projections.map(\.proj).min(),
              let maxProj = projections.map(\.proj).max(),
              (maxProj - minProj) > 0.5 else {
            return nil
        }

        let midProj = (minProj + maxProj) * 0.5
        let negativeSide = projections.filter { $0.proj < midProj }
        let positiveSide = projections.filter { $0.proj >= midProj }

        // Select the dominant (longest) structural wall on each opposing side
        guard let dominantNeg = negativeSide.max(by: { $0.wall.dimensions.x < $1.wall.dimensions.x }),
              let dominantPos = positiveSide.max(by: { $0.wall.dimensions.x < $1.wall.dimensions.x }) else {
            return nil
        }

        let insetNeg = dominantNeg.wall.dimensions.z > 0.001
            ? (dominantNeg.wall.dimensions.z * 0.5)
            : lidarMasonrySkinInset
        let insetPos = dominantPos.wall.dimensions.z > 0.001
            ? (dominantPos.wall.dimensions.z * 0.5)
            : lidarMasonrySkinInset

        let innerNeg = dominantNeg.proj + insetNeg
        let innerPos = dominantPos.proj - insetPos
        let clearSpan = innerPos - innerNeg

        return clearSpan > 0.5 ? clearSpan : nil
    }
}
