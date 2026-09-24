//
//  HowToPlayView.swift
//  PhotoCards
//
//  Four-page rules explainer. Shown on first launch and from the "?" button.
//

import SwiftUI
import Common

struct HowToPlayView: View {
    let onDone: () -> Void

    @State private var page = 0

    private struct Page {
        let icon: String
        let title: String
        let body: String
    }

    private let pages: [Page] = [
        Page(icon: "person.3.fill", title: "Get the crew together",
             body: "One player creates a room and shares the six-character code. Everyone else joins on their own phone. You need at least three players."),
        Page(icon: "text.quote", title: "A prompt appears",
             body: "Each round shows a prompt like \"My face when someone says trust me\". In Classic and Rapid Fire, one player is the judge for that round and the judge role rotates. In Vote mode there's no judge: everyone plays."),
        Page(icon: "photo.on.rectangle.angled", title: "Pick your best photo",
             body: "Everyone playing the round gets a hand of random photos from the PhotoCards library. Choose the funniest, weirdest or most fitting one before the timer ends. Don't like your hand? You can swap it for a new one a couple of times per game."),
        Page(icon: "trophy.fill", title: "Judge, laugh, repeat",
             body: "Photos are revealed anonymously. The judge picks a winner, or in Vote mode everyone votes (not for their own photo). The winner gets a point. First to the target score, or the highest score after the last round, wins.")
    ]

    var body: some View {
        ZStack {
            PhotoBackdrop(imageURL: nil)

            VStack(spacing: 0) {
                HStack {
                    Text("How to play")
                        .font(Font.poppins(.bold, size: 22))
                        .foregroundColor(.white)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    RoundIconButton(icon: "xmark", label: "Close") { onDone() }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        // Scrolls when the text doesn't fit (small phones,
                        // large Dynamic Type); centred otherwise.
                        GeometryReader { proxy in
                            ScrollView {
                                VStack(spacing: 22) {
                                    Image(systemName: item.icon)
                                        .font(.system(size: 56, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 130, height: 130)
                                        .background(Circle().fill(PC.red))
                                        .shadow(color: PC.red.opacity(0.5), radius: 24)
                                        .accessibilityHidden(true)
                                    Text(item.title)
                                        .font(Font.poppins(.bold, size: 26))
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                        .accessibilityAddTraits(.isHeader)
                                    Text(item.body)
                                        .font(Font.poppins(.regular, size: 16))
                                        .foregroundColor(.white.opacity(0.85))
                                        .multilineTextAlignment(.center)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.horizontal, 32)
                                .padding(.vertical, 16)
                                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                            }
                            .scrollBounceBehavior(.basedOnSize)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: page)

                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Color.white : Color.white.opacity(0.35))
                            .frame(width: index == page ? 24 : 8, height: 8)
                            .animation(.spring(response: 0.3), value: page)
                    }
                }
                .padding(.bottom, 20)
                .accessibilityHidden(true)

                Button(page == pages.count - 1 ? "Let's play" : "Next") {
                    PC.haptic()
                    if page < pages.count - 1 {
                        page += 1
                    } else {
                        onDone()
                    }
                }
                .buttonStyle(PillButtonStyle())
                .padding(.horizontal, 22)
                .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    HowToPlayView(onDone: {})
}
