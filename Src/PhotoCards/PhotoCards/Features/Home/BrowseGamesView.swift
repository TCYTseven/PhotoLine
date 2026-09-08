//
//  BrowseGamesView.swift
//  PhotoCards
//
//  Public lobbies that are waiting for players.
//

import SwiftUI
import Common
import Factory

struct BrowseGamesView: View {
    @EnvironmentObject private var navigator: AppNavigator
    @EnvironmentObject private var session: GameSessionStore
    @AppStorage(AppStorageKeys.playerName) private var playerName = ""
    @Injected(\.gameService) private var gameService: GameService

    @State private var games: [PublicGameSummary] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var joiningCode: String?

    var body: some View {
        ZStack {
            PhotoBackdrop(imageURL: nil)

            Group {
                if isLoading && games.isEmpty {
                    ProgressView().tint(.white)
                } else if let loadError, games.isEmpty {
                    emptyState(icon: "wifi.exclamationmark", title: "Couldn't load rooms", message: loadError)
                } else if games.isEmpty {
                    emptyState(icon: "person.3", title: "No public rooms right now", message: "Create one and make it public, or join with a code.")
                } else {
                    list
                }
            }
        }
        .navigationTitle("Public rooms")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
        .refreshable { await load() }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(games) { game in
                    Button {
                        Task { await join(game) }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: game.mode.icon)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(PC.red))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(game.hostUsername.map { "\($0)'s room" } ?? "Open room")
                                    .font(Font.poppins(.bold, size: 16))
                                    .foregroundColor(.white)
                                Text("\(game.mode.title) · \(game.playerCount)/\(game.maxPlayers) players")
                                    .font(Font.poppins(.regular, size: 13))
                                    .foregroundColor(.white.opacity(0.75))
                            }
                            Spacer()
                            if joiningCode == game.roomCode {
                                ProgressView().tint(.white)
                            } else {
                                RoomCodeChip(code: game.roomCode)
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: PC.cornerMedium, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: PC.cornerMedium, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(session.isBusy)
                }
                Text("Public rooms are open to anyone. You can report or block players from inside a game.")
                    .font(Font.poppins(.regular, size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .padding(18)
        }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(.white.opacity(0.8))
            Text(title)
                .font(Font.poppins(.bold, size: 18))
                .foregroundColor(.white)
            Text(message)
                .font(Font.poppins(.regular, size: 14))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await load() } }
                .buttonStyle(SecondaryPillButtonStyle(height: 44))
                .frame(width: 160)
                .padding(.top, 6)
        }
        .padding(30)
    }

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            games = try await gameService.listPublicGames()
        } catch is CancellationError {
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func join(_ game: PublicGameSummary) async {
        joiningCode = game.roomCode
        let name = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if await session.joinGame(code: game.roomCode, username: name) {
            PC.notify(.success)
            navigator.popToRoot()
        } else {
            await load()
        }
        joiningCode = nil
    }
}
