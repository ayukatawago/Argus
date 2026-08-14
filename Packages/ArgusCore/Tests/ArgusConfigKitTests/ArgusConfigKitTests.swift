import Foundation
import Testing

@testable import ArgusConfigKit

@Suite("ArgusConfigKit smoke test")
struct ArgusConfigKitSmokeTests {
    @Test("a default-constructed config round-trips through JSON")
    func defaultConfigRoundTrips() throws {
        let config = ArgusConfig()
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ArgusConfig.self, from: data)
        #expect(decoded == config)
    }
}
