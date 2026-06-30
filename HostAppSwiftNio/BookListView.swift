import SwiftUI

struct BookListView: View {
    @State private var books: [Book] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    private let service = BookService()

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage {
                    VStack(spacing: 28) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(.red)
                            .padding(.bottom, 4)

                        Text("Unable to load books")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    List(books) { book in
                        NavigationLink(value: book) {
                            HStack(spacing: 16) {
                                Image(systemName: book.imageName)
                                    .resizable()
                                    .frame(width: 36, height: 36)
                                    .foregroundColor(.accentColor)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(book.title)
                                        .font(.headline)
                                    Text(book.author)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(book.price)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .navigationTitle("Book Seller")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task {
                            await refreshBooks()
                        }
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isLoading)
                }
            }
            .navigationDestination(for: Book.self) { book in
                BookDetailView(book: book)
            }
            .task {
                await refreshBooks()
            }
        }
    }

    @MainActor
    private func refreshBooks() async {
        isLoading = true
        errorMessage = nil
        do {
            books = try await service.fetchBooks()
        } catch {
            if let serviceError = error as? BookServiceError {
                errorMessage = serviceError.errorDescription
            } else {
                errorMessage = error.localizedDescription
            }
            books = BookData.sampleBooks
        }
        isLoading = false
    }
}

#Preview {
    BookListView()
}
