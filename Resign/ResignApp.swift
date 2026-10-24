//
//  ResignApp.swift
//  Resign
//

import SwiftUI
import SwiftData

@main
struct ResignApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Room.self,
            RoomOpening.self,
            Layout.self,
            Furniture.self,
            Light.self,
            Insight.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    private enum RootScreen: Equatable {
        case home
        case scanning
        case result(UUID)
    }

    @State private var currentScreen: RootScreen = .home

    var body: some Scene {
        WindowGroup {
            Group {
                switch currentScreen {
                case .home:
                    mockHomeView
                case .scanning:
                    RoomScanView(
                        onScanComplete: { savedRoomId in
                            currentScreen = .result(savedRoomId)
                        },
                        onCancel: {
                            currentScreen = .home
                        }
                    )
                case .result(let roomId):
                    RoomScanResultView(roomId: roomId) {
                        currentScreen = .scanning
                    }
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }

    private var mockHomeView: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                Text("Home")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Button {
                    currentScreen = .scanning
                } label: {
                    Label("Scan Room", systemImage: "camera.viewfinder")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .frame(height: 50)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                }

                Spacer()
            }
            .navigationTitle("Resign")
        }
    }
}
