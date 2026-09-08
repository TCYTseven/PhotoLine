//
//  GameSessionView.swift
//  PhotoCards
//
//  Full-screen container for a live game. Switches screens by phase.
//

import SwiftUI
import Common

struct GameSessionView: View {
    @EnvironmentObject private var session: GameSessionStore
    @State private var showLeaveConfirm = false
    @State private var showSettingsEditor = false

    var body: some View {
        ZStack {
            PhotoBackdrop(imageURL: nil)

            if let state = session.state {
                Group {
                    switch state.game.phase {
                    case .lobby:
                        LobbyView(state: state, onEditSettings: { showSettingsEditor = true })
                    case .choosing:
                        ChoosingView(state: state)
                    case .judging:
                        JudgingView(state: state)
                    case .roundResults:
                        RoundResultsView(state: state)
                    case .gameOver:
                        FinalResultsView(state: state)
                    }
                }
                .id(state.game.phase.rawValue + "\(state.game.currentRound)")
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .animation(.easeInOut(duration: 0.3), value: state.game.phase)
                .safeAreaInset(edge: .top) { header(for: state) }
            } else {
                ProgressView().tint(.white)
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog("Leave this game?", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
            Button("Leave game", role: .destructive) {
                Task { await session.leaveGame() }
            }
            Button("Stay", role: .cancel) {}
        } message: {
            Text(leaveMessage)
        }
        .sheet(isPresented: $showSettingsEditor) {
            if let state = session.state {
                NavigationStack {
                    CreateGameView(editing: state, onSaved: { showSettingsEditor = false })
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { showSettingsEditor = false }
                                    .foregroundColor(.white)
                            }
                        }
                }
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )) {
            Button("OK") { session.errorMessage = nil }
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    private var leaveMessage: String {
        guard let state = session.state else { return "" }
        if state.game.status == .lobby && state.me.isHost {
            return "You're the host. Hosting passes to the next player, or the room closes if you're alone."
        }
        if state.game.status == .playing {
            return "You can rejoin with the room code while the game is still running."
        }
        return "You'll go back to the home screen."
    }

    private func header(for state: GameState) -> some View {
        HStack(spacing: 10) {
            RoundIconButton(icon: "xmark", label: "Leave game") {
                showLeaveConfirm = true
            }

            Spacer()

            if state.game.phase == .lobby || state.game.phase == .gameOver {
                RoomCodeChip(code: state.game.roomCode)
            } else {
                Text("Round \(state.game.currentRound) of \(state.game.maxRounds)")
                    .font(Font.poppins(.semiBold, size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
            }

            Spacer()

            if let seconds = session.secondsRemaining, state.game.phaseEndsAt != nil, state.game.phase != .gameOver {
                TimerPill(seconds: seconds, progress: session.phaseProgress)
            } else {
                Color.clear.frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }
}
