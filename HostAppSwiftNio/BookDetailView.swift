import SwiftUI

struct BookDetailView: View {
    let book: Book

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label(book.title, systemImage: book.imageName)
                    .font(.title)
                    .bold()

                Text("by \(book.author)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(book.description)
                    .font(.body)
                    .padding(.top, 8)

                Text("Price: \(book.price)")
                    .font(.headline)
                    .padding(.top, 16)

                Link("Open mock website", destination: URL(string: "http://127.0.0.1:8080/")!)
                    .padding(.top, 20)
            }
            .padding()
        }
        .navigationTitle("Book Details")
    }
}

#Preview {
    NavigationStack {
        BookDetailView(book: BookData.sampleBooks[0])
    }
}
