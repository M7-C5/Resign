//
//  Insight.swift
//  Resign
//

import Foundation
import SwiftData

@Model
public final class Insight {
    public var id: UUID = UUID()
    public var title: String = ""
    public var type: String = "+"          // "+" for positive, "-" for negative
    public var detail: String = ""        // Named 'detail' because 'description' is reserved in SwiftData

    public var layout: Layout?

    public init(
        id: UUID = UUID(),
        title: String = "",
        type: String = "+",
        detail: String = ""
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.detail = detail
    }
}
