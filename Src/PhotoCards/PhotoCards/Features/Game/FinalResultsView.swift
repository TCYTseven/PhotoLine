//
//  FinalResultsView.swift
//  PhotoCards
//

import SwiftUI
import Common

struct FinalResultsView: View {
    @EnvironmentObject private var session: GameSessionStore
    @Environment(\.gameModeration) private var moderation
    let state: GameState

    private var winner: PlayerInfo? { state.winner }
    private var iWon: Bool { winner?.id == state.me.playerId }

    private var topScore: Int { state.leaderboard.first?.score ?? 0 }

    /// Players sharing the top score (the server breaks ties by join order,
    /// which shouldn't be presented as an outright win).
    private var isTie: Bool {
        topScore > 0 && state.players.filter { $0.score == topScore }.count > 1
    }

    /// The host left after the game ended, so nobody can start a rematch.
    private var hostIsGone: Bool {
        !state.players.contains(where: { $0.isHost })
    }

    private var roundsPlayed: Int { state.game.currentRound }

    private var headline: String {
        guard let winner, topScore > 0 else { return "Game over" }
        if isTie { return "It's a tie!" }
        if iWon { return "You win!" }
        return "\(moderation.displayName(winner.username, userId: winner.userId)) wins!"
    }

    private var subheadline: String? {
        guard topScore > 0 else { return "Nobody scored this time." }
        let points = "\(topScore) point\(topScore == 1 ? "" : "s")"
        let rounds = "\(roundsPlayed) round\(roundsPlayed == 1 ? "" : "s")"
        if isTie { return "Tied on \(points) after \(rounds)" }
        return "\(points) after \(rounds)"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 54, weight: .bold))
                        .foregroundColor(.yellow)
                        .shadow(color: .yellow.opacity(0.5), radius: 16)
                        .accessibilityHidden(true)
                    Text(headline)
                        .font(Font.poppins(.black, size: 32))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .accessibilityAddTraits(.isHeader)
                    if let subheadline {
                        Text(subheadline)
                            .font(Font.poppins(.regular, size: 14))
                            .foregroundColor(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 18)

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
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(state.highlights) { highlight in
                                    let author = highlightAuthor(highlight)
                                    VStack(alignment: .leading, spacing: 6) {
                                        PhotoTile(url: highlight.thumbnailUrl, badge: "R\(highlight.roundNumber)")
                                            .frame(width: 150)
                                            .accessibilityHidden(true)
                                        Text(highlight.promptText)
                                            .font(Font.poppins(.medium, size: 12))
                                            .foregroundColor(.white)
                                            .lineLimit(2)
                                        Text(author)
                                            .font(Font.poppins(.regular, size: 11))
                                            .foregroundColor(.white.opacity(0.7))
                                            .lineLimit(1)
                                    }
                                    .frame(width: 150, alignment: .leading)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("Round \(highlight.roundNumber): \(highlight.promptText). Won by \(author).")
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
                        .accessibilityHint("Takes everyone back to the lobby with fresh scores")
                    } else {
                        Text(hostIsGone
                             ? "The host has left, so there's no rematch in this room. Head home to start a new one."
                             : "Waiting for the host to start a rematch…")
                            .font(Font.poppins(.regular, size: 13))
                            .foregroundColor(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
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

    private func highlightAuthor(_ highlight: Highlight) -> String {
        // Highlights carry only the name; match it back to a player to honour blocks.
        let player = state.players.first(where: { $0.username == highlight.username })
        if player?.id == state.me.playerId { return "You" }
        return moderation.displayName(highlight.username, userId: player?.userId)
    }
}
