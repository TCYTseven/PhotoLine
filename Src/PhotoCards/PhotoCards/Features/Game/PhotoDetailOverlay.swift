//
//  PhotoDetailOverlay.swift
//  PhotoCards
//
//  Enlarged photo with the primary action (submit / pick / vote) and a
//  report entry point.
//

import SwiftUI
import Common

struct PhotoDetailOverlay: View {
    let imageURL: URL
    let prompt: String?
    let primaryTitle: String?
    let primaryIcon: String
    let isBusy: Bool
    let onPrimary: (() -> Void)?
    let onClose: () -> Void
    let reportUserId: UUID?
    let reportPhotoId: UUID?

    @State private var showReport = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 16) {
                HStack {
                    RoundIconButton(icon: "xmark", label: "Close") { onClose() }
                    Spacer()
                    RoundIconButton(icon: "flag", label: "Report this photo") { showReport = true }
                }

                if let prompt {
                    Text(prompt)
                        .font(Font.poppins(.semiBold, size: 15))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }

                RemoteImage(url: imageURL, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 460)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)

                Spacer(minLength: 0)

                if let primaryTitle, let onPrimary {
                    Button {
                        PC.haptic(.medium)
                        onPrimary()
                    } label: {
                        HStack(spacing: 10) {
                            if isBusy { ProgressView().tint(.white) }
                            Label(primaryTitle, systemImage: primaryIcon)
                        }
                    }
                    .buttonStyle(PillButtonStyle())
                    .disabled(isBusy)
                } else {
                    Text("Tap anywhere to close")
                        .font(Font.poppins(.regular, size: 13))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showReport) {
            ReportSheet(reportedUserId: reportUserId, photoId: reportPhotoId)
        }
    }
}

// MARK: - Report sheet

struct ReportSheet: View {
    @EnvironmentObject private var session: GameSessionStore
    @Environment(\.dismiss) private var dismiss

    let reportedUserId: UUID?
    let photoId: UUID?

    private let reasons = [
        "Inappropriate or explicit photo",
        "Hateful or harassing content",
        "Offensive name or prompt",
        "Spam or cheating",
        "Something else"
    ]

    @State private var reason: String = "Inappropriate or explicit photo"
    @State private var details = ""
    @State private var alsoBlock = false
    @State private var isSending = false
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                Section("What's wrong?") {
                    Picker("Reason", selection: $reason) {
                        ForEach(reasons, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Details (optional)") {
                    TextField("Tell us more", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }
                if reportedUserId != nil {
                    Section {
                        Toggle("Also block this player", isOn: $alsoBlock)
                    } footer: {
                        Text("Blocked players can't join rooms you host, and you won't see theirs.")
                    }
                }
                Section {
                    Text("Reports are reviewed by the PhotoCards team. Repeated abuse leads to removal from the game.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await send() }
                    } label: {
                        if isSending { ProgressView() } else { Text("Send") }
                    }
                    .disabled(isSending)
                }
            }
            .alert("Thanks for the report", isPresented: $sent) {
                Button("Done") { dismiss() }
            } message: {
                Text("We'll take a look.")
            }
        }
    }

    private func send() async {
        isSending = true
        let ok = await session.report(reason: reason, details: details.isEmpty ? nil : details, reportedUserId: reportedUserId, photoId: photoId)
        if ok, alsoBlock, let reportedUserId {
            _ = await session.block(userId: reportedUserId)
        }
        isSending = false
        if ok { sent = true }
    }
}
