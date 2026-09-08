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

    private var trimmedName: String {
        playerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            PhotoBackdrop()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 8)
                LogoFanView(scale: 0.95)
                Spacer(minLength: 16)
                nameField
                    .padding(.bottom, 14)
                mainButtons
                Spacer(minLength: 16)
                bottomRow
                legalFooter
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 8)
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
        TextField("", text: $playerName, prompt: Text("Your name").foregroundColor(.gray))
            .font(Font.poppins(.semiBold, size: 20))
            .foregroundColor(.black)
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($nameFocused)
            .onChange(of: playerName) { _, newValue in
                if newValue.count > 20 { playerName = String(newValue.prefix(20)) }
            }
            .frame(height: 58)
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

    private var legalFooter: some View {
        HStack(spacing: 4) {
            Text("By playing you agree to our")
            if let terms = URL(string: AppConfiguration.App.termsOfServiceURL) {
                Link("Terms", destination: terms).underline()
            }
            Text("and")
            if let privacy = URL(string: AppConfiguration.App.privacyPolicyURL) {
                Link("Privacy Policy", destination: privacy).underline()
            }
        }
        .font(Font.poppins(.regular, size: 11))
        .foregroundColor(.white.opacity(0.75))
        .padding(.bottom, 4)
    }

    private func requireName() -> Bool {
        PC.haptic()
        if trimmedName.isEmpty {
            showNameRequired = true
            return false
        }
        playerName = trimmedName
        return true
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environmentObject(AppNavigator())
            .environmentObject(GameSessionStore(service: SupabaseGameService()))
    }
}
