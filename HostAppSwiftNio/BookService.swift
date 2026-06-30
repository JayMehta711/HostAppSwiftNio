import Foundation

enum BookServiceError: Error, LocalizedError {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid products URL."
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server."
        case .decodingFailed(let error):
            return "Decoding failed: \(error.localizedDescription)"
        }
    }
}

struct BookService {
    private let baseURL = URL(string: "http://127.0.0.1:8080")!

    func fetchBooks() async throws -> [Book] {
        let endpoint = baseURL.appendingPathComponent("api/products")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw BookServiceError.invalidResponse
            }
            do {
                return try JSONDecoder().decode([Book].self, from: data)
            } catch {
                throw BookServiceError.decodingFailed(error)
            }
        } catch {
            throw BookServiceError.requestFailed(error)
        }
    }
}
