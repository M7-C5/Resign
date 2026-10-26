//
//  LayoutCardView.swift
//  Resign
//

import SwiftUI

struct LayoutCardView: View {
    
    let layoutName: String
    
    @Binding var isSwiped: Bool
    
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            
            // Layout Card
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray)
                
                Text(layoutName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(16)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        if value.translation.width < -40 {
                            withAnimation(.smooth) {
                                isSwiped = true
                            }
                        } else if value.translation.width > 40 {
                            withAnimation(.smooth) {
                                isSwiped = false
                            }
                        }
                    }
            )
            .onTapGesture {
                if isSwiped {
                    withAnimation(.smooth) {
                        isSwiped = false
                    }
                } else {
                    onTap()
                }
            }
            
            // Edit & Delete Buttons
            if isSwiped {
                HStack(spacing: 12) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.gray, in: Circle())
                    }
                    .accessibilityLabel("Rename layout")
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.red, in: Circle())
                    }
                    .accessibilityLabel("Delete layout")
                }
                .padding(.leading, 12)
                .transition(.opacity)
            }
        }
    }
}

#Preview {
    @Previewable @State var isSwiped = false

    VStack {
        LayoutCardView(
            layoutName: "Bedroom 1",
            isSwiped: $isSwiped,
            onTap: {
                print ("Card tapped")
            },
            onEdit: {
                print("Edit tapped")
            },
            onDelete: {
                print("Delete tapped")
            }
        )

        Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.top, 24)
}
