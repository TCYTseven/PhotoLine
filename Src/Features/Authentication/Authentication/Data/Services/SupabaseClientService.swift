//
//  SupabaseClientService.swift
//  Authentication
//
//  Shared Supabase client. One instance for the whole app so auth, database,
//  RPC and Realtime all share the same session.
//

import Foundation
import Supabase
import Common

public final class SupabaseClientService: @unchecked Sendable {
    public static let shared = SupabaseClientService()

    public let client: SupabaseClient

    private init() {
        // The SDK traps on a URL without a host. While the placeholders in
        // AppConfiguration are still in place, fall back to a syntactically
        // valid dummy so the app can show its "backend not configured" screen
        // instead of crashing on launch.
        let configured = URL(string: EnvironmentVars.SUPABASE_URL)
        let url = (configured?.host != nil ? configured : nil)
            ?? URL(string: "https://unconfigured.supabase.co")!
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: EnvironmentVars.SUPABASE_ANON_KEY
        )
    }

    /// For testing purposes
    public init(client: SupabaseClient) {
        self.client = client
    }
}
