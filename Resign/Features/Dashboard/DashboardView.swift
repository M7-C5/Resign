//
//  DashboardView.swift
//  Resign
//
//  Created by Antigravity on 21/10/26.
//

import SwiftUI

public struct DashboardView: View {
    @State private var studioViewModel = Studio3DViewModel()

    public init() {}

    public var body: some View {
        TabView {
            InsightsView(studioViewModel: studioViewModel)
                .tabItem {
                    Label("Diagnostics", systemImage: "sparkles")
                }

            Studio3DView(viewModel: studioViewModel)
                .tabItem {
                    Label("3D Studio", systemImage: "cube.transparent")
                }
        }
    }
}
