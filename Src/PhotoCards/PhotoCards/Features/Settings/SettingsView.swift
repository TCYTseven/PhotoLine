//
//  SettingsView.swift
//  PhotoCards
//
//  Profile name, appearance, legal, support, blocked players and account
//  deletion (App Store Review Guideline 5.1.1(v)).
//

import SwiftUI
import Common
import Factory
import Authentication

struct SettingsView: View {
    @EnvironmentObject private var navigator: AppNavigator
    @AppStorage(AppStorageKeys.playerName) private var playerName = ""
    @Injected(\.gameService) private var gameService: GameService
    @Injected(\.authStatusRepository) private var authStatus: AuthStatusRepository

    @StateObject private var reviewManager = ReviewManager()
    @State private var webPage: WebPage?
    @State private var showHowToPlay = false
    @State private var guestId = ""
    @State private var nameSaveMessage: String?
    /// The name as last confirmed by the server, so leaving the screen only
    /// calls the backend when the name actually changed.
    @State private var savedName: String?

    let onDeleteAccount: () -> Void

    var body: some View {
        Form {
            Group {
            Section {
                TextField("Your name", text: $playerName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await saveName() } }
                    .submitLabel(.done)
                    .onChange(of: playerName) { _, newValue in
                        if newValue.count > PlayerName.maxLength { playerName = String(newValue.prefix(PlayerName.maxLength)) }
                    }
                    .accessibilityLabel("Display name")
                if let nameSaveMessage {
                    Text(nameSaveMessage)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Display name")
            } footer: {
                Text("Shown to other players in your rooms. You play as a guest; no email or password needed.")
            }

            Section("Help") {
                Button {
                    showHowToPlay = true
                } label: {
                    Label("How to play", systemImage: "questionmark.circle")
                }
                Button {
                    open(AppConfiguration.App.supportURL)
                } label: {
                    Label("Help & support", systemImage: "lifepreserver")
                }
                Button {
                    reviewManager.openWriteReview()
                } label: {
                    Label("Rate PhotoCards", systemImage: "star")
                }
                if let website = URL(string: AppConfiguration.App.websiteURL) {
                    ShareLink(
                        item: website,
                        subject: Text("PhotoCards"),
                        message: Text("Play PhotoCards with me: the party game where the funniest photo wins.")
                    ) {
                        Label("Share PhotoCards", systemImage: "square.and.arrow.up")
                    }
                }
            }

            Section("Safety") {
                NavigationLink {
                    BlockedUsersView()
                } label: {
                    Label("Blocked players", systemImage: "hand.raised")
                }
            }

            Section("Legal") {
                Button {
                    open(AppConfiguration.App.privacyPolicyURL)
                } label: {
                    Label("Privacy Policy", systemImage: "lock.shield")
                }
                Button {
                    open(AppConfiguration.App.termsOfServiceURL)
                } label: {
                    Label("Terms of Service", systemImage: "doc.text")
                }
                Button {
                    open(AppConfiguration.App.licensesURL)
                } label: {
                    Label("Photo credits & licenses", systemImage: "photo")
                }
            }

            Section {
                // Opens the confirmation sheet directly. A confirmation dialog
                // in front of it was redundant, and presenting the root sheet
                // while that dialog was still dismissing could drop it.
                Button(role: .destructive) {
                    onDeleteAccount()
                } label: {
                    Label("Delete account & data", systemImage: "trash")
                }
            } header: {
                Text("Account")
            } footer: {
                Text("Permanently removes your guest account, display name, game history, reports and blocks from our servers. This can't be undone.")
            }

            Section {
                LabeledContent("Version", value: AppConfiguration.App.fullVersion)
                if !guestId.isEmpty {
                    LabeledContent("Guest ID", value: String(guestId.prefix(8)))
                        .foregroundColor(.secondary)
                }
            }
            }
            .listRowBackground(Color.white.opacity(0.10))
            .listRowSeparatorTint(.white.opacity(0.12))
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(GameListStyle())
        .tint(.white)
        .sheet(item: $webPage) { page in
            SafariView(url: page.url).ignoresSafeArea()
        }
        .sheet(isPresented: $showHowToPlay) {
            HowToPlayView(onDone: { showHowToPlay = false })
        }
        .task {
            if savedName == nil {
                savedName = PlayerName.clean(playerName)
            }
            guestId = await authStatus.getCurrentUser()?.id ?? ""
        }
        .onDisappear {
            Task { await saveName() }
        }
    }

    private func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        webPage = WebPage(url: url)
    }

    private func saveName() async {
        let trimmed = PlayerName.clean(playerName)
        guard !trimmed.isEmpty, trimmed != savedName else { return }
        playerName = trimmed
        do {
            try await gameService.updateDisplayName(trimmed)
            savedName = trimmed
            nameSaveMessage = nil
        } catch is CancellationError {
        } catch {
            nameSaveMessage = error.localizedDescription
        }
    }
}

// MARK: - Blocked users

struct BlockedUsersView: View {
    @Injected(\.gameService) private var gameService: GameService
    @State private var users: [BlockedUser] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            Group {
            if isLoading && users.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let errorMessage, users.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn't load blocked players")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Button("Try again") { Task { await load() } }
                        .buttonStyle(.borderless)
                }
                .padding(.vertical, 6)
            } else if users.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No blocked players")
                        .font(.headline)
                    Text("To block someone, use the \u{201C}\u{2026}\u{201D} menu next to their name during a game, or report one of their photos. Blocked players can't join rooms you host.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
            } else {
                ForEach(users) { user in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.username).font(.body)
                            Text("Blocked \(user.blockedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Unblock") {
                            Task { await unblock(user) }
                        }
                        .font(.subheadline.weight(.semibold))
                        // Only the button, not the whole row, unblocks.
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Unblock \(user.username)")
                    }
                }
            }
            if let errorMessage, !users.isEmpty {
                Text(errorMessage).font(.footnote).foregroundColor(.red)
            }
            }
            .listRowBackground(Color.white.opacity(0.10))
            .listRowSeparatorTint(.white.opacity(0.12))
        }
        .navigationTitle("Blocked players")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(GameListStyle())
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            users = try await gameService.listBlockedUsers()
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func unblock(_ user: BlockedUser) async {
        do {
            try await gameService.unblockUser(userId: user.userId)
            users.removeAll { $0.id == user.id }
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
