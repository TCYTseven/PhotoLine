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

    private static let allowed = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    private static let length = 6

    init(prefilledCode: String? = nil) {
        _code = State(initialValue: JoinGameView.sanitise(prefilledCode ?? ""))
    }

    private var isComplete: Bool { code.count == Self.length }

    var body: some View {
        ZStack {
            PhotoBackdrop(imageURL: nil)

            VStack(spacing: 26) {
                VStack(spacing: 8) {
                    Text("Enter the room code")
                        .font(Font.poppins(.bold, size: 24))
                        .foregroundColor(.white)
                    Text("Ask the host. It's shown at the top of their lobby.")
                        .font(Font.poppins(.regular, size: 14))
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 30)

                codeBoxes
                    .onTapGesture { codeFocused = true }

                // Hidden text field that actually receives input.
                TextField("", text: $code)
                    .focused($codeFocused)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textContentType(.oneTimeCode)
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

                Button {
                    if let pasted = UIPasteboard.general.string {
                        code = Self.sanitise(pasted)
                    }
                } label: {
                    Label("Paste code", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(SecondaryPillButtonStyle(height: 46))
                .padding(.horizontal, 60)

                Spacer()
            }
        }
        .navigationTitle("Join game")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { codeFocused = true }
    }

    private var codeBoxes: some View {
        HStack(spacing: 10) {
            ForEach(0..<Self.length, id: \.self) { index in
                let character = index < code.count ? String(Array(code)[index]) : ""
                Text(character)
                    .font(Font.poppins(.bold, size: 30))
                    .foregroundColor(.white)
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

    private func join() async {
        guard isComplete else { return }
        codeFocused = false
        let name = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if await session.joinGame(code: code, username: name) {
            PC.notify(.success)
            navigator.popToRoot()
        }
    }
}
