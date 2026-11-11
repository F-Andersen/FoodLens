import SwiftUI
import UIKit

// MARK: - Tokens

enum Theme {
    /// Brand green; brighter in dark mode so it keeps contrast on dark surfaces.
    static let accent = Color(light: UIColor(red: 0.07, green: 0.60, blue: 0.35, alpha: 1),
                              dark: UIColor(red: 0.27, green: 0.84, blue: 0.53, alpha: 1))
    static let accentSoft = accent.opacity(0.14)
    static let warning = Color(light: UIColor(red: 0.90, green: 0.42, blue: 0.10, alpha: 1),
                               dark: UIColor(red: 1.00, green: 0.58, blue: 0.27, alpha: 1))
    static let water = Color(light: UIColor(red: 0.12, green: 0.47, blue: 0.95, alpha: 1),
                             dark: UIColor(red: 0.38, green: 0.66, blue: 1.00, alpha: 1))
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let track = Color(uiColor: .tertiarySystemFill)

    static let heroGradient = LinearGradient(
        colors: [Color(light: UIColor(red: 0.07, green: 0.60, blue: 0.35, alpha: 1), dark: UIColor(red: 0.05, green: 0.36, blue: 0.22, alpha: 1)),
                 Color(light: UIColor(red: 0.20, green: 0.78, blue: 0.52, alpha: 1), dark: UIColor(red: 0.10, green: 0.50, blue: 0.32, alpha: 1))],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

enum Radius {
    static let card: CGFloat = 22
    static let control: CGFloat = 14
}

extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

/// The four tracked nutrients, with one colour and icon each, used everywhere in the app.
enum Macro: CaseIterable, Identifiable {
    case protein, carbs, fat, fiber

    var id: Self { self }

    var title: String {
        switch self {
        case .protein: "Білки"
        case .carbs: "Вуглеводи"
        case .fat: "Жири"
        case .fiber: "Клітковина"
        }
    }

    var shortTitle: String {
        switch self {
        case .protein: "Б"
        case .carbs: "В"
        case .fat: "Ж"
        case .fiber: "К"
        }
    }

    var icon: String {
        switch self {
        case .protein: "fish.fill"
        case .carbs: "bolt.fill"
        case .fat: "drop.fill"
        case .fiber: "leaf.fill"
        }
    }

    var color: Color {
        switch self {
        case .protein: Color(light: UIColor(red: 0.16, green: 0.45, blue: 0.95, alpha: 1), dark: UIColor(red: 0.42, green: 0.65, blue: 1.00, alpha: 1))
        case .carbs: Color(light: UIColor(red: 0.93, green: 0.55, blue: 0.05, alpha: 1), dark: UIColor(red: 1.00, green: 0.72, blue: 0.30, alpha: 1))
        case .fat: Color(light: UIColor(red: 0.78, green: 0.25, blue: 0.70, alpha: 1), dark: UIColor(red: 0.93, green: 0.50, blue: 0.88, alpha: 1))
        case .fiber: Color(light: UIColor(red: 0.20, green: 0.62, blue: 0.30, alpha: 1), dark: UIColor(red: 0.45, green: 0.85, blue: 0.50, alpha: 1))
        }
    }

    func value(in totals: NutritionTotals) -> Double {
        switch self {
        case .protein: totals.protein
        case .carbs: totals.carbs
        case .fat: totals.fat
        case .fiber: totals.fiber
        }
    }

    /// Fat and carbohydrate goals work as upper limits; protein and fiber goals as minimums,
    /// so going over them is shown neutrally and falling short is never an error.
    var isUpperLimit: Bool { self == .fat || self == .carbs }

    func goal(in goals: NutritionGoals) -> Double {
        switch self {
        case .protein: goals.protein
        case .carbs: goals.carbs
        case .fat: goals.fat
        case .fiber: goals.fiber
        }
    }
}

extension MealEntry.MealType {
    var icon: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "carrot.fill"
        }
    }

    var tint: Color {
        switch self {
        case .breakfast: .orange
        case .lunch: .yellow
        case .dinner: .indigo
        case .snack: .pink
        }
    }
}

/// Progress for `value / goal`, safe when the goal is zero.
func progress(_ value: Double, of goal: Double) -> Double {
    goal > 0 ? min(max(value / goal, 0), 1) : 0
}

// MARK: - Modifiers

