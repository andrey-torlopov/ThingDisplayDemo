import SwiftUI

struct InfoView: View {
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            // Dark background with blur - tappable to close
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        isPresented = false
                    }
                }
            ScrollView {
                VStack(spacing: 30) {
                    // Title
                    Text("Cellular Defense")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 20) {
                        InfoBlock(
                            title: "Capture Process",
                            description: "Observe the cell's defense mechanism: a healthy cell (blue) detects an intruder cell (red) and begins the neutralization process."
                        )

                        InfoBlock(
                            title: "Merging",
                            description: "The cells approach and merge together. During the merging process, the intruder is neutralized, and its aggressive red color gradually changes to the healthy blue."
                        )

                        InfoBlock(
                            title: "Division",
                            description: "After successfully neutralizing the threat, the cell begins the division process, creating two new healthy cells ready to defend the organism."
                        )

                        InfoBlock(
                            title: "Cycle Continues",
                            description: "The process repeats continuously, demonstrating the organism's remarkable ability for self-defense and regeneration."
                        )
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 50)
                .padding(.bottom, 50)
            }
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        // Prevent taps on scroll content from closing
                    }
            )
        }
    }
}

struct InfoBlock: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)

                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
            }

            Text(description)
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.9))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    InfoView(isPresented: .constant(true))
}
