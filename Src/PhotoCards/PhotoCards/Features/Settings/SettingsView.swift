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
    @AppStorage(AppStorageKeys.isDarkMode) private var isDarkMode = false
    @Injected(\.gameService) private var gameService: GameService
    @Injected(\.authStatusRepository) private var authStatus: AuthStatusRepository

    @StateObject private var reviewManager = ReviewManager()
    @State private var webPage: WebPage?
    @State private var showDeleteAccount = false
    @State private var showHowToPlay = false
    @State private var guestId = ""
    @State private var nameSaveMessage: String?

    let onDeleteAccount: () -> Void

    var body: some View {
        Form {
            Section {
                TextField("Your name", text: $playerName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await saveName() } }
                    .onChange(of: playerName) { _, newValue in
                        if newValue.count > 20 { playerName = String(newValue.prefix(20)) }
                    }
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

            Section("Appearance") {
                Toggle("Dark mode", isOn: $isDarkMode)
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
                    reviewManager.requestReview()
                } label: {
                    Label("Rate PhotoCards", systemImage: "star")
                }
                ShareLink(item: URL(string: AppConfiguration.App.websiteURL) ?? URL(string: "https://apple.com")!) {
                    Label("Share PhotoCards", systemImage: "square.and.arrow.up")
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
                Button(role: .destructive) {
                    showDeleteAccount = true
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
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .tint(PC.red)
        .sheet(item: $webPage) { page in
            SafariView(url: page.url).ignoresSafeArea()
        }
        .sheet(isPresented: $showHowToPlay) {
            HowToPlayView(onDone: { showHowToPlay = false })
        }
        .confirmationDialog("Delete your account?", isPresented: $showDeleteAccount, titleVisibility: .visible) {
            Button("Delete account & data", role: .destructive) {
                onDeleteAccount()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes everything tied to this guest account. You'll get a fresh guest identity next time you play.")
        }
        .task {
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
        let trimmed = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        playerName = trimmed
        do {
            try await gameService.updateDisplayName(trimmed)
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
            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if users.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No blocked players")
                        .font(.headline)
                    Text("Block someone from a photo's report menu during a game. Blocked players can't join rooms you host.")
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
                    }
                }
            }
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundColor(.red)
            }
        }
        .navigationTitle("Blocked players")
        .navigationBarTitleDisplayMode(.inline)
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
