//
//  GameModels.swift
//  PhotoCards
//
//  Plain value types mirroring the JSON returned by the Supabase RPCs in
//  supabase/schema.sql (get_game_state and friends). The server is the
//  source of truth; these are read-only snapshots.
//

import Foundation

// MARK: - Enums

enum GameMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case classic
    case vote
    case rapid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .vote: return "Vote"
        case .rapid: return "Rapid Fire"
        }
    }

    var subtitle: String {
        switch self {
        case .classic: return "One judge picks the best photo each round."
        case .vote: return "Everyone votes. Most votes wins the round."
        case .rapid: return "Short timers. Blink and you miss it."
        }
    }

    var icon: String {
        switch self {
        case .classic: return "hand.thumbsup.fill"
        case .vote: return "checkmark.seal.fill"
        case .rapid: return "bolt.fill"
        }
    }
}

enum GamePhase: String, Codable, Sendable {
    case lobby
    case choosing
    case judging
    case roundResults = "round_results"
    case gameOver = "game_over"
}

enum GameStatus: String, Codable, Sendable {
    case lobby
    case playing
    case finished
}

// MARK: - State snapshot

struct GameInfo: Codable, Equatable, Sendable {
    let id: UUID
    let roomCode: String
    let hostId: UUID
    let status: GameStatus
    let phase: GamePhase
    let mode: GameMode
    let isPublic: Bool
    let maxPlayers: Int
    let maxRounds: Int
    let targetScore: Int
    let roundTimerSeconds: Int
    let judgeTimerSeconds: Int
    let resultsSeconds: Int
    let handSize: Int
    let refreshesPerPlayer: Int
    let currentRound: Int
    let currentJudgePlayerId: UUID?
    let winnerPlayerId: UUID?
    let phaseEndsAt: Date?
    let serverTime: Date
    let version: Int
    let promptPacks: [String]
    let promptPackSlugs: [String]
    let customPrompts: [String]
    let customPromptCount: Int
}

struct PlayerInfo: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let userId: UUID
    let username: String
    let score: Int
    let isReady: Bool
    let isHost: Bool
    let isConnected: Bool
    let isJudge: Bool
    let joinedAt: Date
    let hasSubmitted: Bool
    let hasVoted: Bool
}

struct MeInfo: Codable, Equatable, Sendable {
    let playerId: UUID
    let userId: UUID
    let username: String
    let isHost: Bool
    let isJudge: Bool
    let refreshesUsed: Int
    let hasSubmitted: Bool
    let myVoteSubmissionId: UUID?
}

struct RoundInfo: Codable, Equatable, Sendable {
    let id: UUID
    let roundNumber: Int
    let judgePlayerId: UUID?
    let judgeUsername: String?
    let promptText: String
    let winnerSubmissionId: UUID?
    let startedAt: Date
    let submissionCount: Int
    let voteCount: Int
}

struct HandCard: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let photoId: UUID
    let imageUrl: URL
    let thumbnailUrl: URL
    let position: Int
}

struct SubmissionInfo: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let photoId: UUID
    let imageUrl: URL
    let thumbnailUrl: URL
    let isWinner: Bool
    let isMine: Bool
    let playerId: UUID?
    let username: String?
    let voteCount: Int?
}

struct Highlight: Codable, Identifiable, Equatable, Sendable {
    let roundNumber: Int
    let promptText: String
    let imageUrl: URL
    let thumbnailUrl: URL
    let username: String

    var id: Int { roundNumber }
}

struct GameState: Codable, Equatable, Sendable {
    let game: GameInfo
    let me: MeInfo
    let players: [PlayerInfo]
    let round: RoundInfo?
    let hand: [HandCard]
    let submissions: [SubmissionInfo]
    let highlights: [Highlight]
}

extension GameState {
    /// Players sorted by score (ties keep join order).
    var leaderboard: [PlayerInfo] {
        players.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.joinedAt < rhs.joinedAt
        }
    }

    var winner: PlayerInfo? {
        if let id = game.winnerPlayerId, let player = players.first(where: { $0.id == id }) {
            return player
        }
        return leaderboard.first
    }

    var winningSubmission: SubmissionInfo? {
        submissions.first(where: { $0.isWinner })
    }

    var judge: PlayerInfo? {
        guard let id = game.currentJudgePlayerId else { return nil }
        return players.first(where: { $0.id == id })
    }

    /// Players expected to submit this round (everyone except the judge).
    var submitters: [PlayerInfo] {
        players.filter { !$0.isJudge }
    }

    var isVoteMode: Bool { game.mode == .vote }

    var refreshesLeft: Int {
        max(0, game.refreshesPerPlayer - me.refreshesUsed)
    }
}

// MARK: - Inputs

struct GameSettings: Equatable, Sendable {
    var mode: GameMode = .classic
    var isPublic: Bool = false
    var maxPlayers: Int = 8
    var maxRounds: Int = 8
    var targetScore: Int = 5
    var roundTimerSeconds: Int = 60
    var packSlugs: [String] = []
    var customPrompts: [String] = []

    static let timerOptions: [Int] = [30, 45, 60, 90, 120]
    static let rapidTimerSeconds = 15
}

// MARK: - Lists

struct PublicGameSummary: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let roomCode: String
    let mode: GameMode
    let maxPlayers: Int
    let playerCount: Int
    let hostUsername: String?
    let createdAt: Date
}

struct PromptPack: Codable, Identifiable, Hashable, Sendable {
    let slug: String
    let name: String
    let description: String?
    let isDefault: Bool
    let promptCount: Int

    var id: String { slug }
}

struct PromptItem: Codable, Identifiable, Equatable, Sendable {
    let text: String
    let category: String

    var id: String { text }
}

struct BlockedUser: Codable, Identifiable, Equatable, Sendable {
    let userId: UUID
    let username: String
    let blockedAt: Date

    var id: UUID { userId }
}

// MARK: - Errors

struct GameServiceError: LocalizedError, Equatable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }

    /// True when the server says the room no longer exists or we are not in it.
    var meansSessionIsGone: Bool {
        let lower = message.lowercased()
        return lower.contains("game not found") || lower.contains("not in this game")
    }
}

// MARK: - Date parsing

/// Postgres returns timestamps like "2026-09-08T18:53:12.364421+00:00".
/// Foundation's ISO8601 formatter only accepts three fractional digits, so
/// normalise first.
enum SupabaseDate {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let whole: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ raw: String) -> Date? {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if value.hasSuffix("+00") { value += ":00" }

        let hasZone = value.hasSuffix("Z") || value.range(of: #"[+-]\d{2}:\d{2}$"#, options: .regularExpression) != nil
        if !hasZone { value += "Z" }

        if let dot = value.firstIndex(of: "."),
           let zoneStart = value[value.index(after: dot)...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            let digits = value[value.index(after: dot)..<zoneStart]
            let normalised = String((digits + "000").prefix(3))
            let rebuilt = String(value[..<dot]) + "." + normalised + String(value[zoneStart...])
            return fractional.date(from: rebuilt)
        }
        return whole.date(from: value) ?? fractional.date(from: value)
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = SupabaseDate.parse(raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date: \(raw)")
            }
            return date
        }
        return decoder
    }
}
