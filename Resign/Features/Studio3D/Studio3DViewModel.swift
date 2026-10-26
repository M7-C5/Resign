import Observation

/// Holds the confirmed lighting and the draft being edited in the sheet.
@Observable
@MainActor
public final class Studio3DViewModel {
    private(set) var lightingSettings = LightingSimulationSettings()
    var lightingDraft = LightingSimulationSettings()
    var isLightingPresented = false

    /// While the sheet is open the room previews the draft; otherwise the confirmed settings.
    var previewLighting: LightingSimulationSettings {
        isLightingPresented ? lightingDraft : lightingSettings
    }

    public init() {}

    func beginLightingEditing() {
        lightingDraft = lightingSettings
        isLightingPresented = true
    }

    func confirmLightingEditing() {
        guard isLightingPresented else { return }
        lightingSettings = lightingDraft
        isLightingPresented = false
    }

    func discardLightingEditing() {
        lightingDraft = lightingSettings
        isLightingPresented = false
    }

    /// Called after any dismissal, including swipe down. The draft never outlives the sheet.
    func sheetDidDismiss() {
        lightingDraft = lightingSettings
    }
}
