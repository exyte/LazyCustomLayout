import SwiftUI

struct Card: View {
    var index: Int

    private static let palette: [Color] = [.blue, .purple, .pink, .orange, .teal]

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Self.palette[index % Self.palette.count].opacity(0.25))
            .overlay {
                Text("\(index)")
                    .font(.title)
                    .bold()
            }
            .padding(8)
    }
}
