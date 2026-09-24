//
//  AuthRemoteDataSourceImpl.swift
//  Authentication
//
//


// AuthRemoteDataSourceImpl.swift
// Authentication module

import Foundation
import Supabase
import Auth
import PostgREST
import os.log

private let logger = Logger(subsystem: "app.photocards.ios.Authentication", category: "AuthRemoteDataSource")

// Typealias to disambiguate from Supabase's Auth.AuthError
typealias SupabaseAuthError = Auth.AuthError

class AuthRemoteDataSourceImpl: AuthRemoteDataSource {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = SupabaseClientService.shared.client) {
        self.supabase = supabase
    }

    func authenticateWithApple(token: String, nonce: String?, userData: [String: Any]?) async throws -> AuthDto.Response {
        logger.debug("Authenticating with Apple")
        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: token,
                    nonce: nonce
                )
            )
            logger.debug("Apple authentication successful. User: \(session.user.id)")
            return mapSessionToResponse(session)
        } catch let error as SupabaseAuthError {
            logger.error("Supabase Apple Auth Error: \(error.localizedDescription)")
            throw mapSupabaseAuthError(error)
        } catch {
            logger.error("Unknown Apple Auth Error: \(error.localizedDescription)")
            throw AuthError.unknown(error)
        }
    }

    func authenticateWithGoogle(token: String, nonce: String?, userData: [String: Any]?) async throws -> AuthDto.Response {
        logger.debug("Authenticating with Google")
        do {
            // Google requires accessToken - get from userData
            let accessToken = userData?["accessToken"] as? String

            let session = try await supabase.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .google,
                    idToken: token,
                    accessToken: accessToken,
                    nonce: nonce
                )
            )
            logger.debug("Google authentication successful. User: \(session.user.id)")
            return mapSessionToResponse(session)
        } catch let error as SupabaseAuthError {
            logger.error("Supabase Google Auth Error: \(error.localizedDescription)")
            throw mapSupabaseAuthError(error)
        } catch {
            logger.error("Unknown Google Auth Error: \(error)")
            throw AuthError.unknown(error)
        }
    }

    func authenticateAnonymously() async throws -> AuthDto.Response {
        logger.debug("Authenticating anonymously")
        do {
            let session = try await supabase.auth.signInAnonymously()
            logger.debug("Anonymous authentication successful. User: \(session.user.id)")
            return mapSessionToResponse(session)
        } catch let error as SupabaseAuthError {
            logger.error("Supabase Anonymous Auth Error: \(error.localizedDescription)")
            throw mapSupabaseAuthError(error)
        } catch {
            logger.error("Unknown Anonymous Auth Error: \(error.localizedDescription)")
            throw mapTransportError(error)
        }
    }

    func refreshToken(token: String) async throws -> AuthDto.Response {
        do {
            let session = try await supabase.auth.refreshSession()
            return mapSessionToResponse(session)
        } catch let error as SupabaseAuthError {
            throw mapSupabaseAuthError(error)
        } catch {
            throw mapTransportError(error)
        }
    }

    func currentSession(validateWithServer: Bool) async throws -> AuthDto.Response {
        do {
            // The SDK keeps the session in the keychain and refreshes it here
            // when the access token has expired. Throws `sessionMissing` on a
            // fresh install, and an API error when the refresh token is dead
            // (revoked, expired, or its user was deleted).
            let session = try await supabase.auth.session

            if validateWithServer {
                do {
                    // Confirms the user still exists server-side. The keychain
                    // survives a reinstall, so a restored session can belong to
                    // a user that has since been deleted.
                    _ = try await supabase.auth.user()
                } catch let error as SupabaseAuthError {
                    logger.info("Stored session rejected by the server; discarding it")
                    try? await supabase.auth.signOut(scope: .local)
                    throw mapSupabaseAuthError(error)
                } catch {
                    // Offline or a transport failure: keep the cached session
                    // rather than replacing the player's guest identity.
                    logger.info("Could not validate session (\(error.localizedDescription)); using cached session")
                }
            }

            return mapSessionToResponse(session)
        } catch let error as AuthError {
            throw error
        } catch let error as SupabaseAuthError {
            throw mapSupabaseAuthError(error)
        } catch {
            throw mapTransportError(error)
        }
    }

    func logout(token: String) async throws {
        do {
            try await supabase.auth.signOut()
        } catch let error as SupabaseAuthError {
            throw mapSupabaseAuthError(error)
        } catch {
            throw mapTransportError(error)
        }
    }

    func deleteAccount(token: String) async throws {
        logger.debug("Deleting account via delete_my_account RPC")
        do {
            // SECURITY DEFINER function defined in supabase/schema.sql. It removes
            // the auth user; every app table cascades from auth.users.
            _ = try await supabase.rpc("delete_my_account").execute()
            // The server-side user is gone; drop the local session too.
            try? await supabase.auth.signOut(scope: .local)
            logger.debug("Account deleted successfully")
        } catch let error as PostgrestError {
            logger.error("delete_my_account failed: \(error.message)")
            throw AuthError.serverError(error.message)
        } catch let error as AuthError {
            throw error
        } catch let error as SupabaseAuthError {
            // No session to authorize the call with.
            throw mapSupabaseAuthError(error)
        } catch {
            logger.error("Unknown error deleting account: \(error.localizedDescription)")
            throw mapTransportError(error)
        }
    }

    // MARK: - Private Helpers

    private func mapSessionToResponse(_ session: Session) -> AuthDto.Response {
        let user = AuthDto.UserDto(
            id: session.user.id.uuidString,
            email: session.user.email ?? "",
            isActive: session.user.emailConfirmedAt != nil,
            isAnonymous: session.user.isAnonymous
        )

        return AuthDto.Response(
            user: user,
            accessToken: session.accessToken,
            accessTokenExpiresAt: Date(timeIntervalSince1970: session.expiresAt),
            refreshToken: session.refreshToken,
            refreshTokenExpiresAt: Date(timeIntervalSince1970: session.expiresAt + 604800) // Add 7 days for refresh token
        )
    }

    /// URLSession failures (offline, timeout, DNS) become `.networkError` so
    /// the app can say "check your connection" instead of a generic failure.
    private func mapTransportError(_ error: Error) -> AuthError {
        if error is URLError || (error as NSError).domain == NSURLErrorDomain {
            return .networkError(error)
        }
        return .unknown(error)
    }

    private func mapSupabaseAuthError(_ error: SupabaseAuthError) -> AuthError {
        switch error {
        case .sessionMissing:
            return .tokenExpired
        default:
            return .unknown(error)
        }
    }
}
