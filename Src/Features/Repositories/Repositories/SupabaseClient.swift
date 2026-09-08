//
//  SupabaseClient.swift
//  Repositories
//

import Foundation
import Supabase
import Common

final class SupabaseProfileClient: @unchecked Sendable {
    static let shared = SupabaseProfileClient()

    let client: SupabaseClient

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

    init(client: SupabaseClient) {
        self.client = client
    }

    var database: PostgrestClient {
        client.database
    }

    var auth: AuthClient {
        client.auth
    }
}

typealias PostgrestClient = Supabase.PostgrestClient
typealias AuthClient = Supabase.AuthClient
