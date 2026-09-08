//
//  CreateGameView.swift
//  PhotoCards
//
//  Host picks the mode, rules and prompt packs, then opens a room.
//

import SwiftUI
import Common
import Factory

struct CreateGameView: View {
    @EnvironmentObject private var navigator: AppNavigator
    @EnvironmentObject private var session: GameSessionStore
    @AppStorage(AppStorageKeys.playerName) private var playerName = ""
    @Injected(\.gameService) private var gameService: GameService

    @State private var settings: GameSettings
    @State private var packs: [PromptPack] = []
    private let editing: GameState?
    private let onSaved: (() -> Void)?

    /// Pass `editing` to change the settings of an existing lobby instead of
    /// creating a new room.
    init(editing: GameState? = nil, onSaved: (() -> Void)? = nil) {
        self.editing = editing
        self.onSaved = onSaved
        var initial = GameSettings()
        if let game = editing?.game {
            initial.mode = game.mode
            initial.isPublic = game.isPublic
            initial.maxPlayers = game.maxPlayers
            initial.maxRounds = game.maxRounds
            initial.targetScore = game.targetScore
            initial.roundTimerSeconds = game.mode == .rapid ? GameSettings.rapidTimerSeconds : game.roundTimerSeconds
            initial.packSlugs = game.promptPackSlugs
            initial.customPrompts = game.customPrompts
        }
        _settings = State(initialValue: initial)
    }

    private var isEditing: Bool { editing != nil }
    @State private var packsFailed = false
    @State private var newPrompt = ""
    @FocusState private var promptFocused: Bool

