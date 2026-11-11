import Charts
import SwiftUI

/// Live deficit: resting + active energy burned so far today against what was eaten.
struct EnergyBalanceCard: View {
    @Environment(DiaryStore.self) private var diary
    @Environment(HealthService.self) private var health
    let setUpProfile: () -> Void

    private static let restingColor = Color(light: UIColor(red: 0.42, green: 0.48, blue: 0.62, alpha: 1),
                                            dark: UIColor(red: 0.58, green: 0.64, blue: 0.78, alpha: 1))

    var body: some View {
        let eaten = diary.todayTotals.calories
        Group {
            if let balance = EnergyBalance.today(snapshot: health.snapshot, profile: diary.profile, eaten: eaten) {
                content(balance)
            } else {
                prompt
            }
        }
        .cardStyle()
    }

    private func content(_ balance: EnergyBalance) -> some View {
        let isDeficit = balance.balanceNow <= 0
        return VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Label("Енергобаланс", systemImage: "scalemass.fill").font(.headline)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Text("\(Int(abs(balance.balanceNow).rounded()))").number(.title3, weight: .bold)) ккал")
                        .font(.subheadline)
                        .foregroundStyle(isDeficit ? Theme.accent : Theme.warning)
                    Text(isDeficit ? "дефіцит зараз" : "профіцит зараз").font(.caption).foregroundStyle(.secondary)
                }
            }

            Chart {
                BarMark(x: .value("ккал", balance.restingSoFar), y: .value("", "Витрачено"))
                    .foregroundStyle(by: .value("Складова", "Спокій"))
                BarMark(x: .value("ккал", balance.active), y: .value("", "Витрачено"))
                    .foregroundStyle(by: .value("Складова", "Активність"))
                BarMark(x: .value("ккал", balance.eaten), y: .value("", "З'їдено"))
                    .foregroundStyle(by: .value("Складова", "Їжа"))
            }
            .chartForegroundStyleScale(["Спокій": Self.restingColor, "Активність": Ring.move.color, "Їжа": Theme.accent])
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: 130)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Витрачено \(Int(balance.burnedSoFar)) ккал, з'їдено \(Int(balance.eaten)) ккал")

            HStack(spacing: Spacing.s) {
                BalanceStat(title: "Спокій", value: balance.restingSoFar, tint: Self.restingColor)
                BalanceStat(title: "Активність", value: balance.active, tint: Ring.move.color)
                BalanceStat(title: "Витрачено", value: balance.burnedSoFar, tint: .primary)
                BalanceStat(title: "З'їдено", value: balance.eaten, tint: Theme.accent)
            }

            let endOfDay = balance.balanceEndOfDay
            Text("Якщо більше нічого не їсти, до кінця дня \(endOfDay <= 0 ? "дефіцит" : "профіцит") становитиме ~\(Int(abs(endOfDay).rounded())) ккал.")
                .font(.caption).foregroundStyle(.secondary)
            Text(balance.source == .health
                 ? "Енергія спокою — з Apple Health."
                 : "Енергія спокою розрахована за вашим профілем (формула Міффліна — Сан Жеора).")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var prompt: some View {
        Button(action: setUpProfile) {
            HStack(spacing: Spacing.m) {
                Image(systemName: "scalemass.fill").font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Енергобаланс").font(.headline)
                    Text("Вкажіть зріст, вагу й вік, щоб бачити реальний дефіцит калорій з урахуванням спокою та активності.")
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
    let value: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Text("\(Int(value.rounded()))").numberFont(.subheadline).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
