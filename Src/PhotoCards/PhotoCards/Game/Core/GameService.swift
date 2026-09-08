//
//  GameService.swift
//  PhotoCards
//
//  Abstraction over the multiplayer backend. The UI only talks to this
//  protocol, so the transport (Supabase today) can be swapped or mocked.
//

import Foundation

protocol GameService: Sendable {
    // Rooms
    func createGame(username: String, settings: GameSettings) async throws -> GameState
    func updateSettings(gameId: UUID, settings: GameSettings) async throws -> GameState
    func joinGame(code: String, username: String) async throws -> GameState
    func activeGame() async throws -> GameState?
    func gameState(gameId: UUID) async throws -> GameState
    func leaveGame(gameId: UUID) async throws
    func listPublicGames() async throws -> [PublicGameSummary]

    // Lobby
    func setReady(gameId: UUID, ready: Bool) async throws -> GameState
    func startGame(gameId: UUID) async throws -> GameState

    // Rounds
    func submitPhoto(gameId: UUID, photoId: UUID) async throws -> GameState
    func refreshHand(gameId: UUID) async throws -> GameState
    func pickWinner(gameId: UUID, submissionId: UUID) async throws -> GameState
    func castVote(gameId: UUID, submissionId: UUID) async throws -> GameState
    func advanceGame(gameId: UUID) async throws -> GameState
    func restartGame(gameId: UUID) async throws -> GameState

    // Content
    func listPromptPacks() async throws -> [PromptPack]
    func listPrompts(packSlug: String) async throws -> [PromptItem]

    // Profile & moderation
    func updateDisplayName(_ name: String) async throws
    func reportContent(reason: String, details: String?, gameId: UUID?, reportedUserId: UUID?, photoId: UUID?) async throws
    func blockUser(userId: UUID) async throws
    func unblockUser(userId: UUID) async throws
    func listBlockedUsers() async throws -> [BlockedUser]

    /// Emits whenever the server bumps the game's version. Terminating the
    /// stream unsubscribes.
    func observeGame(gameId: UUID) -> AsyncStream<Void>
}
