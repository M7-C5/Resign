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

    /// Extracts exact architectural room dimensions (width, length, height)
    /// prioritizing true clear-span floor polygon coordinates from RoomPlan LiDAR,
    /// with robust fallbacks to wall dimensions.
    public static func extractDimensions(
        polygonCorners: [SIMD3<Float>],
        wallHeights: [Float] = [],
        wallLengths: [Float] = []
    ) -> RoomDimensions {
        let height = wallHeights.max().map { max($0, 2.2) } ?? 2.8

        // 1. Primary Source of Truth: RoomPlan Floor Surface Polygon Corners
        if polygonCorners.count >= 3 {
            let xs = polygonCorners.map(\.x)
            let ys = polygonCorners.map(\.y)
            if let minX = xs.min(), let maxX = xs.max(),
               let minY = ys.min(), let maxY = ys.max() {
                let w = maxX - minX
                let l = maxY - minY
                if w > 0.5 && l > 0.5 {
                    return RoomDimensions(width: w, length: l, height: height)
                }
            }
        }

        // 2. Fallback: Orthogonal Wall Length Pairs
        if !wallLengths.isEmpty {
            let sorted = wallLengths.sorted(by: >)
            let w = sorted.first ?? 4.0
            // Match the perpendicular wall with distinctly different length if non-square
            let l = sorted.first(where: { abs($0 - w) > 0.05 }) ?? w
            return RoomDimensions(width: w, length: l, height: height)
        }

        // 3. Safe Default
        return RoomDimensions(width: 4.0, length: 4.0, height: height)
    }
}
