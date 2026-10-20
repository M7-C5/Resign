//
//  ResignTests.swift
//  ResignTests
//
//  Created by Valentino Manuel Gunawan on 16/10/26.
//

import Testing
import ModelIO
import Foundation
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
}
