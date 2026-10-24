//
//  RoomScanViewModelTests.swift
//  ResignTests
//

import Testing
import RoomPlan
import SwiftData
import simd
@testable import Resign

@Suite("RoomScan ViewModel Tests")
struct RoomScanViewModelTests {

    @Test func initialStateReflectsHardwareSupport() {
        let viewModel = RoomScanViewModel()

        if RoomCaptureSession.isSupported {
            #expect(viewModel.state == .ready)
        } else {
            #expect(viewModel.state == .unsupported)
        }
    }

    @Test func viewModelAcceptsCustomExportClosure() {
        var exportInvoked = false
        _ = RoomScanViewModel(
            exportRoom: { _, _ in
                exportInvoked = true
            }
        )
        #expect(!exportInvoked)
    }

    @Test @MainActor func finishConfirmationAlertFlowTransitionsToProcessingOnlyWhenConfirmed() {
        let viewModel = RoomScanViewModel()
        viewModel.state = .scanning

        // Pressing Done triggers the confirmation alert without stopping the scan yet
        viewModel.requestFinishScanning()
        #expect(viewModel.isShowingConfirmationAlert == true)
        #expect(viewModel.state == .scanning)

        // Pressing "No" dismisses the alert and keeps scanning
        viewModel.dismissConfirmationAlert()
        #expect(viewModel.isShowingConfirmationAlert == false)
        #expect(viewModel.state == .scanning)

        // Pressing Done -> "Yes" dismisses the alert and enters .processing
        viewModel.requestFinishScanning()
        #expect(viewModel.isShowingConfirmationAlert == true)
        viewModel.confirmFinishScanning()
        #expect(viewModel.isShowingConfirmationAlert == false)
        #expect(viewModel.state == .processing)
    }

    @Test @MainActor func cancelScanningMarksSessionCancelledAndTransitionsState() {
        let viewModel = RoomScanViewModel()
        viewModel.state = .scanning

        viewModel.cancelScanning()
        #expect(viewModel.isCancelled == true)
        #expect(viewModel.isShowingConfirmationAlert == false)
        #expect(viewModel.state == .cancelled)
    }

    @Test @MainActor func invalidScanWithNoWallsFailsValidationAndDoesNotPersistRoom() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext
        let viewModel = RoomScanViewModel()

        let emptyPayload = CapturedRoomPayload(
            roomLength: 0.0,
            roomWidth: 0.0,
            roomHeight: 0.0,
            floorLevel: 0.0,
            walls: [],
            openings: [],
            objects: []
        )

        #expect(viewModel.isValidScan(payload: emptyPayload) == false)
        viewModel.processPayload(emptyPayload, modelContext: context)

        if case .error(let message) = viewModel.state {
            #expect(!message.isEmpty)
        } else {
            Issue.record("Expected .error state for invalid empty scan, got \(viewModel.state)")
        }

        let savedRooms = try context.fetch(FetchDescriptor<Room>())
        #expect(savedRooms.isEmpty)
    }

    @Test @MainActor func validScanPersistsToSwiftDataAndTransitionsToCompleted() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext
        let viewModel = RoomScanViewModel()

        let walls = [
            ScannedWallPayload(
                position: SIMD3<Float>(0, 1.3, -2.0),
                dimensions: SIMD3<Float>(4.0, 2.6, 0.1),
                rotationYaw: 0
            ),
            ScannedWallPayload(
                position: SIMD3<Float>(0, 1.3, 2.0),
                dimensions: SIMD3<Float>(4.0, 2.6, 0.1),
                rotationYaw: .pi
            )
        ]
        let validPayload = CapturedRoomPayload(
            roomLength: 4.0,
            roomWidth: 4.0,
            roomHeight: 2.6,
            floorLevel: -1.3,
            walls: walls,
            openings: [],
            objects: [
                ScannedObjectPayload(
                    rawCategory: "bed",
                    position: SIMD3<Float>(0, -1.0, -1.0),
                    dimensions: SIMD3<Float>(1.6, 0.6, 2.0),
                    rotationYaw: 0
                )
            ]
        )

        #expect(viewModel.isValidScan(payload: validPayload) == true)
        viewModel.processPayload(validPayload, modelContext: context, roomName: "Master Bedroom")

        guard case .completed(let roomId) = viewModel.state else {
            Issue.record("Expected .completed state, got \(viewModel.state)")
            return
        }

        let savedRooms = try context.fetch(FetchDescriptor<Room>())
        #expect(savedRooms.count == 1)
        #expect(savedRooms.first?.id == roomId)
        #expect(savedRooms.first?.name == "Master Bedroom")
        #expect(savedRooms.first?.layouts.first?.furnitures.count == 1)
    }
}
