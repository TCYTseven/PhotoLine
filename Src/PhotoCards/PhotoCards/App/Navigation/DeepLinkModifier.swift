//
//  DeepLinkModifier.swift
//  PhotoCards
//
//  Unified deep link setup and handling.
//  Manages coordinator lifecycle, auth state watching, and URL processing.
//

import SwiftUI

// MARK: - Readiness State

/// Tracks the initialization state of the deep linking system.
enum DeepLinkReadiness: Equatable {
    case notReady
    case handlerConfigured
    case fullyReady
}

// MARK: - View Modifier

/// Unified modifier for deep linking setup and URL handling.
struct DeepLinkModifier: ViewModifier {

    // MARK: - Dependencies
    @ObservedObject var navigator: AppNavigator

    // MARK: - State

    @State private var coordinator: DeepLinkCoordinator?
    @State private var handler: DeepLinkHandler?
    @State private var readiness: DeepLinkReadiness = .notReady

    // MARK: - Configuration

    /// Delay after authentication before processing pending deep links.
    /// Ensures the navigation stack is fully initialized and ready.
    private let pendingLinkProcessingDelay: TimeInterval = 0.3

    // MARK: - Body

    func body(content: Content) -> some View {
        content
            .onAppear {
                _ = ensureHandler()
            }
            .onOpenURL { url in
                Task { @MainActor in
                    // A cold-start link can arrive before onAppear ran;
                    // set up on demand so the link isn't dropped.
                    ensureHandler().handle(url: url)
                }
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                Task { @MainActor in
                    ensureHandler().handle(userActivity: activity)
                }
            }
    }

    // MARK: - Setup

    /// Creates the handler and coordinator exactly once and returns the handler.
    /// Rebuilding them would throw away a link that is waiting to be routed.
    @discardableResult
    private func ensureHandler() -> DeepLinkHandler {
        if let handler { return handler }

        let deepLinkHandler = DeepLinkSetup.createHandler()
        let newCoordinator = DeepLinkCoordinator(navigator: navigator)
        deepLinkHandler.setRouteHandler(newCoordinator)

        self.handler = deepLinkHandler
        self.coordinator = newCoordinator
        self.readiness = .handlerConfigured
        return deepLinkHandler
    }

}

// MARK: - View Extension

extension View {
    /// Set up deep linking for this view.
    /// Should be called once at the root of your app.
    func withDeepLinking(navigator: AppNavigator) -> some View {
        modifier(DeepLinkModifier(navigator: navigator))
    }
}
