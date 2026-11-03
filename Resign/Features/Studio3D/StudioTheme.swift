//
//  StudioTheme.swift
//  Resign
//

import SwiftUI
import UIKit

/// Design tokens, typography, and palette for 3D Studio architectural views.
public enum StudioTheme {
    /// Warm parchment / linen canvas background (#F8F2E8).
    public static let canvasBackground = Color(red: 248 / 255.0, green: 242 / 255.0, blue: 232 / 255.0)
    public static let uiCanvasBackground = UIColor(red: 248.0 / 255.0, green: 242.0 / 255.0, blue: 232.0 / 255.0, alpha: 1.0)

    /// Deep warm walnut / mahogany typography and icon tint (#6D4531).
    public static let primaryText = Color(red: 109 / 255.0, green: 69 / 255.0, blue: 49 / 255.0)
    public static let secondaryText = Color(red: 139 / 255.0, green: 110 / 255.0, blue: 95 / 255.0)

    /// Soft cream circular button background (#FAF7EF).
    public static let buttonBackground = Color(red: 250 / 255.0, green: 247 / 255.0, blue: 239 / 255.0)
    public static let buttonStroke = Color(red: 232 / 255.0, green: 224 / 255.0, blue: 212 / 255.0)

    /// Inventory button background (#6D4531).
    public static let inventoryBackground = Color(red: 109 / 255.0, green: 69 / 255.0, blue: 49 / 255.0)

    /// Apple New York serif font style for architectural room headers.
    public static func titleFont(size: CGFloat = 22, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}
