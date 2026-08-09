@testable import BookLensCodex
import BookLensSupport
import Foundation
import XCTest

final class CodexAuthenticationURLTests: XCTestCase {
    func testAcceptsOfficialHTTPSAuthenticationHosts() throws {
        let openAI = URL(string: "https://auth.openai.com/authorize")!
        let chatGPT = URL(string: "https://chatgpt.com/auth/device")!
        XCTAssertEqual(try CodexAppServerSession.validateAuthenticationURL(openAI), openAI)
        XCTAssertEqual(try CodexAppServerSession.validateAuthenticationURL(chatGPT), chatGPT)
    }

    func testRejectsHTTPAndLookalikeHosts() {
        XCTAssertThrowsError(
            try CodexAppServerSession.validateAuthenticationURL(
                URL(string: "http://auth.openai.com/authorize")!
            )
        )
        XCTAssertThrowsError(
            try CodexAppServerSession.validateAuthenticationURL(
                URL(string: "https://openai.com.attacker.example/authorize")!
            )
        )
    }
}
