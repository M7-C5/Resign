//
//  DashboardView.swift
//  Resign
//

import SwiftUI

public struct DashboardView: View {
    
    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.white
                    .ignoresSafeArea()
                
                // Empty State
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 50))
                        .foregroundStyle(.gray)
                    
                    Text("No Layout Yet.")
                        .font(.headline)
                        .foregroundStyle(.black)
                    
                    Text("Create a layout to start planning\nand arranging your room.\nTap the + button to get started.")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                }
                .offset(y: -35)
            }
            .navigationTitle("My Layout")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        Studio3DView()
                    } label: {
                        Image(systemName: "sun.max")
                    }
                    .accessibilityLabel("Lighting Simulation")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                // Later will be navigated to Scan New Room
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(.black)
                .padding(.trailing, 24)
                .padding(.bottom, 24)
            }
        }
    }
}

#Preview {
    DashboardView()
    
}
