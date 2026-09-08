//
//  LogoFanView.swift
//  PhotoCards
//
//  The home screen wordmark: a fan of red cards behind a chunky title.
//

import SwiftUI
import Common

struct LogoFanView: View {
    var scale: CGFloat = 1

    var body: some View {
        ZStack {
            // Fanned cards
            ForEach(Array([-52.0, -34.0, -17.0, 0.0, 17.0, 34.0, 52.0].enumerated()), id: \.offset) { index, angle in
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(index % 2 == 0 ? PC.red : PC.darkRed)
                    .frame(width: 56 * scale, height: 118 * scale)
                    .overlay(alignment: .top) {
                        Circle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 10 * scale, height: 10 * scale)
                            .padding(.top, 10 * scale)
                    }
                    .offset(y: -60 * scale)
                    .rotationEffect(.degrees(angle))
            }
            .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 4)

            VStack(spacing: -12 * scale) {
                Text("Photo")
                Text("Cards")
            }
            .font(Font.poppins(.black, size: 64 * scale))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 5)
            .offset(y: 22 * scale)
        }
        .frame(height: 250 * scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PhotoCards")
    }
}

#Preview {
    ZStack {
        PhotoBackdrop()
        LogoFanView()
    }
}
