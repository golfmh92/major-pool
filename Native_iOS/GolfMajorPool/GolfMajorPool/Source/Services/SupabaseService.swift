import Foundation
import Supabase

enum SupabaseConfig {
    static let url = URL(string: "https://sagxezwnwsukmgqfjlci.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNhZ3hlendud3N1a21ncWZqbGNpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYyNDk5MTIsImV4cCI6MjA5MTgyNTkxMn0.0DSywYy6hli0kDmb7ZPspBGegsOK4NM8F7LyQBeOi94"
}

enum SB {
    static let client = SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.anonKey
    )
}
