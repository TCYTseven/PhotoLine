//
//  SupabaseGameService.swift
//  PhotoCards
//
//  GameService backed by the Postgres functions in supabase/schema.sql.
//  Every call is an RPC; realtime is a single subscription on the game row.
//

import Foundation
import Supabase
import Authentication

final class SupabaseGameService: GameService, @unchecked Sendable {

    private let client: SupabaseClient
    private let decoder = SupabaseDate.makeDecoder()

    init(client: SupabaseClient = SupabaseClientService.shared.client) {
        self.client = client
    }

    // MARK: - Rooms

    func createGame(username: String, settings: GameSettings) async throws -> GameState {
        try await call("create_game", params: CreateGameParams(username: username, gameId: nil, settings: settings))
    }

    func updateSettings(gameId: UUID, settings: GameSettings) async throws -> GameState {
        try await call("update_game_settings", params: CreateGameParams(username: nil, gameId: gameId, settings: settings))
    }

    func joinGame(code: String, username: String) async throws -> GameState {
        try await call("join_game", params: JoinParams(roomCode: code, username: username))
    }

    func activeGame() async throws -> GameState? {
        let data = try await rawCall("get_my_active_game", params: NoParams())
        let trimmed = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "null" { return nil }
        return try decode(GameState.self, from: data)
    }

    func gameState(gameId: UUID) async throws -> GameState {
        try await call("get_game_state", params: GameIdParams(gameId: gameId))
    }

    func leaveGame(gameId: UUID) async throws {
        _ = try await rawCall("leave_game", params: GameIdParams(gameId: gameId))
    }

    func listPublicGames() async throws -> [PublicGameSummary] {
        try await call("list_public_games", params: NoParams())
    }

    // MARK: - Lobby

    func setReady(gameId: UUID, ready: Bool) async throws -> GameState {
        try await call("set_ready", params: ReadyParams(gameId: gameId, ready: ready))
    }

    func startGame(gameId: UUID) async throws -> GameState {
        try await call("start_game", params: GameIdParams(gameId: gameId))
    }

    // MARK: - Rounds

    func submitPhoto(gameId: UUID, photoId: UUID) async throws -> GameState {
        try await call("submit_photo", params: PhotoParams(gameId: gameId, photoId: photoId))
    }

    func refreshHand(gameId: UUID) async throws -> GameState {
        try await call("refresh_hand", params: GameIdParams(gameId: gameId))
    }

    func pickWinner(gameId: UUID, submissionId: UUID) async throws -> GameState {
        try await call("pick_winner", params: SubmissionParams(gameId: gameId, submissionId: submissionId))
    }

    func castVote(gameId: UUID, submissionId: UUID) async throws -> GameState {
        try await call("cast_vote", params: SubmissionParams(gameId: gameId, submissionId: submissionId))
    }

    func advanceGame(gameId: UUID) async throws -> GameState {
        try await call("advance_game", params: GameIdParams(gameId: gameId))
    }

    func restartGame(gameId: UUID) async throws -> GameState {
        try await call("restart_game", params: GameIdParams(gameId: gameId))
    }

    // MARK: - Content

    func listPromptPacks() async throws -> [PromptPack] {
        try await call("list_prompt_packs", params: NoParams())
    }

    func listPrompts(packSlug: String) async throws -> [PromptItem] {
        try await call("list_prompts", params: PackParams(packSlug: packSlug))
    }

    // MARK: - Profile & moderation

    func updateDisplayName(_ name: String) async throws {
        _ = try await rawCall("update_display_name", params: NameParams(name: name))
    }

    func reportContent(reason: String, details: String?, gameId: UUID?, reportedUserId: UUID?, photoId: UUID?) async throws {
        _ = try await rawCall("report_content", params: ReportParams(
            reason: reason, details: details, gameId: gameId, reportedUserId: reportedUserId, photoId: photoId
        ))
    }

    func blockUser(userId: UUID) async throws {
        _ = try await rawCall("block_user", params: UserParams(userId: userId))
    }

