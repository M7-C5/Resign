//
//  Studio3DViewModel.swift
//  Resign
//
//  Created by Antigravity on 21/10/26.
//

import Foundation
import Observation

@Observable
public final class Studio3DViewModel {
    public var highlightedFurnitureIDs: Set<UUID> = []
    public var selectedFurnitureID: UUID? = nil

    public init() {}

    public func highlightFurniture(ids: Set<UUID>) {
        highlightedFurnitureIDs = ids
    }

    public func clearHighlights() {
        highlightedFurnitureIDs.removeAll()
    }

    public func isHighlighted(_ id: UUID) -> Bool {
        highlightedFurnitureIDs.contains(id)
    }

    public func toggleHighlight(for id: UUID) {
        if highlightedFurnitureIDs.contains(id) {
            highlightedFurnitureIDs.remove(id)
        } else {
            highlightedFurnitureIDs.insert(id)
        }
    }
}
