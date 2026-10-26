//
//  RoomCreationRoute.swift
//  Resign
//

import Foundation

public enum RoomCreationRoute: Hashable, Sendable {
    case result(roomId: UUID)
    case orientation(layoutID: UUID)
    case lightingSetup(layoutID: UUID)
}