    func unblockUser(userId: UUID) async throws {
        _ = try await rawCall("unblock_user", params: UserParams(userId: userId))
    }

    func listBlockedUsers() async throws -> [BlockedUser] {
        try await call("list_blocked_users", params: NoParams())
    }

    // MARK: - Realtime

    /// Yields once every time the channel becomes subscribed (the first
    /// join and every automatic rejoin after a dropped socket, so the caller
    /// can catch up on anything it missed) and once per UPDATE of the game
    /// row. Finishes when the subscription fails or the server closes the
    /// channel; the caller is expected to observe again after a delay.
    func observeGame(gameId: UUID) -> AsyncStream<Void> {
        let client = self.client
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            // Unique topic per observation: the client caches channels by
            // topic, and re-using a topic that is still tearing down would
            // silently drop the new listener.
            let topic = "game-\(gameId.uuidString.lowercased())-\(UUID().uuidString.lowercased())"
            let channel = client.channel(topic)
            // Listeners must be registered before subscribing.
            let updates = channel.postgresChange(
                UpdateAction.self,
                schema: "public",
                table: "games",
                filter: .eq("id", value: gameId.uuidString.lowercased())
            )
            let statuses = channel.statusChange

            let updatesTask = Task {
                for await _ in updates {
                    continuation.yield(())
                }
            }

            let statusTask = Task {
                var wasSubscribed = false
                for await status in statuses {
                    switch status {
                    case .subscribed:
                        wasSubscribed = true
                        continuation.yield(())
                    case .unsubscribed:
                        // Closed by the server, or a rejoin failed: the SDK
                        // will not retry this channel on its own.
                        if wasSubscribed {
                            continuation.finish()
                            return
                        }
                    default:
                        break
                    }
                }
            }

            let subscribeTask = Task {
                do {
                    try await channel.subscribeWithError()
                    // subscribeWithError can return without joining when the
                    // socket could not connect.
                    if channel.status != .subscribed {
                        continuation.finish()
                    }
                } catch {
                    #if DEBUG
                    print("[SupabaseGameService] realtime subscribe failed: \(error)")
                    #endif
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                subscribeTask.cancel()
                updatesTask.cancel()
                statusTask.cancel()
                // removeChannel unsubscribes and evicts the channel from the cache.
                Task { await client.removeChannel(channel) }
            }
        }
    }

    // MARK: - Plumbing

    private func call<T: Decodable>(_ function: String, params: some Encodable & Sendable) async throws -> T {
        let data = try await rawCall(function, params: params)
        return try decode(T.self, from: data)
    }

    private func rawCall(_ function: String, params: some Encodable & Sendable) async throws -> Data {
        do {
            let response: PostgrestResponse<Void> = try await client.rpc(function, params: params).execute()
            return response.data
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as PostgrestError {
            throw Self.friendly(error)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw GameServiceError("Couldn't reach the server. Check your connection and try again.")
        } catch let error as HTTPError {
            #if DEBUG
            print("[SupabaseGameService] \(function) HTTP \(error.response.statusCode)")
            #endif
            if error.response.statusCode == 401 {
                throw GameServiceError("Your session expired. Please try again.")
            }
            if error.response.statusCode >= 500 {
                throw GameServiceError("The server is busy right now. Please try again in a moment.")
            }
            throw GameServiceError("Something went wrong. Please try again.")
        } catch {
            if Task.isCancelled { throw CancellationError() }
            #if DEBUG
            print("[SupabaseGameService] \(function) failed: \(error)")
            #endif
            throw GameServiceError("Something went wrong. Please try again.")
        }
    }

    /// `raise exception` in schema.sql (SQLSTATE P0001) carries a message
    /// written for players; everything else (permission errors, constraint
    /// races, JWT problems) is technical and gets a generic message.
    private static func friendly(_ error: PostgrestError) -> GameServiceError {
        if error.code == "P0001" {
            return GameServiceError(error.message)
        }
        #if DEBUG
        print("[SupabaseGameService] postgrest error \(error.code ?? "?"): \(error.message)")
        #endif
        if let code = error.code, code.hasPrefix("PGRST3") {
            return GameServiceError("Your session expired. Please try again.")
        }
        return GameServiceError("Something went wrong. Please try again.")
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            #if DEBUG
            print("[SupabaseGameService] decode failure: \(error)")
            #endif
            throw GameServiceError("The server sent something unexpected. Please try again.")
        }
    }
}

