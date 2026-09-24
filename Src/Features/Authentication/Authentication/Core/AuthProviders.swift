//
//  AppleAuthProvider.swift
//  Authentication
//
//


import Foundation

protocol AppleAuthProvider {
    func authenticate() async throws -> AuthModel.AppleAuthResult
}
