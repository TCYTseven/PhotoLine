//
//  DeepLinkCoordinator.swift
//  PhotoCards
//
//  Maps incoming links to app routes.
//    photocards://join?code=ABC123  → join screen with the code filled in
//    photocards://create            → create game
//    photocards://browse            → public rooms
//    photocards://settings          → settings
//

import Foundation

@MainActor
final class DeepLinkCoordinator: DeepLinkRouting {

    private weak var navigator: AppNavigator?

    init(navigator: AppNavigator) {
        self.navigator = navigator
    }

    func route(to route: DeepLinkRoute) -> Bool {
        guard let navigator else { return false }
        let path = route.path.lowercased()
        if path.isEmpty || path == "home" {
            navigator.popToRoot()
            return true
        }
        // Unknown paths are consumed (returning false would park them as a
        // "pending" link that is retried forever).
        guard let appRoute = mapToAppRoute(route) else { return true }
        navigator.popToRoot()
        navigator.navigate(to: appRoute)
        return true
    }

    private func mapToAppRoute(_ route: DeepLinkRoute) -> AppRoute? {
        let path = route.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch path {
        case "join":
            return .joinGame(code: route.parameters["code"] ?? route.parameters["CODE"])
        case "create":
            return .createGame
        case "browse":
            return .browseGames
        case "prompts":
            return .promptPacks
        case "settings":
            return .settings
        default:
            if path.hasPrefix("join/"), let code = route.pathComponent(at: 1) {
                return .joinGame(code: code)
            }
            // Web join page (…/join/?code=ABC123) if it is ever served as a
            // Universal Link from a sub-path such as /PhotoLine/join/.
            if route.pathComponents.last?.lowercased() == "join" {
                return .joinGame(code: route.parameters["code"])
            }
            return nil
        }
    }
}
