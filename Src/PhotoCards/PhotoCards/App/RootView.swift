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

    @AppStorage(AppStorageKeys.isDarkMode) private var isDarkMode = false
    @AppStorage(AppStorageKeys.hasSeenHowToPlay) private var hasSeenHowToPlay = false
    @AppStorage(AppStorageKeys.playerName) private var playerName = ""

    @State private var showDeleteAccountSheet = false
    @State private var forceUpdateInfo: AppUpdateInfo?

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
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
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
        .fullScreenCover(isPresented: Binding(
            get: { !hasSeenHowToPlay && viewModel.launchState == .ready },
            set: { if !$0 { hasSeenHowToPlay = true } }
        )) {
            HowToPlayView(onDone: { hasSeenHowToPlay = true })
        }
        // ═══ Account deletion ═══
        .sheet(isPresented: $showDeleteAccountSheet) {
            AnyView(authCoordinator.deleteAccountSheet())
        }
        // ═══ Room closed / info ═══
        .alert("Heads up", isPresented: Binding(
            get: { session.infoMessage != nil },
            set: { if !$0 { session.dismissInfo() } }
        )) {
            Button("OK") { session.dismissInfo() }
        } message: {
            Text(session.infoMessage ?? "")
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
            .preferredColorScheme(isDarkMode ? .dark : .light)
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
        case .inactive, .background:
            if reviewManager.endSession() {
                reviewManager.requestReview()
            }
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
                    Text("Backend not configured")
                        .font(Font.poppins(.bold, size: 20))
                        .foregroundColor(.white)
                    Text("Add your Supabase URL and anon key to AppConfiguration.swift and run supabase/schema.sql. See docs/SUPABASE_SETUP_GUIDE.md.")
                        .font(Font.poppins(.regular, size: 14))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                case .failed(let message):
                    Text("Couldn't connect")
                        .font(Font.poppins(.bold, size: 20))
                        .foregroundColor(.white)
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
