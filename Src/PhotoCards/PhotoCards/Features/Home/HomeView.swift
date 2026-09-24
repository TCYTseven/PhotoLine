//
//  HomeView.swift
//  PhotoCards
//
//  Landing screen: name, create/join, quick links.
//

import SwiftUI
import Common

struct HomeView: View {
    @EnvironmentObject private var navigator: AppNavigator
    @EnvironmentObject private var session: GameSessionStore
    @AppStorage(AppStorageKeys.playerName) private var playerName = ""
    @FocusState private var nameFocused: Bool
    @State private var showHowToPlay = false
    @State private var showNameRequired = false

    var body: some View {
        ZStack {
            PhotoBackdrop()

            // Scrolls only when it has to (small phones, large text sizes).
            ViewThatFits(in: .vertical) {
                homeStack
                ScrollView {
                    homeStack
                }
                .scrollDismissesKeyboard(.interactively)
            }
            // The name field sits above the keyboard anyway; letting the
            // keyboard resize this would flip ViewThatFits between its two
            // layouts and drop focus mid-typing.
            .ignoresSafeArea(.keyboard)
        }
        .onTapGesture { nameFocused = false }
        .sheet(isPresented: $showHowToPlay) {
            HowToPlayView(onDone: { showHowToPlay = false })
        }
        .alert("What's your name?", isPresented: $showNameRequired) {
            Button("OK") { nameFocused = true }
        } message: {
            Text("Other players will see this name in the room.")
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Pieces

    private var homeStack: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 8)
            LogoFanView(scale: 0.75)
            Spacer(minLength: 8)
            nameField
                .padding(.bottom, 14)
            mainButtons
            Spacer(minLength: 8)
            bottomRow
            legalFooter
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
    }

    private var topBar: some View {
        HStack {
            RoundIconButton(icon: "questionmark", label: "How to play") {
                showHowToPlay = true
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    private var nameField: some View {
        TextField("", text: $playerName, prompt: Text("Your name").foregroundColor(Color(white: 0.45)))
            .font(Font.poppins(.semiBold, size: 20))
            .foregroundColor(.black)
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($nameFocused)
            .onChange(of: playerName) { _, newValue in
                if newValue.count > PlayerName.maxLength { playerName = String(newValue.prefix(PlayerName.maxLength)) }
            }
            .onSubmit { nameFocused = false }
            .frame(minHeight: 58)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.94))
            )
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 6)
            .accessibilityLabel("Your name")
    }

    private var mainButtons: some View {
        VStack(spacing: 12) {
            Button("Create game") {
                guard requireName() else { return }
                navigator.navigate(to: .createGame)
            }
            .buttonStyle(PillButtonStyle())

            Button("Join game") {
                guard requireName() else { return }
                navigator.navigate(to: .joinGame(code: nil))
            }
            .buttonStyle(PillButtonStyle())
        }
    }

    private var bottomRow: some View {
        HStack(alignment: .top, spacing: 28) {
            GlassTile(icon: "list.bullet.rectangle.portrait", title: "Browse") {
                guard requireName() else { return }
                navigator.navigate(to: .browseGames)
            }
            GlassTile(icon: "text.quote", title: "Prompts") {
                navigator.navigate(to: .promptPacks)
            }
            GlassTile(icon: "gearshape.fill", title: "Settings") {
                navigator.navigate(to: .settings)
            }
        }
        .padding(.bottom, 14)
    }

    /// One wrapping Text (the old HStack of four pieces truncated on small
    /// screens and at larger text sizes). Links open in Safari.
    private var legalFooter: some View {
        Text(legalText)
            .font(Font.poppins(.regular, size: 11))
            .foregroundColor(.white.opacity(0.75))
            .tint(.white)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 4)
    }

    private var legalText: AttributedString {
        let markdown = "By playing you agree to our [Terms](\(AppConfiguration.App.termsOfServiceURL)) and [Privacy Policy](\(AppConfiguration.App.privacyPolicyURL))."
        guard var text = try? AttributedString(markdown: markdown) else {
            return AttributedString("By playing you agree to our Terms and Privacy Policy.")
        }
        let linkRanges = text.runs.filter { $0.link != nil }.map { $0.range }
        for range in linkRanges {
            text[range].underlineStyle = Text.LineStyle.single
        }
        return text
    }

    private func requireName() -> Bool {
        PC.haptic()
        let cleaned = PlayerName.clean(playerName)
        if cleaned.isEmpty {
            showNameRequired = true
            return false
        }
        playerName = cleaned
        return true
    }
}

#if DEBUG
/// Offline stand-in so the preview never talks to the real backend.
private struct PreviewGameService: GameService {
    private struct Unavailable: Error {}

    func createGame(username: String, settings: GameSettings) async throws -> GameState { throw Unavailable() }
    func updateSettings(gameId: UUID, settings: GameSettings) async throws -> GameState { throw Unavailable() }
    func joinGame(code: String, username: String) async throws -> GameState { throw Unavailable() }
    func activeGame() async throws -> GameState? { nil }
    func gameState(gameId: UUID) async throws -> GameState { throw Unavailable() }
    func leaveGame(gameId: UUID) async throws {}
    func listPublicGames() async throws -> [PublicGameSummary] { [] }
    func setReady(gameId: UUID, ready: Bool) async throws -> GameState { throw Unavailable() }
    func startGame(gameId: UUID) async throws -> GameState { throw Unavailable() }
    func submitPhoto(gameId: UUID, photoId: UUID) async throws -> GameState { throw Unavailable() }
    func refreshHand(gameId: UUID) async throws -> GameState { throw Unavailable() }
    func pickWinner(gameId: UUID, submissionId: UUID) async throws -> GameState { throw Unavailable() }
    func castVote(gameId: UUID, submissionId: UUID) async throws -> GameState { throw Unavailable() }
    func advanceGame(gameId: UUID) async throws -> GameState { throw Unavailable() }
    func restartGame(gameId: UUID) async throws -> GameState { throw Unavailable() }
    func listPromptPacks() async throws -> [PromptPack] { [] }
    func listPrompts(packSlug: String) async throws -> [PromptItem] { [] }
    func updateDisplayName(_ name: String) async throws {}
    func reportContent(reason: String, details: String?, gameId: UUID?, reportedUserId: UUID?, photoId: UUID?) async throws {}
    func blockUser(userId: UUID) async throws {}
    func unblockUser(userId: UUID) async throws {}
    func listBlockedUsers() async throws -> [BlockedUser] { [] }
    func observeGame(gameId: UUID) -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

#Preview {
    NavigationStack {
        HomeView()
            .environmentObject(AppNavigator())
            .environmentObject(GameSessionStore(service: PreviewGameService()))
    }
}
#endif
