//
//  NotificationServiceFactory.swift
//  PhotoCards
//
//  Factory registration for dependency injection.
//

import Factory
import Foundation

// MARK: - Factory Registration

extension Container {
    var notificationService: Factory<NotificationService> {
        self {
            FirebaseNotificationService()
        }
        .singleton
    }
}
