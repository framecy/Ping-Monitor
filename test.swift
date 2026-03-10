import SwiftUI
import Charts

struct Test: View {
    var body: some View {
        Chart {
            LineMark(x: .value("X", 1), y: .value("Y", 1), series: .value("Type", "U"))
            AreaMark(x: .value("X", 1), y: .value("Y", 1), series: .value("Type", "U"))
        }
    }
}
