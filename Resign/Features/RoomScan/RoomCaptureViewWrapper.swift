//
//  RoomCaptureViewWrapper.swift
//  Resign
//

import SwiftUI
import RoomPlan

@objc(ResignRoomCaptureCoordinator)
public final class RoomCaptureCoordinator: NSObject, RoomCaptureViewDelegate {
    var isCancelled: Bool = false
    var onComplete: ((CapturedRoom) -> Void)?
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
        if isCancelled {
            return false
        }
        if let error {
            onError?(error)
            return false
        }
        return true
    }

    public func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) {
        guard !isCancelled else { return }
        if let error {
            onError?(error)
        } else {
            onComplete?(processedResult)
        }
    }
}

public struct RoomCaptureViewWrapper: UIViewRepresentable {
    public let captureView: RoomCaptureView
    public let isCancelled: Bool
    public let onComplete: (CapturedRoom) -> Void
    public let onError: (Error) -> Void

    public init(
        captureView: RoomCaptureView,
        isCancelled: Bool = false,
        onComplete: @escaping (CapturedRoom) -> Void,
        onError: @escaping (Error) -> Void = { _ in }
    ) {
        self.captureView = captureView
        self.isCancelled = isCancelled
        self.onComplete = onComplete
        self.onError = onError
    }

    public func makeUIView(context: Context) -> RoomCaptureView {
        captureView.delegate = context.coordinator
        context.coordinator.isCancelled = isCancelled
        context.coordinator.onComplete = onComplete
        context.coordinator.onError = onError
        return captureView
    }

    public func updateUIView(_ uiView: RoomCaptureView, context: Context) {
        context.coordinator.isCancelled = isCancelled
        context.coordinator.onComplete = onComplete
        context.coordinator.onError = onError
    }

    public func makeCoordinator() -> RoomCaptureCoordinator {
        RoomCaptureCoordinator()
    }
}
