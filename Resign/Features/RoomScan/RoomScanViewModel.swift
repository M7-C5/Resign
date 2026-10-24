//
//  RoomScanViewModel.swift
//  Resign
//

import Foundation
import CoreGraphics
import Observation
import RoomPlan
import SwiftData
import simd

@Observable
public final class RoomScanViewModel {

    public enum ScanState: Equatable {
        case checkingHardware
        case unsupported
        case ready
        case scanning
        case processing
        case cancelled
        case completed(roomId: UUID)
        case error(String)
    }

    public var state: ScanState = .checkingHardware
    public var isShowingConfirmationAlert: Bool = false
    public var isCancelled: Bool = false

    public var isSupported: Bool {
        RoomCaptureSession.isSupported
    }

    @ObservationIgnored private var _captureView: RoomCaptureView?

    @MainActor
    public var captureView: RoomCaptureView {
        if let existing = _captureView {
            return existing
        }
        let view = RoomCaptureView(frame: .zero)
        _captureView = view
        return view
    }

    private let mapper: RoomCaptureMapper
    private let exportRoom: @Sendable (CapturedRoom, URL) throws -> Void

    public init(
        mapper: RoomCaptureMapper = RoomCaptureMapper(),
        exportRoom: @escaping @Sendable (CapturedRoom, URL) throws -> Void = { room, url in
            try room.export(to: url, exportOptions: .parametric)
        }
    ) {
        self.mapper = mapper
        self.exportRoom = exportRoom
        checkHardware()
    }

    public func checkHardware() {
        if isSupported {
            state = .ready
        } else {
            state = .unsupported
        }
    }

    @MainActor
    public func startScanning() {
        guard isSupported else {
            state = .unsupported
            return
        }

        isCancelled = false
        isShowingConfirmationAlert = false
        let configuration = RoomCaptureSession.Configuration()
        captureView.captureSession.run(configuration: configuration)
        state = .scanning
    }

    @MainActor
    public func requestFinishScanning() {
        guard state == .scanning else { return }
        isShowingConfirmationAlert = true
    }

    @MainActor
    public func dismissConfirmationAlert() {
        isShowingConfirmationAlert = false
    }

    @MainActor
    public func confirmFinishScanning() {
        isShowingConfirmationAlert = false
        stopScanning()
    }

    @MainActor
    public func stopScanning() {
        isCancelled = false
        _captureView?.captureSession.stop()
        state = .processing
    }

    @MainActor
    public func cancelScanning() {
        isCancelled = true
        isShowingConfirmationAlert = false
        _captureView?.captureSession.stop(pauseARSession: true)
        state = .cancelled
    }

    public func isValidScan(payload: CapturedRoomPayload) -> Bool {
        !payload.walls.isEmpty && payload.roomWidth >= 0.5 && payload.roomLength >= 0.5
    }

    public func process(
        capturedRoom: CapturedRoom,
        modelContext: ModelContext,
        roomName: String = "Scanned Room"
    ) {
        guard !isCancelled else { return }
        state = .processing

        let payload = makePayload(from: capturedRoom)
        processPayload(payload, modelContext: modelContext, roomName: roomName) { fileURL in
            try self.exportRoom(capturedRoom, fileURL)
        }
    }

    public func processPayload(
        _ payload: CapturedRoomPayload,
        modelContext: ModelContext,
        roomName: String = "Scanned Room",
        exportAction: ((URL) throws -> Void)? = nil
    ) {
        guard !isCancelled else { return }
        state = .processing

        guard isValidScan(payload: payload) else {
            state = .error("Invalid scan: Not enough room geometry was captured. Please scan the room walls and floor before finishing.")
            return
        }

        let room = mapper.mapToRoom(payload: payload, roomName: roomName)

        if let exportAction {
            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let roomDir = docsDir.appendingPathComponent("Rooms/\(room.id)", isDirectory: true)

            try? FileManager.default.createDirectory(at: roomDir, withIntermediateDirectories: true)
            let fileURL = roomDir.appendingPathComponent("Room.usdz")

            do {
                try exportAction(fileURL)
                if let firstLayout = room.layouts.first {
                    firstLayout.usdzURL = fileURL
                }
            } catch {
                print("[RoomScanViewModel] Failed to export parametric USDZ: \(error)")
            }
        }

        modelContext.insert(room)
        do {
            try modelContext.save()
            state = .completed(roomId: room.id)
        } catch {
            state = .error("Failed to save scanned room: \(error.localizedDescription)")
        }
    }

