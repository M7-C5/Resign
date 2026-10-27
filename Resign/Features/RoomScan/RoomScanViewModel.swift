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
    public func reset() {
        isCancelled = false
        isShowingConfirmationAlert = false
        checkHardware()
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

    #if DEBUG
    @discardableResult
    public func loadMockRoom(modelContext: ModelContext, name: String = "Master Bedroom") -> UUID {
        let room = Room(
            name: name,
            longitude: -122.4194,
            latitude: 37.7749,
            compass: 90.0,
            length: 4.2,
            width: 5.0,
            height: 2.6
        )

        let window = RoomOpening(type: "window", posX: 2.5, posY: 1.45, posZ: 0.0, width: 1.6, height: 1.2)
        let door = RoomOpening(type: "door", posX: -1.5, posY: 1.05, posZ: 2.1, width: 0.9, height: 2.1)
        room.openings.append(window)
        room.openings.append(door)

        let layout = Layout(name: "Original Layout")
        if let bundleURL = Bundle.main.url(forResource: "MockRoom", withExtension: "usdz") {
            layout.usdzURL = bundleURL
        }

        let bed = Furniture(name: "Queen Bed", category: "bed", texture: "oak_fabric", positionX: -1.3, positionY: 0.5, positionZ: -1.0, rotationYaw: 0, length: 2.0, width: 1.6, height: 0.9)
        let desk = Furniture(name: "Work Desk", category: "desk", texture: "walnut", positionX: 2.1, positionY: 0.75, positionZ: -1.2, rotationYaw: .pi / 2, length: 1.4, width: 0.7, height: 0.75)
        let chair = Furniture(name: "Task Chair", category: "chair", texture: "black_mesh", positionX: 1.4, positionY: 0.5, positionZ: -1.2, rotationYaw: -.pi / 2, length: 0.6, width: 0.6, height: 0.9)
        let sofa = Furniture(name: "3-Seater Sofa", category: "sofa", texture: "grey_fabric", positionX: 1.2, positionY: 0.45, positionZ: 1.1, rotationYaw: 0, length: 2.1, width: 0.85, height: 0.8)
        let wardrobe = Furniture(name: "Wardrobe", category: "storage", texture: "white_lacquer", positionX: -2.18, positionY: 1.05, positionZ: 1.2, rotationYaw: 0, length: 1.5, width: 0.6, height: 2.1)
        let tv = Furniture(name: "TV Console", category: "tv", texture: "wood_walnut", positionX: 1.2, positionY: 0.25, positionZ: -1.8, rotationYaw: 0, length: 1.4, width: 0.4, height: 0.5)

        layout.furnitures.append(bed)
        layout.furnitures.append(desk)
        layout.furnitures.append(chair)
        layout.furnitures.append(sofa)
        layout.furnitures.append(wardrobe)
        layout.furnitures.append(tv)

        room.layouts.append(layout)
        modelContext.insert(room)
        try? modelContext.save()

        state = .completed(roomId: room.id)
        return room.id
    }
    #endif

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
