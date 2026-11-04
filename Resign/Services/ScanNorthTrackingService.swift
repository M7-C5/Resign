import ARKit
import CoreLocation
import Foundation

/// Foreground-only sensor adapter; does not take over RoomPlan's ARSession delegate.
@MainActor
final class ScanNorthTrackingService: NSObject, CLLocationManagerDelegate {
    private struct CameraSample {
        let date: Date
        let reference: SIMD3<Float>
    }
    private let manager = CLLocationManager()
    private weak var session: ARSession?
    private var timer: Timer?
    private var cameraSamples: [CameraSample] = []
    private var estimator = ScanNorthEstimator()
    private var reference: ScanNorthReference?
    private var referenceChangedAt = Date.distantPast
    private var running = false
    private(set) var calibration: ScanNorthCalibration?
    private(set) var status: NorthCalibrationStatus = .searching
    var onStatusChange: (@MainActor (NorthCalibrationStatus) -> Void)?
    private var interferenceMonitor = CompassInterferenceMonitor()
    private var interferenceWarning: CompassInterferenceWarning?
    var onInterferenceChange: (@MainActor (CompassInterferenceWarning?) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        // Updated from the horizontal projection of the actual camera axes while scanning.
        manager.headingOrientation = .landscapeLeft
        manager.headingFilter = kCLHeadingFilterNone
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func start(session: ARSession) {
        stopSensors()
        calibration = nil
        estimator = ScanNorthEstimator()
        reference = nil
        interferenceMonitor = CompassInterferenceMonitor()
        guard CLLocationManager.headingAvailable() else {
            updateStatus(.compassUnavailable)
            return
        }
        self.session = session
        running = true
        updateStatus(.searching)
        let samplingTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recordCameraFrame() }
        }
        timer = samplingTimer
        RunLoop.main.add(samplingTimer, forMode: .common)
        updateAuthorization()
    }

    func stop(discard: Bool) {
        if running, !discard {
            // A bearing remains valid for this AR world after successful estimation.
            // Tracking loss and reference changes explicitly invalidate it below.
            acceptEstimate(estimator.estimate(at: Date()))
        }
        if discard { calibration = nil }
        updateStatus(NorthCalibrationStatus.afterStop(
            discard: discard,
            calibration: calibration,
            previous: status
        ))
        stopSensors()
    }

    private func stopSensors() {
        running = false
        timer?.invalidate()
        timer = nil
        manager.stopUpdatingHeading()
        manager.stopUpdatingLocation()
        session = nil
        cameraSamples.removeAll()
        updateInterferenceWarning(nil)
    }

    private func recordCameraFrame() {
        if running { updateInterferenceWarning(interferenceMonitor.warning(at: Date())) }
        guard running, let frame = session?.currentFrame else { return }
        guard case .normal = frame.camera.trackingState else {
            cameraSamples.removeAll()
            estimator = ScanNorthEstimator()
            calibration = nil
            updateStatus(.searching)
            return
        }
        let date = Date(timeIntervalSinceNow: frame.timestamp - ProcessInfo.processInfo.systemUptime)
        guard cameraSamples.last.map({ date > $0.date }) ?? true else { return }
        let x = frame.camera.transform.columns.0
        let y = frame.camera.transform.columns.1
        let portraitTop = SIMD3<Float>(-x.x, -x.y, -x.z)
        let landscapeTop = SIMD3<Float>(y.x, y.y, y.z)
        let next = ScanNorthReference.choose(portraitTop: portraitTop, landscapeTop: landscapeTop, current: reference)
        if next != reference {
            reference = next
            referenceChangedAt = Date()
            manager.headingOrientation = next == .portrait ? .portrait : .landscapeLeft
            cameraSamples.removeAll()
            estimator = ScanNorthEstimator()
            calibration = nil
            updateStatus(.searching)
        }
        cameraSamples.append(CameraSample(date: date, reference: next == .portrait ? portraitTop : landscapeTop))
        cameraSamples = Array(cameraSamples.suffix(30))
    }

    private func updateAuthorization() {
        guard running else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation() // Needed by Core Location to resolve true north.
            manager.startUpdatingHeading()
        case .denied, .restricted:
            stop(discard: true, status: .permissionRequired)
        @unknown default:
            stop(discard: true, status: .permissionRequired)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorization()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Location updates enable trueHeading; geographic coordinates are not retained.
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
        guard running, (0...1).contains(-heading.timestamp.timeIntervalSinceNow) else { return }
        interferenceMonitor.add(field: [heading.x, heading.y, heading.z],
                                accuracy: heading.headingAccuracy, at: heading.timestamp)
        updateInterferenceWarning(interferenceMonitor.warning(at: Date()))
        guard heading.timestamp >= referenceChangedAt else { return }
        guard heading.trueHeading >= 0 else {
            if calibration == nil { updateStatus(.waitingForTrueNorth) }
            return
        }
        guard heading.headingAccuracy.isFinite, heading.headingAccuracy >= 0 else {
            if calibration == nil { updateStatus(.improvingAccuracy) }
            return
        }
        guard let camera = cameraSamples.min(by: {
                  abs($0.date.timeIntervalSince(heading.timestamp)) < abs($1.date.timeIntervalSince(heading.timestamp))
              }), abs(camera.date.timeIntervalSince(heading.timestamp)) <= 0.2 else { return }
        estimator.add(trueHeading: heading.trueHeading, accuracy: heading.headingAccuracy,
                      cameraReference: camera.reference, at: heading.timestamp)
        acceptEstimate(estimator.estimate(at: heading.timestamp))
        if let calibration {
            updateStatus(.calibrated(calibration))
        } else {
            updateStatus(.collecting(sampleCount: estimator.sampleCount))
        }
    }

    private func acceptEstimate(_ estimate: ScanNorthCalibration?) {
        guard let estimate else { return }
        if let calibration {
            if calibration.isRefined && !estimate.isRefined { return }
            if !estimate.isRefined && estimate.accuracyDegrees > calibration.accuracyDegrees { return }
        }
        calibration = estimate
    }

    private func updateStatus(_ status: NorthCalibrationStatus) {
        guard self.status != status else { return }
        self.status = status
        onStatusChange?(status)
    }

    private func updateInterferenceWarning(_ warning: CompassInterferenceWarning?) {
        guard warning != interferenceWarning else { return }
        interferenceWarning = warning
        onInterferenceChange?(warning)
    }

    private func stop(discard: Bool, status: NorthCalibrationStatus) {
        if discard { calibration = nil }
        updateStatus(status)
        stopSensors()
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        false // No extra calibration screen; unreliable samples remain uncalibrated.
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .denied {
            stop(discard: true, status: .permissionRequired)
        }
    }
}
