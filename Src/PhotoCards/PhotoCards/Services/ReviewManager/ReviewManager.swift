//
//  ReviewManager.swift
//  PhotoCards
//
//  Asks for an App Store rating at most once, after the player has spent a
//  meaningful amount of time in the app, and only at a calm moment (right
//  after a game ends). The system additionally caps the prompt at three
//  times a year (App Store Review Guideline 5.6.1).
//

import Foundation
import StoreKit
import SwiftUI
import UIKit
import Events
import Factory
import Common

final class ReviewManager: ObservableObject {
    @LazyInjected(\.eventViewModel) private var eventViewModel: EventViewModel

    // MARK: - Constants & Dependencies

    private struct Keys {
        static let accumulatedUsage = "accumulatedUsageTime"
        static let hasReviewed = "userHasReviewed"
    }

    private let userDefaults: UserDefaults

    // Production threshold is 1200 seconds (20 minutes)
    // Debug threshold is 5 seconds for testing
    #if DEBUG
    private let reviewThreshold: TimeInterval = 5
    #else
    private let reviewThreshold: TimeInterval = 1200
    #endif

    // Session tracking
    private var sessionStartDate: Date?

    // MARK: - Initializer

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        subscribeToEvents()
    }

    private func subscribeToEvents() {
        eventViewModel.subscribe(for: self, to: [.appRating]) { [weak self] event in
            if event == .appRatingRequested {
                Task { @MainActor in
                    self?.requestReviewIfEligible()
                }
            }
        }
    }

    deinit {
        eventViewModel.unsubscribe(self)
    }

    // MARK: - Computed Properties

    var userHasReviewed: Bool {
        get { userDefaults.bool(forKey: Keys.hasReviewed) }
        set { userDefaults.set(newValue, forKey: Keys.hasReviewed) }
    }

    private var accumulatedUsage: TimeInterval {
        get { userDefaults.double(forKey: Keys.accumulatedUsage) }
        set { userDefaults.set(newValue, forKey: Keys.accumulatedUsage) }
    }

    // MARK: - Session Management

    func startSession() {
        guard !userHasReviewed else { return }
        sessionStartDate = Date()
        log("Session started")
    }

    /// Banks the time since `startSession()`. Returns true once the usage
    /// threshold has been reached.
    @discardableResult
    func endSession() -> Bool {
        guard !userHasReviewed else { return false }
        if let start = sessionStartDate {
            accumulatedUsage += max(0, Date().timeIntervalSince(start))
            sessionStartDate = nil
            log("Total accumulated usage: \(accumulatedUsage.rounded()) seconds")
        }
        return accumulatedUsage >= reviewThreshold
    }

    // MARK: - Review Request

    /// Automatic prompt: only once, only after enough play time, only while
    /// the app is in the foreground. Safe to call often.
    @MainActor
    func requestReviewIfEligible() {
        guard !userHasReviewed else { return }
        // Bank the running session so far without ending it.
        if endSession() {
            // Give the game screen time to finish dismissing first.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.2))
                self?.requestReview()
            }
        }
        startSession()
    }

    /// Shows the system rating prompt. The system decides whether it
    /// actually appears (it is capped per year and never shows on TestFlight).
    @MainActor
    func requestReview() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            log("No active window scene; not requesting a review")
            return
        }
        log("Requesting review...")
        AppStore.requestReview(in: windowScene)
        resetTracking()
    }

    /// For an explicit "Rate PhotoCards" button. Opens the App Store's
    /// write-a-review page when the app is listed (the system prompt may be
    /// suppressed, which would make the button look broken), otherwise falls
    /// back to the system prompt.
    @MainActor
    func openWriteReview() {
        let appStoreID = AppConfiguration.App.appStoreID.trimmingCharacters(in: .whitespaces)
        if !appStoreID.isEmpty,
           let url = URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review") {
            UIApplication.shared.open(url)
            userHasReviewed = true
        } else {
            requestReview()
        }
    }

    private func resetTracking() {
        accumulatedUsage = 0
        userHasReviewed = true
        log("Reset tracking; user marked as having been asked")
    }

    // MARK: - Utilities

    private func log(_ message: String) {
        #if DEBUG
        print("📊 ReviewManager: \(message)")
        #endif
    }
}
