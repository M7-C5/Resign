//
//  ViewportPreset.swift
//  Resign
//

import Foundation

/// Architectural viewport presets for rapid 3D studio viewpoint alignment.
public enum ViewportPreset: String, CaseIterable, Identifiable, Sendable {
    case top
    case front
    case back
    case left
    case right
    case dollhouse

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .top: return "Top"
        case .front: return "Front"
        case .back: return "Back"
        case .left: return "Left"
        case .right: return "Right"
        case .dollhouse: return "Reset Angle"
        }
    }

    public var systemImage: String {
        switch self {
        case .top: return "square.topthird.inset.filled"
        case .front: return "rectangle.portrait.and.arrow.forward"
        case .back: return "rectangle.portrait.and.arrow.backward"
        case .left: return "arrow.left.to.line"
        case .right: return "arrow.right.to.line"
        case .dollhouse: return "cube.transparent"
        }
    }

    public var targetYaw: Float {
        switch self {
        case .top: return 0.0
        case .front: return 0.0
        case .back: return .pi
        case .left: return -.pi / 2.0
        case .right: return .pi / 2.0
        case .dollhouse: return -0.73
        }
    }

    public var targetPitch: Float {
        switch self {
        case .top: return 1.55 // ~89° bird's-eye
        case .front, .back, .left, .right: return 0.15 // Eye-level orthogonal angle
        case .dollhouse: return 0.62 // Standard isometric tilt
        }
    }
}
