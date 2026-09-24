//
//  AuthUtils.swift
//  Authentication
//
//

import Foundation
import CryptoKit

struct AuthUtils {
    // Adapted from https://firebase.google.com/docs/auth/ios/apple
    static func randomNonceString(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: max(length, 1))
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            // Fall back to the system CSPRNG instead of crashing.
            var generator = SystemRandomNumberGenerator()
            randomBytes = randomBytes.map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &generator) }
        }

        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

        let nonce = randomBytes.map { byte in
            // Pick a random character from the set, wrapping around if needed.
            charset[Int(byte) % charset.count]
        }

        return String(nonce)
    }

    @available(iOS 13, *)
    static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            return String(format: "%02x", $0)
        }.joined()

        return hashString
    }
}
