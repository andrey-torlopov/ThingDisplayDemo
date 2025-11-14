import SwiftUI

struct CellLabelView: View {
    let cellPositions: [CellLabelData]

    var body: some View {
        GeometryReader { geometry in
            ForEach(Array(cellPositions.enumerated()), id: \.element.id) { index, data in
                CellLabel(
                    text: data.label,
                    cellPosition: data.screenPosition,
                    geometry: geometry,
                    isHealthyCell: index < 2  // First two are healthy cells
                )
            }
        }
    }
}

struct CellLabel: View {
    let text: String
    let cellPosition: CGPoint
    let geometry: GeometryProxy
    let isHealthyCell: Bool

    var body: some View {
        ZStack {
            // Line from cell to label (left for healthy, right for invader)
            Path { path in
                path.move(to: cellPosition)
                path.addLine(to: CGPoint(x: cellPosition.x, y: cellPosition.y - 80))
                if isHealthyCell {
                    // Line to the left for healthy cells
                    path.addLine(to: CGPoint(x: cellPosition.x - 100, y: cellPosition.y - 80))
                } else {
                    // Line to the right for invader
                    path.addLine(to: CGPoint(x: cellPosition.x + 100, y: cellPosition.y - 80))
                }
            }
            .stroke(Color.white.opacity(0.8), lineWidth: 2)

            // Label background and text (two lines)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(text.components(separatedBy: "\n"), id: \.self) { line in
                    Text(line)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.5), lineWidth: 1)
                    )
            )
            .position(
                x: isHealthyCell ? cellPosition.x - 140 : cellPosition.x + 140,
                y: cellPosition.y - 80
            )
        }
    }
}

struct CellLabelData: Identifiable {
    let id = UUID()
    let label: String
    let screenPosition: CGPoint
}

#Preview {
    CellLabelView(cellPositions: [
        CellLabelData(label: "CELL", screenPosition: CGPoint(x: 100, y: 200)),
        CellLabelData(label: "DOG", screenPosition: CGPoint(x: 300, y: 200))
    ])
    .background(Color.black)
}
