import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "printer.fill")
                .font(.title2)
                .foregroundColor(.orange)
            Text("PrintHub")
                .font(.headline)
            Text("Add the complication\nto your watch face")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
