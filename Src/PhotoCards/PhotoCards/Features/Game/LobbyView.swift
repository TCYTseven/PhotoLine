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

    private var canStart: Bool { state.players.count >= 3 }

    private var shareText: String {
        "Join my PhotoCards room! Code: \(state.game.roomCode)\n\(AppConfiguration.App.joinURL(code: state.game.roomCode))"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    codeCard
                    playersCard
                    settingsCard
                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
            }
        }
        .overlay(alignment: .bottom) { footer }
    }

    private var codeCard: some View {
        VStack(spacing: 12) {
            Text("Room code")
                .font(Font.poppins(.semiBold, size: 13))
                .foregroundColor(.white.opacity(0.7))
            RoomCodeChip(code: state.game.roomCode, large: true)
            Text("Share it with friends so they can join.")
                .font(Font.poppins(.regular, size: 13))
                .foregroundColor(.white.opacity(0.7))
            HStack(spacing: 12) {
                ShareLink(item: shareText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(SecondaryPillButtonStyle(height: 44))
                Button {
                    UIPasteboard.general.string = state.game.roomCode
                    PC.notify(.success)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(SecondaryPillButtonStyle(height: 44))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: PC.cornerLarge, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PC.cornerLarge, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
    }

    private var playersCard: some View {
        VStack(spacing: 10) {
            HStack {
                DarkSectionHeader(title: "Players")
                Text("\(state.players.count)/\(state.game.maxPlayers)")
                    .font(Font.poppins(.semiBold, size: 12))
                    .foregroundColor(.white.opacity(0.7))
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
                        Text("Need \(3 - state.players.count) more to start (minimum 3).")
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
                }
            }
            SurfaceCard {
                VStack(alignment: .leading, spacing: 10) {
                    settingRow(icon: state.game.mode.icon, title: state.game.mode.title, detail: state.game.mode.subtitle)
                    settingRow(icon: "flag.checkered", title: "\(state.game.maxRounds) rounds", detail: "First to \(state.game.targetScore) points wins early")
                    settingRow(icon: "timer", title: "\(state.game.roundTimerSeconds)s per round", detail: "\(state.game.handSize) photos in hand, \(state.game.refreshesPerPlayer) refreshes")
                    settingRow(icon: "text.quote", title: state.game.promptPacks.joined(separator: ", "), detail: state.game.customPromptCount > 0 ? "+ \(state.game.customPromptCount) custom prompts" : "Prompt packs")
                    settingRow(icon: state.game.isPublic ? "globe" : "lock.fill", title: state.game.isPublic ? "Public room" : "Private room", detail: state.game.isPublic ? "Listed under Browse" : "Only people with the code")
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
                        Text(canStart ? "Start game" : "Waiting for players…")
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
                .buttonStyle(PillButtonStyle(fill: isReady ? Color.green : PC.red))
                .disabled(session.isBusy)
                Text("The host starts the game once everyone is in.")
                    .font(Font.poppins(.regular, size: 12))
                    .foregroundColor(.white.opacity(0.7))
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

    let player: PlayerInfo
    var isMe = false
    var trailing: Trailing = .none

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(player.username)
                        .font(Font.poppins(.semiBold, size: 16))
                        .foregroundColor(.white)
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
            }
            Spacer()
            trailingView
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var avatar: some View {
        Text(String(player.username.prefix(1)).uppercased())
            .font(Font.poppins(.bold, size: 17))
            .foregroundColor(.white)
            .frame(width: 38, height: 38)
            .background(Circle().fill(player.isJudge ? PC.red : Color.white.opacity(0.2)))
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
    var compact = false

    var body: some View {
        SurfaceCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(state.leaderboard.enumerated()), id: \.element.id) { index, player in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(Font.poppins(.bold, size: 14))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 22)
                        PlayerRow(player: player, isMe: player.id == state.me.playerId, trailing: .score)
                    }
                    .padding(.leading, 12)
                    if player.id != state.leaderboard.last?.id {
                        Divider().background(Color.white.opacity(0.15)).padding(.leading, 60)
                    }
                }
            }
        }
    }
}
