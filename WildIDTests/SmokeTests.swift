import XCTest
@testable import WildID

final class SmokeTests: XCTestCase {
    func testGroupsFromAncestry() {
        XCTAssertEqual(AnimalGroup.from(ancestorIDs: [48460, 1, 2, 355675, 3, 4954]), .birds)
        XCTAssertEqual(AnimalGroup.from(ancestorIDs: [1, 47120, 47158]), .insects)
        XCTAssertEqual(AnimalGroup.from(ancestorIDs: [1]), .other)
    }
}
