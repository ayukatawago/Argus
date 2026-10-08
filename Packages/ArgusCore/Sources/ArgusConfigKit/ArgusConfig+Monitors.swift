import Foundation

extension ArgusConfig {
    public struct PopupShortcut: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var name: String
        public var key: String
        public var command: String
        public var sizePercent: Int

        public init(id: String, name: String, key: String, command: String, sizePercent: Int) {
            self.id = id
            self.name = name
            self.key = key
            self.command = command
            self.sizePercent = sizePercent
        }

        /// `key` and `command` are what make a shortcut meaningful, so a shortcut lacking either is
        /// rejected (and dropped by the lossy array decode). `id`/`name`/`sizePercent` fall back to
        /// sensible values; `sizePercent` is clamped to a window size that can actually be shown.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: RawStringKey.self)
            let key = try container.decode(String.self, forKey: RawStringKey("key"))
            let command = try container.decode(String.self, forKey: RawStringKey("command"))
            let name = (try? container.decodeIfPresent(String.self, forKey: RawStringKey("name"))) ?? command
            self.init(
                id: (try? container.decodeIfPresent(String.self, forKey: RawStringKey("id"))) ?? name,
                name: name,
                key: key,
                command: command,
                sizePercent: min(
                    max((try? container.decodeIfPresent(Int.self, forKey: RawStringKey("sizePercent"))) ?? 80, 10), 100)
            )
        }

        public static let lazygitDefault = PopupShortcut(
            id: "lazygit",
            name: "lazygit",
            key: "g",
            command: "lazygit",
            sizePercent: 80
        )
    }

    /// A polling interval that is safe to turn into a sleep: finite and at least one second. A
    /// hand-edited negative, zero or NaN value would otherwise spin the poll loop or trap converting
    /// to `UInt64` nanoseconds.
    public static func sanitizedInterval(_ seconds: Double, default fallback: Double) -> Double {
        guard seconds.isFinite else { return fallback }
        return max(seconds, 1)
    }

    /// `sanitizedInterval` as a `Task.sleep`-ready nanosecond count (capped at one day, so the
    /// multiplication can never overflow `UInt64`).
    public static func intervalNanoseconds(_ seconds: Double, default fallback: Double) -> UInt64 {
        UInt64(min(sanitizedInterval(seconds, default: fallback), 86_400) * 1_000_000_000)
    }

    public struct DiskMonitor: Codable, Equatable, Sendable {
        public var checkIntervalSeconds: Double = 60
        public var alertThresholdPercent: Double = 5.0
        public var sizeCheckIntervalSeconds: Double = 1800

        public init() {}

        // Per-key defaults, so `{"diskMonitor":{"checkIntervalSeconds":30}}` keeps the other fields
        // instead of failing the decode and resetting the whole config.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: RawStringKey.self)
            func read(_ key: String, _ fallback: Double) -> Double {
                (try? container.decodeIfPresent(Double.self, forKey: RawStringKey(key))) ?? fallback
            }
            checkIntervalSeconds = ArgusConfig.sanitizedInterval(read("checkIntervalSeconds", 60), default: 60)
            alertThresholdPercent = read("alertThresholdPercent", 5.0)
            sizeCheckIntervalSeconds = ArgusConfig.sanitizedInterval(
                read("sizeCheckIntervalSeconds", 1800), default: 1800)
        }
    }

    public struct GitHub: Codable, Equatable, Sendable {
        public var apiBaseURL: String = "https://api.github.com"
        public var token: String = ""
        public var refreshIntervalSeconds: Double = 300

        public init() {}

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: RawStringKey.self)
            func read<T: Decodable>(_ key: String, _ fallback: T) -> T {
                (try? container.decodeIfPresent(T.self, forKey: RawStringKey(key))) ?? fallback
            }
            apiBaseURL = read("apiBaseURL", "https://api.github.com")
            token = read("token", "")
            refreshIntervalSeconds = ArgusConfig.sanitizedInterval(read("refreshIntervalSeconds", 300), default: 300)
        }
    }
}
