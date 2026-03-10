import SwiftUI
import Charts

struct TestChart: View {
    struct Sample: Identifiable { let id = UUID(); let t: Int; let val: Double }
    var data: [Sample] = []
    var body: some View {
        Chart {
            ForEach(data) { sample in
                AreaMark(
                    x: .value("T", sample.t),
                    y: .value("V", sample.val),
                    stacking: .unstacked
                )
            }
        }
    }
}
