//
//  PlayerNamePrompt.swift
//  PhotoCards
//
//  Display-name rules shared by the home screen, settings and every screen
//  that can be reached directly from a link (join / create / browse), so a
//  player who opens photocards://join?code=… before ever typing a name is
//  asked for one instead of hitting a server error.
//

import SwiftUI

enum PlayerName {
    /// Mirrors `_clean_username` in supabase/schema.sql.
    static let maxLength = 20

    /// Collapses runs of whitespace, trims, and caps the length.
    static func clean(_ raw: String) -> String {
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(collapsed.prefix(maxLength))
    }
}

/// Alert with a text field that asks for a display name, saves it and then
/// runs `onContinue` with the cleaned name.
struct PlayerNamePrompt: ViewModifier {
    @Binding var isPresented: Bool
    let onContinue: (String) -> Void

    @AppStorage(AppStorageKeys.playerName) private var playerName = ""
    @State private var draft = ""

    init(isPresented: Binding<Bool>, onContinue: @escaping (String) -> Void) {
        self._isPresented = isPresented
        self.onContinue = onContinue
    }

    func body(content: Content) -> some View {
        content
            .alert("What's your name?", isPresented: $isPresented) {
                TextField("Your name", text: $draft)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                Button("Continue") {
                    let name = PlayerName.clean(draft)
                    guard !name.isEmpty else { return }
                    playerName = name
                    onContinue(name)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Other players will see this name in the room.")
            }
            .onChange(of: isPresented) { _, presented in
                if presented { draft = playerName }
            }
    }
}

extension View {
    /// Asks for a display name when `isPresented` becomes true.
    func playerNamePrompt(isPresented: Binding<Bool>, onContinue: @escaping (String) -> Void) -> some View {
        modifier(PlayerNamePrompt(isPresented: isPresented, onContinue: onContinue))
    }
}
