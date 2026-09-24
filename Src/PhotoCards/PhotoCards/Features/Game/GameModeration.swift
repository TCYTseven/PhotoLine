//
//  GameModeration.swift
//  PhotoCards
//
//  Report & block for everything players can put on screen: photos,
//  display names and custom prompts (App Store Guideline 1.2).
//
//  GameSessionView owns the report sheet and the block confirmation, so
//  neither is torn down when the game moves to the next phase. Screens
//  reach them through the `gameModeration` environment value.
//

import SwiftUI
import Common

// MARK: - What is being reported

struct ReportTarget: Identifiable {
    enum Kind {
        case photo
        case player
        case prompt
    }

    let id = UUID()
    let kind: Kind
    var reportedUserId: UUID? = nil
    var reportedName: String? = nil
    var photoId: UUID? = nil
    /// Extra context sent along with the report (e.g. the prompt text).
    var context: String? = nil

    var title: String {
        switch kind {
        case .photo: return "Report photo"
        case .player: return "Report player"
        case .prompt: return "Report prompt"
        }
    }
}

// MARK: - Environment

struct GameModeration {
    var myUserId: UUID? = nil
    var blockedUserIds: Set<UUID> = []
    var report: (ReportTarget) -> Void = { _ in }
    var requestBlock: (PlayerInfo) -> Void = { _ in }

    func isBlocked(_ userId: UUID?) -> Bool {
        guard let userId else { return false }
        return blockedUserIds.contains(userId)
    }

    /// Hides the display name of anyone the player blocked this session.
    func displayName(_ username: String, userId: UUID?) -> String {
        isBlocked(userId) ? "Blocked player" : username
    }

    func canModerate(_ player: PlayerInfo) -> Bool {
        player.userId != myUserId
    }
}

private struct GameModerationKey: EnvironmentKey {
    static var defaultValue: GameModeration { GameModeration() }
}

extension EnvironmentValues {
    var gameModeration: GameModeration {
        get { self[GameModerationKey.self] }
        set { self[GameModerationKey.self] = newValue }
    }
}

extension GameState {
    /// The user behind a player id (submissions only carry the player id).
    func userId(forPlayer playerId: UUID?) -> UUID? {
        guard let playerId else { return nil }
        return players.first(where: { $0.id == playerId })?.userId
    }

    /// Custom prompts are written by the host; pack prompts are ours.
    func isCustomPrompt(_ text: String) -> Bool {
        game.customPrompts.contains(text)
    }
}

// MARK: - "…" menu on a player row

struct PlayerActionsMenu: View {
    @Environment(\.gameModeration) private var moderation
    let player: PlayerInfo

    var body: some View {
        Menu {
            Button {
                moderation.report(ReportTarget(
                    kind: .player,
                    reportedUserId: player.userId,
                    reportedName: player.username,
                    context: "Display name: \(player.username)"
                ))
            } label: {
                Label("Report player", systemImage: "flag")
            }
            if !moderation.isBlocked(player.userId) {
                Button(role: .destructive) {
                    moderation.requestBlock(player)
                } label: {
                    Label("Block player", systemImage: "hand.raised")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More options for \(moderation.displayName(player.username, userId: player.userId))")
    }
}

// MARK: - Prompt card with a report button

struct ReportablePromptCard: View {
    @Environment(\.gameModeration) private var moderation
    let state: GameState
    let round: RoundInfo
    let caption: String

    var body: some View {
        PromptCard(text: round.promptText, caption: caption)
            .overlay(alignment: .bottomTrailing) {
                Button {
                    let isCustom = state.isCustomPrompt(round.promptText)
                    moderation.report(ReportTarget(
                        kind: .prompt,
                        reportedUserId: isCustom && state.game.hostId != moderation.myUserId ? state.game.hostId : nil,
                        context: "\(isCustom ? "Custom prompt" : "Prompt"): \(round.promptText)"
                    ))
                } label: {
                    Image(systemName: "flag")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black.opacity(0.45))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .padding(.bottom, 6)
                .accessibilityLabel("Report this prompt")
            }
    }
}

// MARK: - Report sheet

struct ReportSheet: View {
    @EnvironmentObject private var session: GameSessionStore
    @Environment(\.dismiss) private var dismiss

    let target: ReportTarget
    /// Offer "Also block" only for another player.
    let canBlock: Bool
    let onBlocked: (UUID) -> Void

    private static let reasons = [
        "Inappropriate or explicit photo",
        "Offensive display name",
        "Offensive prompt",
        "Hateful or harassing content",
        "Spam or cheating",
        "Something else"
    ]

    @State private var reason: String
    @State private var details = ""
    @State private var alsoBlock = false
    @State private var isSending = false
    @State private var sent = false
    @State private var sendError: String?

    init(target: ReportTarget, canBlock: Bool, onBlocked: @escaping (UUID) -> Void) {
        self.target = target
        self.canBlock = canBlock
        self.onBlocked = onBlocked
        let initial: String
        switch target.kind {
        case .photo: initial = "Inappropriate or explicit photo"
        case .player: initial = "Offensive display name"
        case .prompt: initial = "Offensive prompt"
        }
        _reason = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let name = target.reportedName {
                    Section {
                        Text(name)
                            .lineLimit(2)
                    } header: {
                        Text("Player")
                    }
                } else if target.kind == .prompt, let context = target.context {
                    Section {
                        Text(context)
                    } header: {
                        Text("Prompt")
                    }
                }
                Section {
                    Picker("Reason", selection: $reason) {
                        ForEach(Self.reasons, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("What's wrong?")
                }
                Section {
                    TextField("Tell us more", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Details (optional)")
                }
                if canBlock, target.reportedUserId != nil {
                    Section {
                        Toggle(target.kind == .prompt ? "Also block the host who added it" : "Also block this player", isOn: $alsoBlock)
                    } footer: {
                        Text("You won't see their name, they can't join rooms you host, and rooms they host won't show up for you.")
                    }
                }
                if let sendError {
                    Section {
                        Label(sendError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                    }
                }
                Section {
                    Text("Reports are reviewed by the PhotoCards team. Content that breaks the rules is removed, and repeat offenders are banned.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle(target.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await send() }
                    } label: {
                        if isSending { ProgressView() } else { Text("Send") }
                    }
                    .disabled(isSending)
                    .accessibilityLabel("Send report")
                }
            }
            .alert("Thanks for the report", isPresented: $sent) {
                Button("Done") { dismiss() }
            } message: {
                Text(alsoBlock ? "We'll take a look. This player is now blocked." : "We'll take a look.")
            }
        }
        .interactiveDismissDisabled(isSending)
    }

    private func send() async {
        isSending = true
        sendError = nil
        let typed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = [target.context, typed.isEmpty ? nil : typed]
            .compactMap { $0 }
            .joined(separator: "\n\n")
        let ok = await session.report(
            reason: reason,
            details: combined.isEmpty ? nil : combined,
            reportedUserId: target.reportedUserId,
            photoId: target.photoId
        )
        if !ok {
            // Show the failure here; the game screen's alert can't appear
            // over this sheet.
            sendError = session.errorMessage ?? "Couldn't send the report. Check your connection and try again."
            session.errorMessage = nil
            isSending = false
            return
        }
        if alsoBlock, canBlock, let userId = target.reportedUserId {
            if await session.block(userId: userId) {
                onBlocked(userId)
            } else {
                session.errorMessage = nil
                alsoBlock = false
            }
        }
        isSending = false
        PC.notify(.success)
        sent = true
    }
}
