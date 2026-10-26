import SwiftUI

/// Root window layout: Toolbar on top, map canvas in the center, side panel on the right.
struct ContentView: View {
    @StateObject private var vm = AppViewModel()

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(vm: vm)
            HSplitView {
                MapCanvasView(vm: vm)
                SidePanelView(vm: vm)
            }
        }
    }
}
