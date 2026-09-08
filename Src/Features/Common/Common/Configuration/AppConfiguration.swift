//
//  AppConfiguration.swift
//  Common
//
//  Central configuration file for the app.
//  Fill in your service credentials before building.
//
//  Required setup:
//  - Supabase: https://supabase.com/dashboard/project/_/settings/api
//  - Google OAuth: https://console.cloud.google.com/apis/credentials
//  - RevenueCat: https://app.revenuecat.com/
//

import Foundation

/// Central configuration for the app
/// Fill in your values before building
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
        public static let url = "YOUR_SUPABASE_URL"
        /// Your Supabase anon/public key (Debug)
        public static let anonKey = "YOUR_SUPABASE_ANON_KEY"
        #else
        /// Your Supabase project URL (Release)
        public static let url = "YOUR_SUPABASE_URL"
        /// Your Supabase anon/public key (Release)
        public static let anonKey = "YOUR_SUPABASE_ANON_KEY"
        #endif
    }

    // MARK: - Google Sign-In
    // Get this from: https://console.cloud.google.com/apis/credentials
    // Note: Also update GIDClientID in Info.plist with this value

    public enum Google {
        /// Your Google OAuth Client ID
        public static let clientID = "YOUR_GOOGLE_CLIENT_ID"
    }

    // MARK: - RevenueCat
    // Get these from: https://app.revenuecat.com/

    public enum RevenueCat {
        #if DEBUG
        /// Your RevenueCat API key (Debug/Sandbox)
        public static let apiKey = "YOUR_REVENUECAT_API_KEY"
        #else
        /// Your RevenueCat API key (Production)
        public static let apiKey = "YOUR_REVENUECAT_API_KEY"
        #endif

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
    // Your backend API configuration

    public enum API {
        #if DEBUG
        /// API base URL for development
        public static let baseURL = "http://localhost:8080"
        #else
        /// API base URL for production
        public static let baseURL = "https://api.yourapp.com"
        #endif
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

        /// App Store ID (numeric ID from App Store Connect). Only used by the
        /// update checker; leave empty until the app is listed.
        public static let appStoreID = ""
    }
}
