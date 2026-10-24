import SwiftUI

struct PhotoCreditsView: View {
    @Environment(\.dismiss) private var dismiss
    private let credits = PhotoCredit.load()

    var body: some View {
        NavigationStack {
            List {
                ForEach(credits) { credit in
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(credit.title).font(.headline)
                            Text(credit.author).font(.body)
                            Text(credit.changes).font(.footnote).foregroundStyle(.secondary)
                            Link("Исходная фотография", destination: credit.sourceURL)
                                .frame(minHeight: 44)
                            Link(credit.license, destination: credit.licenseURL)
                                .frame(minHeight: 44)
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section {
                    Text("Фотографии мест сопровождаются именами авторов и ссылками на исходники. Изображения локальных примеров событий используются как иллюстрации.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Фотографии")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }.frame(minHeight: 44)
                }
            }
            .accessibilityIdentifier("photo-credits-content")
        }
        .tint(SeruColor.action)
    }
}

private struct PhotoCredit: Decodable, Identifiable {
    let title: String
    let author: String
    let license: String
    let sourceURL: URL
    let licenseURL: URL
    let changes: String
    var id: URL { sourceURL }

    static func load() -> [PhotoCredit] {
        guard let url = Bundle.main.url(forResource: "PhotoCredits", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let credits = try? JSONDecoder().decode([PhotoCredit].self, from: data) else { return [] }
        return credits
    }
}
