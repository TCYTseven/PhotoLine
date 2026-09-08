//
//  GameSessionStore.swift
//  PhotoCards
//
//  Owns the live game session on the client:
//   • keeps the latest server snapshot (GameState)
//   • listens to Realtime and polls as a fallback
//   • runs the countdown clock and asks the server to advance when a
//     phase timer expires (the server decides; clients only nudge)
//   • exposes async actions for every screen
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class GameSessionStore: ObservableObject {

    // MARK: - Published state

    @Published private(set) var state: GameState?
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?
    @Published private(set) var infoMessage: String?
    @Published private(set) var now = Date()

    // MARK: - Private

    private let service: GameService
    private var observeTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var advanceInFlight = false
    private var lastAdvanceAttempt: Date = .distantPast
    /// serverTime - deviceTime at the moment the last snapshot arrived.
    private var serverOffset: TimeInterval = 0

    private let pollInterval: TimeInterval = 4

    init(service: GameService) {
        self.service = service
    }

    // MARK: - Derived

    var isInGame: Bool { state != nil }
    var gameId: UUID? { state?.game.id }

    /// Best guess of the server clock right now.
    var serverNow: Date { now.addingTimeInterval(serverOffset) }

    var secondsRemaining: Int? {
        guard let ends = state?.game.phaseEndsAt else { return nil }
        return max(0, Int(ends.timeIntervalSince(serverNow).rounded(.up)))
    }

    var phaseProgress: Double {
        guard let state, let ends = state.game.phaseEndsAt else { return 0 }
        let total: Double
        switch state.game.phase {
        case .choosing: total = Double(state.game.roundTimerSeconds)
        case .judging: total = Double(state.game.judgeTimerSeconds)
        case .roundResults: total = Double(state.game.resultsSeconds)
        default: total = 1
        }
        guard total > 0 else { return 0 }
        let remaining = max(0, ends.timeIntervalSince(serverNow))
        return min(1, max(0, remaining / total))
    }

    // MARK: - Lifecycle

    /// Called on launch and when the app returns to the foreground.
    func restoreActiveGame() async {
        do {
            if let restored = try await service.activeGame() {
                apply(restored)
            } else if state != nil {
                clearSession(message: nil)
            }
        } catch is CancellationError {
        } catch {
            // Offline or backend unreachable: keep whatever we have.
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if let gameId {
                startObserving(gameId: gameId)
                Task { await refresh() }
            }
        case .background:
            stopObserving()
        default:
            break
        }
    }

    func clearSession(message: String?) {
        stopObserving()
        state = nil
        infoMessage = message
        serverOffset = 0
    }

    func dismissInfo() {
        infoMessage = nil
    }

    // MARK: - Actions

    @discardableResult
    func createGame(username: String, settings: GameSettings) async -> Bool {
        await perform { try await self.service.createGame(username: username, settings: settings) }
    }

    @discardableResult
    func updateSettings(_ settings: GameSettings) async -> Bool {
        guard let gameId else { return false }
        return await perform { try await self.service.updateSettings(gameId: gameId, settings: settings) }
    }

    @discardableResult
    func joinGame(code: String, username: String) async -> Bool {
        await perform { try await self.service.joinGame(code: code, username: username) }
    }

    func leaveGame() async {
        guard let gameId else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await service.leaveGame(gameId: gameId)
        } catch {
            // Leaving must always succeed locally, even offline.
        }
        clearSession(message: nil)
    }

    @discardableResult
    func setReady(_ ready: Bool) async -> Bool {
        guard let gameId else { return false }
        return await perform { try await self.service.setReady(gameId: gameId, ready: ready) }
    }

    @discardableResult
    func startGame() async -> Bool {
        guard let gameId else { return false }
        return await perform { try await self.service.startGame(gameId: gameId) }
    }

    @discardableResult
    func submitPhoto(photoId: UUID) async -> Bool {
        guard let gameId else { return false }
        return await perform { try await self.service.submitPhoto(gameId: gameId, photoId: photoId) }
    }

    @discardableResult
    func refreshHand() async -> Bool {
        guard let gameId else { return false }
        return await perform { try await self.service.refreshHand(gameId: gameId) }
    }

    @discardableResult
    func pickWinner(submissionId: UUID) async -> Bool {
        guard let gameId else { return false }
        return await perform { try await self.service.pickWinner(gameId: gameId, submissionId: submissionId) }
    }

    @discardableResult
    func castVote(submissionId: UUID) async -> Bool {
        guard let gameId else { return false }
        return await perform { try await self.service.castVote(gameId: gameId, submissionId: submissionId) }
    }

    @discardableResult
    func playAgain() async -> Bool {
        guard let gameId else { return false }
        return await perform { try await self.service.restartGame(gameId: gameId) }
    }

    func report(reason: String, details: String?, reportedUserId: UUID?, photoId: UUID?) async -> Bool {
        do {
            try await service.reportContent(reason: reason, details: details, gameId: gameId, reportedUserId: reportedUserId, photoId: photoId)
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func block(userId: UUID) async -> Bool {
        do {
            try await service.blockUser(userId: userId)
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Re-fetches the snapshot. Silent on failure (polling calls this a lot).
    func refresh() async {
        guard let gameId else { return }
        do {
            let fresh = try await service.gameState(gameId: gameId)
            apply(fresh)
        } catch is CancellationError {
        } catch let error as GameServiceError where error.meansSessionIsGone {
            clearSession(message: "The room was closed.")
        } catch {
            // transient; the next poll will retry
        }
    }

    // MARK: - Internals

    private func perform(_ operation: @escaping () async throws -> GameState) async -> Bool {
        isBusy = true
        defer { isBusy = false }
        do {
            let fresh = try await operation()
            apply(fresh)
            return true
        } catch is CancellationError {
            return false
        } catch let error as GameServiceError where error.meansSessionIsGone {
            clearSession(message: "The room was closed.")
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func apply(_ fresh: GameState) {
        // Ignore stale snapshots that raced with a newer one.
        if let current = state, current.game.id == fresh.game.id, fresh.game.version < current.game.version {
            return
        }
        let previousGameId = state?.game.id
        serverOffset = fresh.game.serverTime.timeIntervalSince(Date())
        now = Date()
        state = fresh

        if previousGameId != fresh.game.id {
            startObserving(gameId: fresh.game.id)
        } else if observeTask == nil {
            startObserving(gameId: fresh.game.id)
        }
    }

    private func startObserving(gameId: UUID) {
        stopObserving()

        observeTask = Task { [weak self] in
            guard let self else { return }
            for await _ in self.service.observeGame(gameId: gameId) {
                if Task.isCancelled { break }
                await self.refresh()
            }
        }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.pollInterval ?? 4))
                if Task.isCancelled { break }
                await self?.refresh()
            }
        }

        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                await self?.tick()
            }
        }
    }

    private func stopObserving() {
        observeTask?.cancel()
        pollTask?.cancel()
        tickTask?.cancel()
        observeTask = nil
        pollTask = nil
        tickTask = nil
    }

    private func tick() async {
        now = Date()
        await advanceIfExpired()
    }

    /// When a phase timer has run out, ask the server to move on. The host
    /// nudges first; everyone else waits a little so one call usually wins.
    private func advanceIfExpired() async {
        guard let state, let gameId,
              state.game.status == .playing,
              let ends = state.game.phaseEndsAt else { return }

        let overdue = serverNow.timeIntervalSince(ends)
        let grace: TimeInterval = state.me.isHost ? 0.3 : 2.5
        guard overdue >= grace,
              !advanceInFlight,
              Date().timeIntervalSince(lastAdvanceAttempt) > 3 else { return }

        advanceInFlight = true
        lastAdvanceAttempt = Date()
        defer { advanceInFlight = false }

        do {
            let fresh = try await service.advanceGame(gameId: gameId)
            apply(fresh)
        } catch is CancellationError {
        } catch let error as GameServiceError where error.meansSessionIsGone {
            clearSession(message: "The room was closed.")
        } catch {
            // transient
        }
    }
}
