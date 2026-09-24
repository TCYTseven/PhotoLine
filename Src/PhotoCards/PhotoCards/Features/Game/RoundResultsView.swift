//
//  RoundResultsView.swift
//  PhotoCards
//

import SwiftUI
import Common

struct RoundResultsView: View {
    @EnvironmentObject private var session: GameSessionStore
    @Environment(\.gameModeration) private var moderation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: GameState

    @State private var selected: SubmissionInfo?

    private func name(for submission: SubmissionInfo) -> String {
        guard let username = submission.username else { return "Someone" }
        return moderation.displayName(username, userId: state.userId(forPlayer: submission.playerId))
    }

    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if let round = state.round {
                        Text(round.promptText)
                            .font(Font.poppins(.semiBold, size: 16))
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 24)
                            .accessibilityLabel("Prompt: \(round.promptText)")
                    }

                    if let winning = state.winningSubmission {
                        VStack(spacing: 12) {
                            Button {
                                selected = winning
                            } label: {
                                Color.clear
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay(RemoteImage(url: winning.imageUrl))
                                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                                            .stroke(Color.white, lineWidth: 4)
                                    )
                                    .shadow(color: PC.red.opacity(0.5), radius: 20)
                                    .frame(maxWidth: 360)
                                    .padding(.horizontal, 30)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Winning photo by \(name(for: winning))")
                            .accessibilityHint("Opens a larger preview")

                            HStack(spacing: 8) {
                                Image(systemName: "trophy.fill")
                                    .foregroundColor(.yellow)
                                    .accessibilityHidden(true)
                                Text(winning.isMine ? "You win the round!" : "\(name(for: winning)) wins the round!")
                                    .font(Font.poppins(.bold, size: 20))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 18)
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isHeader)

                            if state.isVoteMode, let votes = winning.voteCount {
                                Text("\(votes) vote\(votes == 1 ? "" : "s")")
                                    .font(Font.poppins(.regular, size: 13))
                                    .foregroundColor(.white.opacity(0.75))
                            }
                        }
                        .padding(.top, 4)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "zzz")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                                .accessibilityHidden(true)
                            Text("No winner this round")
                                .font(Font.poppins(.bold, size: 20))
                                .foregroundColor(.white)
                                .accessibilityAddTraits(.isHeader)
                            Text(state.submissions.isEmpty ? "Nobody sent a photo in time." : "No photo was picked this round.")
                                .font(Font.poppins(.regular, size: 14))
                                .foregroundColor(.white.opacity(0.75))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 30)
                        .padding(.horizontal, 18)
                    }

                    if state.submissions.count > 1 {
                        VStack(spacing: 10) {
                            DarkSectionHeader(title: "Everyone's photos")
                                .padding(.horizontal, 18)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 10) {
                                    ForEach(state.submissions) { submission in
                                        Button {
                                            PC.haptic()
                                            selected = submission
                                        } label: {
                                            VStack(spacing: 6) {
                                                PhotoTile(url: submission.thumbnailUrl, selected: submission.isWinner, badge: submission.isWinner ? "Winner" : nil)
                                                    .frame(width: 110)
                                                Text(submission.isMine ? "You" : name(for: submission))
                                                    .font(Font.poppins(.medium, size: 12))
                                                    .foregroundColor(.white.opacity(0.85))
                                                    .lineLimit(1)
                                                if state.isVoteMode, let votes = submission.voteCount {
                                                    Text("\(votes) vote\(votes == 1 ? "" : "s")")
                                                        .font(Font.poppins(.regular, size: 11))
                                                        .foregroundColor(.white.opacity(0.6))
                                                }
                                            }
                                            .frame(width: 110)
                                            .padding(.vertical, 6)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityElement(children: .combine)
                                        .accessibilityHint("Opens a larger preview")
                                    }
                                }
                                .padding(.horizontal, 18)
                            }
                        }
                    }

                    VStack(spacing: 10) {
                        DarkSectionHeader(title: "Scores")
                        LeaderboardView(state: state)
                    }
                    .padding(.horizontal, 18)

                    if let seconds = session.secondsRemaining {
                        Text(nextLabel(seconds))
                            .font(Font.poppins(.semiBold, size: 14))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.top, 4)
                    }
                    Color.clear.frame(height: 24)
                }
                .padding(.top, 6)
            }

            if let submission = selected {
                PhotoDetailOverlay(
                    imageURL: submission.imageUrl,
                    prompt: state.round?.promptText,
                    primaryTitle: nil,
                    primaryIcon: "photo",
                    isBusy: false,
                    onPrimary: nil,
                    onClose: { selected = nil },
                    reportPhotoId: submission.photoId
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selected?.id)
    }

    private func nextLabel(_ seconds: Int) -> String {
        let isLast = state.game.currentRound >= state.game.maxRounds
            || (state.leaderboard.first?.score ?? 0) >= state.game.targetScore
        if seconds == 0 {
            return isLast ? "Loading final results…" : "Starting next round…"
        }
        return isLast ? "Final results in \(seconds)s" : "Next round in \(seconds)s"
    }
}
