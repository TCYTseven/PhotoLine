//
//  AuthRemoteDataSource.swift
//  Authentication
//
//


// AuthDataSources.swift
// Authentication module

import Foundation

protocol AuthRemoteDataSource {
    func authenticateWithApple(token: String, nonce: String?, userData: [String: Any]?) async throws -> AuthDto.Response
    func authenticateAnonymously() async throws -> AuthDto.Response
    func refreshToken(token: String) async throws -> AuthDto.Response
    /// The SDK's stored session (refreshed first when the access token has
    /// expired). With `validateWithServer`, also asks the server whether the
    /// user still exists; a rejected session is dropped locally.
    func currentSession(validateWithServer: Bool) async throws -> AuthDto.Response
    func logout(token: String) async throws
    func deleteAccount(token: String) async throws
}

protocol AuthLocalDataSource {
    func saveToken(_ token: AuthModel.AuthToken) async throws
    func getToken() async -> AuthModel.AuthToken?
    func clearToken() async throws
}