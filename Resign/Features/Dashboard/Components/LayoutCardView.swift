//
//  LayoutCardView.swift
//  Resign
//

import SwiftUI

public struct LayoutCardView: View {
    public let layoutName: String
    public var layoutCount: Int? = nil

    @Binding public var isSwiped: Bool

    public let onTap: () -> Void
    public let onEdit: () -> Void
    public let onDelete: () -> Void

    public init(
        layoutName: String,
        layoutCount: Int? = nil,
        isSwiped: Binding<Bool>,
        onTap: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.layoutName = layoutName
        self.layoutCount = layoutCount
        self._isSwiped = isSwiped
        self.onTap = onTap
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Layout Card
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .secondarySystemFill))

                LinearGradient(
                    colors: [Color.black.opacity(0.0), Color.black.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 4) {
                    Text(layoutName)
                        .font(.headline)
                        .foregroundStyle(.white)

                    if let count = layoutCount {
                        Text("\(count) \(count == 1 ? "layout" : "layouts")")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
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
                            .background(Color.secondary, in: Circle())
                    }
                    .accessibilityLabel("Rename room")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.red, in: Circle())
                    }
                    .accessibilityLabel("Delete room")
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
            layoutCount: 3,
            isSwiped: $isSwiped,
            onTap: {
                print("Card tapped")
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
