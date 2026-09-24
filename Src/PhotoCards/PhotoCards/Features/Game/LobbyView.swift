//
//  LobbyView.swift
//  PhotoCards
//

import SwiftUI
import Common

struct LobbyView: View {
    @EnvironmentObject private var session: GameSessionStore
    let state: GameState
    let onEditSettings: () -> Void

    @State private var showDetails = false
    @State private var copied = false

    private var canStart: Bool { state.players.count >= 3 }
    private var missingPlayers: Int { max(0, 3 - state.players.count) }

    private var shareText: String {
        "Join my PhotoCards room! Code: \(state.game.roomCode)\n\(AppConfiguration.App.joinURL(code: state.game.roomCode))"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    codeCard
                    playersCard
                    settingsCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
    }

    private var codeCard: some View {
        VStack(spacing: 10) {
            Text("Invite your crew")
                .font(Font.poppins(.bold, size: 24))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Share the code. Get everyone in.")
                .font(Font.poppins(.regular, size: 13))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
            RoomCodeChip(code: state.game.roomCode, large: true)
            HStack(spacing: 12) {
                ShareLink(item: shareText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(SecondaryPillButtonStyle(height: 44))
                .accessibilityLabel("Share room code")
                Button {
                    UIPasteboard.general.string = state.game.roomCode
                    PC.notify(.success)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(SecondaryPillButtonStyle(height: 44))
                .accessibilityLabel(copied ? "Room code copied" : "Copy room code")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)

    }

    private var playersCard: some View {
        VStack(spacing: 10) {
            HStack {
                DarkSectionHeader(title: "Players")
                Text("\(state.players.count)/\(state.game.maxPlayers)")
                    .font(Font.poppins(.semiBold, size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .accessibilityLabel("\(state.players.count) of \(state.game.maxPlayers) players")
            }
            SurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(state.players) { player in
                        PlayerRow(player: player, isMe: player.id == state.me.playerId, trailing: .ready)
                        if player.id != state.players.last?.id {
                            Divider().background(Color.white.opacity(0.15)).padding(.leading, 60)
                        }
                    }
                    if !canStart {
                        Text("Waiting for \(missingPlayers) more player\(missingPlayers == 1 ? "" : "s") (3 needed to start)")
                            .multilineTextAlignment(.center)
                            .font(Font.poppins(.regular, size: 13))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(12)
                    }
                }
            }
        }
    }

    private var settingsCard: some View {
        VStack(spacing: 10) {
            HStack {
                DarkSectionHeader(title: "Settings")
                if state.me.isHost {
                    Button("Edit") { onEditSettings() }
                        .font(Font.poppins(.semiBold, size: 13))
                        .foregroundColor(.white)
                        .disabled(session.isBusy)
                        .accessibilityLabel("Edit settings")
                }
            }
            SurfaceCard {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(spacing: 6) {
                        Label(state.game.mode.title, systemImage: state.game.mode.icon)
                            .font(Font.poppins(.semiBold, size: 18))
                        Text(state.game.mode.subtitle)
                            .font(Font.poppins(.regular, size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    Text("\(state.game.maxRounds) rounds · \(state.game.roundTimerSeconds)s · \(state.game.isPublic ? "Public" : "Private")")
                        .font(Font.poppins(.regular, size: 13))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(maxWidth: .infinity)
                    DisclosureGroup("Details", isExpanded: $showDetails) {
                        VStack(alignment: .leading, spacing: 10) {
                            settingRow(icon: "flag.checkered", title: "\(state.game.maxRounds) rounds", detail: "First to \(state.game.targetScore) points wins early")
                            settingRow(icon: "timer", title: "\(state.game.roundTimerSeconds)s per round", detail: "\(state.game.handSize) photos in hand, \(state.game.refreshesPerPlayer) refresh\(state.game.refreshesPerPlayer == 1 ? "" : "es")")
                            settingRow(icon: "text.quote", title: state.game.promptPacks.isEmpty ? "Default prompts" : state.game.promptPacks.joined(separator: ", "), detail: state.game.customPromptCount > 0 ? "+ \(state.game.customPromptCount) custom prompts" : "Prompt packs")
                            settingRow(icon: state.game.isPublic ? "globe" : "lock.fill", title: state.game.isPublic ? "Public room" : "Private room", detail: state.game.isPublic ? "Listed under Browse" : "Only people with the code")
                        }
                        .padding(.top, 8)
                    }
                    .font(Font.poppins(.medium, size: 13))
                    .tint(.white)
                    .foregroundStyle(.white)
                }
            }
        }
    }

    private func settingRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Font.poppins(.semiBold, size: 15))
                    .foregroundColor(.white)
                Text(detail)
                    .font(Font.poppins(.regular, size: 12))
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if state.me.isHost {
                Button {
                    Task {
                        if await session.startGame() { PC.notify(.success) }
                    }
                } label: {
                    HStack(spacing: 10) {
                        if session.isBusy { ProgressView().tint(.white) }
                        Text(canStart ? "Start game" : "Need \(missingPlayers) more player\(missingPlayers == 1 ? "" : "s")")
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(!canStart || session.isBusy)
                .opacity(canStart ? 1 : 0.7)
            } else {
                Button {
                    Task { await session.setReady(!isReady) }
                } label: {
                    Label(isReady ? "Ready!" : "I'm ready", systemImage: isReady ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(PillButtonStyle(fill: isReady ? Color(red: 0.12, green: 0.52, blue: 0.28) : PC.red))
                .accessibilityHint(isReady ? "Double tap if you are not ready yet" : "Tells the host you are ready")
                .disabled(session.isBusy)
                Text("The host starts the game once everyone is in.")
                    .font(Font.poppins(.regular, size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    private var isReady: Bool {
        state.players.first(where: { $0.id == state.me.playerId })?.isReady ?? false
    }
}

// MARK: - Player row

struct PlayerRow: View {
    enum Trailing {
        case ready
        case score
        case submitted
        case voted
        case none
    }

    @Environment(\.gameModeration) private var moderation

    let player: PlayerInfo
    var isMe = false
    var trailing: Trailing = .none
    /// Shows the report / block menu for other players.
    var showsActions = true

    private var isBlocked: Bool { moderation.isBlocked(player.userId) }
    private var name: String { moderation.displayName(player.username, userId: player.userId) }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 12) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(Font.poppins(.semiBold, size: 16))
                            .foregroundColor(.white.opacity(isBlocked ? 0.6 : 1))
                            .lineLimit(1)
                        if isMe {
                            Text("you")
                                .font(Font.poppins(.medium, size: 11))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.2)))
                        }
                    }
                    HStack(spacing: 6) {
                        if player.isHost {
                            Label("Host", systemImage: "crown.fill")
                        }
                        if player.isJudge {
                            Label("Judge", systemImage: "hand.thumbsup.fill")
                        }
                        if !player.isConnected {
                            Label("Away", systemImage: "wifi.slash")
                        }
                    }
                    .font(Font.poppins(.regular, size: 11))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                trailingView
            }
            .accessibilityElement(children: .combine)

            if showsActions && !isMe && moderation.canModerate(player) {
                PlayerActionsMenu(player: player)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, showsActions && !isMe ? 4 : 14)
        .padding(.vertical, 10)
    }

    private var avatar: some View {
        Text(isBlocked ? "?" : String(player.username.prefix(1)).uppercased())
            .font(Font.poppins(.bold, size: 17))
            .foregroundColor(.white)
            .frame(width: 38, height: 38)
            .background(Circle().fill(player.isJudge ? PC.red : Color.white.opacity(0.2)))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var trailingView: some View {
        switch trailing {
        case .ready:
            Image(systemName: player.isReady ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 22))
                .foregroundColor(player.isReady ? .green : .white.opacity(0.4))
                .accessibilityLabel(player.isReady ? "Ready" : "Not ready")
        case .score:
            ScoreBadge(score: player.score)
                .accessibilityLabel("\(player.score) point\(player.score == 1 ? "" : "s")")
        case .submitted:
            if player.isJudge {
                Text("judging")
                    .font(Font.poppins(.medium, size: 12))
                    .foregroundColor(.white.opacity(0.6))
            } else {
                Image(systemName: player.hasSubmitted ? "checkmark.circle.fill" : "hourglass")
                    .font(.system(size: 20))
                    .foregroundColor(player.hasSubmitted ? .green : .white.opacity(0.5))
                    .accessibilityLabel(player.hasSubmitted ? "Submitted" : "Still choosing")
            }
        case .voted:
            Image(systemName: player.hasVoted ? "checkmark.circle.fill" : "hourglass")
                .font(.system(size: 20))
                .foregroundColor(player.hasVoted ? .green : .white.opacity(0.5))
                .accessibilityLabel(player.hasVoted ? "Voted" : "Still voting")
        case .none:
            EmptyView()
        }
    }
}

struct LeaderboardView: View {
    let state: GameState

    var body: some View {
        let ranked = state.leaderboard
        SurfaceCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, player in
                    HStack(spacing: 0) {
                        Text("\(index + 1)")
                            .font(Font.poppins(.bold, size: 14))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 22)
                            .accessibilityLabel("Rank \(index + 1)")
                        PlayerRow(player: player, isMe: player.id == state.me.playerId, trailing: .score)
                    }
                    .padding(.leading, 12)
                    if player.id != ranked.last?.id {
                        Divider().background(Color.white.opacity(0.15)).padding(.leading, 60)
                    }
                }
            }
        }
    }
}
