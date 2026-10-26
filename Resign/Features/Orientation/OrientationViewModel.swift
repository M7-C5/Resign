//
//  OrientationViewModel.swift
//  Resign
//

import Foundation
import Observation
import CoreLocation

@MainActor
@Observable
public final class OrientationViewModel: NSObject, CLLocationManagerDelegate {
    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private var calibration = NorthAlignmentCalibration()
    @ObservationIgnored private var isActive = false

    private(set) var headingDegrees: Double?
    private(set) var headingReference = ""
    private(set) var headingAccuracy: Double?
    private(set) var usesManualHeading = false
    private(set) var now = Date()

    var isHeadingLocked: Bool { calibration.isLocked }
    var isHoldingNorth: Bool { calibration.alignedSince != nil && !calibration.isLocked }
    var needsCompassCalibration: Bool {
        !usesManualHeading && (headingAccuracy ?? 0) > NorthAlignmentCalibration.northToleranceDegrees
    }
    var lockProgress: Double { calibration.progress(at: now) }

    public override init() {
        super.init()
        locationManager.delegate = self
        locationManager.headingFilter = 1
        locationManager.headingOrientation = .portrait
    }

    func start() {
        guard !calibration.isLocked else { return }
        isActive = true
        #if targetEnvironment(simulator)
        usesManualHeading = true
        headingReference = "Preview compass"
        setManualHeading(180)
        return
        #else
        guard CLLocationManager.headingAvailable() else {
            usesManualHeading = true
            headingReference = "Manual compass"
            setManualHeading(180)
            return
        }

        usesManualHeading = false
        locationManager.startUpdatingHeading()
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            startLocationReference()
        case .denied, .restricted:
            headingReference = "Magnetic North"
        @unknown default:
            headingReference = "Magnetic North"
        }
        #endif
    }

    func stop() {
        isActive = false
        locationManager.stopUpdatingHeading()
        locationManager.stopUpdatingLocation()
    }

    func tick(at date: Date = Date()) {
        now = date
        if usesManualHeading, let headingDegrees, !calibration.isLocked,
           calibration.update(headingDegrees: headingDegrees, at: date) {
            stop()
        }
    }

    func setManualHeading(_ degrees: Double, at date: Date = Date()) {
        guard usesManualHeading, !calibration.isLocked else { return }
        receiveHeading(degrees, reference: "Manual compass", accuracy: nil, at: date)
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isActive else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            startLocationReference()
        case .denied, .restricted:
            headingReference = "Magnetic North"
            manager.stopUpdatingLocation()
        case .notDetermined:
            break
        @unknown default:
            headingReference = "Magnetic North"
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard isActive else { return }
        guard newHeading.headingAccuracy >= 0 else { return }
        let hasTrueHeading = newHeading.trueHeading >= 0
        receiveHeading(
            hasTrueHeading ? newHeading.trueHeading : newHeading.magneticHeading,
            reference: hasTrueHeading ? "True North" : "Magnetic North",
            accuracy: newHeading.headingAccuracy,
            at: Date()
        )
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        headingReference = "Magnetic North"
        manager.stopUpdatingLocation()
    }

    public func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }

    private func startLocationReference() {
        guard isActive, !calibration.isLocked else { return }
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.startUpdatingLocation()
    }

    private func receiveHeading(_ degrees: Double, reference: String, accuracy: Double?, at date: Date) {
        guard !calibration.isLocked else { return }
        let normalized = NorthAlignmentCalibration.normalized(degrees)
        headingDegrees = normalized
        headingReference = reference
        headingAccuracy = accuracy
        let didLock = calibration.update(headingDegrees: normalized, accuracyDegrees: accuracy, at: date)
        now = date
        if didLock {
            stop()
        }
    }
}
