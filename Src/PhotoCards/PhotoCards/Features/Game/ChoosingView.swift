//
//  ChoosingView.swift
//  PhotoCards
//
//  The "pick a photo from your hand" phase. Judges and players who already
//  submitted see a waiting screen instead.
//

import SwiftUI
import Common

struct ChoosingView: View {
    @EnvironmentObject private var session: GameSessionStore
    let state: GameState

    @State private var selected: HandCard?
    @State private var showRefreshConfirm = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        ZStack {
            if state.me.isJudge {
                WaitingView(
                    state: state,
                    icon: "hand.thumbsup.fill",
                    title: "You're the judge",
                    subtitle: "Sit back. You'll pick the winner once everyone has sent a photo."
                )
            } else if state.me.hasSubmitted {
                WaitingView(
                    state: state,
                    icon: "paperplane.fill",
                    title: "Photo sent!",
                    subtitle: "Waiting for the others to choose."
                )
            } else {
                handScreen
            }

            if let card = selected {
                PhotoDetailOverlay(
                    imageURL: card.imageUrl,
                    prompt: state.round?.promptText,
                    primaryTitle: "Submit this photo",
                    primaryIcon: "paperplane.fill",
                    isBusy: session.isBusy,
                    onPrimary: {
                        Task {
                            if await session.submitPhoto(photoId: card.photoId) {
                                PC.notify(.success)
                            }
                            selected = nil
                        }
                    },
                    onClose: { selected = nil },
                    reportUserId: nil,
                    reportPhotoId: card.photoId
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selected?.id)
        .confirmationDialog("Swap your whole hand for 16 new photos?", isPresented: $showRefreshConfirm, titleVisibility: .visible) {
            Button("Refresh hand") {
                Task {
                    if await session.refreshHand() { PC.haptic(.medium) }
                }
            }
            Button("Keep my hand", role: .cancel) {}
        } message: {
            Text("\(state.refreshesLeft) refresh\(state.refreshesLeft == 1 ? "" : "es") left this game.")
        }
    }

    private var handScreen: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    if let round = state.round {
                        PromptCard(text: round.promptText, caption: judgeCaption(round))
                            .padding(.horizontal, 18)
                            .padding(.top, 4)
                    }

                    HStack {
                        Text("Pick the photo that fits best")
                            .font(Font.poppins(.semiBold, size: 14))
                            .foregroundColor(.white.opacity(0.85))
                        Spacer()
                        Button {
                            showRefreshConfirm = true
                        } label: {
                            Label("Refresh (\(state.refreshesLeft))", systemImage: "arrow.triangle.2.circlepath")
                                .font(Font.poppins(.semiBold, size: 13))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.white.opacity(0.18)))
                        }
                        .disabled(state.refreshesLeft == 0 || session.isBusy)
                        .opacity(state.refreshesLeft == 0 ? 0.5 : 1)
                    }
                    .padding(.horizontal, 18)

                    if state.hand.isEmpty {
                        VStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("Dealing your photos…")
                                .font(Font.poppins(.regular, size: 14))
                                .foregroundColor(.white.opacity(0.75))
                        }
                        .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(state.hand) { card in
                                Button {
                                    PC.haptic()
                                    selected = card
                                } label: {
                                    PhotoTile(url: card.thumbnailUrl, selected: selected?.id == card.id)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Photo \(card.position)")
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    Color.clear.frame(height: 24)
                }
            }
        }
    }

    private func judgeCaption(_ round: RoundInfo) -> String {
        if state.isVoteMode { return "Everyone votes this round" }
        if let judge = round.judgeUsername { return "\(judge) is judging" }
        return "PhotoCards"
    }
}

// MARK: - Waiting screen (judge waiting / already submitted)

struct WaitingView: View {
    let state: GameState
    let icon: String
    let title: String
    let subtitle: String

    private var submitted: Int { state.round?.submissionCount ?? 0 }
    private var expected: Int { state.submitters.count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                if let round = state.round {
                    PromptCard(text: round.promptText, caption: state.isVoteMode ? "Everyone votes this round" : (round.judgeUsername.map { "\($0) is judging" } ?? "PhotoCards"))
                        .padding(.horizontal, 18)
                        .padding(.top, 4)
                }

                VStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 84, height: 84)
                        .background(Circle().fill(PC.red))
                        .shadow(color: PC.red.opacity(0.5), radius: 14)
                    Text(title)
                        .font(Font.poppins(.bold, size: 24))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(Font.poppins(.regular, size: 14))
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    Text("\(submitted) of \(expected) photos in")
                        .font(Font.poppins(.semiBold, size: 14))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                }
                .padding(.top, 10)

                VStack(spacing: 10) {
                    DarkSectionHeader(title: "Players")
                    SurfaceCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(state.players) { player in
                                PlayerRow(player: player, isMe: player.id == state.me.playerId, trailing: .submitted)
                                if player.id != state.players.last?.id {
                                    Divider().background(Color.white.opacity(0.15)).padding(.leading, 60)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                Color.clear.frame(height: 24)
            }
        }
    }
}
