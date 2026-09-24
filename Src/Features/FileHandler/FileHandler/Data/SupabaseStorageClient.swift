//
//  SupabaseStorageClient.swift
//  FileHandler
//

import Foundation
import Supabase
import Common

final class SupabaseStorageClient: @unchecked Sendable {
    static let shared = SupabaseStorageClient()

    let client: SupabaseClient

    private init() {
        // Same guard as SupabaseClientService: the SDK traps on a URL without a host.
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

    var storage: SupabaseStorageClient_Storage {
        client.storage
    }
}

typealias SupabaseStorageClient_Storage = Supabase.SupabaseStorageClient
