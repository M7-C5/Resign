//
//  RoomCaptureViewWrapper.swift
//  Resign
//

import SwiftUI
import RoomPlan

@objc(ResignRoomCaptureCoordinator)
public final class RoomCaptureCoordinator: NSObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    var onComplete: ((CapturedRoom) -> Void)?
    var onInstruction: ((RoomCaptureSession.Instruction) -> Void)?
    var onError: ((Error) -> Void)?

    public override init() {
        super.init()
    }

    public required init?(coder: NSCoder) {
        super.init()
    }

    public func encode(with coder: NSCoder) {}

    // RoomCaptureViewDelegate
    public func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?) -> Bool {
        return true
    }

    public func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) {
        if let error {
            onError?(error)
        } else {
            onComplete?(processedResult)
        }
    }

    // RoomCaptureSessionDelegate
    public func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {
        onInstruction?(instruction)
    }
}

public struct RoomCaptureViewWrapper: UIViewRepresentable {
    public let captureView: RoomCaptureView
    public let onComplete: (CapturedRoom) -> Void
    public let onInstruction: (RoomCaptureSession.Instruction) -> Void
    public let onError: (Error) -> Void

    public init(
        captureView: RoomCaptureView,
        onComplete: @escaping (CapturedRoom) -> Void,
        onInstruction: @escaping (RoomCaptureSession.Instruction) -> Void = { _ in },
        onError: @escaping (Error) -> Void = { _ in }
    ) {
        self.captureView = captureView
        self.onComplete = onComplete
        self.onInstruction = onInstruction
        self.onError = onError
    }

    public func makeUIView(context: Context) -> RoomCaptureView {
        captureView.delegate = context.coordinator
        captureView.captureSession.delegate = context.coordinator
        context.coordinator.onComplete = onComplete
        context.coordinator.onInstruction = onInstruction
        context.coordinator.onError = onError
        return captureView
    }

    public func updateUIView(_ uiView: RoomCaptureView, context: Context) {}

    public func makeCoordinator() -> RoomCaptureCoordinator {
        RoomCaptureCoordinator()
    }
}
