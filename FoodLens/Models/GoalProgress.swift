import Foundation

/// Progress of one daily value against its goal, computed on the whole numbers the screen shows,
/// so "159 / 100 г" always comes with "+59 г".
struct GoalProgress: Equatable, Sendable {
    enum State: Equatable, Sendable {
        /// Below the goal. Never an error: the day may not be over.
        case below
        case reached
        /// Above a goal that works as an upper limit (energy, fat, carbohydrates).
        case overLimit
        /// Above a goal that works as a minimum (protein, fiber): fine, shown neutrally.
        case aboveMinimum
    }

    let value: Int
    let goal: Int
    let isUpperLimit: Bool

    init(value: Double, goal: Double, isUpperLimit: Bool) {
        self.value = Int(max(value, 0).rounded())
        self.goal = Int(max(goal, 0).rounded())
        self.isUpperLimit = isUpperLimit
    }

    /// Bar fill, 0…1.
    var fraction: Double { goal > 0 ? min(Double(value) / Double(goal), 1) : 0 }
    /// Where the goal sits on a bar that is scaled to the value once the value is larger, 0…1.
    var goalMarker: Double? { value > goal && goal > 0 ? Double(goal) / Double(value) : nil }
    var excess: Int { max(value - goal, 0) }
    var remaining: Int { max(goal - value, 0) }

    var state: State {
        guard goal > 0 else { return .below }
        if value > goal { return isUpperLimit ? .overLimit : .aboveMinimum }
        return value == goal ? .reached : .below
    }
}
