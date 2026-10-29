import Testing
import Foundation
@testable import ConsoleCore

@Suite struct ModelRouteTests {
    @Test func decodesRuntimeShape() throws {
        let j = #"{"default":{"provider":"ollama","model":"muse-glimmer:30b-mlx","baseURL":"http://127.0.0.1:11434/v1","paid":false,"skill":"chat","why":"default: local"},"fallback":"m3ta/qwen3-abl-8b-nothink-32k","toggles":{"agentic":{"provider":"meta","model":"muse-spark-1.3","enabled":false},"heavy":{"provider":"meta","model":"muse-wonder-1.0","enabled":false}},"jev":{"daily_usd_cap":0,"models":{}},"metaKeyPresent":false}"#
        let r = try JSONDecoder().decode(ModelRoute.self, from: Data(j.utf8))
        #expect(r.default.model == "muse-glimmer:30b-mlx")
        #expect(r.default.paid == false)
        #expect(r.paidEnabledCount == 0)
        #expect(r.jev?.daily_usd_cap == 0)
        #expect(ModelRoute.url.host == "127.0.0.1")
    }
}
