//
//  AuthRepositoryImpl.swift
//  Authentication
//
//


import Foundation
import Factory
import Common
import Events

class AuthRepositoryImpl: AuthRepository {
    // Inject data sources
    @Injected(\.authRemoteDataSource) private var remoteDataSource: AuthRemoteDataSource
    @Injected(\.authLocalDataSource) private var localDataSource: AuthLocalDataSource
    // Lazy: the guest-only app never shows social sign-in, so don't build these.
    @LazyInjected(\.appleAuthProvider) private var appleProvider: AppleAuthProvider
    @LazyInjected(\.googleAuthProvider) private var googleProvider: GoogleAuthProvider
    @Injected(\.eventViewModel) private var eventViewModel: EventViewModel
    
    // MARK: - Social Sign-in
    
    public func signInWithApple() async throws -> AuthModel.AuthToken {
        do {
            // 1. Get Apple credentials
            let appleResult = try await appleProvider.authenticate()
            
            // 2. Exchange with backend for token
            let tokenDto = try await remoteDataSource.authenticateWithApple(
                token: appleResult.token,
                nonce: appleResult.nonce,
                userData: appleResult.userData
            )
            
            // 3. Create and save token
            let token = tokenDto.toCore
            try? await localDataSource.saveToken(token)
            
            // 4. Emit signed in event
            await emit(.userLoggedIn)
            
            return token
        } catch let error as NSError {
            switch error.domain {
            case "com.apple.authenticationservices":
                throw AuthError.userCancelled
            default:
                throw AuthError.authProviderError(error)
            }
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.unknown(error)
        }
    }
    
    public func signInWithGoogle() async throws -> AuthModel.AuthToken {
        do {
            // 1. Get Google credentials
            let googleResult = try await googleProvider.authenticate()

            // 2. Exchange with backend for token
            let tokenDto = try await remoteDataSource.authenticateWithGoogle(
                token: googleResult.token,
                nonce: googleResult.nonce,
                userData: googleResult.userData
            )

            // 3. Create and save token
            let token = tokenDto.toCore
            try? await localDataSource.saveToken(token)

            // 4. Emit signed in event
            await emit(.userLoggedIn)

            return token
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.unknown(error)
        }
    }

    public func signInAnonymously() async throws -> AuthModel.AuthToken {
        // 0. Reuse a stored guest session instead of minting a second identity.
        //    If it could not be refreshed only because we are offline, fail
        //    with the network error rather than replacing the player's guest
        //    (and their active game) the moment connectivity flickers back.
        do {
            let existing = try await remoteDataSource.currentSession(validateWithServer: false).toCore
            try? await localDataSource.saveToken(existing)
            await emit(.userLoggedIn)
            return existing
        } catch let error as AuthError {
            if case .networkError = error {
                throw error
            }
            // No session, or a dead one: fall through and create a new guest.
        } catch {
            // Fall through and create a new guest.
        }

        do {
            // 1. Sign in anonymously via Supabase (the SDK stores the session)
            let tokenDto = try await remoteDataSource.authenticateAnonymously()

            // 2. Mirror it locally. The SDK session is the source of truth, so a
            //    keychain write failure must not fail a sign-in that succeeded.
            let token = tokenDto.toCore
            try? await localDataSource.saveToken(token)

            // 3. Emit signed in event
            await emit(.userLoggedIn)

            return token
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.unknown(error)
        }
    }

    // MARK: - Token Management

    /// The current session, refreshed if its access token expired, or nil when
    /// there is no usable session.
    public func getCurrentToken() async -> AuthModel.AuthToken? {
        await loadSession(validateWithServer: false)
    }

    public func refreshToken() async throws -> AuthModel.AuthToken {
        let storedRefreshToken = await localDataSource.getToken()?.refreshToken ?? ""

        do {
            let tokenDto = try await remoteDataSource.refreshToken(token: storedRefreshToken)
            let newToken = tokenDto.toCore
            try? await localDataSource.saveToken(newToken)
            return newToken
        } catch {
            throw AuthError.refreshFailed
        }
    }

    /// Reads the Supabase SDK's session rather than the local mirror: the SDK
    /// session is what every RPC is authorized with, so the two can never
    /// disagree about whether the player is signed in. A missing, corrupted or
    /// dead session (e.g. a keychain restored after reinstall for a user that
    /// no longer exists) yields nil, and the caller starts a fresh guest.
    private func loadSession(validateWithServer: Bool) async -> AuthModel.AuthToken? {
        do {
            let token = try await remoteDataSource.currentSession(validateWithServer: validateWithServer).toCore
            try? await localDataSource.saveToken(token)
            return token
        } catch {
            if let authError = error as? AuthError, case .networkError = authError {
                // Keep the mirror; the session may still be good once online.
            } else {
                try? await localDataSource.clearToken()
            }
            return nil
        }
    }

    // MARK: - Session Management

    public func logout() async throws {
        // Notify the server when possible, but always finish the local logout.
        do {
            try await remoteDataSource.logout(token: "")
        } catch {
            // Ignored: the local state is cleared regardless.
        }

        try? await localDataSource.clearToken()

        // Always emit logout event to update UI state
        await emit(.userLoggedOut)
    }

    public func deleteAccount() async throws {
        // Authorized by the SDK session; throws if there is none or the RPC fails.
        try await remoteDataSource.deleteAccount(token: "")

        // The account is gone server-side. A local cleanup failure must not
        // surface as "delete failed" (and must not block the fresh guest).
        try? await localDataSource.clearToken()

        // Emit logout event (the app signs in a fresh guest on this)
        await emit(.userLoggedOut)
    }

    // MARK: - Status Check

    public func isAuthenticated() async -> Bool {
        guard let token = await loadSession(validateWithServer: true) else {
            return false
        }

        return !token.isExpired
    }

    public func getCurrentUser() async -> AuthModel.User? {
        guard let token = await getCurrentToken() else {
            return nil
        }

        return token.user
    }

    public func isAnonymous() async -> Bool {
        guard let user = await getCurrentUser() else { return false }
        return user.isAnonymous
    }

    // MARK: - Events

    /// Observers (RootViewModel) drive UI state, so deliver on the main actor.
    private func emit(_ event: EventViewModel.Event) async {
        let events = eventViewModel
        await MainActor.run {
            events.emit(event)
        }
    }
}
