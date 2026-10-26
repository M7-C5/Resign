//
//  AppRoute.swift
//  Resign
//

import Foundation

public enum AppRoute: Hashable {
    case dashboard
    case roomScan
    case orientation(roomId: UUID)
    /// Phase 4 — 5×5 ceiling light grid.
    /// Carries the `Layout.id` of the record that will receive the saved `Light` objects.
    case lightingSetup(layoutID: UUID)
    /// The studio simulates only the lights attached to this layout.
    case studio3D(layoutID: UUID?)
}
