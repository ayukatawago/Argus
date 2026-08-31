import Foundation
import Testing

@testable import AgentStateKit

@Suite("SessionActivityArbiter")
struct SessionActivityArbiterTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let window: TimeInterval = 900

    private typealias Observation = SessionActivityArbiter.SessionObservation

    private func observation(cwd: String, state: String, secondsAgo: TimeInterval) -> Observation {
        Observation(cwd: cwd, state: state, lastActivity: now.addingTimeInterval(-secondsAgo))
    }

    private func resolvedState(_ observations: [Observation], for cwd: String) -> String? {
        SessionActivityArbiter.resolve(observations, now: now, window: window)[cwd]
    }

    // MARK: - resolve

    @Test("a single fresh observation publishes its state")
    func singleFreshObservationPublishes() {
        let obs = observation(cwd: "/repo", state: "running", secondsAgo: 10)
        #expect(resolvedState([obs], for: "/repo") == "running")
    }

    @Test("a stale observation (mtime-touched but content long outside the window) is dropped and never publishes")
    func staleObservationIsDropped() {
        let obs = observation(cwd: "/repo", state: "done", secondsAgo: 40 * 24 * 3_600)
        #expect(resolvedState([obs], for: "/repo") == nil)
    }

    @Test("a live running file beats a just-finished sibling on the same cwd, regardless of input order")
    func liveRunningBeatsJustFinishedSibling() {
        let live = observation(cwd: "/repo", state: "running", secondsAgo: 5)
        let finished = observation(cwd: "/repo", state: "done", secondsAgo: 300)
        #expect(resolvedState([live, finished], for: "/repo") == "running")
        #expect(resolvedState([finished, live], for: "/repo") == "running")
    }

    @Test("once the live session itself finishes, its newer done wins over an older running sibling")
    func newerDoneWinsOverOlderRunning() {
        let olderRunning = observation(cwd: "/repo", state: "running", secondsAgo: 300)
        let newlyDone = observation(cwd: "/repo", state: "done", secondsAgo: 5)
        #expect(resolvedState([olderRunning, newlyDone], for: "/repo") == "done")
    }

    @Test("a future-dated observation is dropped rather than pinning the cwd")
    func futureDatedObservationIsDropped() {
        let obs = observation(cwd: "/repo", state: "done", secondsAgo: -60)
        #expect(resolvedState([obs], for: "/repo") == nil)
    }

    @Test("an exact tie on lastActivity resolves by displayPriority, identically for both input orders")
    func exactTieResolvesByDisplayPriority() {
        let running = observation(cwd: "/repo", state: "running", secondsAgo: 5)
        let waiting = observation(cwd: "/repo", state: "waitingForApproval", secondsAgo: 5)
        #expect(resolvedState([running, waiting], for: "/repo") == "waitingForApproval")
        #expect(resolvedState([waiting, running], for: "/repo") == "waitingForApproval")
    }

    @Test("two different cwds each resolve independently")
    func independentCwdsResolveIndependently() {
        let repoA = observation(cwd: "/repo-a", state: "running", secondsAgo: 5)
        let repoB = observation(cwd: "/repo-b", state: "done", secondsAgo: 5)
        let resolved = SessionActivityArbiter.resolve([repoA, repoB], now: now, window: window)
        #expect(resolved == ["/repo-a": "running", "/repo-b": "done"])
    }

    // MARK: - emissions

    @Test("a cwd dropping out of resolved (every bound file went stale) emits idle once")
    func cwdDroppingOutOfResolvedEmitsIdle() {
        let emissions = SessionActivityArbiter.emissions(resolved: [:], lastEmitted: ["/repo": "done"])
        #expect(emissions == [SessionActivityArbiter.StateEmission(cwd: "/repo", state: "idle")])
    }

    @Test("idle is not re-emitted once already published")
    func idleIsNotReEmittedOnceAlreadyPublished() {
        let emissions = SessionActivityArbiter.emissions(resolved: [:], lastEmitted: ["/repo": "idle"])
        #expect(emissions.isEmpty)
    }

    @Test("an unchanged resolved state produces no emission")
    func unchangedStateProducesNoEmission() {
        let lastEmitted = ["/repo": "running"]
        let emissions = SessionActivityArbiter.emissions(resolved: ["/repo": "running"], lastEmitted: lastEmitted)
        #expect(emissions.isEmpty)
    }

    @Test("a new cwd with no prior emission publishes immediately")
    func newCwdWithNoPriorEmissionPublishes() {
        let emissions = SessionActivityArbiter.emissions(resolved: ["/repo": "running"], lastEmitted: [:])
        #expect(emissions == [SessionActivityArbiter.StateEmission(cwd: "/repo", state: "running")])
    }

    @Test("two cwds publish independently, sorted by cwd for deterministic ordering")
    func multipleCwdsPublishSortedByCwd() {
        let resolved = ["/z-repo": "done", "/a-repo": "running"]
        let emissions = SessionActivityArbiter.emissions(resolved: resolved, lastEmitted: [:])
        #expect(
            emissions == [
                SessionActivityArbiter.StateEmission(cwd: "/a-repo", state: "running"),
                SessionActivityArbiter.StateEmission(cwd: "/z-repo", state: "done"),
            ])
    }
}
