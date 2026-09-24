//
//  GameSessionView.swift
//  PhotoCards
//
//  Full-screen container for a live game. Switches screens by phase and
//  owns the app-wide game sheets: leave confirmation, lobby settings,
//  reporting and blocking.
//

import SwiftUI
import Common

struct GameSessionView: View {
    @EnvironmentObject private var session: GameSessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showLeaveConfirm = false
    @State private var showSettingsEditor = false
    @State private var reportTarget: ReportTarget?
    @State private var blockCandidate: PlayerInfo?
    @State private var blockedUserIds: Set<UUID> = []
    @State private var blockedName: String?

    var body: some View {
        ZStack {
            PhotoBackdrop(imageURL: nil)

            if let state = session.state {
                phaseContent(for: state)
                    .id(phaseKey(for: state))
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
            } else {
                ProgressView()
                    .tint(.white)
                    .accessibilityLabel("Loading game")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let state = session.state {
                header(for: state)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: session.state.map { phaseKey(for: $0) })
        .environment(\.gameModeration, moderation)
        // Fixed-height pill buttons and the header can't grow forever.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showLeaveConfirm) {
            leaveSheet
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
                // The game screen's alert can't appear over this sheet.
                .alert("Couldn't save settings", isPresented: errorBinding(visible: true)) {
                    Button("OK") { session.errorMessage = nil }
                } message: {
                    Text(session.errorMessage ?? "")
                }
            }
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(
                target: target,
                canBlock: target.reportedUserId != nil && target.reportedUserId != session.state?.me.userId,
                onBlocked: { blockedUserIds.insert($0) }
            )
            .environmentObject(session)
        }
        .confirmationDialog(
            "Block this player?",
            isPresented: Binding(
                get: { blockCandidate != nil },
                set: { if !$0 { blockCandidate = nil } }
            ),
            titleVisibility: .visible,
            presenting: blockCandidate
        ) { player in
            Button("Block \(player.username)", role: .destructive) {
                Task { await block(player) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You won't see their name, they can't join rooms you host, and rooms they host won't show up for you.")
        }
        .alert("Player blocked", isPresented: Binding(
            get: { blockedName != nil },
            set: { if !$0 { blockedName = nil } }
        )) {
            Button("Stay in game", role: .cancel) { blockedName = nil }
            Button("Leave room", role: .destructive) {
                blockedName = nil
                Task { await session.leaveGame() }
            }
        } message: {
            Text("\(blockedName ?? "They") won't be able to join your rooms. You can leave this room now, or unblock them later in Settings.")
        }
        // Sheets show their own errors; this alert can't appear over them.
        .alert("Something went wrong", isPresented: errorBinding(
            visible: reportTarget == nil && !showSettingsEditor && !showLeaveConfirm
        )) {
            Button("OK") { session.errorMessage = nil }
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    // MARK: - Phases

    @ViewBuilder
    private func phaseContent(for state: GameState) -> some View {
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

    private func phaseKey(for state: GameState) -> String {
        "\(state.game.phase.rawValue)-\(state.game.currentRound)"
    }

    private func errorBinding(visible: Bool) -> Binding<Bool> {
        Binding(
            get: { visible && session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )
    }

    // MARK: - Moderation

    private var moderation: GameModeration {
        GameModeration(
            myUserId: session.state?.me.userId,
            blockedUserIds: blockedUserIds,
            report: { target in reportTarget = target },
            requestBlock: { player in blockCandidate = player }
        )
    }

    private func block(_ player: PlayerInfo) async {
        blockCandidate = nil
        if await session.block(userId: player.userId) {
            blockedUserIds.insert(player.userId)
            PC.notify(.success)
            blockedName = player.username
        }
    }

    // MARK: - Leave

    private var leaveSheet: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(PC.red)
                    .frame(width: 70, height: 70)
                    .background(PC.red.opacity(0.15), in: Circle())
                    .accessibilityHidden(true)
                Text("Leave this room?")
                    .font(Font.poppins(.bold, size: 24))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
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
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents(dynamicTypeSize >= .xxLarge ? [.large] : [.height(400)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground { PhotoBackdrop(imageURL: nil) }
        .preferredColorScheme(.dark)
    }

    private var leaveMessage: String {
        guard let state = session.state else { return "" }
        if state.game.status == .lobby && state.me.isHost {
            return "You're the host. Hosting passes to the next player, or the room closes if you're alone."
        }
        if state.game.status == .playing {
            return "You can rejoin with the room code while the game is still running. If fewer than 3 players are left, the game ends."
        }
        return "You'll go back to the home screen."
    }

    // MARK: - Header

    private func header(for state: GameState) -> some View {
        HStack(spacing: 10) {
            RoundIconButton(icon: "xmark", label: "Leave game") {
                showLeaveConfirm = true
            }

            Spacer(minLength: 4)

            Group {
                switch state.game.phase {
                case .lobby:
                    Text("Lobby")
                        .font(Font.poppins(.semiBold, size: 16))
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                case .gameOver:
                    RoomCodeChip(code: state.game.roomCode)
                default:
                    Label {
                        Text("Round \(state.game.currentRound) of \(state.game.maxRounds)")
                    } icon: {
                        Image(systemName: state.game.mode.icon)
                    }
                    .font(Font.poppins(.semiBold, size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(state.game.mode.title), round \(state.game.currentRound) of \(state.game.maxRounds)")
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            Spacer(minLength: 4)

            if let seconds = session.secondsRemaining, state.game.phaseEndsAt != nil,
               state.game.phase != .gameOver, state.game.phase != .lobby {
                TimerPill(seconds: seconds, progress: session.phaseProgress)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(seconds > 0 ? "\(seconds) seconds left" : "Time's up")
            } else {
                Color.clear
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}
