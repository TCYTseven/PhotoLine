//
//  RemoteImage.swift
//  PhotoCards
//
//  Thin wrapper around NukeUI's LazyImage with a consistent placeholder.
//

import SwiftUI
import NukeUI

struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if state.error != nil {
                ZStack {
                    Color.gray.opacity(0.25)
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundColor(.white.opacity(0.6))
                }
            } else {
                ZStack {
                    Color.gray.opacity(0.2)
                    ProgressView()
                        .tint(.white)
                }
            }
        }
    }
}

/// Square photo tile used in the hand and the reveal grids.
struct PhotoTile: View {
    let url: URL
    var selected = false
    var dimmed = false
    var badge: String? = nil
    var cornerRadius: CGFloat = 14

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(RemoteImage(url: url))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(selected ? Color.white : Color.white.opacity(0.15), lineWidth: selected ? 4 : 1)
                )
                .shadow(color: selected ? PC.red.opacity(0.6) : .clear, radius: 10)
                .opacity(dimmed ? 0.45 : 1)
                .scaleEffect(selected ? 1.03 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: selected)

            if let badge {
                Text(badge)
                    .font(Font.poppins(.bold, size: 11))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(PC.red))
                    .padding(6)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
