//
//  ResignTests.swift
//  ResignTests
//
//  Created by Valentino Manuel Gunawan on 16/10/26.
//

import Testing
import ModelIO
import Foundation
import SwiftData
@testable import Resign

@Suite("Resign Architecture Smoke Tests")
struct ResignTests {

    @Test func placeholder() {
        #expect(true)
    }

    @Test func mockRoomUSDZContainsAllRequiredElements() {
        guard let url = Bundle.main.url(forResource: "MockRoom", withExtension: "usdz") else {
            #expect(Bool(false), "MockRoom.usdz not found in Bundle.main")
            return
        }
        let asset = MDLAsset(url: url)
        #expect(asset.count > 0, "MDLAsset should load objects from MockRoom.usdz")
        
        let requiredNames = ["Window", "Door", "Bed", "Desk", "Chair", "Sofa", "Closet", "TV"]
        var foundNames: [String] = []
        
        func inspect(object: MDLObject) {
            if requiredNames.contains(object.name) {
                foundNames.append(object.name)
            }
            for i in 0..<object.children.count {
                inspect(object: object.children[i])
            }
        }
        
        for i in 0..<asset.count {
            inspect(object: asset.object(at: i))
        }
        
        for target in requiredNames {
            #expect(foundNames.contains(target), "Expected '\(target)' in MockRoom.usdz")
        }
    }

    @Test @MainActor func roomHierarchyPersistence() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext

        let room = Room(
            name: "Master Bedroom",
            longitude: -122.4194,
            latitude: 37.7749,
            compass: 85.0,
            length: 4.2,
            width: 5.0,
            height: 2.6
        )

        let window = RoomOpening(type: "window", posX: 2.5, posY: 1.45, posZ: 0.0, width: 1.6, height: 1.2)
        room.openings.append(window)

        let layout = Layout(name: "Circadian Optimal")
        
        let bed = Furniture(name: "Queen Bed", category: "bed", texture: "oak_fabric", positionX: -1.3, positionY: 0.5, positionZ: -1.0, rotationYaw: 0, length: 2.0, width: 1.6, height: 1.0)
        let desk = Furniture(name: "Work Desk", category: "desk", texture: "metal_wood", positionX: 2.1, positionY: 0.75, positionZ: -1.2, rotationYaw: .pi / 2, length: 1.2, width: 0.65, height: 0.75)
        layout.furnitures.append(bed)
        layout.furnitures.append(desk)

        let light = Light(name: "Center Fixture", coordinateX: 2.0, coordinateY: 2.0, elevationZ: 2.6, brightness: 1200, colorTemp: 4000, isOn: true)
        layout.lights.append(light)

        let insight = Insight(title: "Great Morning Light", type: "+", detail: "Desk receives natural illumination.")
        layout.insights.append(insight)

        room.layouts.append(layout)
        context.insert(room)
        try context.save()

        let descriptor = FetchDescriptor<Room>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        
        let savedRoom = fetched[0]
        #expect(savedRoom.name == "Master Bedroom")
        #expect(savedRoom.openings.count == 1)
        #expect(savedRoom.openings[0].type == "window")
        #expect(savedRoom.layouts.count == 1)
        
        let savedLayout = savedRoom.layouts[0]
        #expect(savedLayout.furnitures.count == 2)
        #expect(savedLayout.lights.count == 1)
        #expect(savedLayout.insights.count == 1)
        let furnitureCategories = Set(savedLayout.furnitures.map(\.category))
        #expect(furnitureCategories.contains("bed"))
        #expect(furnitureCategories.contains("desk"))
        #expect(savedRoom.createdAt <= Date())
        #expect(savedLayout.createdAt <= Date())
    }

    @Test @MainActor func modelDefaultInitializers() {
        let room = Room()
        #expect(room.name == "Room")
        #expect(room.length == 4.2)
        #expect(room.width == 5.0)

        let opening = RoomOpening()
        #expect(opening.type == "window")

        let layout = Layout()
        #expect(layout.name == "Layout")

        let furniture = Furniture()
        #expect(furniture.name == "Furniture")
        #expect(furniture.isArchived == false)

        let light = Light()
        #expect(light.isOn == true)
        #expect(light.brightness == 800.0)

        let insight = Insight()
        #expect(insight.type == "+")
    }

    @Test @MainActor func furnitureArchivedAndRotationProperties() {
        let chair = Furniture(
            name: "Office Chair",
            category: "chair",
            texture: "charcoal_mesh",
            positionX: 1.4,
            positionY: 0.45,
            positionZ: -1.2,
            rotationYaw: .pi / 4,
            isArchived: true
        )
        #expect(chair.isArchived == true)
        #expect(chair.category == "chair")
        #expect(chair.texture == "charcoal_mesh")
        #expect(chair.rotationYaw == .pi / 4)
    }
}
