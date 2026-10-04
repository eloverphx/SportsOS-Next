import SwiftUI

struct ScoreOverlayView: View {
    let state: ScoreboardState

    var body: some View {
        HStack(spacing: 0) {
            team(
                name: state.homeName,
                score: state.homeScore,
                scoreFirst: false
            )

            VStack(spacing: 1) {
                Text("P\(state.period)")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)

                Text(state.clock)
                    .font(.title3.monospacedDigit().bold())
            }
            .frame(minWidth: 88)
            .padding(.horizontal, 14)

            Divider()
                .overlay(.white.opacity(0.18))

            team(
                name: state.awayName,
                score: state.awayScore,
                scoreFirst: true
            )
        }
        .frame(height: 52)
        .background(.black.opacity(0.76))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.16))
        )
    }

    private func team(
        name: String,
        score: Int,
        scoreFirst: Bool
    ) -> some View {
        HStack {
            if scoreFirst {
                Text("\(score)")
                    .font(.title2.bold())
            }

            Text(name)
                .font(.subheadline.bold())
                .lineLimit(1)

            Spacer()

            if !scoreFirst {
                Text("\(score)")
                    .font(.title2.bold())
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
    }
}
