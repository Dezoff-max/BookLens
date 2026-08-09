import BookLensSupport
import XCTest

final class RedactorTests: XCTestCase {
    func testRedactsEmailTokenAndUserPath() {
        let source = "email dmitry@example.com bearer secret-value path /Users/admin/private/file.txt"
        let redacted = Redactor().redact(source)

        XCTAssertFalse(redacted.contains("dmitry@example.com"))
        XCTAssertFalse(redacted.contains("secret-value"))
        XCTAssertFalse(redacted.contains("/Users/admin"))
    }
}
