//
//  RootView.swift
//  PhotoCards
//
//  Root of the app:
//   • signs the player in as a guest (anonymous Supabase session)
//   • hosts the navigation stack (home → create / join / browse / settings)
//   • presents the live game full screen whenever a session is active
//   • first-launch "how to play", account deletion, force update, offline banner
//

import SwiftUI
import Factory
import Common
import Authentication

struct RootView: View {

    @StateObject private var viewModel = RootViewModel()
    @StateObject private var navigator = AppNavigator()
    @StateObject private var session = GameSessionStore(service: Container.shared.gameService())
    @StateObject private var reviewManager = ReviewManager()

    @AppStorage(AppStorageKeys.hasSeenHowToPlay) private var hasSeenHowToPlay = false
    @AppStorage(AppStorageKeys.playerName) private var playerName = ""

    @State private var showDeleteAccountSheet = false
    @State private var forceUpdateInfo: AppUpdateInfo?
    /// What the "Heads up" alert shows. Mirrors `session.infoMessage`, but is
    /// set a beat later when a game has just ended: an alert requested while
    /// the full-screen game is still dismissing is silently dropped.
    @State private var infoAlert: String?
    @State private var gameEndedAt: Date?

    @Environment(\.scenePhase) private var scenePhase
    @Injected(\.networkMonitor) private var networkMonitor: NetworkMonitor
    @Injected(\.appUpdateChecker) private var appUpdateChecker: AppUpdateChecker
    @Injected(\.authCoordinator) private var authCoordinator: any AuthCoordinator

