import Foundation

enum BookData {
    static let sampleBooks: [Book] = [
        Book(
            id: UUID(),
            title: "Modern SwiftUI Patterns",
            author: "Sara Holmes",
            description: "A practical guide to building modern SwiftUI apps with real-world examples.",
            imageName: "book",
            price: "$24.99"
        ),
        Book(
            id: UUID(),
            title: "Networking with SwiftNIO",
            author: "Jordan Lee",
            description: "Learn how to build fast HTTP services and mock servers using SwiftNIO.",
            imageName: "network",
            price: "$29.99"
        ),
        Book(
            id: UUID(),
            title: "Designing Great iOS Interfaces",
            author: "Priya Kapoor",
            description: "Design polished mobile interfaces and use SwiftUI to create delightful customer experiences.",
            imageName: "paintpalette",
            price: "$19.99"
        ),
        Book(
            id: UUID(),
            title: "Swift Testing Essentials",
            author: "Alex Chen",
            description: "Master the art of testing Swift applications with real unit and UI test techniques.",
            imageName: "checkmark.seal",
            price: "$21.99"
        )
    ]
}
