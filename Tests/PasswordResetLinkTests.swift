import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import SeruCore
#else
@testable import SeruendeshAI
#endif

struct PasswordResetLinkTests {
    @Test func acceptsOnlyResetEntryPointsAndOneValidToken() {
        let token = "a-secure-random-reset-token-12345"
        #expect(PasswordResetLink.token(from: URL(string: "https://seruendesh.site/reset-password?token=\(token)")!) == token)
        #expect(PasswordResetLink.token(from: URL(string: "seruendesh://reset-password?token=\(token)")!) == token)
        for raw in ["https://other.example/reset-password?token=\(token)", "https://seruendesh.site/unrelated?token=\(token)", "http://seruendesh.site/reset-password?token=\(token)", "seruendesh://other?token=\(token)", "seruendesh://reset-password?token=short", "seruendesh://reset-password?token=\(token)&token=\(token)"] {
            #expect(PasswordResetLink.token(from: URL(string: raw)!) == nil)
        }
    }
}