    var body: some View {
        VStack(spacing: 0) {
            if !networkMonitor.isConnected {
                NetworkBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            content
        }
        .animation(.easeInOut(duration: 0.3), value: networkMonitor.isConnected)
        .environmentObject(navigator)
        .environmentObject(session)
        .withDeepLinking(navigator: navigator)
        .task {
            await viewModel.bootstrap()
        }
        .onChange(of: viewModel.launchState) { _, newState in
            if newState == .ready {
                Task { await session.restoreActiveGame() }
            }
        }
        .onChange(of: viewModel.accountDeletionCount) { _, _ in
            // A fresh guest identity: forget everything local as well.
            playerName = ""
            session.clearSession(message: nil)
            navigator.popToRoot()
        }
        // `initial: true` so the cold launch counts too (usage time for the
        // review prompt, update check); onChange alone skips the first value.
        .onChange(of: scenePhase, initial: true) { _, phase in
            handleScenePhase(phase)
        }
        .onChange(of: networkMonitor.isConnected) { _, connected in
            // Came back online while stuck on "Couldn't connect": retry for them.
            if connected, case .failed = viewModel.launchState {
                Task { await viewModel.bootstrap() }
            }
        }
        .onChange(of: session.isInGame) { wasInGame, isInGame in
            // A game just ended and the player is back home: a natural,
            // non-interruptive moment for the (rate-limited) review prompt.
            if wasInGame && !isInGame {
                gameEndedAt = Date()
            }
            if wasInGame && !isInGame && session.infoMessage == nil && session.errorMessage == nil {
                reviewManager.requestReviewIfEligible()
            }
        }
        // ═══ Live game ═══
        .fullScreenCover(isPresented: Binding(
            get: { session.isInGame && viewModel.launchState == .ready },
            set: { _ in }
        )) {
            GameSessionView()
                .environmentObject(session)
                .environmentObject(navigator)
        }
        // ═══ First launch ═══
        // Never at the same time as a restored game (e.g. after a reinstall the
        // keychain session survives but UserDefaults don't): two full-screen
        // covers on one view can't present together.
        .fullScreenCover(isPresented: Binding(
            get: { !hasSeenHowToPlay && viewModel.launchState == .ready && !session.isInGame },
            set: { if !$0 { hasSeenHowToPlay = true } }
        )) {
            HowToPlayView(onDone: { hasSeenHowToPlay = true })
        }
        // ═══ Account deletion ═══
        .sheet(isPresented: $showDeleteAccountSheet) {
            AnyView(authCoordinator.deleteAccountSheet())
        }
        // ═══ Room closed / create & join errors ═══
        .onChange(of: session.infoMessage) { _, message in
            presentInfo(message)
        }
        .alert("Heads up", isPresented: Binding(
            get: { infoAlert != nil },
            set: { if !$0 { dismissInfoAlert() } }
        )) {
            Button("OK") { dismissInfoAlert() }
        } message: {
            Text(infoAlert ?? "")
        }
        .overlay {
            if let info = forceUpdateInfo, info.isForceUpdateRequired {
                ForceUpdateView(updateInfo: info)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Content by launch state

    @ViewBuilder
    private var content: some View {
        switch viewModel.launchState {
        case .loading:
            LaunchStatusView(kind: .loading, retry: nil)
        case .unconfigured:
            LaunchStatusView(kind: .unconfigured, retry: nil)
        case .failed(let message):
            LaunchStatusView(kind: .failed(message), retry: { Task { await viewModel.bootstrap() } })
        case .ready:
            NavigationStack(path: $navigator.navigationPath) {
                HomeView()
                    .navigationDestination(for: AppRoute.self) { route in
                        destination(for: route)
                    }
            }
            .tint(PC.red)
            // Every screen is drawn on the dark photo backdrop with white
            // text, so the app is dark-only (a light scheme gave dark status
            // bar text on the dark home screen).
            .preferredColorScheme(.dark)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .createGame:
            CreateGameView()
        case .joinGame(let code):
            JoinGameView(prefilledCode: code)
        case .browseGames:
            BrowseGamesView()
        case .promptPacks:
            PromptPacksView()
        case .settings:
            SettingsView(onDeleteAccount: { showDeleteAccountSheet = true })
        }
    }

    // MARK: - Info alert

    private func presentInfo(_ message: String?) {
        guard let message else {
            infoAlert = nil
            return
        }
        Task { @MainActor in
            // Let the isInGame onChange run first, then wait out the game
            // cover's dismissal if one is under way.
            try? await Task.sleep(for: .milliseconds(100))
            if let ended = gameEndedAt, Date().timeIntervalSince(ended) < 1.5 {
                try? await Task.sleep(for: .milliseconds(650))
            }
            if session.infoMessage == message {
                infoAlert = message
            }
        }
    }

    private func dismissInfoAlert() {
        infoAlert = nil
        session.dismissInfo()
    }

    // MARK: - Scene phase

    private func handleScenePhase(_ phase: ScenePhase) {
        session.handleScenePhase(phase)
        switch phase {
        case .active:
            reviewManager.startSession()
            Task { await checkForUpdates() }
            if viewModel.launchState == .ready {
                Task { await session.restoreActiveGame() }
            }
        case .background:
            // Only bank the usage time here. Asking for a review while the
            // scene is leaving the foreground never shows the prompt, yet
            // used to mark the player as "already asked" forever.
            reviewManager.endSession()
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    private func checkForUpdates() async {
        guard let info = try? await appUpdateChecker.checkForUpdate(), info.isForceUpdateRequired else { return }
        withAnimation { forceUpdateInfo = info }
    }
}

// MARK: - Launch status screens

struct LaunchStatusView: View {
    enum Kind: Equatable {
        case loading
        case unconfigured
        case failed(String)
    }

    let kind: Kind
    let retry: (() -> Void)?

    private static var unconfiguredMessage: String {
        #if DEBUG
        return "Add your Supabase URL and anon key to AppConfiguration.swift and run supabase/schema.sql. See docs/SUPABASE_SETUP_GUIDE.md."
        #else
        return "We can't reach our servers right now. Please try again later."
        #endif
    }

    var body: some View {
        ZStack {
            PhotoBackdrop(imageURL: nil)
            VStack(spacing: 18) {
                LogoFanView(scale: 0.7)
                switch kind {
                case .loading:
                    ProgressView().tint(.white)
                    Text("Getting things ready…")
                        .font(Font.poppins(.regular, size: 14))
                        .foregroundColor(.white.opacity(0.8))
                case .unconfigured:
                    Text("PhotoCards is unavailable")
                        .font(Font.poppins(.bold, size: 20))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Text(Self.unconfiguredMessage)
                        .font(Font.poppins(.regular, size: 14))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                case .failed(let message):
                    Text("Couldn't connect")
                        .font(Font.poppins(.bold, size: 20))
                        .foregroundColor(.white)
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .font(Font.poppins(.regular, size: 14))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    if let retry {
                        Button("Try again", action: retry)
                            .buttonStyle(PillButtonStyle())
                            .frame(width: 200)
                            .padding(.top, 6)
                    }
                }
            }
            .padding()
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    RootView()
}
