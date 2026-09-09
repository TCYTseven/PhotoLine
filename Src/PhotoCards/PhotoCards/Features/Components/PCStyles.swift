//
//  PCStyles.swift
//  PhotoCards
//
//  Shared look & feel: pill buttons, glass tiles, cards, timer pill.
//

import SwiftUI
import Common

// MARK: - Palette helpers

enum PC {
    static let red = Theme.Colors.primary
    static let darkRed = Theme.Colors.secondary
    static let cornerLarge: CGFloat = 22
    static let cornerMedium: CGFloat = 16
    static let cornerSmall: CGFloat = 12

    static func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

// MARK: - Pill button (the big red buttons on the home screen)

struct PillButtonStyle: ButtonStyle {
    var fill: Color = PC.red
    var foreground: Color = .white
    var height: CGFloat = 58

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.poppins(.bold, size: 19))
            .foregroundColor(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: height / 2.6, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: height / 2.6, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SecondaryPillButtonStyle: ButtonStyle {
    var height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.poppins(.semiBold, size: 17))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: height / 2.6, style: .continuous)
                    .fill(Color.white.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: height / 2.6, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Glass square tile (bottom row on home)

struct GlassTile: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            PC.haptic()
            action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 64, height: 64)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.2))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    )
                Text(title)
                    .font(Font.poppins(.semiBold, size: 13))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - Round icon button ("?" on home, close buttons)

struct RoundIconButton: View {
    let icon: String
    var label: String
    let action: () -> Void

    var body: some View {
        Button {
            PC.haptic()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.black.opacity(0.35)))
                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Backdrop (blurred photo + dark gradient)

struct PhotoBackdrop: View {
    var imageURL: URL? = URL(string: "https://picsum.photos/id/29/900/1600")

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.14, blue: 0.24), Color(red: 0.45, green: 0.15, blue: 0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
            if let imageURL {
                RemoteImage(url: imageURL, contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .blur(radius: 18)
                    .scaleEffect(1.15)
                    .opacity(0.85)
            }
            LinearGradient(
                colors: [Color.black.opacity(0.15), Color.black.opacity(0.25), Color.black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Card container (light surface on dark backdrop)

struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: PC.cornerLarge, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PC.cornerLarge, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
    }
}

// MARK: - Prompt card (looks like a physical game card)

struct PromptCard: View {
    let text: String
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text)
                .font(Font.poppins(.bold, size: 22))
                .foregroundColor(.black)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(caption ?? "PhotoCards")
                    .font(Font.poppins(.semiBold, size: 12))
                Spacer()
            }
            .foregroundColor(.black.opacity(0.45))
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
        )
        .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Prompt: \(text)")
    }
}

// MARK: - Timer pill

struct TimerPill: View {
    let seconds: Int
    var progress: Double = 1

    private var urgent: Bool { seconds <= 10 }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.25), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(urgent ? Color.yellow : Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
            }
            .frame(width: 20, height: 20)
            Text("\(seconds)s")
                .font(Font.poppins(.bold, size: 16))
                .monospacedDigit()
                .foregroundColor(urgent ? .yellow : .white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.4)))
        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
        .accessibilityLabel("\(seconds) seconds left")
    }
}

// MARK: - Room code chip

struct RoomCodeChip: View {
    let code: String
    var large = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "number")
                .font(.system(size: large ? 16 : 12, weight: .bold))
            Text(code)
                .font(Font.poppins(.bold, size: large ? 30 : 15))
                .tracking(large ? 6 : 2)
        }
        .foregroundColor(.white)
        .padding(.horizontal, large ? 20 : 12)
        .padding(.vertical, large ? 10 : 6)
        .background(Capsule().fill(Color.white.opacity(0.18)))
        .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
        .accessibilityLabel("Room code \(code.map { String($0) }.joined(separator: " "))")
    }
}

// MARK: - Score badge

struct ScoreBadge: View {
    let score: Int

    var body: some View {
        Text("\(score)")
            .font(Font.poppins(.bold, size: 15))
            .monospacedDigit()
            .foregroundColor(.white)
            .frame(minWidth: 34)
            .padding(.vertical, 6)
            .background(Capsule().fill(PC.red))
    }
}

// MARK: - Section header on dark backgrounds

struct DarkSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(Font.poppins(.semiBold, size: 12))
            .tracking(1.2)
            .foregroundColor(.white.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Shared styling for utility screens, including their nested lists.
struct GameListStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
            .background { PhotoBackdrop(imageURL: nil) }
            .font(Font.poppins(.regular, size: 14))
            .foregroundStyle(.white)
            .tint(.white)
            .preferredColorScheme(.dark)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}
