//
//  AppConfiguration.swift
//  Common
//
//  Central configuration file for the app.
//
//  PhotoCards only talks to Supabase (guest / anonymous auth, RPCs and
//  Realtime). The Google, RevenueCat and API sections below belong to optional
//  starter modules the app does not use; they are intentionally empty.
//

import Foundation

/// Central configuration for the app
public enum AppConfiguration {

    // MARK: - Environment

    public enum Environment {
        #if DEBUG
        public static let isDebug = true
        #else
        public static let isDebug = false
        #endif
    }

    // MARK: - Supabase
    // Get these from: https://supabase.com/dashboard/project/_/settings/api

    public enum Supabase {
        /// True once real credentials replaced the placeholders below.
        public static var isConfigured: Bool {
            !url.contains("YOUR_SUPABASE") && !anonKey.contains("YOUR_SUPABASE") && URL(string: url)?.host != nil
        }

        #if DEBUG
        /// Your Supabase project URL (Debug)
        public static let url = "https://zmmtljxkbzlqbtysduxo.supabase.co"
        /// Your Supabase anon/public key (Debug)
        public static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InptbXRsanhrYnpscWJ0eXNkdXhvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg4ODk3MzAsImV4cCI6MjEwNDQ2NTczMH0.qUukjpgwYZbvtBa85Ts60pBLjzfXBpz3fY6g_izo6X4"
        #else
        /// Your Supabase project URL (Release)
        public static let url = "https://zmmtljxkbzlqbtysduxo.supabase.co"
        /// Your Supabase anon/public key (Release)
        public static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InptbXRsanhrYnpscWJ0eXNkdXhvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg4ODk3MzAsImV4cCI6MjEwNDQ2NTczMH0.qUukjpgwYZbvtBa85Ts60pBLjzfXBpz3fY6g_izo6X4"
        #endif
    }

    // MARK: - Google Sign-In
    // Not used: PhotoCards has no social sign-in. Empty disables the provider
    // (GoogleAuthProviderImpl refuses to start without a client ID).

    public enum Google {
        /// Google OAuth Client ID (unused)
        public static let clientID = ""
    }

    // MARK: - RevenueCat
    // Not used: PhotoCards has no in-app purchases. The Subscription module
    // is not imported by the app.

    public enum RevenueCat {
        /// RevenueCat API key (unused)
        public static let apiKey = ""

        /// Your RevenueCat entitlement identifier
        /// This is configured in RevenueCat dashboard under Project > Entitlements
        public static let entitlementID = "pro"
    }

    // MARK: - Deep Links
    // Configure your app's URL scheme and Universal Link domains

    public enum DeepLink {
        /// Custom URL scheme: photocards://join?code=ABC123
        public static let urlScheme = "photocards"

        /// Universal Link domains. Add your own domain (with an
        /// apple-app-site-association file) to open https links directly.
        public static let universalLinkDomains: [String] = []
    }

    // MARK: - API
    // Not used: there is no custom backend besides Supabase (HTTPNetworking
    // has no callers).

    public enum API {
        /// REST API base URL (unused)
        public static let baseURL = ""
    }

    // MARK: - App Info
    // App information fetched from Info.plist (source of truth)

    public enum App {
        /// App version from Info.plist (e.g., "1.0.0")
        public static var version: String {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        }

        /// Build number from Info.plist (e.g., "42")
        public static var buildNumber: String {
            Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        }

        /// Full version string (e.g., "1.0.0 (42)")
        public static var fullVersion: String {
            "\(version) (\(buildNumber))"
        }

        /// Bundle identifier from Info.plist
        public static var bundleID: String {
            Bundle.main.bundleIdentifier ?? "app.photocards.ios"
        }

        /// App display name from Info.plist
        public static var name: String {
            Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
                ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
                ?? "PhotoCards"
        }

        /// Public website (landing page, deployed from the repo's web/ folder).
        public static let websiteURL = "https://tcytseven.github.io/PhotoLine/"

        /// Privacy policy URL
        public static let privacyPolicyURL = "https://tcytseven.github.io/PhotoLine/privacy/"

        /// Terms of service URL
        public static let termsOfServiceURL = "https://tcytseven.github.io/PhotoLine/terms/"

        /// Help & support page (also the App Store "Support URL")
        public static let supportURL = "https://tcytseven.github.io/PhotoLine/support/"

        /// Photo credits and open-source licenses
        public static let licensesURL = "https://tcytseven.github.io/PhotoLine/licenses/"

        /// Web page that shows a room code and deep-links into the app.
        public static func joinURL(code: String) -> String {
            "https://tcytseven.github.io/PhotoLine/join/?code=\(code)"
        }

        /// App Store ID (numeric ID from App Store Connect). Only a fallback
        /// for the update checker, which prefers the store URL returned by the
        /// iTunes lookup; fill in once the app is listed.
        public static let appStoreID = ""
    }
}
