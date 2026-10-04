import SwiftUI

struct VerticalLevelMeter: View {
    let value: Double
    let clipping: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(.black.opacity(0.45))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                .green,
                                .yellow,
                                .red
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(
                        height: max(
                            3,
                            geometry.size.height * value
                        )
                    )

                Rectangle()
                    .fill(.white.opacity(0.9))
                    .frame(height: 2)
                    .offset(
                        y: -(geometry.size.height * 0.72)
                    )
            }
            .shadow(
                color: clipping ? .red : .clear,
                radius: 8
            )
        }
    }
}
