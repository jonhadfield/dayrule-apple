import SwiftUI

/// Paper ruled row: hairline under content, fixed phone row height.
struct RuledRow<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        content()
            .frame(minHeight: Tokens.rowHeightPhone, alignment: .center)
            .padding(.vertical, 4)
            .overlay(alignment: .bottom) {
                colors.hairline.frame(height: 1)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(colors.bg)
    }
}
