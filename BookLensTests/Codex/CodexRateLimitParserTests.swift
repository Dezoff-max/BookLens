@testable import BookLensCodex
import BookLensDomain
import Foundation
import Testing

struct CodexRateLimitParserTests {
    @Test func parsesMainWeeklyLimitAndRemainingPercent() throws {
        let response: JSONValue = [
            "rateLimits": [
                "limitId": "codex",
                "primary": [
                    "usedPercent": 81,
                    "windowDurationMins": 10_080,
                    "resetsAt": 1_786_183_474,
                ],
            ],
            "rateLimitsByLimitId": [
                "codex": [
                    "limitId": "codex",
                    "primary": [
                        "usedPercent": 81,
                        "windowDurationMins": 10_080,
                        "resetsAt": 1_786_183_474,
                    ],
                ],
                "codex_bengalfox": [
                    "limitId": "codex_bengalfox",
                    "primary": ["usedPercent": 5],
                ],
            ],
        ]

        let snapshot = CodexRateLimitParser().parsePrimary(from: response)

        #expect(snapshot?.limitID == "codex")
        #expect(snapshot?.usedPercent == 81)
        #expect(snapshot?.remainingPercent == 19)
        #expect(snapshot?.windowDurationMinutes == 10_080)
        #expect(snapshot?.resetsAt?.timeIntervalSince1970 == 1_786_183_474)
    }

    @Test func returnsNilWhenPrimaryWindowIsUnavailable() {
        let response: JSONValue = ["rateLimits": ["limitId": "codex"]]
        #expect(CodexRateLimitParser().parsePrimary(from: response) == nil)
    }

    @Test func fallsBackWhenNamedCodexBucketHasNoPrimaryWindow() {
        let response: JSONValue = [
            "rateLimits": [
                "limitId": "codex",
                "primary": ["usedPercent": 12],
            ],
            "rateLimitsByLimitId": [
                "codex": nil,
            ],
        ]

        let snapshot = CodexRateLimitParser().parsePrimary(from: response)

        #expect(snapshot?.usedPercent == 12)
        #expect(snapshot?.remainingPercent == 88)
    }

    @Test func findsCodexBucketByLimitIDWhenKeyChanges() {
        let response: JSONValue = [
            "rateLimitsByLimitId": [
                "primary-codex-plan": [
                    "limitId": "codex",
                    "limitName": "Codex",
                    "primary": [
                        "usedPercent": 24,
                        "windowDurationMins": 300,
                    ],
                ],
            ],
        ]

        let snapshot = CodexRateLimitParser().parsePrimary(from: response)

        #expect(snapshot?.limitID == "codex")
        #expect(snapshot?.remainingPercent == 76)
        #expect(snapshot?.windowDurationMinutes == 300)
    }

    @Test func persistsLastValidSnapshotForAReplacementSession() async throws {
        let suiteName = "BookLensTests.CodexRateLimitCache.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 1_786_000_000)
        let expected = CodexRateLimitSnapshot(
            limitID: "codex",
            limitName: "Codex",
            usedPercent: 31,
            windowDurationMinutes: 10_080,
            resetsAt: now.addingTimeInterval(3_600)
        )
        let firstSessionCache = CodexRateLimitCache(
            defaultsSuiteName: suiteName,
            defaultsKey: "snapshot",
            maximumAge: 3_600
        )
        _ = await firstSessionCache.record(expected, now: now)

        let replacementSessionCache = CodexRateLimitCache(
            defaultsSuiteName: suiteName,
            defaultsKey: "snapshot",
            maximumAge: 3_600
        )
        let restored = await replacementSessionCache.latest(now: now.addingTimeInterval(30))

        #expect(restored == expected)
    }

    @Test func discardsExpiredCachedSnapshot() async throws {
        let suiteName = "BookLensTests.CodexRateLimitCache.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 1_786_000_000)
        let cache = CodexRateLimitCache(
            defaultsSuiteName: suiteName,
            defaultsKey: "snapshot",
            maximumAge: 60
        )
        let snapshot = CodexRateLimitSnapshot(
            limitID: "codex",
            limitName: nil,
            usedPercent: 31,
            windowDurationMinutes: 300,
            resetsAt: now.addingTimeInterval(3_600)
        )
        _ = await cache.record(snapshot, now: now)

        let restored = await cache.latest(now: now.addingTimeInterval(61))

        #expect(restored == nil)
    }
}