    var body: some View {
        ZStack {
            PhotoBackdrop(imageURL: nil)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    modeSection
                    rulesSection
                    packsSection
                    customPromptsSection
                    Color.clear.frame(height: 90)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack {
                Spacer()
                createButton
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
                    .background(
                        LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea()
                    )
            }
        }
        .navigationTitle(isEditing ? "Game settings" : "Create game")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await loadPacks() }
    }

    // MARK: - Sections

    private var modeSection: some View {
        VStack(spacing: 10) {
            DarkSectionHeader(title: "Game mode")
            ForEach(GameMode.allCases) { mode in
                Button {
                    PC.haptic()
                    settings.mode = mode
                    if mode == .rapid {
                        settings.roundTimerSeconds = GameSettings.rapidTimerSeconds
                    } else if settings.roundTimerSeconds == GameSettings.rapidTimerSeconds {
                        settings.roundTimerSeconds = 60
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(settings.mode == mode ? PC.red : Color.white.opacity(0.15)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.title)
                                .font(Font.poppins(.bold, size: 17))
                                .foregroundColor(.white)
                            Text(mode.subtitle)
                                .font(Font.poppins(.regular, size: 13))
                                .foregroundColor(.white.opacity(0.75))
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: settings.mode == mode ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundColor(settings.mode == mode ? .white : .white.opacity(0.4))
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: PC.cornerMedium, style: .continuous)
                            .fill(Color.white.opacity(settings.mode == mode ? 0.2 : 0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PC.cornerMedium, style: .continuous)
                            .stroke(settings.mode == mode ? Color.white.opacity(0.6) : Color.white.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(settings.mode == mode ? .isSelected : [])
            }
        }
    }

    private var rulesSection: some View {
        VStack(spacing: 10) {
            DarkSectionHeader(title: "Rules")
            SurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    stepperRow(title: "Rounds", value: $settings.maxRounds, range: 1...30)
                    divider
                    stepperRow(title: "Points to win", value: $settings.targetScore, range: 1...30)
                    divider
                    stepperRow(title: "Max players", value: $settings.maxPlayers, range: 3...12)
                    divider
                    timerRow
                    divider
                    Toggle(isOn: $settings.isPublic) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Public room")
                                .font(Font.poppins(.semiBold, size: 16))
                                .foregroundColor(.white)
                            Text("Anyone can find it under Browse.")
                                .font(Font.poppins(.regular, size: 12))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .tint(PC.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private var timerRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Round timer")
                    .font(Font.poppins(.semiBold, size: 16))
                    .foregroundColor(.white)
                Spacer()
                if settings.mode == .rapid {
                    Text("\(GameSettings.rapidTimerSeconds)s in Rapid Fire")
                        .font(Font.poppins(.regular, size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            if settings.mode != .rapid {
                Picker("Round timer", selection: $settings.roundTimerSeconds) {
                    ForEach(GameSettings.timerOptions, id: \.self) { seconds in
                        Text("\(seconds)s").tag(seconds)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var packsSection: some View {
        VStack(spacing: 10) {
            DarkSectionHeader(title: "Prompt packs")
            SurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    if packs.isEmpty {
                        HStack {
                            if packsFailed {
                                Text("Couldn't load packs. The default pack will be used.")
                                    .font(Font.poppins(.regular, size: 13))
                                    .foregroundColor(.white.opacity(0.75))
                            } else {
                                ProgressView().tint(.white)
                                Text("Loading packs…")
                                    .font(Font.poppins(.regular, size: 13))
                                    .foregroundColor(.white.opacity(0.75))
                            }
                        }
                        .padding(16)
                    } else {
                        ForEach(packs) { pack in
                            Button {
                                PC.haptic()
                                togglePack(pack)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: isSelected(pack) ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 22))
                                        .foregroundColor(isSelected(pack) ? PC.red : .white.opacity(0.5))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pack.name)
                                            .font(Font.poppins(.semiBold, size: 16))
                                            .foregroundColor(.white)
                                        if let description = pack.description {
                                            Text(description)
                                                .font(Font.poppins(.regular, size: 12))
                                                .foregroundColor(.white.opacity(0.7))
                                                .multilineTextAlignment(.leading)
                                        }
                                    }
                                    Spacer()
                                    Text("\(pack.promptCount)")
                                        .font(Font.poppins(.medium, size: 12))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isSelected(pack) ? .isSelected : [])
                            if pack.id != packs.last?.id { divider }
                        }
                    }
                }
            }
        }
    }

    private var customPromptsSection: some View {
        VStack(spacing: 10) {
            DarkSectionHeader(title: "Your own prompts (optional)")
            SurfaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        TextField("", text: $newPrompt, prompt: Text("e.g. When the WiFi finally connects").foregroundColor(.white.opacity(0.45)))
                            .font(Font.poppins(.regular, size: 15))
                            .foregroundColor(.white)
                            .focused($promptFocused)
                            .submitLabel(.done)
                            .onSubmit(addPrompt)
                        Button {
                            addPrompt()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 26))
                                .foregroundColor(canAddPrompt ? PC.red : .white.opacity(0.3))
                        }
                        .disabled(!canAddPrompt)
                        .accessibilityLabel("Add prompt")
                    }
                    if !settings.customPrompts.isEmpty {
                        ForEach(Array(settings.customPrompts.enumerated()), id: \.offset) { index, prompt in
                            HStack {
                                Text(prompt)
                                    .font(Font.poppins(.regular, size: 14))
                                    .foregroundColor(.white)
                                Spacer()
                                Button {
                                    settings.customPrompts.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .accessibilityLabel("Remove prompt")
                            }
                        }
                    }
                    Text("Custom prompts are used first. Keep them friendly: they're shown to everyone in the room.")
                        .font(Font.poppins(.regular, size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
    }

    private var createButton: some View {
        Button {
            Task { await create() }
        } label: {
            HStack(spacing: 10) {
                if session.isBusy { ProgressView().tint(.white) }
                Text(session.isBusy ? (isEditing ? "Saving…" : "Opening room…") : (isEditing ? "Save settings" : "Create room"))
            }
        }
        .buttonStyle(PillButtonStyle())
        .disabled(session.isBusy)
    }

    private var divider: some View {
        Divider().background(Color.white.opacity(0.15)).padding(.leading, 16)
    }

    private func stepperRow(title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(title)
                .font(Font.poppins(.semiBold, size: 16))
                .foregroundColor(.white)
            Spacer()
            Text("\(value.wrappedValue)")
                .font(Font.poppins(.bold, size: 17))
                .monospacedDigit()
                .foregroundColor(.white)
                .frame(minWidth: 30)
            Stepper("", value: value, in: range)
                .labelsHidden()
                .tint(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value.wrappedValue)")
    }

    // MARK: - Logic

    private var canAddPrompt: Bool {
        let trimmed = newPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 3 && settings.customPrompts.count < 30
    }

    private func addPrompt() {
        let trimmed = newPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canAddPrompt, !settings.customPrompts.contains(trimmed) else { return }
        PC.haptic()
        settings.customPrompts.append(String(trimmed.prefix(140)))
        newPrompt = ""
    }

    private func isSelected(_ pack: PromptPack) -> Bool {
        settings.packSlugs.contains(pack.slug)
    }

    private func togglePack(_ pack: PromptPack) {
        if let index = settings.packSlugs.firstIndex(of: pack.slug) {
            settings.packSlugs.remove(at: index)
        } else {
            settings.packSlugs.append(pack.slug)
        }
    }

    private func loadPacks() async {
        do {
            let loaded = try await gameService.listPromptPacks()
            packs = loaded
            if settings.packSlugs.isEmpty && !isEditing {
                settings.packSlugs = loaded.filter { $0.isDefault }.map { $0.slug }
            }
        } catch {
            packsFailed = true
        }
    }

    private func create() async {
        promptFocused = false
        if isEditing {
            if await session.updateSettings(settings) {
                PC.notify(.success)
                onSaved?()
            }
            return
        }
        let name = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if await session.createGame(username: name, settings: settings) {
            PC.notify(.success)
            navigator.popToRoot()
        }
    }
}
