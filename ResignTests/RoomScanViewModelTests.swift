//
//  RoomScanViewModelTests.swift
//  ResignTests
//

import Testing
import RoomPlan
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

    @Test func instructionTextMappingProvidesActionableGuidance() {
        let viewModel = RoomScanViewModel()

        viewModel.handleInstruction(.lowTexture)
        #expect(viewModel.instructionText?.contains("textured") == true)

        viewModel.handleInstruction(.turnOnLight)
        #expect(viewModel.instructionText?.contains("light") == true)

        viewModel.handleInstruction(.slowDown)
        #expect(viewModel.instructionText?.contains("Slow down") == true)
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
}
