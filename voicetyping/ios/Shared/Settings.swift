import Foundation

final class Settings {

    static let shared = Settings()

    private let defaults: UserDefaults

    init(suiteName: String = "group.com.voicetyping.shared") {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    var selectedMode: OutputMode {
        get {
            guard let raw = defaults.string(forKey: "selectedMode"),
                  let mode = OutputMode(rawValue: raw) else { return .casual }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: "selectedMode") }
    }

    var proxyURL: String {
        get { defaults.string(forKey: "proxyURL") ?? "https://asia-northeast1-voicetyping-prod.cloudfunctions.net/formatText" }
        set { defaults.set(newValue, forKey: "proxyURL") }
    }

    var customAPIKey: String? {
        get { defaults.string(forKey: "customAPIKey") }
        set { defaults.set(newValue, forKey: "customAPIKey") }
    }

    var deviceId: String {
        if let id = defaults.string(forKey: "deviceId") { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: "deviceId")
        return id
    }
}
