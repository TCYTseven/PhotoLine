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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: GameState

    @State private var selected: SubmissionInfo?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)

    private var canDecide: Bool {
        state.isVoteMode || state.me.isJudge
    }

    /// The timer ran out but the server hasn't resolved the round yet.
    private var timeUp: Bool { session.secondsRemaining == 0 }

    private var headline: String {
        if state.isVoteMode { return state.me.myVoteSubmissionId == nil ? "Vote for the best photo" : "Vote cast" }
        if state.me.isJudge { return "Pick the winner" }
        return "\(state.round?.judgeUsername ?? "The judge") is deciding…"
    }

    private var subline: String {
        if state.isVoteMode {
            let votes = state.round?.voteCount ?? 0
            let total = state.players.count
            let hint = state.me.myVoteSubmissionId == nil
                ? "You can't vote for your own."
                : "You can change it until time runs out."
            return "\(votes) of \(total) vote\(total == 1 ? "" : "s") in. \(hint)"
        }
        if state.me.isJudge { return "Nobody knows whose photo is whose. Tap one to look closer." }
        return "Photos are anonymous until the judge decides."
    }

    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    if let round = state.round {
                        ReportablePromptCard(
                            state: state,
                            round: round,
                            caption: state.isVoteMode ? "Everyone votes" : (state.me.isJudge ? "You decide" : "\(round.judgeUsername ?? "The judge") decides")
                        )
                        .padding(.horizontal, 18)
                        .padding(.top, 4)
                    }

                    VStack(spacing: 4) {
                        Text(headline)
                            .font(Font.poppins(.bold, size: 20))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        Text(subline)
                            .font(Font.poppins(.regular, size: 13))
                            .foregroundColor(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 24)

                    if state.submissions.isEmpty {
                        VStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("Revealing the photos…")
                                .font(Font.poppins(.regular, size: 14))
                                .foregroundColor(.white.opacity(0.75))
                        }
                        .padding(.top, 30)
                        .accessibilityElement(children: .combine)
                    } else {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(Array(state.submissions.enumerated()), id: \.element.id) { index, submission in
                                let isMyVote = state.me.myVoteSubmissionId == submission.id
                                Button {
                                    PC.haptic()
                                    selected = submission
                                } label: {
                                    PhotoTile(
                                        url: submission.thumbnailUrl,
                                        selected: isMyVote,
                                        badge: submission.isMine ? "Yours" : (isMyVote ? "Your vote" : nil),
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
                                .accessibilityLabel(accessibilityLabel(for: submission, index: index, isMyVote: isMyVote))
                                .accessibilityHint("Opens a larger preview")
                                .accessibilityAddTraits(isMyVote ? .isSelected : [])
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    Color.clear.frame(height: 24)
                }
            }

            if let submission = selected {
                PhotoDetailOverlay(
                    imageURL: submission.imageUrl,
                    prompt: state.round?.promptText,
                    primaryTitle: primaryTitle(for: submission),
                    primaryIcon: primaryIcon(for: submission),
                    isBusy: session.isBusy,
                    onPrimary: primaryAction(for: submission),
                    onClose: { selected = nil },
                    reportPhotoId: submission.photoId
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selected?.id)
    }

    private func accessibilityLabel(for submission: SubmissionInfo, index: Int, isMyVote: Bool) -> String {
        var label = "Photo \(index + 1) of \(state.submissions.count)"
        if submission.isMine { label += ", your photo" }
        if isMyVote { label += ", your vote" }
        return label
    }

    private func primaryTitle(for submission: SubmissionInfo) -> String? {
        if state.isVoteMode {
            if submission.isMine { return "Can't vote for your own" }
            if timeUp { return "Voting closed" }
            return state.me.myVoteSubmissionId == submission.id ? "Your vote" : "Vote for this"
        }
        guard state.me.isJudge else { return nil }
        return timeUp ? "Time's up" : "This one wins"
    }

    private func primaryIcon(for submission: SubmissionInfo) -> String {
        if state.isVoteMode {
            if submission.isMine { return "person.crop.circle.badge.xmark" }
            return state.me.myVoteSubmissionId == submission.id ? "checkmark.circle.fill" : "checkmark.seal.fill"
        }
        return "trophy.fill"
    }

    private func primaryAction(for submission: SubmissionInfo) -> (() -> Void)? {
        guard canDecide, !timeUp else { return nil }
        if state.isVoteMode {
            guard !submission.isMine, state.me.myVoteSubmissionId != submission.id else { return nil }
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
