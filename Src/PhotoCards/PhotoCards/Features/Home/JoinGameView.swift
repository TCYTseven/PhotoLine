//
//  JoinGameView.swift
//  PhotoCards
//
//  Enter a six character room code.
//

import SwiftUI
import Common

struct JoinGameView: View {
    @EnvironmentObject private var navigator: AppNavigator
    @EnvironmentObject private var session: GameSessionStore
    @AppStorage(AppStorageKeys.playerName) private var playerName = ""
    @FocusState private var codeFocused: Bool
    @State private var code: String
    @State private var askForName = false

    private static let allowed = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    private static let length = 6

    init(prefilledCode: String? = nil) {
        _code = State(initialValue: JoinGameView.sanitise(prefilledCode ?? ""))
    }

    private var isComplete: Bool { code.count == Self.length }

    var body: some View {
        ZStack {
            PhotoBackdrop(imageURL: nil)

            ScrollView {
            VStack(spacing: 26) {
                VStack(spacing: 8) {
                    Text("Enter the room code")
                        .font(Font.poppins(.bold, size: 24))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text("Ask the host. It's shown at the top of their lobby.")
                        .font(Font.poppins(.regular, size: 14))
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 30)

                codeBoxes
                    .contentShape(Rectangle())
                    .onTapGesture { codeFocused = true }

                // Hidden text field that actually receives input.
                TextField("", text: $code)
                    .focused($codeFocused)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.join)
                    .onSubmit { Task { await join() } }
                    .onChange(of: code) { _, newValue in
                        let cleaned = Self.sanitise(newValue)
                        if cleaned != newValue { code = cleaned }
                    }
                    .frame(width: 1, height: 1)
                    .opacity(0.02)
                    .accessibilityLabel("Room code")

                Button {
                    Task { await join() }
                } label: {
                    HStack(spacing: 10) {
                        if session.isBusy { ProgressView().tint(.white) }
                        Text(session.isBusy ? "Joining…" : "Join room")
                    }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(!isComplete || session.isBusy)
                .opacity(isComplete ? 1 : 0.6)
                .padding(.horizontal, 22)

                // PasteButton reads the clipboard without the system
                // "Allow Paste" prompt that UIPasteboard access triggers.
                PasteButton(payloadType: String.self) { strings in
                    guard let pasted = strings.first else { return }
                    let cleaned = Self.sanitise(pasted)
                    Task { @MainActor in
                        code = cleaned
                    }
                }
                .buttonBorderShape(.capsule)
                .tint(.white.opacity(0.25))
                .labelStyle(.titleAndIcon)
            }
            .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .navigationTitle("Join game")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { codeFocused = true }
        .playerNamePrompt(isPresented: $askForName) { name in
            Task { await join(name: name) }
        }
    }

    private var codeBoxes: some View {
        HStack(spacing: 10) {
            ForEach(0..<Self.length, id: \.self) { index in
                let character = index < code.count ? String(Array(code)[index]) : ""
                Text(character)
                    .font(Font.poppins(.bold, size: 30))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(width: 48, height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.16))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(index == code.count && codeFocused ? Color.white : Color.white.opacity(0.35), lineWidth: 2)
                    )
            }
        }
        .accessibilityHidden(true)
    }

    private static func sanitise(_ raw: String) -> String {
        String(raw.uppercased().filter { allowed.contains($0) }.prefix(length))
    }

    private func join(name enteredName: String? = nil) async {
        guard isComplete, !session.isBusy else { return }
        codeFocused = false
        // Reached straight from a link, the player may not have a name yet.
        let name = PlayerName.clean(enteredName ?? playerName)
        guard !name.isEmpty else {
            askForName = true
            return
        }
        if await session.joinGame(code: code, username: name) {
            PC.notify(.success)
            navigator.popToRoot()
        }
    }
}
