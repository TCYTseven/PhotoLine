//
//  GameServiceFactory.swift
//  PhotoCards
//
//  Dependency injection registrations for the game layer.
//

import Foundation
import Factory

extension Container {
    var gameService: Factory<GameService> {
        self { SupabaseGameService() }
            .singleton
    }
}
