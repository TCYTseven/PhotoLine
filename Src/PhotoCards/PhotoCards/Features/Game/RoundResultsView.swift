//
//  RoundResultsView.swift
//  PhotoCards
//

import SwiftUI
import Common

struct RoundResultsView: View {
    @EnvironmentObject private var session: GameSessionStore
    let state: GameState

    private var winnerName: String? {
        state.winningSubmission?.username
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                if let round = state.round {
                    Text(round.promptText)
                        .font(Font.poppins(.semiBold, size: 16))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                if let winning = state.winningSubmission {
                    VStack(spacing: 12) {
                        RemoteImage(url: winning.imageUrl)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.white, lineWidth: 4)
                            )
                            .shadow(color: PC.red.opacity(0.5), radius: 20)
                            .padding(.horizontal, 30)

                        HStack(spacing: 8) {
                            Image(systemName: "trophy.fill")
                                .foregroundColor(.yellow)
                            Text("\(winnerName ?? "Someone") wins the round!")
                                .font(Font.poppins(.bold, size: 20))
                                .foregroundColor(.white)
                        }
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
                        Text("No winner this round")
                            .font(Font.poppins(.bold, size: 20))
                            .foregroundColor(.white)
                        Text("Nobody sent a photo in time.")
                            .font(Font.poppins(.regular, size: 14))
                            .foregroundColor(.white.opacity(0.75))
                    }
                    .padding(.vertical, 30)
                }

                if state.submissions.count > 1 {
                    VStack(spacing: 10) {
                        DarkSectionHeader(title: "Everyone's photos")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(state.submissions) { submission in
                                    VStack(spacing: 6) {
                                        PhotoTile(url: submission.thumbnailUrl, selected: submission.isWinner, badge: submission.isWinner ? "Winner" : nil)
                                            .frame(width: 110)
                                        Text(submission.username ?? "?")
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
                                }
                            }
                            .padding(.horizontal, 18)
                        }
                    }
                }

                VStack(spacing: 10) {
                    DarkSectionHeader(title: "Scores")
                        .padding(.horizontal, 18)
                    LeaderboardView(state: state)
                        .padding(.horizontal, 18)
                }

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
    }

    private func nextLabel(_ seconds: Int) -> String {
        let isLast = state.game.currentRound >= state.game.maxRounds
            || (state.leaderboard.first?.score ?? 0) >= state.game.targetScore
        return isLast ? "Final results in \(seconds)s" : "Next round in \(seconds)s"
    }
}
