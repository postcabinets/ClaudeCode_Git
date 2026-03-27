import SwiftUI

struct ModeSelector: View {
    @Binding var selectedMode: OutputMode

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OutputMode.allCases, id: \.self) { mode in
                Button(action: { selectedMode = mode }) {
                    Text(mode.label)
                        .font(.caption2)
                        .fontWeight(selectedMode == mode ? .bold : .regular)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            selectedMode == mode
                                ? Color.blue.opacity(0.2)
                                : Color.gray.opacity(0.1)
                        )
                        .cornerRadius(8)
                        .foregroundColor(selectedMode == mode ? .blue : .gray)
                }
            }
        }
    }
}

extension OutputMode {
    var label: String {
        switch self {
        case .casual: return "カジュアル"
        case .business: return "ビジネス"
        case .technical: return "テクニカル"
        case .raw: return "そのまま"
        }
    }
}
