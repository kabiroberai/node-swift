import NodeAPI
import NodeJSC
import XCTest

final class NodeJSCTests: XCTestCase {
    func testBasic() {
        var ran = false
        NodeEnvironment.withJSC {
            let string = try NodeString("Hello, world!")
            XCTAssertEqual(try string.string(), "Hello, world!")
            ran = true
        }
        XCTAssert(ran)
    }
}
