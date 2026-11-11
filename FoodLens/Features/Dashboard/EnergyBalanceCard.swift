import Charts
import SwiftUI

/// Live estimated deficit: resting + active energy burned so far today against what was eaten.
struct EnergyBalanceCard: View {
    @Environment(DiaryStore.self) private var diary
    @Environment(HealthService.self) private var health
    let setUpProfile: () -> Void

    static let restingColor = Color(light: UIColor(red: 0.42, green: 0.48, blue: 0.62, alpha: 1),
                                    dark: UIColor(red: 0.58, green: 0.64, blue: 0.78, alpha: 1))

    var body: some View {
        Group {
            if let balance = EnergyBalance.today(snapshot: health.snapshot, profile: diary.profileForEstimates,
                                                 eaten: diary.todayTotals.calories) {
                content(balance)
            } else {
                prompt
            }
        }
        .cardStyle()
    }

    private func content(_ balance: EnergyBalance) -> some View {
        let shown = balance.display
        let tint = shown.isDeficit ? Theme.accent : Theme.warning
        return VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Label("Енергобаланс", systemImage: "scalemass.fill").font(.headline)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(spacing: 4) {
                        Image(systemName: shown.isDeficit ? "arrow.down.right" : "arrow.up.right")
                            .font(.subheadline.weight(.bold))
                        Text("\(Text("\(abs(shown.deficit))").number(.title3, weight: .bold)) ккал").font(.subheadline)
                    }
                    .foregroundStyle(tint)
                    Text(shown.isDeficit ? "орієнтовний дефіцит" : "орієнтовний профіцит")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            chart(shown)

            HStack(spacing: Spacing.s) {
                BalanceStat(title: "Спокій", value: shown.resting, tint: Self.restingColor)
                BalanceStat(title: "Активність", value: shown.active, tint: Ring.move.color)
                BalanceStat(title: "Витрати", value: shown.burned, tint: .primary)
                BalanceStat(title: "Спожито", value: shown.eaten, tint: Theme.accent)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                let endOfDay = Int(balance.deficitEndOfDay.rounded())
                Text("Якщо більше нічого не їсти, до кінця дня \(endOfDay >= 0 ? "дефіцит" : "профіцит") становитиме ~\(abs(endOfDay)) ккал.")
                    .font(.caption).foregroundStyle(.secondary)
                if balance.isLargeDeficit {
                    Label("Дефіцит понад 1 000 ккал за день. Якщо це не пропущений запис, подбайте про достатнє харчування.",
                          systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(Theme.warning)
                }
                Text("«Залишилось» у картці вище — це залишок до цілі харчування. Дефіцит — інше: витрати енергії мінус спожите.")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(sourceNote(balance)).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    /// Two bars on one scale: burned (resting + active) and eaten. The gap between them is drawn
    /// as a pale segment, so both bars end at the same length and the difference is visible.
    private func chart(_ shown: EnergyBalance.Display) -> some View {
        let gap = abs(shown.deficit)
        var domain = ["Спокій", "Активність", "Їжа"]
        var range: [Color] = [Self.restingColor, Ring.move.color, Theme.accent]
        if gap > 0 {
            domain.append(shown.isDeficit ? "Дефіцит" : "Профіцит")
            range.append(shown.isDeficit ? Theme.accent.opacity(0.22) : Theme.warning.opacity(0.35))
        }
        return Chart {
            BarMark(x: .value("ккал", shown.resting), y: .value("", "Витрати"))
                .foregroundStyle(by: .value("Складова", "Спокій"))
            BarMark(x: .value("ккал", shown.active), y: .value("", "Витрати"))
                .foregroundStyle(by: .value("Складова", "Активність"))
            if !shown.isDeficit, gap > 0 {
                BarMark(x: .value("ккал", gap), y: .value("", "Витрати"))
                    .foregroundStyle(by: .value("Складова", "Профіцит"))
            }
            BarMark(x: .value("ккал", shown.eaten), y: .value("", "Спожито"))
                .foregroundStyle(by: .value("Складова", "Їжа"))
            if shown.isDeficit, gap > 0 {
                BarMark(x: .value("ккал", gap), y: .value("", "Спожито"))
                    .foregroundStyle(by: .value("Складова", "Дефіцит"))
            }
        }
        .chartForegroundStyleScale(domain: domain, range: range)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 130)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Витрати \(shown.burned) ккал, спожито \(shown.eaten) ккал, \(shown.isDeficit ? "дефіцит" : "профіцит") \(gap) ккал")
    }

    private func sourceNote(_ balance: EnergyBalance) -> String {
        let resting = balance.source == .health
            ? "Енергія спокою — з Apple Health."
            : "Енергія спокою — оцінка за вашим профілем (формула Міффліна — Сан Жеора), бо Apple Health її не надав."
        let active = balance.hasActiveData
            ? "Активні калорії — з Apple Health (тренування вже входять у них)."
            : "Активних калорій з Apple Health немає — враховано 0."
        return "\(resting) \(active) Витрати енергії — оцінка, тому дефіцит орієнтовний."
    }

    private var prompt: some View {
        Button(action: setUpProfile) {
            HStack(spacing: Spacing.m) {
                Image(systemName: "scalemass.fill").font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Енергобаланс").font(.headline)
                    Text("Вкажіть зріст, вагу й вік або дозвольте читати енергію спокою з Apple Health, щоб бачити орієнтовний дефіцит.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct BalanceStat: View {
    let title: String
    let value: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Text("\(value)").numberFont(.subheadline).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
