import Foundation

/// Window-based UI policy, independent of device identity and saved lighting coordinates.
struct LightingWorkspaceLayout: Sendable {
    let size: CGSize
    let accessibilityText: Bool

    init(size: CGSize, accessibilityText: Bool = false) {
        self.size = size
        self.accessibilityText = accessibilityText
    }

    var usesSidePanel: Bool { size.width >= 900 && size.height >= 500 && !accessibilityText }
    var panelWidth: CGFloat { min(380, max(320, size.width * 0.30)) }

    func simulationBottomInset(isEditing: Bool) -> CGFloat {
        isEditing && !usesSidePanel ? min(300, size.height * 0.45) : 0
    }
}
