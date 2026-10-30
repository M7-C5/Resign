import SwiftUI
import UIKit
import CoreLocation

/// Reads only the hosting window, so separate iPad scenes do not share orientation state.
struct CompassHeadingOrientationReader: UIViewRepresentable {
    let onChange: (CLDeviceOrientation) -> Void

    static func headingOrientation(for interface: UIInterfaceOrientation) -> CLDeviceOrientation? {
        switch interface {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        // UIKit's interface rotation is opposite to the physical device rotation.
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        default: return nil
        }
    }

    func makeUIView(context: Context) -> OrientationProbe {
        let view = OrientationProbe()
        view.onChange = onChange
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: OrientationProbe, context: Context) {
        view.onChange = onChange
        view.reportOrientation()
    }

    final class OrientationProbe: UIView {
        var onChange: ((CLDeviceOrientation) -> Void)?
        private var lastReported: CLDeviceOrientation?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            reportOrientation()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            reportOrientation()
        }

        func reportOrientation() {
            guard let interface = window?.windowScene?.effectiveGeometry.interfaceOrientation,
                  let orientation = CompassHeadingOrientationReader.headingOrientation(for: interface),
                  orientation != lastReported else { return }
            lastReported = orientation
            Task { @MainActor [weak self] in
                guard let self, self.lastReported == orientation else { return }
                self.onChange?(orientation)
            }
        }
    }
}
