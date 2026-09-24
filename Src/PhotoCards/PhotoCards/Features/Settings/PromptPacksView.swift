//
//  PromptPacksView.swift
//  PhotoCards
//
//  Browse the prompt packs and their prompts.
//

import SwiftUI
import Common
import Factory

struct PromptPacksView: View {
    @AppStorage(AppStorageKeys.selectedPromptPacks) private var selectedPacks = "party-mix"

    private func toggle(_ slug: String) {
        // Drop slugs of packs that no longer exist, so a stale one can't be
        // the "last selected pack" that blocks deselecting a real one.
        let known = Set(packs.map { $0.slug })
        var selected = selectedPacks.split(separator: ",").map(String.init).filter { known.contains($0) }
        if selected.contains(slug) {
            guard selected.count > 1 else { return }
            selected.removeAll { $0 == slug }
        } else {
            selected.append(slug)
        }
        selectedPacks = selected.joined(separator: ",")
        PC.haptic()
    }

    @Injected(\.gameService) private var gameService: GameService
    @State private var packs: [PromptPack] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            Group {
            Section {
                Text("Choose the packs your next game uses. Tap the circle to select a pack; open a pack to preview its prompts.")
                    .font(Font.poppins(.regular, size: 13))
                    .foregroundStyle(.white.opacity(0.7))
            }
            if isLoading && packs.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let errorMessage, packs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn't load prompt packs").font(Font.poppins(.semiBold, size: 16))
                    Text(errorMessage).font(.footnote).foregroundColor(.white.opacity(0.65))
                    Button("Try again") { Task { await load() } }
                        .buttonStyle(.borderless)
                }
            } else {
                ForEach(packs) { pack in
                    HStack(spacing: 12) {
                        let selected = selectedPacks.split(separator: ",").contains(Substring(pack.slug))
                        Button { toggle(pack.slug) } label: {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 26))
                                .foregroundStyle(selected ? PC.red : .white.opacity(0.5))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(pack.name)
                        .accessibilityValue(selected ? "Selected" : "Not selected")
                        .accessibilityHint(selected ? "Removes this pack from your next game" : "Adds this pack to your next game")
                    NavigationLink {
                        PromptListView(pack: pack)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(pack.name).font(Font.poppins(.semiBold, size: 16))
                                if pack.isDefault {
                                    Text("Default")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(PC.red.opacity(0.15)))
                                        .foregroundColor(PC.red)
                                }
                            }
                            if let description = pack.description {
                                Text(description).font(Font.poppins(.regular, size: 12)).foregroundColor(.white.opacity(0.65))
                            }
                            Text("\(pack.promptCount) prompts").font(Font.poppins(.medium, size: 11)).foregroundColor(.white.opacity(0.65))
                        }
                        .padding(.vertical, 4)
                    }
                    }
                }
            }
            }
            .listRowBackground(Color.white.opacity(0.10))
            .listRowSeparatorTint(.white.opacity(0.12))
        }
        .navigationTitle("Prompt packs")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(GameListStyle())
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            packs = try await gameService.listPromptPacks()
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct PromptListView: View {
    @Injected(\.gameService) private var gameService: GameService
    let pack: PromptPack
    @State private var prompts: [PromptItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            Group {
            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn't load prompts").font(Font.poppins(.semiBold, size: 16))
                    Text(errorMessage).font(.footnote).foregroundColor(.white.opacity(0.65))
                    Button("Try again") { Task { await load() } }
                        .buttonStyle(.borderless)
                }
            } else if prompts.isEmpty {
                Text("This pack has no prompts yet.")
                    .foregroundColor(.white.opacity(0.7))
            } else {
                ForEach(prompts) { prompt in
                    Text(prompt.text)
                }
            }
            }
            .listRowBackground(Color.white.opacity(0.10))
            .listRowSeparatorTint(.white.opacity(0.12))
        }
        .navigationTitle(pack.name)
        .navigationBarTitleDisplayMode(.inline)
        .modifier(GameListStyle())
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            prompts = try await gameService.listPrompts(packSlug: pack.slug)
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
