import Foundation
import Observation

/// UI-only choices for the current viewer session, independent of persisted lights.
struct LightingSimulationSettings: Equatable {
    var artificialLightsOn = true
    var minuteOfDay = 720

    var timeLabel: String {
        String(format: "%02d.%02d", minuteOfDay / 60, minuteOfDay % 60)
    }
}

@Observable
@MainActor
public final class Studio3DViewModel {
    private(set) var lightingSettings = LightingSimulationSettings()
    var lightingDraft = LightingSimulationSettings()
    private(set) var isLightingPresented = false

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
}
