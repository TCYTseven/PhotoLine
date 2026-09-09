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
        .sheet(isPresented: $showLeaveConfirm) {
            VStack(spacing: 18) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(PC.red)
                    .frame(width: 70, height: 70)
                    .background(PC.red.opacity(0.15), in: Circle())
                Text("Leave this room?")
                    .font(Font.poppins(.bold, size: 24))
                Text(leaveMessage)
                    .font(Font.poppins(.regular, size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 10) {
                    Button("Stay in game") { showLeaveConfirm = false }
                        .buttonStyle(PillButtonStyle())
                    Button {
                        showLeaveConfirm = false
                        Task { await session.leaveGame() }
                    } label: {
                        Text("Leave room")
                    }
                    .buttonStyle(SecondaryPillButtonStyle(height: 48))
                    .disabled(session.isBusy)
                }
            }
            .foregroundStyle(.white)
            .padding(24)
            .presentationDetents([.height(390)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
            .presentationBackground { PhotoBackdrop(imageURL: nil) }
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

            if state.game.phase == .lobby {
                Text("Your room")
                    .font(Font.poppins(.semiBold, size: 16))
                    .foregroundStyle(.white)
            } else if state.game.phase == .gameOver {
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
