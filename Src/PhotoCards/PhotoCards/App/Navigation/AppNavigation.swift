//
//  AppNavigation.swift
//  PhotoCards
//
//  Routes and the navigator that drives the root NavigationStack.
//

import SwiftUI

enum AppRoute: Hashable {
    case createGame
    case joinGame(code: String?)
    case browseGames
    case promptPacks
    case settings
}

@MainActor
final class AppNavigator: ObservableObject {
    @Published var navigationPath = NavigationPath()

    func navigate(to route: AppRoute) {
        navigationPath.append(route)
    }

    func popToRoot() {
        navigationPath = NavigationPath()
    }
}
