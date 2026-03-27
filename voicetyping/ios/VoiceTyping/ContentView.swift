import SwiftUI

struct ContentView: View {
    @State private var selectedMode: OutputMode = Settings.shared.selectedMode

    var body: some View {
        NavigationView {
            List {
                Section("セットアップ") {
                    NavigationLink("キーボードを有効にする") {
                        OnboardingView()
                    }
                }

                Section("デフォルトモード") {
                    ForEach(OutputMode.allCases, id: \.self) { mode in
                        HStack {
                            Text(mode.label)
                            Spacer()
                            if mode == selectedMode {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedMode = mode
                            Settings.shared.selectedMode = mode
                        }
                    }
                }

                Section("バージョン") {
                    HStack {
                        Text("VoiceTyping")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("VoiceTyping")
        }
    }
}
