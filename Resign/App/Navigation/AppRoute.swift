//
//  AppRoute.swift
//  Resign
//

import Foundation

public enum AppRoute: Hashable {
    case dashboard
    case roomScan
    case orientation(roomId: UUID)
}
