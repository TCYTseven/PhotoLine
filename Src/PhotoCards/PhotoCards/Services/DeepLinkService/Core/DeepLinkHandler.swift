//
//  DeepLinkHandler.swift
//  PhotoCards
//
//  Main entry point for handling deep links in your app.
//

import Combine
import Foundation
import SwiftUI

// MARK: - Routing Protocol

/// Implement this protocol to handle deep link navigation.
/// Your app's coordinator or navigation manager should conform to this.
protocol DeepLinkRouting: AnyObject {
    /// Route to the destination for a deep link route
    /// Return true if the link was handled, false otherwise
    @MainActor
    func route(to route: DeepLinkRoute) -> Bool
}

// MARK: - Route Result

enum DeepLinkRouteResult: Sendable {
    case handled
    case deferred  // Handle later (e.g., after auth)
    case notHandled
}

// MARK: - Handler

/// Main handler for processing incoming deep links.
final class DeepLinkHandler: ObservableObject, @unchecked Sendable {
    private let parser: DeepLinkParsing
    private weak var routeHandler: DeepLinkRouting?
    private var pendingDeepLink: DeepLinkRoute?

    /// Published for SwiftUI observation
    @Published private(set) var lastDeepLink: DeepLinkRoute?

    /// Tracks whether coordinator was configured via .setupDeepLinking()
    private var isCoordinatorConfigured = false

    init(parser: DeepLinkParsing) {
        self.parser = parser
    }

    // MARK: - Configuration

    /// Set the route handler (call this when your coordinator is ready)
    func setRouteHandler(_ handler: DeepLinkRouting) {
        self.routeHandler = handler
        isCoordinatorConfigured = true

        // If there's a pending deep link, route it now
        if let pending = pendingDeepLink {
            #if DEBUG
            print("🔗 DeepLinkHandler: Handler set, routing pending link: \(pending.path)")
            #endif
            Task { @MainActor in
                _ = self.handle(route: pending)
            }
        } else {
            #if DEBUG
            print("🔗 DeepLinkHandler: Handler set, no pending links")
            #endif
        }
    }

    // MARK: - Setup Validation

    /// Debug-only check that a route handler has been attached.
    private func validateSetup() {
        #if DEBUG
        if !isCoordinatorConfigured {
            print("🔗 DeepLinkHandler: no route handler yet; links are deferred until withDeepLinking(navigator:) sets one up.")
        }
        #endif
    }

    // MARK: - Handle Incoming URLs

    /// Handle a URL (from URL scheme or Universal Link)
    @MainActor
    @discardableResult
    func handle(url: URL) -> Bool {
        validateSetup()

        guard let route = parser.parse(url: url) else {
            #if DEBUG
            print("[DeepLink] Could not parse URL: \(url)")
            #endif
            return false
        }

        return handle(route: route)
    }

    /// Handle an NSUserActivity (for Universal Links)
    @MainActor
    @discardableResult
    func handle(userActivity: NSUserActivity) -> Bool {
        validateSetup()

        guard let route = parser.parse(userActivity: userActivity) else {
            #if DEBUG
            print("[DeepLink] Could not parse user activity")
            #endif
            return false
        }

        return handle(route: route)
    }

    /// Handle a deep link route directly
    @MainActor
    @discardableResult
    func handle(route: DeepLinkRoute) -> Bool {
        validateSetup()

        lastDeepLink = route

        guard let handler = routeHandler else {
            // No handler yet, defer the link
            #if DEBUG
            print("🔗 DeepLinkHandler: No handler available, deferring: \(route.path)")
            #endif
            pendingDeepLink = route
            return true  // Deferred counts as handled
        }

        #if DEBUG
        print("🔗 DeepLinkHandler: Routing to handler: \(route.path)")
        #endif

        let handled = handler.route(to: route)
        if handled {
            pendingDeepLink = nil
            #if DEBUG
            print("[DeepLink] Handled: \(route.path)")
            #endif
            return true
        } else {
            // Handler returned false - defer the link for later
            pendingDeepLink = route
            #if DEBUG
            print("[DeepLink] Deferred: \(route.path)")
            #endif
            return true  // Deferred counts as handled
        }
    }

    // MARK: - Pending Links

    /// Check for pending deep link (e.g., after auth)
    var hasPendingDeepLink: Bool {
        pendingDeepLink != nil
    }

    /// Process pending deep link
    @MainActor
    func processPendingDeepLink() {
        #if DEBUG
        print("🔗 DeepLinkHandler: Processing pending deep link...")
        #endif
        if let pending = consumePendingDeepLink() {
            _ = handle(route: pending)
        } else {
            #if DEBUG
            print("🔗 DeepLinkHandler: No pending link found")
            #endif
        }
    }

    /// Get and clear the pending deep link
    private func consumePendingDeepLink() -> DeepLinkRoute? {
        let link = pendingDeepLink
        #if DEBUG
        if let link {
            print("🔗 DeepLinkHandler: Consuming pending link: \(link.path)")
        } else {
            print("🔗 DeepLinkHandler: No pending link to consume")
        }
        #endif
        pendingDeepLink = nil
        return link
    }

    /// Clear any pending deep link
    func clearPendingDeepLink() {
        pendingDeepLink = nil
    }
}
