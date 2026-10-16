//
//  Item.swift
//  Resign
//
//  Created by Valentino Manuel Gunawan on 16/10/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
