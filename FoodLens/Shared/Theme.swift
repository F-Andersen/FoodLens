import SwiftUI

enum Theme {
    static let accent = Color(red: 0.10, green: 0.72, blue: 0.42)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let calorieGradient = LinearGradient(
        colors: [Color(red: 0.08, green: 0.68, blue: 0.39), Color(red: 0.22, green: 0.82, blue: 0.55)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

extension View {
    func cardStyle() -> some View {
        padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.primary.opacity(0.045)) }
    }
}

/// Progress for `value / goal`, safe when the goal is zero.
func progress(_ value: Double, of goal: Double) -> Double {
    goal > 0 ? min(max(value / goal, 0), 1) : 0
}

struct NutritionSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String

    var body: some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: "\(Int(value.rounded())) \(unit)")
            Slider(value: $value, in: range, step: 1)
        }
    }
}

struct NumberFieldRow: View {
    let title: String
    @Binding var value: Double
    let unit: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: $value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

struct MealRow: View {
    let entry: MealEntry

    private var details: String {
        var parts = [entry.mealType.title]
        if entry.grams > 0 { parts.append("\(Int(entry.grams.rounded())) г") }
        parts.append("Б \(Int(entry.protein))  Ж \(Int(entry.fat))  В \(Int(entry.carbs))")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(entry.name).font(.headline)
                if entry.isFavorite { Image(systemName: "star.fill").foregroundStyle(.yellow).accessibilityLabel("Обране") }
                Spacer()
                Text("\(entry.kcal) ккал").bold()
            }
            Text(details).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct StorageIssueBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) { Image(systemName: "xmark").font(.footnote.bold()) }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрити")
        }
        .padding(12)
        .background(.orange.opacity(0.12))
    }
}

/// Presents the system share sheet for a file.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
