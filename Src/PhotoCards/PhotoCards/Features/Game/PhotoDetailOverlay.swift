//
//  PhotoDetailOverlay.swift
//  PhotoCards
//
//  Enlarged photo with the primary action (submit / pick / vote) and a
//  report entry point. The report sheet itself lives in GameSessionView so
//  it survives the game moving on to the next phase.
//

import SwiftUI
import Common

struct PhotoDetailOverlay: View {
    @Environment(\.gameModeration) private var moderation

    let imageURL: URL
    let prompt: String?
    /// Title of the main button. When `onPrimary` is nil the button is shown
    /// disabled, which explains why the action isn't available.
    let primaryTitle: String?
    let primaryIcon: String
    let isBusy: Bool
    let onPrimary: (() -> Void)?
    let onClose: () -> Void
    var reportUserId: UUID? = nil
    let reportPhotoId: UUID?

    var body: some View {
        ZStack {
            Color.black.opacity(0.88)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
                .accessibilityHidden(true)

            VStack(spacing: 14) {
                HStack {
                    Button {
                        moderation.report(ReportTarget(
                            kind: .photo,
                            reportedUserId: reportUserId,
                            photoId: reportPhotoId,
                            context: prompt.map { "Prompt: \($0)" }
                        ))
                    } label: {
                        Label("Report", systemImage: "flag")
                            .font(Font.poppins(.semiBold, size: 13))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 40)
                            .background(Capsule().fill(Color.black.opacity(0.35)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Report this photo")

                    Spacer()

                    RoundIconButton(icon: "xmark", label: "Close preview") { onClose() }
                }

                if let prompt {
                    Text(prompt)
                        .font(Font.poppins(.semiBold, size: 15))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 12)
                }

                RemoteImage(url: imageURL, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 460)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                    .layoutPriority(-1)
                    .accessibilityHidden(true)

                Spacer(minLength: 0)

                if let primaryTitle {
                    Button {
                        guard let onPrimary else { return }
                        PC.haptic(.medium)
                        onPrimary()
                    } label: {
                        HStack(spacing: 10) {
                            if isBusy { ProgressView().tint(.white) }
                            Label(primaryTitle, systemImage: primaryIcon)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .buttonStyle(PillButtonStyle(fill: onPrimary == nil ? Color.white.opacity(0.18) : PC.red))
                    .disabled(isBusy || onPrimary == nil)
                } else {
                    Text("Tap anywhere to close")
                        .font(Font.poppins(.regular, size: 13))
                        .foregroundColor(.white.opacity(0.6))
                        .accessibilityHidden(true)
                }
            }
            .padding(20)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { onClose() }
    }
}
