import SwiftUI

struct VerticalZoomControl: View {
    @Binding var value: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            Text("ZOOM")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)

            Text(String(format: "%.1f×", value))
                .font(.caption.bold())

            Slider(
                value: Binding(
                    get: {
                        Double(value)
                    },
                    set: {
                        value = CGFloat($0)
                    }
                ),
                in: 0.5...5.0,
                step: 0.1
            )
            .rotationEffect(.degrees(-90))
            .frame(width: 210)
            .frame(width: 34, height: 210)
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
