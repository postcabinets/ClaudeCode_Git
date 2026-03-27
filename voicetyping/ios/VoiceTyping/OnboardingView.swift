import SwiftUI

struct OnboardingView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "keyboard")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("VoiceTyping を有効にする")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 16) {
                StepRow(number: 1, text: "「設定」アプリを開く")
                StepRow(number: 2, text: "「一般」→「キーボード」→「キーボード」")
                StepRow(number: 3, text: "「新しいキーボードを追加」をタップ")
                StepRow(number: 4, text: "「VoiceTyping」を選択")
                StepRow(number: 5, text: "「フルアクセスを許可」をONにする")
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.headline)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .padding(24)
    }
}

struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 24, height: 24)
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(Circle())
            Text(text)
                .font(.body)
        }
    }
}