// MARK: - RPC parameter payloads (keys match the SQL argument names)

private struct NoParams: Encodable, Sendable {}

private struct GameIdParams: Encodable, Sendable {
    let gameId: UUID
    enum CodingKeys: String, CodingKey { case gameId = "p_game_id" }
}

private struct JoinParams: Encodable, Sendable {
    let roomCode: String
    let username: String
    enum CodingKeys: String, CodingKey {
        case roomCode = "p_room_code"
        case username = "p_username"
    }
}

private struct ReadyParams: Encodable, Sendable {
    let gameId: UUID
    let ready: Bool
    enum CodingKeys: String, CodingKey {
        case gameId = "p_game_id"
        case ready = "p_ready"
    }
}

private struct PhotoParams: Encodable, Sendable {
    let gameId: UUID
    let photoId: UUID
    enum CodingKeys: String, CodingKey {
        case gameId = "p_game_id"
        case photoId = "p_photo_id"
    }
}

private struct SubmissionParams: Encodable, Sendable {
    let gameId: UUID
    let submissionId: UUID
    enum CodingKeys: String, CodingKey {
        case gameId = "p_game_id"
        case submissionId = "p_submission_id"
    }
}

private struct PackParams: Encodable, Sendable {
    let packSlug: String
    enum CodingKeys: String, CodingKey { case packSlug = "p_pack_slug" }
}

private struct NameParams: Encodable, Sendable {
    let name: String
    enum CodingKeys: String, CodingKey { case name = "p_name" }
}

private struct UserParams: Encodable, Sendable {
    let userId: UUID
    enum CodingKeys: String, CodingKey { case userId = "p_user_id" }
}

private struct ReportParams: Encodable, Sendable {
    let reason: String
    let details: String?
    let gameId: UUID?
    let reportedUserId: UUID?
    let photoId: UUID?
    enum CodingKeys: String, CodingKey {
        case reason = "p_reason"
        case details = "p_details"
        case gameId = "p_game_id"
        case reportedUserId = "p_reported_user_id"
        case photoId = "p_photo_id"
    }
}

/// Shared by create_game (username set) and update_game_settings (gameId set).
private struct CreateGameParams: Encodable, Sendable {
    let username: String?
    let gameId: UUID?
    let settings: GameSettings

    enum CodingKeys: String, CodingKey {
        case username = "p_username"
        case gameId = "p_game_id"
        case mode = "p_mode"
        case isPublic = "p_is_public"
        case maxPlayers = "p_max_players"
        case maxRounds = "p_max_rounds"
        case targetScore = "p_target_score"
        case roundTimerSeconds = "p_round_timer_seconds"
        case packSlugs = "p_pack_slugs"
        case customPrompts = "p_custom_prompts"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(username, forKey: .username)
        try container.encodeIfPresent(gameId, forKey: .gameId)
        try container.encode(settings.mode.rawValue, forKey: .mode)
        try container.encode(settings.isPublic, forKey: .isPublic)
        try container.encode(settings.maxPlayers, forKey: .maxPlayers)
        try container.encode(settings.maxRounds, forKey: .maxRounds)
        try container.encode(settings.targetScore, forKey: .targetScore)
        try container.encode(settings.roundTimerSeconds, forKey: .roundTimerSeconds)
        try container.encode(settings.packSlugs, forKey: .packSlugs)
        try container.encode(settings.customPrompts, forKey: .customPrompts)
    }
}
