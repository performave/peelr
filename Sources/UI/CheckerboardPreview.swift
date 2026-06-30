import SwiftUI

/// Renders an image over a transparency checkerboard so alpha is visible.
struct CheckerboardPreview: View {
    let image: NSImage?
    var placeholder: String = "No image"

    var body: some View {
        ZStack {
            Checkerboard()
                .fill(Color(white: 0.85))
                .background(Color.white)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                Text(placeholder)
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }
}

private struct Checkerboard: Shape {
    var square: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cols = Int(ceil(rect.width / square))
        let rows = Int(ceil(rect.height / square))
        for row in 0..<rows {
            for col in 0..<cols where (row + col).isMultiple(of: 2) {
                path.addRect(CGRect(x: CGFloat(col) * square, y: CGFloat(row) * square,
                                    width: square, height: square))
            }
        }
        return path
    }
}
