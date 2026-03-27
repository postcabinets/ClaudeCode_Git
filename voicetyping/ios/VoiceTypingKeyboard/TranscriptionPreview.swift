import SwiftUI

struct TranscriptionPreview: View {
    let rawText: String
    let cleanedText: String?
    let isProcessing: Bool
    let showRaw: Bool
    let onInsert: () -> Void

    var body: some View {
        if !rawText.isEmpty || isProcessing {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(displayText)
                        .font(.callout)
                        .foregroundColor(.primary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }

                if cleanedText != nil {
                    Button(action: onInsert) {
                        HStack {
                            Image(systemName: "arrow.up.circle.fill")
                            Text("入力")
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .padding(.horizontal, 4)
        }
    }

    private var displayText: String {
        if showRaw { return rawText }
        return cleanedText ?? rawText
    }
}
