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
    /// serverTime - deviceTime, measured at the midpoint of the request that
    /// produced the last snapshot.
    private var serverOffset: TimeInterval = 0
    /// Changes whenever the local session ends or switches to another game.
    /// Every request captures it first and drops its result if it changed,
    /// so a response that raced with "leave" can't resurrect the session.
    private var sessionToken = UUID()
    /// Actions currently running, so a double tap can't send them twice.
    private var inFlightActions: Set<String> = []
    private var busyCount = 0 {
        didSet { isBusy = busyCount > 0 }
    }
    private var refreshInFlight = false
    private var refreshQueued = false
    private var isRestoring = false
    private var isInBackground = false

    private let pollInterval: TimeInterval = 4

    private static let pendingLeaveKey = "GameSessionStore.pendingLeaveGameId"

    /// A game we left locally but couldn't tell the server about (offline).
    /// Retried on the next restore so the room doesn't pull us back in.
    private var pendingLeaveGameId: UUID? {
        get {
            UserDefaults.standard.string(forKey: Self.pendingLeaveKey).flatMap { UUID(uuidString: $0) }
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.uuidString, forKey: Self.pendingLeaveKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.pendingLeaveKey)
            }
        }
    }

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
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

        await flushPendingLeave()

        let token = sessionToken
        let requestedAt = Date()
        let restored: GameState?
        do {
            restored = try await service.activeGame()
        } catch {
            // Offline or backend unreachable: keep whatever we have.
            return
        }
        guard token == sessionToken else { return }

        if let restored, restored.game.id != pendingLeaveGameId {
            apply(restored, requestedAt: requestedAt)
        } else if state != nil {
            // get_my_active_game skips finished games, but the final results
            // screen (and "Play again") must survive a trip to the
            // background. Ask about our own game directly; refresh() ends the
            // session only if the server says it is really gone.
            await refresh()
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            isInBackground = false
            if let gameId {
                if observeTask == nil {
                    startObserving(gameId: gameId)
                }
                Task { await refresh() }
            }
        case .background:
            isInBackground = true
            stopObserving()
        default:
            break
        }
    }

    func clearSession(message: String?) {
        stopObserving()
        state = nil
        sessionToken = UUID()
        infoMessage = message
        // An in-game error has no screen left to show on.
        errorMessage = nil
        serverOffset = 0
        lastAdvanceAttempt = .distantPast
    }

    func dismissInfo() {
        infoMessage = nil
    }

    // MARK: - Actions

    @discardableResult
    func createGame(username: String, settings: GameSettings) async -> Bool {
        await perform("session", startsSession: true) {
            try await self.service.createGame(username: username, settings: settings)
        }
    }

    @discardableResult
    func updateSettings(_ settings: GameSettings) async -> Bool {
        guard let gameId else { return false }
        return await perform("settings") { try await self.service.updateSettings(gameId: gameId, settings: settings) }
    }

    @discardableResult
    func joinGame(code: String, username: String) async -> Bool {
        await perform("session", startsSession: true) {
            try await self.service.joinGame(code: code, username: username)
        }
    }

    /// Leaving always succeeds locally, immediately, even offline. If the
    /// server can't be told now, it is told on the next restore.
    func leaveGame() async {
        guard let gameId else { return }
        pendingLeaveGameId = gameId
        clearSession(message: nil)
        do {
            try await service.leaveGame(gameId: gameId)
            if pendingLeaveGameId == gameId { pendingLeaveGameId = nil }
        } catch {
            // Kept in pendingLeaveGameId; retried by restoreActiveGame().
        }
    }

    @discardableResult
    func setReady(_ ready: Bool) async -> Bool {
        guard let gameId else { return false }
        return await perform("ready") { try await self.service.setReady(gameId: gameId, ready: ready) }
    }

    @discardableResult
    func startGame() async -> Bool {
        guard let gameId else { return false }
        return await perform("start") { try await self.service.startGame(gameId: gameId) }
    }

    @discardableResult
    func submitPhoto(photoId: UUID) async -> Bool {
        guard let gameId, state?.me.hasSubmitted != true else { return false }
        return await perform("submit") { try await self.service.submitPhoto(gameId: gameId, photoId: photoId) }
    }

    @discardableResult
    func refreshHand() async -> Bool {
        guard let gameId else { return false }
        return await perform("refreshHand") { try await self.service.refreshHand(gameId: gameId) }
    }

    @discardableResult
    func pickWinner(submissionId: UUID) async -> Bool {
        guard let gameId else { return false }
        return await perform("pickWinner") { try await self.service.pickWinner(gameId: gameId, submissionId: submissionId) }
    }

    @discardableResult
    func castVote(submissionId: UUID) async -> Bool {
        guard let gameId else { return false }
        return await perform("vote") { try await self.service.castVote(gameId: gameId, submissionId: submissionId) }
    }

    @discardableResult
    func playAgain() async -> Bool {
        guard let gameId else { return false }
        return await perform("restart") { try await self.service.restartGame(gameId: gameId) }
    }

    func report(reason: String, details: String?, reportedUserId: UUID?, photoId: UUID?) async -> Bool {
        do {
            try await service.reportContent(reason: reason, details: details, gameId: gameId, reportedUserId: reportedUserId, photoId: photoId)
            return true
        } catch is CancellationError {
            return false
        } catch {
            showError(error)
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
            showError(error)
            return false
        }
    }

    /// Re-fetches the snapshot. Silent on transient failure (polling calls
    /// this a lot). Overlapping calls are coalesced into one follow-up fetch.
    func refresh() async {
        guard state != nil else { return }
        if refreshInFlight {
            refreshQueued = true
            return
        }
        refreshInFlight = true
        defer { refreshInFlight = false }

        repeat {
            refreshQueued = false
            guard let gameId else { return }
            let token = sessionToken
            let requestedAt = Date()
            do {
                let fresh = try await service.gameState(gameId: gameId)
                guard token == sessionToken else { return }
                apply(fresh, requestedAt: requestedAt)
            } catch is CancellationError {
                return
            } catch let error as GameServiceError where error.meansSessionIsGone {
                guard token == sessionToken else { return }
                clearSession(message: error.sessionEndedMessage)
                return
            } catch {
                // transient; the next poll will retry
                return
            }
        } while refreshQueued
    }

    // MARK: - Internals

    /// Runs one server action. `key` de-duplicates concurrent taps of the
    /// same action; `startsSession` marks create/join, whose result replaces
    /// whatever session there was.
    private func perform(
        _ key: String,
        startsSession: Bool = false,
        _ operation: @escaping () async throws -> GameState
    ) async -> Bool {
        guard !inFlightActions.contains(key) else { return false }
        inFlightActions.insert(key)
        busyCount += 1
        defer {
            inFlightActions.remove(key)
            busyCount -= 1
        }

        let token = sessionToken
        let requestedAt = Date()
        do {
            let fresh = try await operation()
            if startsSession {
                pendingLeaveGameId = nil
            } else if token != sessionToken {
                // We left (or switched games) while this was in flight.
                return false
            }
            apply(fresh, requestedAt: requestedAt)
            return state?.game.id == fresh.game.id
        } catch is CancellationError {
            return false
        } catch let error as GameServiceError where error.meansSessionIsGone && !startsSession {
            if token == sessionToken {
                clearSession(message: error.sessionEndedMessage)
            }
            return false
        } catch {
            if startsSession || token == sessionToken {
                showError(error)
            }
            return false
        }
    }

    /// In a game the error goes to GameSessionView's alert; outside one
    /// (create / join / browse) only RootView's info alert is on screen.
    private func showError(_ error: Error) {
        let message = (error as? GameServiceError)?.message
            ?? "Something went wrong. Please try again."
        if state == nil {
            infoMessage = message
        } else {
            errorMessage = message
        }
    }

    private func apply(_ fresh: GameState, requestedAt: Date) {
        // Ignore stale snapshots that raced with a newer one.
        if let current = state, current.game.id == fresh.game.id, fresh.game.version < current.game.version {
            return
        }

        // get_game_state still answers for a player who left mid-game (their
        // row is kept with left_at set) but lists only players still in it.
        // Missing from the list means we left, e.g. from another device.
        guard fresh.players.contains(where: { $0.id == fresh.me.playerId }) else {
            clearSession(message: "You're no longer in this room.")
            return
        }

        let received = Date()
        let midpoint = requestedAt.addingTimeInterval(received.timeIntervalSince(requestedAt) / 2)
        serverOffset = fresh.game.serverTime.timeIntervalSince(midpoint)
        now = received

        let switchedGame = state?.game.id != fresh.game.id
        state = fresh

        if switchedGame {
            sessionToken = UUID()
            lastAdvanceAttempt = .distantPast
            if !isInBackground { startObserving(gameId: fresh.game.id) }
        } else if observeTask == nil && !isInBackground {
            startObserving(gameId: fresh.game.id)
        }
    }

    private func startObserving(gameId: UUID) {
        stopObserving()
        let service = self.service

        // Realtime: refresh on every change. The stream ends if the channel
        // fails or is closed by the server; re-subscribe with backoff.
        observeTask = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                for await _ in service.observeGame(gameId: gameId) {
                    failures = 0
                    guard let self else { return }
                    await self.refresh()
                }
                if Task.isCancelled { break }
                failures += 1
                let delay = min(30, 2 * Double(failures))
                try? await Task.sleep(for: .seconds(delay))
            }
        }

        // Polling fallback for missed realtime events and deleted rooms
        // (a DELETE never reaches an UPDATE listener).
        let interval = pollInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
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

        let token = sessionToken
        let requestedAt = Date()
        do {
            let fresh = try await service.advanceGame(gameId: gameId)
            guard token == sessionToken else { return }
            apply(fresh, requestedAt: requestedAt)
        } catch is CancellationError {
        } catch let error as GameServiceError where error.meansSessionIsGone {
            guard token == sessionToken else { return }
            clearSession(message: error.sessionEndedMessage)
        } catch {
            // transient
        }
    }

    private func flushPendingLeave() async {
        guard let pending = pendingLeaveGameId else { return }
        do {
            try await service.leaveGame(gameId: pending)
            if pendingLeaveGameId == pending { pendingLeaveGameId = nil }
        } catch {
            // Still offline; try again next time.
        }
    }
}
