import SwiftUI

struct ReadingGoalsSection: View {
    let goal: ReadingGoal?

    var body: some View {
        VStack(spacing: 8) {
            Text("Reading Goals")
                .font(.title3.bold())

            Text("Read every day, see your stats soar and finish more books.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let goal {
                Gauge(value: goal.todayProgress) {
                    Text("Today")
                } currentValueLabel: {
                    Text(goal.todayTimeText) // 1:11
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(.blue)
                .frame(width: 140, height: 140)

                Text(goal.goalText) // of your 5-minute goal
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}