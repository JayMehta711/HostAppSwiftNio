import Foundation

struct Book: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let author: String
    let description: String
    let imageName: String
    let price: String
}
