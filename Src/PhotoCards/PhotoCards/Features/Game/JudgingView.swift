//
//  JudgingView.swift
//  PhotoCards
//
//  Anonymous reveal. The judge picks (classic / rapid) or everyone votes.
//

import SwiftUI
import Common

struct JudgingView: View {
    @EnvironmentObject private var session: GameSessionStore
    let state: GameState

    @State private var selected: SubmissionInfo?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)

    private var canDecide: Bool {
        state.isVoteMode || state.me.isJudge
    }

    private var headline: String {
        if state.isVoteMode { return "Vote for the best photo" }
        if state.me.isJudge { return "Pick the winner" }
        return "\(state.round?.judgeUsername ?? "The judge") is deciding…"
    }

    private var subline: String {
        if state.isVoteMode {
            let votes = state.round?.voteCount ?? 0
            let hint = state.me.myVoteSubmissionId == nil ? "You can't vote for your own." : "You voted. You can change it until time runs out."
            return "\(votes) of \(state.players.count) votes in. \(hint)"
        }
        if state.me.isJudge { return "Nobody knows whose photo is whose. Tap one to look closer." }
        return "Photos are anonymous until the judge decides."
    }

    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    if let round = state.round {
                        PromptCard(text: round.promptText, caption: state.isVoteMode ? "Everyone votes" : "\(round.judgeUsername ?? "Judge") decides")
                            .padding(.horizontal, 18)
                            .padding(.top, 4)
                    }

                    VStack(spacing: 4) {
                        Text(headline)
                            .font(Font.poppins(.bold, size: 20))
                            .foregroundColor(.white)
                        Text(subline)
                            .font(Font.poppins(.regular, size: 13))
                            .foregroundColor(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Array(state.submissions.enumerated()), id: \.element.id) { index, submission in
                            Button {
                                PC.haptic()
                                selected = submission
                            } label: {
                                PhotoTile(
                                    url: submission.imageUrl,
                                    selected: state.me.myVoteSubmissionId == submission.id,
                                    badge: submission.isMine ? "Yours" : (state.me.myVoteSubmissionId == submission.id ? "Your vote" : nil),
                                    cornerRadius: 18
                                )
                                .overlay(alignment: .bottomLeading) {
                                    Text("#\(index + 1)")
                                        .font(Font.poppins(.bold, size: 12))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.black.opacity(0.5)))
                                        .padding(8)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Submission \(index + 1)\(submission.isMine ? ", yours" : "")")
                        }
                    }
                    .padding(.horizontal, 16)
                    Color.clear.frame(height: 24)
                }
            }

            if let submission = selected {
                PhotoDetailOverlay(
                    imageURL: submission.imageUrl,
                    prompt: state.round?.promptText,
                    primaryTitle: primaryTitle(for: submission),
                    primaryIcon: state.isVoteMode ? "checkmark.seal.fill" : "trophy.fill",
                    isBusy: session.isBusy,
                    onPrimary: primaryAction(for: submission),
                    onClose: { selected = nil },
                    reportUserId: nil,
                    reportPhotoId: submission.photoId
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selected?.id)
    }

    private func primaryTitle(for submission: SubmissionInfo) -> String? {
        if state.isVoteMode {
            if submission.isMine { return nil }
            return state.me.myVoteSubmissionId == submission.id ? "Voted ✓" : "Vote for this"
        }
        return state.me.isJudge ? "This one wins" : nil
    }

    private func primaryAction(for submission: SubmissionInfo) -> (() -> Void)? {
        guard canDecide else { return nil }
        if state.isVoteMode {
            if submission.isMine { return nil }
            return {
                Task {
                    if await session.castVote(submissionId: submission.id) { PC.notify(.success) }
                    selected = nil
                }
            }
        }
        return {
            Task {
                if await session.pickWinner(submissionId: submission.id) { PC.notify(.success) }
                selected = nil
            }
        }
    }
}
