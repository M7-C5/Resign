import Foundation

public enum AppRoute: Hashable {
    case dashboard
    case roomScan
    case orientation(roomId: UUID)
    /// 5×5 ceiling light grid; saves `Light` objects on the associated layout.
    case lightingSetup(layoutID: UUID)
    /// The studio simulates only the lights attached to this layout.
    case studio3D(layoutID: UUID?)
}
