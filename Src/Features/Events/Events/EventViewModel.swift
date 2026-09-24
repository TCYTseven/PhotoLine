//
//  EventViewModel.swift
//  ListingShared
//
//

import Foundation

@Observable
public final class EventViewModel {
    // MARK: - State
    public enum Event: Equatable {
        case userLoggedIn
        case userLoggedOut
        case profileUpdated
        case userSubscribed
        case appRatingRequested
        case networkConnectivityChanged(isConnected: Bool)
    }

    // MARK: - Event Type for Selective Subscription
    public enum EventType: Equatable {
        case authentication
        case profile
        case subscription
        case appRating
        case network

        // Helper to determine if an Event matches this EventType
        public func matches(_ event: Event) -> Bool {
            switch (self, event) {
            case (.authentication, .userLoggedIn), (.authentication, .userLoggedOut): return true
            case (.profile, .profileUpdated): return true
            case (.subscription, .userSubscribed): return true
            case (.appRating, .appRatingRequested): return true
            case (.network, .networkConnectivityChanged): return true
            default: return false
            }
        }
    }

    // MARK: - Properties
    private(set) var lastEvent: Event?

    // Store observers with their interested event types. Guarded by `lock`:
    // events can be emitted from background tasks while views subscribe and
    // unsubscribe on the main thread.
    @ObservationIgnored
    private var observers: [ObjectIdentifier: (eventTypes: Set<EventType>, handler: (Event) -> Void)] = [:]

    private let lock = NSLock()

    public init() {}

    // MARK: - Methods
    public func emit(_ event: Event) {
        lastEvent = event

        // Snapshot the interested handlers under the lock, then call them
        // outside it so a handler may subscribe/unsubscribe without deadlocking.
        let handlers: [(Event) -> Void] = lock.withLock {
            observers.values
                .filter { observerInfo in
                    observerInfo.eventTypes.contains { eventType in
                        eventType.matches(event)
                    }
                }
                .map { $0.handler }
        }

        handlers.forEach { $0(event) }
    }

    public func subscribe(
        for observer: AnyObject,
        to eventTypes: Set<EventType>,
        handler: @escaping (Event) -> Void
    ) {
        let id = ObjectIdentifier(observer)
        lock.withLock {
            observers[id] = (eventTypes: eventTypes, handler: handler)
        }
    }

    public func unsubscribe(_ observer: AnyObject) {
        let id = ObjectIdentifier(observer)
        lock.withLock {
            _ = observers.removeValue(forKey: id)
        }
    }
}
