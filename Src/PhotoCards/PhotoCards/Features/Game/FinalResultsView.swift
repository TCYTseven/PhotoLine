//
//  FinalResultsView.swift
//  PhotoCards
//

import SwiftUI
import Common

struct FinalResultsView: View {
    @EnvironmentObject private var session: GameSessionStore
    let state: GameState

    private var winner: PlayerInfo? { state.winner }
    private var iWon: Bool { winner?.id == state.me.playerId }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 54, weight: .bold))
                        .foregroundColor(.yellow)
                        .shadow(color: .yellow.opacity(0.5), radius: 16)
                    Text(iWon ? "You win!" : "\(winner?.username ?? "Nobody") wins!")
                        .font(Font.poppins(.black, size: 32))
                        .foregroundColor(.white)
                    if let winner {
                        Text("\(winner.score) point\(winner.score == 1 ? "" : "s") after \(state.game.currentRound) round\(state.game.currentRound == 1 ? "" : "s")")
                            .font(Font.poppins(.regular, size: 14))
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
                .padding(.top, 12)

                VStack(spacing: 10) {
                    DarkSectionHeader(title: "Final scores")
                    LeaderboardView(state: state)
                }
                .padding(.horizontal, 18)

                if !state.highlights.isEmpty {
                    VStack(spacing: 10) {
                        DarkSectionHeader(title: "Winning photos")
                            .padding(.horizontal, 18)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(state.highlights) { highlight in
                                    VStack(alignment: .leading, spacing: 6) {
                                        PhotoTile(url: highlight.thumbnailUrl, badge: "R\(highlight.roundNumber)")
                                            .frame(width: 150)
                                        Text(highlight.promptText)
                                            .font(Font.poppins(.medium, size: 12))
                                            .foregroundColor(.white)
                                            .lineLimit(2)
                                        Text(highlight.username)
                                            .font(Font.poppins(.regular, size: 11))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    .frame(width: 150, alignment: .leading)
                                }
                            }
                            .padding(.horizontal, 18)
                        }
                    }
                }

                VStack(spacing: 12) {
                    if state.me.isHost {
                        Button {
                            Task {
                                if await session.playAgain() { PC.notify(.success) }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                if session.isBusy { ProgressView().tint(.white) }
                                Label("Play again", systemImage: "arrow.counterclockwise")
                            }
                        }
                        .buttonStyle(PillButtonStyle())
                        .disabled(session.isBusy)
                    } else {
                        Text("Waiting for the host to start a new game…")
                            .font(Font.poppins(.regular, size: 13))
                            .foregroundColor(.white.opacity(0.75))
                    }
                    Button {
                        Task { await session.leaveGame() }
                    } label: {
                        Label("Back to home", systemImage: "house.fill")
                    }
                    .buttonStyle(SecondaryPillButtonStyle())
                    .disabled(session.isBusy)
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                Color.clear.frame(height: 24)
            }
        }
    }
}
