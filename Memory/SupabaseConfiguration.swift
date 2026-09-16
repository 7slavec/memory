import Foundation

struct SupabaseConfiguration {
    let url: URL
    let publishableKey: String

    static var current: SupabaseConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        let bundledValues = bundledConfiguration
        let urlString = environment["SUPABASE_URL"] ?? bundledValues?["SUPABASE_URL"]
        let key = environment["SUPABASE_PUBLISHABLE_KEY"] ?? bundledValues?["SUPABASE_PUBLISHABLE_KEY"]

        guard let urlString,
              let key,
              !urlString.isEmpty,
              !key.isEmpty,
              !urlString.contains("YOUR_PROJECT"),
              !key.contains("YOUR_PUBLISHABLE_KEY"),
              let url = URL(string: urlString),
              url.scheme == "https" else {
            return nil
        }

        return SupabaseConfiguration(url: url, publishableKey: key)
    }

    private static var bundledConfiguration: [String: String]? {
        guard let url = Bundle.main.url(forResource: "SupabaseConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let values = try? PropertyListDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return values
    }
}
