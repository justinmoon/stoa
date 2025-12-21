import SwiftUI

enum SplitDirection {
    case horizontal  // left | right
    case vertical    // top / bottom
}

struct SplitView<L: View, R: View>: View {
    let direction: SplitDirection
    let ratio: CGFloat
    let left: L
    let right: R
    
    private let dividerSize: CGFloat = 1
    
    init(
        _ direction: SplitDirection,
        ratio: CGFloat = 0.5,
        @ViewBuilder left: () -> L,
        @ViewBuilder right: () -> R
    ) {
        self.direction = direction
        self.ratio = ratio
        self.left = left()
        self.right = right()
    }
    
    var body: some View {
        GeometryReader { geo in
            let leftRect = leftRect(for: geo.size)
            let rightRect = rightRect(for: geo.size, leftRect: leftRect)
            
            ZStack(alignment: .topLeading) {
                left
                    .frame(width: leftRect.width, height: leftRect.height)
                    .offset(x: leftRect.origin.x, y: leftRect.origin.y)
                
                right
                    .frame(width: rightRect.width, height: rightRect.height)
                    .offset(x: rightRect.origin.x, y: rightRect.origin.y)
                
                // Divider
                divider(for: geo.size, leftRect: leftRect)
            }
        }
    }
    
    @ViewBuilder
    private func divider(for size: CGSize, leftRect: CGRect) -> some View {
        switch direction {
        case .horizontal:
            Rectangle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: dividerSize, height: size.height)
                .offset(x: leftRect.width, y: 0)
        case .vertical:
            Rectangle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: size.width, height: dividerSize)
                .offset(x: 0, y: leftRect.height)
        }
    }
    
    private func leftRect(for size: CGSize) -> CGRect {
        switch direction {
        case .horizontal:
            let width = (size.width - dividerSize) * ratio
            return CGRect(x: 0, y: 0, width: width, height: size.height)
        case .vertical:
            let height = (size.height - dividerSize) * ratio
            return CGRect(x: 0, y: 0, width: size.width, height: height)
        }
    }
    
    private func rightRect(for size: CGSize, leftRect: CGRect) -> CGRect {
        switch direction {
        case .horizontal:
            let x = leftRect.width + dividerSize
            let width = size.width - x
            return CGRect(x: x, y: 0, width: width, height: size.height)
        case .vertical:
            let y = leftRect.height + dividerSize
            let height = size.height - y
            return CGRect(x: 0, y: y, width: size.width, height: height)
        }
    }
}
