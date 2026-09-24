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

    /// The sign-in currently running, if any. The launch `.task`, the Retry
    /// button, the reconnect retry and the post-deletion `userLoggedOut`
    /// event can overlap; coalescing keeps a single guest sign-in in flight
    /// so we never create two anonymous users (and orphan one).
    /// Failures stay in `.failed` with a Retry button; nothing here loops.
    private var bootstrapTask: Task<Void, Never>?

    func bootstrap() async {
        if let running = bootstrapTask {
            await running.value
            return
        }
        let task = Task { await self.performBootstrap() }
        bootstrapTask = task
        await task.value
        bootstrapTask = nil
    }

    private func performBootstrap() async {
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