extension View {
    func cardStyle(padding: CGFloat = Spacing.l) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    /// Rounded system font for numbers; scales with Dynamic Type.
    func numberFont(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> some View {
        font(.system(style, design: .rounded, weight: weight)).monospacedDigit()
    }
}

extension View {
    /// Number pads have no return key, so every screen with input gets a «Готово» button above the
    /// keyboard, and scrolling the form also hides it.
    func keyboardDismissal() -> some View {
        scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .fontWeight(.semibold)
                }
            }
    }
}

extension Text {
    /// Text-returning variant of `numberFont`, for use inside interpolated `Text`.
    func number(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Text {
        font(.system(style, design: .rounded, weight: weight)).monospacedDigit().foregroundStyle(.primary)
    }
}

// MARK: - Components

struct SectionTitle: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold())
            Spacer()
            if let trailing { Text(trailing).font(.subheadline).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, Spacing.xs)
    }
}

/// A circular progress ring. Turns to the warning colour when the value goes over the goal.
struct ProgressRing<Center: View>: View {
    let value: Double
    let goal: Double
    var lineWidth: CGFloat = 14
    var tint: Color = Theme.accent
    @ViewBuilder var center: () -> Center

    private var fraction: Double { progress(value, of: goal) }
    private var isOver: Bool { goal > 0 && value > goal }

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(isOver ? Theme.warning : tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.6), value: fraction)
            center()
        }
        .padding(lineWidth / 2)
    }
}

/// A slim labelled progress bar for one nutrient.
struct MacroBar: View {
    let macro: Macro
    let value: Double
    let goal: Double

    private var progress: GoalProgress { GoalProgress(value: value, goal: goal, isUpperLimit: macro.isUpperLimit) }

    var body: some View {
        let progress = progress
        let isOver = progress.state == .overLimit
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: macro.icon).foregroundStyle(macro.color).font(.caption)
                Text(macro.title).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Text("\(progress.value)").number(.subheadline).foregroundStyle(isOver ? Theme.warning : .primary)) / \(progress.goal) г")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    if let marker = progress.goalMarker {
                        // Over the goal: the bar is scaled to the value and a tick shows where the goal was.
                        Capsule().fill(isOver ? Theme.warning : macro.color)
                        Rectangle().fill(Theme.card)
                            .frame(width: 2)
                            .offset(x: proxy.size.width * marker - 1)
                    } else {
                        Capsule().fill(macro.color)
                            .frame(width: proxy.size.width * progress.fraction)
                    }
                }
                .animation(.smooth, value: value)
            }
            .frame(height: 8)
            if progress.excess > 0 {
                Text(isOver ? "Перевищення: +\(progress.excess) г" : "Понад ціль: +\(progress.excess) г")
                    .font(.caption)
                    .foregroundStyle(isOver ? Theme.warning : .secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(macro.title)
        .accessibilityValue(accessibilityValue(progress))
    }

    private func accessibilityValue(_ progress: GoalProgress) -> String {
        let base = "\(progress.value) з \(progress.goal) грам"
        guard progress.excess > 0 else { return base }
        return progress.state == .overLimit ? "\(base), перевищення на \(progress.excess)" : "\(base), понад ціль на \(progress.excess)"
    }
}

struct MealTypeBadge: View {
    let type: MealEntry.MealType
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: type.icon)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(type.tint)
            .frame(width: size, height: size)
            .background(type.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
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
                .monospacedDigit()
                .frame(maxWidth: 110)
            Text(unit).foregroundStyle(.secondary)
        }
    }
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

struct MealRow: View {
    let entry: MealEntry
    var showsBadge = true

    private var details: String {
        var parts: [String] = []
        if entry.grams > 0 { parts.append("\(Int(entry.grams.rounded())) г") }
        parts.append("Б \(Int(entry.protein)) · Ж \(Int(entry.fat)) · В \(Int(entry.carbs))")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: Spacing.m) {
            if showsBadge { MealTypeBadge(type: entry.mealType) }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(entry.name).font(.body.weight(.medium)).lineLimit(2)
                    if entry.isFavorite {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow).accessibilityLabel("Обране")
                    }
                }
                Text(details).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: Spacing.s)
            Text("\(Text("\(entry.kcal)").number(.body)) ккал").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct StorageIssueBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            Text(message).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) { Image(systemName: "xmark").font(.footnote.bold()) }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрити")
        }
        .padding(12)
        .background(.regularMaterial)
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

extension String {
    /// "неділя, 8 листопада" → "Неділя, 8 листопада" (unlike `capitalized`, which capitalises every word).
    var capitalizedFirstLetter: String { prefix(1).uppercased() + dropFirst() }
}
