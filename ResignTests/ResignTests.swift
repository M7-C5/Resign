//
//  ResignTests.swift
//  ResignTests
//
//  Created by Valentino Manuel Gunawan on 16/10/26.
//

import Testing
import Foundation
import SwiftData
@testable import Resign

@Suite("Resign Domain & SwiftData Unit Tests")
struct ResignTests {

    @Test("Verifies Item model initialization")
    func itemInitialization() {
        let referenceDate = Date(timeIntervalSince1970: 1700000000)
        let item = Item(timestamp: referenceDate)
        #expect(item.timestamp == referenceDate)
    }

    @Test("Verifies Item insertion and retrieval in in-memory ModelContainer")
    @MainActor
    func inMemoryContainerPersistence() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext

        let testDate = Date(timeIntervalSince1970: 1700000000)
        let item = Item(timestamp: testDate)
        context.insert(item)
        try context.save()

        let descriptor = FetchDescriptor<Item>()
        let items = try context.fetch(descriptor)

        #expect(items.count == 1)
        #expect(items.first?.timestamp == testDate)
    }

    @Test("Verifies Item deletion from in-memory ModelContainer")
    @MainActor
    func inMemoryContainerDeletion() throws {
        let container = try ModelContainer.createInMemoryContainer()
        let context = container.mainContext

        let item = Item(timestamp: Date())
        context.insert(item)
        try context.save()

        context.delete(item)
        try context.save()

        let descriptor = FetchDescriptor<Item>()
        let remainingItems = try context.fetch(descriptor)

        #expect(remainingItems.isEmpty)
    }
}
