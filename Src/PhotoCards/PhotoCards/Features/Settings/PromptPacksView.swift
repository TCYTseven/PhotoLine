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
    @Injected(\.gameService) private var gameService: GameService
    @State private var packs: [PromptPack] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn't load prompt packs").font(.headline)
                    Text(errorMessage).font(.footnote).foregroundColor(.secondary)
                    Button("Try again") { Task { await load() } }
                }
            } else {
                ForEach(packs) { pack in
                    NavigationLink {
                        PromptListView(pack: pack)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(pack.name).font(.headline)
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
                                Text(description).font(.subheadline).foregroundColor(.secondary)
                            }
                            Text("\(pack.promptCount) prompts").font(.caption).foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Prompt packs")
        .navigationBarTitleDisplayMode(.inline)
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

    var body: some View {
        List {
            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else {
                ForEach(prompts) { prompt in
                    Text(prompt.text)
                }
            }
        }
        .navigationTitle(pack.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            prompts = (try? await gameService.listPrompts(packSlug: pack.slug)) ?? []
            isLoading = false
        }
    }
}
