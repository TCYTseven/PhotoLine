//
//  SafariView.swift
//  PhotoCards
//
//  In-app browser for the privacy policy, terms and support pages.
//

import SwiftUI
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

/// Identifiable wrapper so `.sheet(item:)` can present a URL.
struct WebPage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
