import UIKit

/// A printable PDF summary of the last `days` days.
enum FoodReport {
    static func make(
        entries: [MealEntry], weights: [WeightRecord], goals: NutritionGoals,
        days: Int = 30, now: Date = .now, calendar: Calendar = .current,
        directory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) ?? now
        let periodEntries = entries.filter { $0.date >= start && $0.date <= now }
        let byDay = Dictionary(grouping: periodEntries) { calendar.startOfDay(for: $0.date) }
        let sortedDays = byDay.keys.sorted(by: >)
        let periodWeights = weights.filter { $0.date >= start && $0.date <= now }.sorted { $0.date < $1.date }

        let fileName = "FoodLens-звіт-\(now.formatted(.iso8601.year().month().day())).pdf"
        let url = directory.appendingPathComponent(fileName)
        let page = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 in points
        let margin: CGFloat = 42
        let contentWidth = page.width - margin * 2

        try UIGraphicsPDFRenderer(bounds: page).writePDF(to: url) { context in
            var y = margin
            context.beginPage()

            func draw(_ text: String, size: CGFloat = 11, bold: Bool = false, color: UIColor = .black) {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size),
                    // Explicit colours: `.label` turns white in dark mode and the text would vanish on paper.
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]
                let height = ceil((text as NSString).boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin], attributes: attributes, context: nil
                ).height)
                if y + height > page.height - margin {
                    context.beginPage()
                    y = margin
                }
                (text as NSString).draw(in: CGRect(x: margin, y: y, width: contentWidth, height: height), withAttributes: attributes)
                y += height + 6
            }

            let loggedDays = max(sortedDays.count, 1)
            let totalCalories = NutritionTotals(entries: periodEntries)
            draw("FoodLens — звіт про харчування", size: 22, bold: true)
            draw("Період: \(start.formatted(date: .long, time: .omitted)) — \(now.formatted(date: .long, time: .omitted))", color: .darkGray)
            draw("Створено: \(now.formatted(date: .long, time: .shortened))", color: .darkGray)
            y += 8
            draw("Підсумок", size: 15, bold: true)
            draw("Днів із записами: \(sortedDays.count) · Страв: \(periodEntries.count)")
            draw("Середньо за день: \(totalCalories.kcal / loggedDays) ккал (ціль \(Int(goals.calories)) ккал)")
            draw("Білки \(Int(totalCalories.protein) / loggedDays) г · Жири \(Int(totalCalories.fat) / loggedDays) г · Вуглеводи \(Int(totalCalories.carbs) / loggedDays) г на день")
            if let first = periodWeights.first, let last = periodWeights.last {
                let change = last.kilograms - first.kilograms
                draw("Вага: \(first.kilograms.formatted()) → \(last.kilograms.formatted()) кг (\(change >= 0 ? "+" : "")\(change.formatted(.number.precision(.fractionLength(1)))) кг)")
            }

            for day in sortedDays {
                let dayEntries = (byDay[day] ?? []).sorted { $0.date < $1.date }
                let dayTotals = NutritionTotals(entries: dayEntries)
                y += 10
                draw("\(day.formatted(date: .complete, time: .omitted)) — \(dayTotals.kcal) ккал", size: 13, bold: true)
                for entry in dayEntries {
                    let weight = entry.grams > 0 ? ", \(Int(entry.grams)) г" : ""
                    draw("\(entry.date.formatted(date: .omitted, time: .shortened))  \(entry.mealType.title): \(entry.name)\(weight) — \(entry.kcal) ккал · Б \(Int(entry.protein)) Ж \(Int(entry.fat)) В \(Int(entry.carbs))")
                }
            }
            if sortedDays.isEmpty {
                y += 10
                draw("За цей період записів немає.", color: .darkGray)
            }
        }
        return url
    }
}
