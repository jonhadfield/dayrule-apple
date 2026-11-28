import SwiftUI
import WidgetKit

@main
struct DayruleWidgetBundle: WidgetBundle {
    var body: some Widget {
        CountsWidget()
        TodayCountWidget()
        InboxCountWidget()
    }
}
