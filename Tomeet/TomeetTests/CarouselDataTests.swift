import Foundation
import Testing
@testable import Tomeet

struct CarouselDataTests {
    @Test func recentFirstThenRestByTitle() {
        let zebra = Book(title: "Zebra", author: "A", format: .epub,
                         lastOpenedDate: Date(timeIntervalSinceNow: -100))
        let apple = Book(title: "Apple", author: "A", format: .epub)   // 未读过
        let mango = Book(title: "Mango", author: "A", format: .epub,
                         lastOpenedDate: .now)
        let result = CarouselData.books([zebra, apple, mango])
        #expect(result.map(\.title) == ["Mango", "Zebra", "Apple"])
    }

    @Test func emptyInputGivesEmpty() {
        #expect(CarouselData.books([]).isEmpty)
    }

    @Test func allReadKeepsRecentOrder() {
        let old = Book(title: "B", author: "A", format: .epub,
                       lastOpenedDate: Date(timeIntervalSinceNow: -200))
        let new = Book(title: "A", author: "A", format: .epub,
                       lastOpenedDate: .now)
        #expect(CarouselData.books([old, new]).map(\.title) == ["A", "B"])
    }
}