    private func makePayload(from room: CapturedRoom) -> CapturedRoomPayload {
        var walls: [ScannedWallPayload] = []
        var wallHeights: [Float] = []
        var wallLengths: [Float] = []

        for wall in room.walls {
            let pos = SIMD3<Float>(wall.transform.columns.3.x, wall.transform.columns.3.y, wall.transform.columns.3.z)
            let yaw = atan2(-wall.transform.columns.0.z, wall.transform.columns.0.x)
            walls.append(ScannedWallPayload(
                id: wall.identifier,
                position: pos,
                dimensions: wall.dimensions,
                rotationYaw: yaw,
                transform: wall.transform
            ))
            wallHeights.append(wall.dimensions.y)
            wallLengths.append(wall.dimensions.x)
        }

        let floorCorners = room.floors.first?.polygonCorners ?? []
        let dims = RoomDimensionExtractor.extractDimensions(
            polygonCorners: floorCorners,
            walls: walls,
            wallHeights: wallHeights,
            wallLengths: wallLengths
        )
        let floorLevel = room.floors.first?.transform.columns.3.y ?? (walls.map { $0.position.y - $0.dimensions.y / 2.0 }.min() ?? 0.0)

        var openings: [ScannedOpeningPayload] = []
        for window in room.windows {
            let pos = SIMD3<Float>(window.transform.columns.3.x, window.transform.columns.3.y, window.transform.columns.3.z)
            openings.append(ScannedOpeningPayload(type: "window", position: pos, dimensions: window.dimensions))
        }
        for door in room.doors {
            let pos = SIMD3<Float>(door.transform.columns.3.x, door.transform.columns.3.y, door.transform.columns.3.z)
            openings.append(ScannedOpeningPayload(type: "door", position: pos, dimensions: door.dimensions))
        }
        for opening in room.openings {
            let pos = SIMD3<Float>(opening.transform.columns.3.x, opening.transform.columns.3.y, opening.transform.columns.3.z)
            openings.append(ScannedOpeningPayload(type: "opening", position: pos, dimensions: opening.dimensions))
        }

        var objects: [ScannedObjectPayload] = []
        for object in room.objects {
            let pos = SIMD3<Float>(object.transform.columns.3.x, object.transform.columns.3.y, object.transform.columns.3.z)
            let yaw = atan2(-object.transform.columns.0.z, object.transform.columns.0.x)
            let cat = stringCategory(for: object.category)
            objects.append(ScannedObjectPayload(rawCategory: cat, position: pos, dimensions: object.dimensions, rotationYaw: yaw))
        }

        return CapturedRoomPayload(
            roomLength: dims.length,
            roomWidth: dims.width,
            roomHeight: dims.height,
            floorLevel: floorLevel,
            walls: walls,
            openings: openings,
            objects: objects
        )
    }

    private func stringCategory(for category: CapturedRoom.Object.Category) -> String {
        switch category {
        case .storage: return "storage"
        case .refrigerator: return "refrigerator"
        case .stove: return "stove"
        case .bed: return "bed"
        case .sink: return "sink"
        case .washerDryer: return "washerdryer"
        case .toilet: return "toilet"
        case .bathtub: return "bathtub"
        case .oven: return "oven"
        case .dishwasher: return "dishwasher"
        case .table: return "table"
        case .sofa: return "sofa"
        case .chair: return "chair"
        case .fireplace: return "fireplace"
        case .television: return "television"
        case .stairs: return "stairs"
        @unknown default: return "unknown"
        }
    }
}
