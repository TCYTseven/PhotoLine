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
        client = SupabaseClient(
            supabaseURL: URL(string: EnvironmentVars.SUPABASE_URL)!,
            supabaseKey: EnvironmentVars.SUPABASE_ANON_KEY
        )
    }

    /// For testing purposes
    public init(client: SupabaseClient) {
        self.client = client
    }
}
