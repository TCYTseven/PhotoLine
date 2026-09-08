//
//  RootViewModel.swift
//  PhotoCards
//
//  Guest sign-in. Players never see a login screen: on first launch we
//  create an anonymous Supabase session and reuse it afterwards. Deleting
//  the account (Settings) signs out and creates a brand-new guest.
//

import Foundation
import SwiftUI
import Factory
import Common
import Events
import Authentication

@MainActor
final class RootViewModel: ObservableObject {

    enum LaunchState: Equatable {
        case loading
        case unconfigured
        case ready
        case failed(String)
    }

    @Published private(set) var launchState: LaunchState = .loading
    /// Incremented every time the account is deleted so views can reset.
    @Published private(set) var accountDeletionCount = 0

    @Injected(\.authRepository) private var authRepository: AuthRepository
    @Injected(\.eventViewModel) private var eventViewModel: EventViewModel

    init() {
        eventViewModel.subscribe(for: self, to: [.authentication]) { [weak self] event in
            guard event == .userLoggedOut else { return }
            Task { @MainActor in
                guard let self else { return }
                self.accountDeletionCount += 1
                await self.bootstrap()
            }
        }
    }

    deinit {
        Container.shared.eventViewModel().unsubscribe(self)
    }

    func bootstrap() async {
        guard AppConfiguration.Supabase.isConfigured else {
            launchState = .unconfigured
            return
        }

        launchState = .loading

        if await authRepository.isAuthenticated() {
            launchState = .ready
            return
        }

        do {
            _ = try await authRepository.signInAnonymously()
            launchState = .ready
        } catch let error as AuthError {
            launchState = .failed(friendlyMessage(for: error))
        } catch {
            launchState = .failed("Check your internet connection and try again.")
        }
    }

    private func friendlyMessage(for error: AuthError) -> String {
        switch error {
        case .networkError:
            return "Check your internet connection and try again."
        default:
            return "We couldn't start a guest session. Please try again in a moment."
        }
    }
}
