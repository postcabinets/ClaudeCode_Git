# VoiceTyping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a free, cross-platform voice input app (iOS keyboard + Android IME + Mac menu bar) that converts speech to clean text using OS-native STT and Gemini Flash.

**Architecture:** Three-layer pipeline — OS Speech API (free STT) → Gemini Flash API via Firebase proxy (free LLM cleanup) → text output. Each platform is a native app sharing the same LLM prompt and formatting logic. iOS/Android ship as custom keyboards; Mac as a menu bar app with global hotkey.

**Tech Stack:** Swift/SwiftUI (iOS+Mac), Kotlin/Jetpack Compose (Android), Firebase Cloud Functions (TypeScript), Gemini 2.0 Flash API.

**Spec:** `docs/superpowers/specs/2026-03-27-voicetyping-design.md`

---

## File Structure

```
voicetyping/
├── firebase/                          # Firebase Cloud Functions (API proxy)
│   ├── package.json
│   ├── tsconfig.json
│   └── src/
│       └── index.ts                   # Gemini proxy + rate limiter
│
├── ios/                               # Xcode project (iOS app + keyboard extension)
│   ├── VoiceTyping.xcodeproj/
│   ├── VoiceTyping/                   # Host app (settings, onboarding)
│   │   ├── VoiceTypingApp.swift       # App entry point
│   │   ├── ContentView.swift          # Main settings view
│   │   ├── OnboardingView.swift       # Keyboard enable guide
│   │   └── Info.plist
│   ├── VoiceTypingKeyboard/           # Keyboard extension target
│   │   ├── KeyboardViewController.swift  # UIInputViewController
│   │   ├── KeyboardView.swift         # SwiftUI keyboard layout
│   │   ├── SpeechManager.swift        # Apple Speech continuous recognition
│   │   ├── TranscriptionPreview.swift # Real-time + cleaned text preview
│   │   ├── ModeSelector.swift         # casual/business/technical/raw toggle
│   │   └── Info.plist                 # NSExtension config
│   ├── Shared/                        # Shared between app + extension (via App Group)
│   │   ├── LLMFormatter.swift         # Gemini API call + prompt
│   │   ├── RegexCleanup.swift         # Offline fallback formatter
│   │   ├── Settings.swift             # UserDefaults wrapper (App Group)
│   │   └── Models.swift               # OutputMode enum, FormattingResult
│   └── Tests/
│       ├── RegexCleanupTests.swift
│       ├── LLMFormatterTests.swift
│       └── ModelsTests.swift
│
├── android/                           # Android Studio project
│   ├── app/
│   │   ├── build.gradle.kts
│   │   ├── src/main/
│   │   │   ├── AndroidManifest.xml
│   │   │   ├── kotlin/com/voicetyping/
│   │   │   │   ├── MainActivity.kt          # Settings + onboarding
│   │   │   │   ├── ime/
│   │   │   │   │   ├── VoiceTypingIME.kt    # InputMethodService
│   │   │   │   │   ├── KeyboardView.kt      # Compose keyboard UI
│   │   │   │   │   ├── SpeechManager.kt     # SpeechRecognizer wrapper
│   │   │   │   │   └── ModeSelector.kt      # Mode toggle UI
│   │   │   │   ├── formatter/
│   │   │   │   │   ├── LLMFormatter.kt      # Gemini API call + prompt
│   │   │   │   │   └── RegexCleanup.kt      # Offline fallback
│   │   │   │   └── model/
│   │   │   │       ├── OutputMode.kt        # Enum
│   │   │   │       └── Settings.kt          # SharedPreferences wrapper
│   │   │   └── res/
│   │   │       ├── xml/method.xml           # IME declaration
│   │   │       └── values/strings.xml
│   │   └── src/test/
│   │       ├── RegexCleanupTest.kt
│   │       └── LLMFormatterTest.kt
│   ├── build.gradle.kts
│   └── settings.gradle.kts
│
├── mac/                               # Xcode project (macOS menu bar app)
│   ├── VoiceTypingMac.xcodeproj/
│   ├── VoiceTypingMac/
│   │   ├── VoiceTypingMacApp.swift    # Menu bar app entry
│   │   ├── HotkeyManager.swift        # Global hotkey (CGEvent tap)
│   │   ├── FloatingWindow.swift       # Transcription overlay
│   │   ├── SpeechManager.swift        # Apple Speech recognition
│   │   ├── TextInjector.swift         # Paste via Accessibility API
│   │   ├── SettingsView.swift         # Preferences window
│   │   ├── LLMFormatter.swift         # (same logic as iOS Shared/)
│   │   ├── RegexCleanup.swift         # (same logic as iOS Shared/)
│   │   └── Info.plist
│   └── Tests/
│       └── MacIntegrationTests.swift
│
└── docs/
    ├── specs/2026-03-27-voicetyping-design.md
    └── plans/2026-03-27-voicetyping-plan.md   # This file
```

---

## Phase 1: Firebase Proxy + Shared Logic

### Task 1: Firebase Cloud Function — Gemini Proxy

**Files:**
- Create: `voicetyping/firebase/package.json`
- Create: `voicetyping/firebase/tsconfig.json`
- Create: `voicetyping/firebase/src/index.ts`

- [ ] **Step 1: Initialize Firebase project**

```bash
mkdir -p voicetyping/firebase && cd voicetyping/firebase
npm init -y
npm install firebase-functions firebase-admin @google/generative-ai
npm install -D typescript @types/node
```

- [ ] **Step 2: Create tsconfig.json**

```json
{
  "compilerOptions": {
    "module": "commonjs",
    "target": "es2020",
    "outDir": "./lib",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true
  },
  "include": ["src/**/*"]
}
```

- [ ] **Step 3: Write the proxy function**

```typescript
// voicetyping/firebase/src/index.ts
import { onRequest } from "firebase-functions/v2/https";
import { GoogleGenerativeAI } from "@google/generative-ai";

const GEMINI_API_KEY = process.env.GEMINI_API_KEY ?? "";
const RATE_LIMIT_PER_DEVICE = 30; // requests per minute
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();

function checkRateLimit(deviceId: string): boolean {
  const now = Date.now();
  const entry = rateLimitMap.get(deviceId);
  if (!entry || now > entry.resetAt) {
    rateLimitMap.set(deviceId, { count: 1, resetAt: now + 60_000 });
    return true;
  }
  if (entry.count >= RATE_LIMIT_PER_DEVICE) return false;
  entry.count++;
  return true;
}

const SYSTEM_PROMPT = `You are a voice-to-text formatter. Your job is to clean up speech transcriptions.

Rules:
1. Remove filler words (えー, あの, うーん, um, uh, like, you know)
2. Detect self-corrections: keep only the final version
   Example: "明日、いや明後日" → "明後日"
3. Add proper punctuation (。、！？ for Japanese; .,!? for English)
4. Convert spoken grammar to written grammar
5. Preserve the speaker's meaning exactly — do NOT add content
6. Keep the same language as input
7. If mixed languages, preserve the mixing naturally

Output ONLY the cleaned text. No explanations.`;

const MODE_INSTRUCTIONS: Record<string, string> = {
  casual: "Light cleanup, keep conversational tone.",
  business: "Formal, polite. Use 敬語 for Japanese.",
  technical: "Clear, precise instruction language.",
  raw: "",
};

export const formatText = onRequest(
  { cors: true, region: "asia-northeast1" },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    const { text, mode = "casual", deviceId = "unknown" } = req.body;

    if (!text || typeof text !== "string" || text.trim().length === 0) {
      res.status(400).json({ error: "Missing text" });
      return;
    }

    if (mode === "raw") {
      res.json({ result: text });
      return;
    }

    if (!checkRateLimit(deviceId)) {
      res.status(429).json({ error: "Rate limited" });
      return;
    }

    try {
      const genAI = new GoogleGenerativeAI(GEMINI_API_KEY);
      const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });

      const modeInstruction = MODE_INSTRUCTIONS[mode] ?? MODE_INSTRUCTIONS.casual;
      const prompt = `${SYSTEM_PROMPT}\n\nMode: ${mode}\n${modeInstruction}\n\nTranscription to clean:\n${text}`;

      const result = await model.generateContent(prompt);
      const cleaned = result.response.text().trim();

      res.json({ result: cleaned });
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : "Unknown error";
      res.status(500).json({ error: message });
    }
  }
);
```

- [ ] **Step 4: Update package.json scripts**

```bash
cd voicetyping/firebase
npx json -I -f package.json -e 'this.main="lib/index.js"; this.scripts={build:"tsc",serve:"firebase emulators:start --only functions",deploy:"firebase deploy --only functions"}'
```

- [ ] **Step 5: Build and verify compilation**

```bash
cd voicetyping/firebase && npm run build
```

Expected: Compiles to `lib/index.js` without errors.

- [ ] **Step 6: Commit**

```bash
git add voicetyping/firebase/
git commit -m "feat: add Firebase Gemini proxy function with rate limiting"
```

---

### Task 2: RegexCleanup (Swift — shared between iOS and Mac)

**Files:**
- Create: `voicetyping/ios/Shared/Models.swift`
- Create: `voicetyping/ios/Shared/RegexCleanup.swift`
- Create: `voicetyping/ios/Tests/RegexCleanupTests.swift`

- [ ] **Step 1: Create the Xcode project directory structure**

```bash
mkdir -p voicetyping/ios/{VoiceTyping,VoiceTypingKeyboard,Shared,Tests}
```

- [ ] **Step 2: Write Models.swift**

```swift
// voicetyping/ios/Shared/Models.swift
import Foundation

enum OutputMode: String, CaseIterable, Codable {
    case casual
    case business
    case technical
    case raw
}

struct FormattingResult {
    let original: String
    let cleaned: String
    let mode: OutputMode
    let wasLLMFormatted: Bool
}
```

- [ ] **Step 3: Write failing tests for RegexCleanup**

```swift
// voicetyping/ios/Tests/RegexCleanupTests.swift
import XCTest
@testable import VoiceTyping

final class RegexCleanupTests: XCTestCase {

    let cleanup = RegexCleanup()

    func testRemovesJapaneseFillers() {
        let input = "えーっと、あの、明日のミーティングなんだけど"
        let result = cleanup.clean(input)
        XCTAssertFalse(result.contains("えーっと"))
        XCTAssertFalse(result.contains("あの"))
        XCTAssertTrue(result.contains("明日のミーティング"))
    }

    func testRemovesEnglishFillers() {
        let input = "um so like you know the meeting is tomorrow"
        let result = cleanup.clean(input)
        XCTAssertFalse(result.contains("um "))
        XCTAssertFalse(result.contains("like "))
        XCTAssertFalse(result.contains("you know "))
        XCTAssertTrue(result.contains("the meeting is tomorrow"))
    }

    func testTrimsWhitespace() {
        let input = "  hello   world  "
        let result = cleanup.clean(input)
        XCTAssertEqual(result, "hello world")
    }

    func testEmptyStringReturnsEmpty() {
        let result = cleanup.clean("")
        XCTAssertEqual(result, "")
    }

    func testPreservesNormalText() {
        let input = "明後日の15時からミーティングです"
        let result = cleanup.clean(input)
        XCTAssertEqual(result, "明後日の15時からミーティングです")
    }
}
```

- [ ] **Step 4: Write RegexCleanup implementation**

```swift
// voicetyping/ios/Shared/RegexCleanup.swift
import Foundation

final class RegexCleanup {

    private let jaFillers = [
        "えーっと[、,]?\\s*",
        "えーと[、,]?\\s*",
        "えー[、,]?\\s*",
        "あのー?[、,]?\\s*",
        "うーん[、,]?\\s*",
        "まあ[、,]?\\s*",
        "なんか[、,]?\\s*",
        "そのー?[、,]?\\s*",
    ]

    private let enFillers = [
        "\\bum+\\b[,.]?\\s*",
        "\\buh+\\b[,.]?\\s*",
        "\\blike\\b[,]?\\s+(?=\\w)",
        "\\byou know\\b[,.]?\\s*",
        "\\bso\\b[,]?\\s+(?=\\w)",
        "\\bbasically\\b[,.]?\\s*",
        "\\bactually\\b[,.]?\\s*",
        "\\bi mean\\b[,.]?\\s*",
    ]

    func clean(_ text: String) -> String {
        guard !text.isEmpty else { return "" }

        var result = text

        let allFillers = jaFillers + enFillers
        for pattern in allFillers {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        // Collapse multiple spaces
        if let spaceRegex = try? NSRegularExpression(pattern: "\\s{2,}") {
            result = spaceRegex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: " "
            )
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 5: Run tests**

Tests will be run after Xcode project is created. For now verify file syntax:
```bash
swiftc -typecheck voicetyping/ios/Shared/Models.swift voicetyping/ios/Shared/RegexCleanup.swift 2>&1 || echo "Will verify in Xcode"
```

- [ ] **Step 6: Commit**

```bash
git add voicetyping/ios/Shared/ voicetyping/ios/Tests/
git commit -m "feat: add RegexCleanup with filler removal for Japanese/English"
```

---

### Task 3: LLMFormatter (Swift — Gemini API client)

**Files:**
- Create: `voicetyping/ios/Shared/LLMFormatter.swift`
- Create: `voicetyping/ios/Shared/Settings.swift`
- Create: `voicetyping/ios/Tests/LLMFormatterTests.swift`

- [ ] **Step 1: Write Settings.swift**

```swift
// voicetyping/ios/Shared/Settings.swift
import Foundation

final class Settings {

    static let shared = Settings()

    private let defaults: UserDefaults

    init(suiteName: String = "group.com.voicetyping.shared") {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    var selectedMode: OutputMode {
        get {
            guard let raw = defaults.string(forKey: "selectedMode"),
                  let mode = OutputMode(rawValue: raw) else { return .casual }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: "selectedMode") }
    }

    var proxyURL: String {
        get { defaults.string(forKey: "proxyURL") ?? "https://asia-northeast1-voicetyping-prod.cloudfunctions.net/formatText" }
        set { defaults.set(newValue, forKey: "proxyURL") }
    }

    var customAPIKey: String? {
        get { defaults.string(forKey: "customAPIKey") }
        set { defaults.set(newValue, forKey: "customAPIKey") }
    }

    var deviceId: String {
        if let id = defaults.string(forKey: "deviceId") { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: "deviceId")
        return id
    }
}
```

- [ ] **Step 2: Write LLMFormatter**

```swift
// voicetyping/ios/Shared/LLMFormatter.swift
import Foundation

final class LLMFormatter {

    private let settings: Settings
    private let regexCleanup: RegexCleanup
    private let session: URLSession

    init(settings: Settings = .shared, session: URLSession = .shared) {
        self.settings = settings
        self.regexCleanup = RegexCleanup()
        self.session = session
    }

    func format(_ text: String, mode: OutputMode) async -> FormattingResult {
        guard !text.isEmpty else {
            return FormattingResult(original: text, cleaned: text, mode: mode, wasLLMFormatted: false)
        }

        if mode == .raw {
            return FormattingResult(original: text, cleaned: text, mode: mode, wasLLMFormatted: false)
        }

        // Try LLM first
        do {
            let cleaned = try await callProxy(text: text, mode: mode)
            return FormattingResult(original: text, cleaned: cleaned, mode: mode, wasLLMFormatted: true)
        } catch {
            // Fallback to regex
            let cleaned = regexCleanup.clean(text)
            return FormattingResult(original: text, cleaned: cleaned, mode: mode, wasLLMFormatted: false)
        }
    }

    private func callProxy(text: String, mode: OutputMode) async throws -> String {
        guard let url = URL(string: settings.proxyURL) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5

        let body: [String: String] = [
            "text": text,
            "mode": mode.rawValue,
            "deviceId": settings.deviceId,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? String else {
            throw URLError(.cannotParseResponse)
        }

        return result
    }
}
```

- [ ] **Step 3: Write LLMFormatter tests**

```swift
// voicetyping/ios/Tests/LLMFormatterTests.swift
import XCTest
@testable import VoiceTyping

final class LLMFormatterTests: XCTestCase {

    func testRawModeReturnsOriginalText() async {
        let formatter = LLMFormatter()
        let result = await formatter.format("えーっと、hello", mode: .raw)
        XCTAssertEqual(result.cleaned, "えーっと、hello")
        XCTAssertFalse(result.wasLLMFormatted)
    }

    func testEmptyTextReturnsEmpty() async {
        let formatter = LLMFormatter()
        let result = await formatter.format("", mode: .casual)
        XCTAssertEqual(result.cleaned, "")
        XCTAssertFalse(result.wasLLMFormatted)
    }

    func testFallsBackToRegexOnNetworkError() async {
        // Use invalid URL to force failure
        let settings = Settings(suiteName: "test.\(UUID().uuidString)")
        settings.proxyURL = "https://invalid.example.com/404"
        let formatter = LLMFormatter(settings: settings)

        let result = await formatter.format("えーっと、hello world", mode: .casual)
        // Should fall back to regex cleanup
        XCTAssertFalse(result.wasLLMFormatted)
        XCTAssertFalse(result.cleaned.contains("えーっと"))
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add voicetyping/ios/Shared/LLMFormatter.swift voicetyping/ios/Shared/Settings.swift voicetyping/ios/Tests/LLMFormatterTests.swift
git commit -m "feat: add LLMFormatter with Gemini proxy + regex fallback"
```

---

## Phase 2: iOS Keyboard Extension

### Task 4: Create Xcode Project with Keyboard Extension Target

**Files:**
- Create: Xcode project at `voicetyping/ios/`

- [ ] **Step 1: Create Xcode project via command line**

This must be done in Xcode (or `xcodegen`). Create a `project.yml` for XcodeGen:

```yaml
# voicetyping/ios/project.yml
name: VoiceTyping
options:
  bundleIdPrefix: com.voicetyping
  deploymentTarget:
    iOS: "16.0"

settings:
  SWIFT_VERSION: "5.9"
  DEVELOPMENT_TEAM: ""

targets:
  VoiceTyping:
    type: application
    platform: iOS
    sources:
      - VoiceTyping
      - Shared
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.voicetyping.app
      INFOPLIST_FILE: VoiceTyping/Info.plist
    dependencies:
      - target: VoiceTypingKeyboard

  VoiceTypingKeyboard:
    type: app-extension
    platform: iOS
    sources:
      - VoiceTypingKeyboard
      - Shared
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.voicetyping.app.keyboard
      INFOPLIST_FILE: VoiceTypingKeyboard/Info.plist
    entitlements:
      path: VoiceTypingKeyboard/VoiceTypingKeyboard.entitlements

  VoiceTypingTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - Tests
      - Shared
    dependencies:
      - target: VoiceTyping
```

- [ ] **Step 2: Install xcodegen and generate project**

```bash
brew install xcodegen
cd voicetyping/ios && xcodegen generate
```

Expected: `VoiceTyping.xcodeproj` created.

- [ ] **Step 3: Create Info.plist for keyboard extension**

```xml
<!-- voicetyping/ios/VoiceTypingKeyboard/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionAttributes</key>
        <dict>
            <key>IsASCIICapable</key>
            <true/>
            <key>PrefersRightToLeft</key>
            <false/>
            <key>PrimaryLanguage</key>
            <string>ja</string>
            <key>RequestsOpenAccess</key>
            <true/>
        </dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.keyboard-service</string>
        <key>NSExtensionPrincipalClass</key>
        <string>$(PRODUCT_MODULE_NAME).KeyboardViewController</string>
    </dict>
    <key>NSMicrophoneUsageDescription</key>
    <string>VoiceTyping uses your microphone for voice input.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>VoiceTyping uses speech recognition to convert your voice to text.</string>
</dict>
</plist>
```

- [ ] **Step 4: Create entitlements for App Group**

```xml
<!-- voicetyping/ios/VoiceTypingKeyboard/VoiceTypingKeyboard.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.voicetyping.shared</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 5: Commit**

```bash
git add voicetyping/ios/
git commit -m "feat: create Xcode project with keyboard extension target"
```

---

### Task 5: SpeechManager — Persistent Recording (iOS)

**Files:**
- Create: `voicetyping/ios/VoiceTypingKeyboard/SpeechManager.swift`

- [ ] **Step 1: Write SpeechManager with persistent recording**

```swift
// voicetyping/ios/VoiceTypingKeyboard/SpeechManager.swift
import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechManager: ObservableObject {

    @Published var isRecording = false
    @Published var transcription = ""
    @Published var error: String?

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    init() {
        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    }

    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            error = "音声認識の許可が必要です"
            return false
        }

        let audioStatus = await AVAudioApplication.requestRecordPermission()
        guard audioStatus else {
            error = "マイクの許可が必要です"
            return false
        }

        return true
    }

    func startRecording() {
        guard !isRecording else { return }

        transcription = ""
        error = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true // Privacy: never leave device

        // KEY: This prevents auto-cutoff on silence
        if #available(iOS 16, *) {
            request.addsPunctuation = true
        }

        guard let recognizer = recognizer, recognizer.isAvailable else {
            error = "音声認識が利用できません"
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            recognitionRequest = request
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, taskError in
                Task { @MainActor in
                    guard let self = self else { return }
                    if let result = result {
                        self.transcription = result.bestTranscription.formattedString
                    }
                    if let taskError = taskError {
                        // If the task ended due to an error (not user cancel), restart
                        let nsError = taskError as NSError
                        if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                            // "No speech detected" — restart silently for persistent recording
                            self.restartRecognitionTask()
                        }
                    }
                }
            }

            isRecording = true
        } catch {
            self.error = "録音を開始できませんでした: \(error.localizedDescription)"
        }
    }

    func stopRecording() -> String {
        guard isRecording else { return transcription }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false)

        return transcription
    }

    /// Restart recognition without stopping audio engine (handles Apple's 60s limit)
    private func restartRecognitionTask() {
        guard isRecording else { return }

        let currentText = transcription
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        if #available(iOS 16, *) {
            request.addsPunctuation = true
        }

        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, taskError in
            Task { @MainActor in
                guard let self = self else { return }
                if let result = result {
                    self.transcription = currentText + " " + result.bestTranscription.formattedString
                }
                if let taskError = taskError {
                    let nsError = taskError as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                        self.restartRecognitionTask()
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add voicetyping/ios/VoiceTypingKeyboard/SpeechManager.swift
git commit -m "feat: add SpeechManager with persistent recording (no auto-cutoff)"
```

---

### Task 6: Keyboard UI — SwiftUI Layout + Mic Button

**Files:**
- Create: `voicetyping/ios/VoiceTypingKeyboard/KeyboardViewController.swift`
- Create: `voicetyping/ios/VoiceTypingKeyboard/KeyboardView.swift`
- Create: `voicetyping/ios/VoiceTypingKeyboard/TranscriptionPreview.swift`
- Create: `voicetyping/ios/VoiceTypingKeyboard/ModeSelector.swift`

- [ ] **Step 1: Write KeyboardViewController (UIKit bridge)**

```swift
// voicetyping/ios/VoiceTypingKeyboard/KeyboardViewController.swift
import UIKit
import SwiftUI

class KeyboardViewController: UIInputViewController {

    private var hostingController: UIHostingController<KeyboardView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        let keyboardView = KeyboardView(
            textDocumentProxy: textDocumentProxy,
            advanceToNextInputMode: { [weak self] in
                self?.advanceToNextInputMode()
            }
        )

        let host = UIHostingController(rootView: keyboardView)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear

        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)

        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        hostingController = host
    }
}
```

- [ ] **Step 2: Write ModeSelector**

```swift
// voicetyping/ios/VoiceTypingKeyboard/ModeSelector.swift
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
```

- [ ] **Step 3: Write TranscriptionPreview**

```swift
// voicetyping/ios/VoiceTypingKeyboard/TranscriptionPreview.swift
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
```

- [ ] **Step 4: Write KeyboardView (main layout)**

```swift
// voicetyping/ios/VoiceTypingKeyboard/KeyboardView.swift
import SwiftUI
import UIKit

struct KeyboardView: View {
    let textDocumentProxy: UITextDocumentProxy
    let advanceToNextInputMode: () -> Void

    @StateObject private var speechManager = SpeechManager()
    @State private var selectedMode: OutputMode = Settings.shared.selectedMode
    @State private var cleanedText: String?
    @State private var isProcessing = false
    @State private var showRaw = false

    private let formatter = LLMFormatter()

    var body: some View {
        VStack(spacing: 4) {
            // Mode selector
            ModeSelector(selectedMode: $selectedMode)
                .padding(.top, 4)

            // Transcription preview
            TranscriptionPreview(
                rawText: speechManager.transcription,
                cleanedText: cleanedText,
                isProcessing: isProcessing,
                showRaw: showRaw,
                onInsert: insertText
            )
            .onTapGesture {
                if cleanedText != nil { showRaw.toggle() }
            }

            Spacer(minLength: 2)

            // Bottom row: globe, space, mic
            HStack(spacing: 0) {
                // Globe button (switch keyboard)
                Button(action: advanceToNextInputMode) {
                    Image(systemName: "globe")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .foregroundColor(.primary)
                }

                // Space bar
                Button(action: { textDocumentProxy.insertText(" ") }) {
                    Text("space")
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color(.systemBackground))
                        .cornerRadius(6)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 4)

                // Backspace
                Button(action: { textDocumentProxy.deleteBackward() }) {
                    Image(systemName: "delete.left")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .foregroundColor(.primary)
                }

                // Mic button
                Button(action: toggleRecording) {
                    Image(systemName: speechManager.isRecording ? "mic.fill" : "mic")
                        .font(.title2)
                        .frame(width: 52, height: 52)
                        .background(speechManager.isRecording ? Color.red : Color.blue)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)

            // Return key
            HStack {
                Spacer()
                Button(action: { textDocumentProxy.insertText("\n") }) {
                    Text("return")
                        .font(.callout)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
        .frame(height: 260)
        .background(Color(.systemGray5))
    }

    private func toggleRecording() {
        if speechManager.isRecording {
            let rawText = speechManager.stopRecording()
            processText(rawText)
        } else {
            cleanedText = nil
            showRaw = false
            Task {
                let granted = await speechManager.requestPermissions()
                if granted {
                    speechManager.startRecording()
                }
            }
        }

        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }

    private func processText(_ text: String) {
        guard !text.isEmpty else { return }
        isProcessing = true
        Task {
            let result = await formatter.format(text, mode: selectedMode)
            cleanedText = result.cleaned
            isProcessing = false
        }
    }

    private func insertText() {
        guard let text = cleanedText ?? (speechManager.transcription.isEmpty ? nil : speechManager.transcription) else { return }
        textDocumentProxy.insertText(text)
        cleanedText = nil
        speechManager.transcription = ""
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add voicetyping/ios/VoiceTypingKeyboard/
git commit -m "feat: add iOS keyboard extension with voice input UI"
```

---

### Task 7: iOS Host App — Onboarding + Settings

**Files:**
- Create: `voicetyping/ios/VoiceTyping/VoiceTypingApp.swift`
- Create: `voicetyping/ios/VoiceTyping/ContentView.swift`
- Create: `voicetyping/ios/VoiceTyping/OnboardingView.swift`
- Create: `voicetyping/ios/VoiceTyping/Info.plist`

- [ ] **Step 1: Write VoiceTypingApp.swift**

```swift
// voicetyping/ios/VoiceTyping/VoiceTypingApp.swift
import SwiftUI

@main
struct VoiceTypingApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

- [ ] **Step 2: Write OnboardingView**

```swift
// voicetyping/ios/VoiceTyping/OnboardingView.swift
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
```

- [ ] **Step 3: Write ContentView**

```swift
// voicetyping/ios/VoiceTyping/ContentView.swift
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
```

- [ ] **Step 4: Write host app Info.plist**

```xml
<!-- voicetyping/ios/VoiceTyping/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>VoiceTyping</string>
    <key>CFBundleDisplayName</key>
    <string>VoiceTyping</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>VoiceTyping uses your microphone for voice input.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>VoiceTyping uses speech recognition to convert your voice to text.</string>
</dict>
</plist>
```

- [ ] **Step 5: Commit**

```bash
git add voicetyping/ios/VoiceTyping/
git commit -m "feat: add iOS host app with onboarding and settings"
```

---

## Phase 3: Android IME

### Task 8: Android Project Setup

**Files:**
- Create: `voicetyping/android/settings.gradle.kts`
- Create: `voicetyping/android/build.gradle.kts`
- Create: `voicetyping/android/app/build.gradle.kts`
- Create: `voicetyping/android/app/src/main/AndroidManifest.xml`
- Create: `voicetyping/android/app/src/main/res/xml/method.xml`
- Create: `voicetyping/android/app/src/main/res/values/strings.xml`

- [ ] **Step 1: Create project structure**

```bash
mkdir -p voicetyping/android/app/src/{main/{kotlin/com/voicetyping/{ime,formatter,model},res/{xml,values,layout}},test/kotlin/com/voicetyping}
```

- [ ] **Step 2: Write settings.gradle.kts**

```kotlin
// voicetyping/android/settings.gradle.kts
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolution {
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "VoiceTyping"
include(":app")
```

- [ ] **Step 3: Write root build.gradle.kts**

```kotlin
// voicetyping/android/build.gradle.kts
plugins {
    id("com.android.application") version "8.7.0" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.1.0" apply false
}
```

- [ ] **Step 4: Write app/build.gradle.kts**

```kotlin
// voicetyping/android/app/build.gradle.kts
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.voicetyping"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.voicetyping"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.compose.ui:ui:1.7.6")
    implementation("androidx.compose.material3:material3:1.3.1")
    implementation("androidx.compose.ui:ui-tooling-preview:1.7.6")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
}
```

- [ ] **Step 5: Write AndroidManifest.xml**

```xml
<!-- voicetyping/android/app/src/main/AndroidManifest.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.INTERNET" />

    <application
        android:label="VoiceTyping"
        android:supportsRtl="true"
        android:theme="@style/Theme.Material3.DayNight">

        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <service
            android:name=".ime.VoiceTypingIME"
            android:exported="true"
            android:permission="android.permission.BIND_INPUT_METHOD">
            <intent-filter>
                <action android:name="android.view.InputMethod" />
            </intent-filter>
            <meta-data
                android:name="android.view.im"
                android:resource="@xml/method" />
        </service>

    </application>
</manifest>
```

- [ ] **Step 6: Write IME declaration and strings**

```xml
<!-- voicetyping/android/app/src/main/res/xml/method.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<input-method xmlns:android="http://schemas.android.com/apk/res/android"
    android:settingsActivity="com.voicetyping.MainActivity">
    <subtype
        android:label="日本語"
        android:imeSubtypeLocale="ja_JP"
        android:imeSubtypeMode="voice" />
    <subtype
        android:label="English"
        android:imeSubtypeLocale="en_US"
        android:imeSubtypeMode="voice" />
</input-method>
```

```xml
<!-- voicetyping/android/app/src/main/res/values/strings.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<resources>
    <string name="app_name">VoiceTyping</string>
</resources>
```

- [ ] **Step 7: Commit**

```bash
git add voicetyping/android/
git commit -m "feat: scaffold Android project with IME service declaration"
```

---

### Task 9: Android RegexCleanup + LLMFormatter

**Files:**
- Create: `voicetyping/android/app/src/main/kotlin/com/voicetyping/model/OutputMode.kt`
- Create: `voicetyping/android/app/src/main/kotlin/com/voicetyping/model/Settings.kt`
- Create: `voicetyping/android/app/src/main/kotlin/com/voicetyping/formatter/RegexCleanup.kt`
- Create: `voicetyping/android/app/src/main/kotlin/com/voicetyping/formatter/LLMFormatter.kt`
- Create: `voicetyping/android/app/src/test/kotlin/com/voicetyping/RegexCleanupTest.kt`

- [ ] **Step 1: Write OutputMode.kt**

```kotlin
// voicetyping/android/app/src/main/kotlin/com/voicetyping/model/OutputMode.kt
package com.voicetyping.model

enum class OutputMode(val label: String) {
    CASUAL("カジュアル"),
    BUSINESS("ビジネス"),
    TECHNICAL("テクニカル"),
    RAW("そのまま");
}
```

- [ ] **Step 2: Write Settings.kt**

```kotlin
// voicetyping/android/app/src/main/kotlin/com/voicetyping/model/Settings.kt
package com.voicetyping.model

import android.content.Context
import android.content.SharedPreferences
import java.util.UUID

class Settings(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences("voicetyping_prefs", Context.MODE_PRIVATE)

    var selectedMode: OutputMode
        get() = OutputMode.entries.find { it.name == prefs.getString("mode", null) } ?: OutputMode.CASUAL
        set(value) = prefs.edit().putString("mode", value.name).apply()

    val proxyURL: String
        get() = prefs.getString("proxyURL", "https://asia-northeast1-voicetyping-prod.cloudfunctions.net/formatText")!!

    val deviceId: String
        get() {
            val existing = prefs.getString("deviceId", null)
            if (existing != null) return existing
            val id = UUID.randomUUID().toString()
            prefs.edit().putString("deviceId", id).apply()
            return id
        }
}
```

- [ ] **Step 3: Write RegexCleanup.kt**

```kotlin
// voicetyping/android/app/src/main/kotlin/com/voicetyping/formatter/RegexCleanup.kt
package com.voicetyping.formatter

class RegexCleanup {

    private val jaFillers = listOf(
        "えーっと[、,]?\\s*",
        "えーと[、,]?\\s*",
        "えー[、,]?\\s*",
        "あのー?[、,]?\\s*",
        "うーん[、,]?\\s*",
        "まあ[、,]?\\s*",
        "なんか[、,]?\\s*",
        "そのー?[、,]?\\s*",
    )

    private val enFillers = listOf(
        "\\bum+\\b[,.]?\\s*",
        "\\buh+\\b[,.]?\\s*",
        "\\blike\\b[,]?\\s+(?=\\w)",
        "\\byou know\\b[,.]?\\s*",
        "\\bso\\b[,]?\\s+(?=\\w)",
        "\\bbasically\\b[,.]?\\s*",
        "\\bactually\\b[,.]?\\s*",
        "\\bi mean\\b[,.]?\\s*",
    )

    fun clean(text: String): String {
        if (text.isBlank()) return ""

        var result = text
        (jaFillers + enFillers).forEach { pattern ->
            result = Regex(pattern, RegexOption.IGNORE_CASE).replace(result, "")
        }
        result = result.replace(Regex("\\s{2,}"), " ").trim()
        return result
    }
}
```

- [ ] **Step 4: Write LLMFormatter.kt**

```kotlin
// voicetyping/android/app/src/main/kotlin/com/voicetyping/formatter/LLMFormatter.kt
package com.voicetyping.formatter

import com.voicetyping.model.OutputMode
import com.voicetyping.model.Settings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

data class FormattingResult(
    val original: String,
    val cleaned: String,
    val mode: OutputMode,
    val wasLLMFormatted: Boolean,
)

class LLMFormatter(private val settings: Settings) {

    private val client = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(5, TimeUnit.SECONDS)
        .build()

    private val regexCleanup = RegexCleanup()

    suspend fun format(text: String, mode: OutputMode): FormattingResult {
        if (text.isBlank()) return FormattingResult(text, text, mode, false)
        if (mode == OutputMode.RAW) return FormattingResult(text, text, mode, false)

        return try {
            val cleaned = callProxy(text, mode)
            FormattingResult(text, cleaned, mode, true)
        } catch (_: Exception) {
            val cleaned = regexCleanup.clean(text)
            FormattingResult(text, cleaned, mode, false)
        }
    }

    private suspend fun callProxy(text: String, mode: OutputMode): String =
        withContext(Dispatchers.IO) {
            val json = JSONObject().apply {
                put("text", text)
                put("mode", mode.name.lowercase())
                put("deviceId", settings.deviceId)
            }

            val body = json.toString().toRequestBody("application/json".toMediaType())
            val request = Request.Builder()
                .url(settings.proxyURL)
                .post(body)
                .build()

            val response = client.newCall(request).execute()
            if (!response.isSuccessful) throw RuntimeException("HTTP ${response.code}")

            val responseBody = response.body?.string() ?: throw RuntimeException("Empty response")
            JSONObject(responseBody).getString("result")
        }
}
```

- [ ] **Step 5: Write RegexCleanupTest.kt**

```kotlin
// voicetyping/android/app/src/test/kotlin/com/voicetyping/RegexCleanupTest.kt
package com.voicetyping

import com.voicetyping.formatter.RegexCleanup
import org.junit.Assert.*
import org.junit.Test

class RegexCleanupTest {

    private val cleanup = RegexCleanup()

    @Test
    fun removesJapaneseFillers() {
        val result = cleanup.clean("えーっと、あの、明日のミーティングなんだけど")
        assertFalse(result.contains("えーっと"))
        assertFalse(result.contains("あの"))
        assertTrue(result.contains("明日のミーティング"))
    }

    @Test
    fun removesEnglishFillers() {
        val result = cleanup.clean("um so like you know the meeting is tomorrow")
        assertFalse(result.contains("um "))
        assertFalse(result.contains("like "))
        assertFalse(result.contains("you know "))
        assertTrue(result.contains("the meeting is tomorrow"))
    }

    @Test
    fun trimsWhitespace() {
        assertEquals("hello world", cleanup.clean("  hello   world  "))
    }

    @Test
    fun emptyReturnsEmpty() {
        assertEquals("", cleanup.clean(""))
    }

    @Test
    fun preservesNormalText() {
        val input = "明後日の15時からミーティングです"
        assertEquals(input, cleanup.clean(input))
    }
}
```

- [ ] **Step 6: Commit**

```bash
git add voicetyping/android/app/src/
git commit -m "feat: add Android RegexCleanup and LLMFormatter"
```

---

### Task 10: Android IME — SpeechManager + Keyboard UI

**Files:**
- Create: `voicetyping/android/app/src/main/kotlin/com/voicetyping/ime/SpeechManager.kt`
- Create: `voicetyping/android/app/src/main/kotlin/com/voicetyping/ime/VoiceTypingIME.kt`
- Create: `voicetyping/android/app/src/main/kotlin/com/voicetyping/ime/KeyboardView.kt`
- Create: `voicetyping/android/app/src/main/kotlin/com/voicetyping/ime/ModeSelector.kt`
- Create: `voicetyping/android/app/src/main/kotlin/com/voicetyping/MainActivity.kt`

- [ ] **Step 1: Write SpeechManager.kt with persistent recording**

```kotlin
// voicetyping/android/app/src/main/kotlin/com/voicetyping/ime/SpeechManager.kt
package com.voicetyping.ime

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

class SpeechManager(private val context: Context) {

    private val _transcription = MutableStateFlow("")
    val transcription: StateFlow<String> = _transcription

    private val _isRecording = MutableStateFlow(false)
    val isRecording: StateFlow<Boolean> = _isRecording

    private var speechRecognizer: SpeechRecognizer? = null
    private var accumulatedText = ""

    fun startRecording() {
        accumulatedText = ""
        _transcription.value = ""
        _isRecording.value = true
        startListening()
    }

    fun stopRecording(): String {
        _isRecording.value = false
        speechRecognizer?.stopListening()
        speechRecognizer?.destroy()
        speechRecognizer = null
        return _transcription.value
    }

    private fun startListening() {
        if (!_isRecording.value) return

        speechRecognizer?.destroy()
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(context)

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            // KEY: Max silence timeout to prevent auto-cutoff
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 60_000L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 30_000L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 60_000L)
        }

        speechRecognizer?.setRecognitionListener(object : RecognitionListener {
            override fun onResults(results: Bundle?) {
                val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                if (!matches.isNullOrEmpty()) {
                    accumulatedText = if (accumulatedText.isEmpty()) {
                        matches[0]
                    } else {
                        "$accumulatedText ${matches[0]}"
                    }
                    _transcription.value = accumulatedText
                }
                // Restart for persistent recording
                if (_isRecording.value) {
                    startListening()
                }
            }

            override fun onPartialResults(partialResults: Bundle?) {
                val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                if (!matches.isNullOrEmpty()) {
                    _transcription.value = if (accumulatedText.isEmpty()) {
                        matches[0]
                    } else {
                        "$accumulatedText ${matches[0]}"
                    }
                }
            }

            override fun onError(error: Int) {
                // On error (including silence timeout), restart if still recording
                if (_isRecording.value && error != SpeechRecognizer.ERROR_CLIENT) {
                    startListening()
                }
            }

            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })

        speechRecognizer?.startListening(intent)
    }
}
```

- [ ] **Step 2: Write ModeSelector.kt**

```kotlin
// voicetyping/android/app/src/main/kotlin/com/voicetyping/ime/ModeSelector.kt
package com.voicetyping.ime

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.voicetyping.model.OutputMode

@Composable
fun ModeSelector(
    selectedMode: OutputMode,
    onModeSelected: (OutputMode) -> Unit,
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
    ) {
        OutputMode.entries.forEach { mode ->
            FilterChip(
                selected = mode == selectedMode,
                onClick = { onModeSelected(mode) },
                label = { Text(mode.label, fontSize = 11.sp) },
                shape = RoundedCornerShape(8.dp),
                modifier = Modifier.height(28.dp),
            )
        }
    }
}
```

- [ ] **Step 3: Write KeyboardView.kt**

```kotlin
// voicetyping/android/app/src/main/kotlin/com/voicetyping/ime/KeyboardView.kt
package com.voicetyping.ime

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.voicetyping.model.OutputMode

@Composable
fun KeyboardLayout(
    transcription: String,
    cleanedText: String?,
    isRecording: Boolean,
    isProcessing: Boolean,
    selectedMode: OutputMode,
    onModeSelected: (OutputMode) -> Unit,
    onMicTap: () -> Unit,
    onInsert: () -> Unit,
    onBackspace: () -> Unit,
    onSpace: () -> Unit,
    onReturn: () -> Unit,
    onSwitchKeyboard: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .height(240.dp)
            .background(MaterialTheme.colorScheme.surfaceVariant)
    ) {
        // Mode selector
        ModeSelector(selectedMode = selectedMode, onModeSelected = onModeSelected)

        // Preview area
        if (transcription.isNotEmpty() || isProcessing) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(MaterialTheme.colorScheme.surface)
                    .clickable { if (cleanedText != null) onInsert() }
                    .padding(8.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = cleanedText ?: transcription,
                        fontSize = 14.sp,
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                    if (isProcessing) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            strokeWidth = 2.dp,
                        )
                    }
                    if (cleanedText != null) {
                        TextButton(onClick = onInsert) {
                            Text("入力", fontSize = 12.sp)
                        }
                    }
                }
            }
        }

        Spacer(modifier = Modifier.weight(1f))

        // Bottom row
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Globe (switch keyboard)
            IconButton(onClick = onSwitchKeyboard) {
                Text("🌐", fontSize = 20.sp)
            }

            // Space
            Button(
                onClick = onSpace,
                modifier = Modifier
                    .weight(1f)
                    .height(44.dp)
                    .padding(horizontal = 4.dp),
                shape = RoundedCornerShape(6.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    contentColor = MaterialTheme.colorScheme.onSurface,
                ),
            ) {
                Text("space")
            }

            // Backspace
            IconButton(onClick = onBackspace) {
                Text("⌫", fontSize = 20.sp)
            }

            // Mic button
            IconButton(
                onClick = onMicTap,
                modifier = Modifier
                    .size(52.dp)
                    .clip(CircleShape)
                    .background(if (isRecording) Color.Red else MaterialTheme.colorScheme.primary),
            ) {
                Text(
                    if (isRecording) "🔴" else "🎤",
                    fontSize = 22.sp,
                )
            }
        }

        // Return row
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.End,
        ) {
            Button(onClick = onReturn, shape = RoundedCornerShape(6.dp)) {
                Text("return")
            }
        }
    }
}
```

- [ ] **Step 4: Write VoiceTypingIME.kt**

```kotlin
// voicetyping/android/app/src/main/kotlin/com/voicetyping/ime/VoiceTypingIME.kt
package com.voicetyping.ime

import android.inputmethodservice.InputMethodService
import android.view.View
import androidx.compose.runtime.*
import androidx.compose.ui.platform.ComposeView
import androidx.lifecycle.setViewTreeLifecycleOwner
import com.voicetyping.formatter.LLMFormatter
import com.voicetyping.model.OutputMode
import com.voicetyping.model.Settings
import kotlinx.coroutines.*

class VoiceTypingIME : InputMethodService() {

    private lateinit var settings: Settings
    private lateinit var formatter: LLMFormatter
    private lateinit var speechManager: SpeechManager
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun onCreate() {
        super.onCreate()
        settings = Settings(this)
        formatter = LLMFormatter(settings)
        speechManager = SpeechManager(this)
    }

    override fun onCreateInputView(): View {
        val composeView = ComposeView(this).apply {
            setViewTreeLifecycleOwner(VoiceTypingLifecycleOwner())
            setContent {
                val transcription by speechManager.transcription.collectAsState()
                val isRecording by speechManager.isRecording.collectAsState()
                var selectedMode by remember { mutableStateOf(settings.selectedMode) }
                var cleanedText by remember { mutableStateOf<String?>(null) }
                var isProcessing by remember { mutableStateOf(false) }

                KeyboardLayout(
                    transcription = transcription,
                    cleanedText = cleanedText,
                    isRecording = isRecording,
                    isProcessing = isProcessing,
                    selectedMode = selectedMode,
                    onModeSelected = {
                        selectedMode = it
                        settings.selectedMode = it
                    },
                    onMicTap = {
                        if (isRecording) {
                            val raw = speechManager.stopRecording()
                            if (raw.isNotBlank()) {
                                isProcessing = true
                                scope.launch {
                                    val result = formatter.format(raw, selectedMode)
                                    cleanedText = result.cleaned
                                    isProcessing = false
                                }
                            }
                        } else {
                            cleanedText = null
                            speechManager.startRecording()
                        }
                    },
                    onInsert = {
                        val text = cleanedText ?: transcription
                        if (text.isNotBlank()) {
                            currentInputConnection?.commitText(text, 1)
                            cleanedText = null
                        }
                    },
                    onBackspace = {
                        currentInputConnection?.deleteSurroundingText(1, 0)
                    },
                    onSpace = {
                        currentInputConnection?.commitText(" ", 1)
                    },
                    onReturn = {
                        currentInputConnection?.commitText("\n", 1)
                    },
                    onSwitchKeyboard = {
                        switchToNextInputMethod(false)
                    },
                )
            }
        }
        return composeView
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
```

- [ ] **Step 5: Write VoiceTypingLifecycleOwner helper**

```kotlin
// voicetyping/android/app/src/main/kotlin/com/voicetyping/ime/VoiceTypingLifecycleOwner.kt
package com.voicetyping.ime

import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry

class VoiceTypingLifecycleOwner : LifecycleOwner {
    private val registry = LifecycleRegistry(this)

    init {
        registry.currentState = Lifecycle.State.RESUMED
    }

    override val lifecycle: Lifecycle = registry
}
```

- [ ] **Step 6: Write MainActivity.kt (settings + onboarding)**

```kotlin
// voicetyping/android/app/src/main/kotlin/com/voicetyping/MainActivity.kt
package com.voicetyping

import android.content.Intent
import android.os.Bundle
import android.provider.Settings as AndroidSettings
import android.view.inputmethod.InputMethodManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.voicetyping.model.OutputMode
import com.voicetyping.model.Settings

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val settings = Settings(this)

        setContent {
            MaterialTheme {
                var selectedMode by remember { mutableStateOf(settings.selectedMode) }

                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(24.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    Text("VoiceTyping", fontSize = 28.sp)

                    Text("セットアップ", style = MaterialTheme.typography.titleMedium)

                    OutlinedButton(onClick = {
                        startActivity(Intent(AndroidSettings.ACTION_INPUT_METHOD_SETTINGS))
                    }) {
                        Text("キーボードを有効にする")
                    }

                    OutlinedButton(onClick = {
                        val imm = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
                        imm.showInputMethodPicker()
                    }) {
                        Text("キーボードを切り替える")
                    }

                    Spacer(modifier = Modifier.height(16.dp))

                    Text("デフォルトモード", style = MaterialTheme.typography.titleMedium)

                    OutputMode.entries.forEach { mode ->
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            RadioButton(
                                selected = mode == selectedMode,
                                onClick = {
                                    selectedMode = mode
                                    settings.selectedMode = mode
                                },
                            )
                            Text(mode.label, modifier = Modifier.padding(start = 8.dp))
                        }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 7: Commit**

```bash
git add voicetyping/android/
git commit -m "feat: add Android IME with persistent voice recording and Compose UI"
```

---

## Phase 4: Mac Menu Bar App

### Task 11: Mac App — Menu Bar + Global Hotkey + Floating Window

**Files:**
- Create: `voicetyping/mac/VoiceTypingMac/VoiceTypingMacApp.swift`
- Create: `voicetyping/mac/VoiceTypingMac/HotkeyManager.swift`
- Create: `voicetyping/mac/VoiceTypingMac/FloatingWindow.swift`
- Create: `voicetyping/mac/VoiceTypingMac/SpeechManager.swift`
- Create: `voicetyping/mac/VoiceTypingMac/TextInjector.swift`
- Create: `voicetyping/mac/VoiceTypingMac/SettingsView.swift`
- Create: `voicetyping/mac/VoiceTypingMac/LLMFormatter.swift` (copy from iOS Shared)
- Create: `voicetyping/mac/VoiceTypingMac/RegexCleanup.swift` (copy from iOS Shared)
- Create: `voicetyping/mac/VoiceTypingMac/Models.swift` (copy from iOS Shared)
- Create: `voicetyping/mac/VoiceTypingMac/Info.plist`
- Create: `voicetyping/mac/project.yml`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p voicetyping/mac/{VoiceTypingMac,Tests}
```

- [ ] **Step 2: Copy shared files from iOS**

```bash
cp voicetyping/ios/Shared/{Models.swift,RegexCleanup.swift,LLMFormatter.swift} voicetyping/mac/VoiceTypingMac/
```

Update Settings for macOS (no App Group needed):

```swift
// voicetyping/mac/VoiceTypingMac/Settings.swift
import Foundation

final class Settings {

    static let shared = Settings()

    private let defaults = UserDefaults.standard

    var selectedMode: OutputMode {
        get {
            guard let raw = defaults.string(forKey: "selectedMode"),
                  let mode = OutputMode(rawValue: raw) else { return .casual }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: "selectedMode") }
    }

    var proxyURL: String {
        get { defaults.string(forKey: "proxyURL") ?? "https://asia-northeast1-voicetyping-prod.cloudfunctions.net/formatText" }
        set { defaults.set(newValue, forKey: "proxyURL") }
    }

    var customAPIKey: String? {
        get { defaults.string(forKey: "customAPIKey") }
        set { defaults.set(newValue, forKey: "customAPIKey") }
    }

    var deviceId: String {
        if let id = defaults.string(forKey: "deviceId") { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: "deviceId")
        return id
    }

    var hotkeyKeyCode: UInt16 {
        get { UInt16(defaults.integer(forKey: "hotkeyKeyCode").nonZeroOr(58)) } // 58 = Right Option
        set { defaults.set(Int(newValue), forKey: "hotkeyKeyCode") }
    }
}

private extension Int {
    func nonZeroOr(_ fallback: Int) -> Int { self == 0 ? fallback : self }
}
```

- [ ] **Step 3: Write SpeechManager for Mac**

```swift
// voicetyping/mac/VoiceTypingMac/SpeechManager.swift
import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechManager: ObservableObject {

    @Published var isRecording = false
    @Published var transcription = ""

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var accumulatedText = ""

    init() {
        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    }

    func startRecording() {
        guard !isRecording else { return }
        accumulatedText = ""
        transcription = ""
        beginRecognitionSession()
        isRecording = true
    }

    func stopRecording() -> String {
        guard isRecording else { return transcription }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        return transcription
    }

    private func beginRecognitionSession() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13, *) {
            request.requiresOnDeviceRecognition = true
        }

        let currentAccumulated = accumulatedText
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try? audioEngine.start()

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let result = result {
                    let partial = result.bestTranscription.formattedString
                    self.transcription = currentAccumulated.isEmpty ? partial : "\(currentAccumulated) \(partial)"
                }
                if error != nil, self.isRecording {
                    self.accumulatedText = self.transcription
                    self.beginRecognitionSession()
                }
            }
        }
    }
}
```

- [ ] **Step 4: Write HotkeyManager**

```swift
// voicetyping/mac/VoiceTypingMac/HotkeyManager.swift
import Cocoa

final class HotkeyManager {

    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private let keyCode: UInt16

    init(keyCode: UInt16 = 58) { // 58 = Right Option
        self.keyCode = keyCode
    }

    func start() {
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

            if type == .flagsChanged && event.getIntegerValueField(.keyboardEventKeycode) == Int64(manager.keyCode) {
                let flags = event.flags
                if flags.contains(.maskAlternate) {
                    manager.onHotkeyDown?()
                } else {
                    manager.onHotkeyUp?()
                }
            }

            return Unmanaged.passRetained(event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        )

        guard let eventTap = eventTap else { return }
        let source = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
}
```

- [ ] **Step 5: Write TextInjector**

```swift
// voicetyping/mac/VoiceTypingMac/TextInjector.swift
import Cocoa

final class TextInjector {

    func inject(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V key
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // Restore clipboard after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let prev = previousContents {
                pasteboard.clearContents()
                pasteboard.setString(prev, forType: .string)
            }
        }
    }
}
```

- [ ] **Step 6: Write FloatingWindow**

```swift
// voicetyping/mac/VoiceTypingMac/FloatingWindow.swift
import Cocoa
import SwiftUI

final class FloatingWindow: NSPanel {

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 80),
            styleMask: [.nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
    }

    func showNearCursor() {
        let mouseLocation = NSEvent.mouseLocation
        setFrameOrigin(NSPoint(x: mouseLocation.x - 200, y: mouseLocation.y + 20))
        orderFront(nil)
    }

    func updateContent(text: String, isProcessing: Bool) {
        contentView = NSHostingView(rootView:
            HStack {
                Text(text.isEmpty ? "話してください..." : text)
                    .foregroundColor(.white)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .padding(12)
            .frame(width: 400)
            .background(Color.black.opacity(0.85))
            .cornerRadius(12)
        )
    }
}
```

- [ ] **Step 7: Write VoiceTypingMacApp (menu bar)**

```swift
// voicetyping/mac/VoiceTypingMac/VoiceTypingMacApp.swift
import SwiftUI

@main
struct VoiceTypingMacApp: App {

    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("VoiceTyping", systemImage: appState.isRecording ? "mic.fill" : "mic") {
            VStack(alignment: .leading, spacing: 8) {
                Text(appState.isRecording ? "録音中..." : "Right Option で録音")
                    .font(.headline)

                if !appState.lastTranscription.isEmpty {
                    Divider()
                    Text(appState.lastTranscription)
                        .font(.body)
                        .lineLimit(5)
                }

                Divider()

                Menu("モード: \(appState.selectedMode.label)") {
                    ForEach(OutputMode.allCases, id: \.self) { mode in
                        Button(mode.label) {
                            appState.selectedMode = mode
                            Settings.shared.selectedMode = mode
                        }
                    }
                }

                Button("設定...") { appState.showSettings = true }
                Divider()
                Button("終了") { NSApplication.shared.terminate(nil) }
            }
            .padding(8)
            .frame(width: 300)
        }

        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppState: ObservableObject {

    @Published var isRecording = false
    @Published var lastTranscription = ""
    @Published var selectedMode: OutputMode = Settings.shared.selectedMode
    @Published var showSettings = false

    private let speechManager = SpeechManager()
    private let hotkeyManager = HotkeyManager()
    private let formatter = LLMFormatter()
    private let textInjector = TextInjector()
    private let floatingWindow = FloatingWindow()

    init() {
        hotkeyManager.onHotkeyDown = { [weak self] in
            Task { @MainActor in self?.startRecording() }
        }
        hotkeyManager.onHotkeyUp = { [weak self] in
            Task { @MainActor in self?.stopAndProcess() }
        }
        hotkeyManager.start()

        // Observe speech transcription changes
        speechManager.$transcription.assign(to: &$lastTranscription)
        speechManager.$isRecording.assign(to: &$isRecording)
    }

    private func startRecording() {
        floatingWindow.showNearCursor()
        floatingWindow.updateContent(text: "", isProcessing: false)
        speechManager.startRecording()
    }

    private func stopAndProcess() {
        let rawText = speechManager.stopRecording()
        guard !rawText.isEmpty else {
            floatingWindow.orderOut(nil)
            return
        }

        floatingWindow.updateContent(text: rawText, isProcessing: true)

        Task {
            let result = await formatter.format(rawText, mode: selectedMode)
            floatingWindow.updateContent(text: result.cleaned, isProcessing: false)
            textInjector.inject(result.cleaned)

            try? await Task.sleep(nanoseconds: 1_000_000_000) // Show result for 1s
            floatingWindow.orderOut(nil)
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
```

- [ ] **Step 8: Write SettingsView**

```swift
// voicetyping/mac/VoiceTypingMac/SettingsView.swift
import SwiftUI

struct SettingsView: View {

    @State private var selectedMode = Settings.shared.selectedMode
    @State private var customAPIKey = Settings.shared.customAPIKey ?? ""

    var body: some View {
        Form {
            Section("デフォルトモード") {
                Picker("モード", selection: $selectedMode) {
                    ForEach(OutputMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .onChange(of: selectedMode) { _, newValue in
                    Settings.shared.selectedMode = newValue
                }
            }

            Section("API設定（オプション）") {
                TextField("Gemini API Key（空欄でプロキシ使用）", text: $customAPIKey)
                    .onChange(of: customAPIKey) { _, newValue in
                        Settings.shared.customAPIKey = newValue.isEmpty ? nil : newValue
                    }
            }

            Section("ショートカット") {
                Text("Right Option キーを長押しで録音")
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
```

- [ ] **Step 9: Write project.yml for XcodeGen**

```yaml
# voicetyping/mac/project.yml
name: VoiceTypingMac
options:
  bundleIdPrefix: com.voicetyping
  deploymentTarget:
    macOS: "13.0"

settings:
  SWIFT_VERSION: "5.9"
  DEVELOPMENT_TEAM: ""

targets:
  VoiceTypingMac:
    type: application
    platform: macOS
    sources:
      - VoiceTypingMac
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.voicetyping.mac
      INFOPLIST_FILE: VoiceTypingMac/Info.plist
    entitlements:
      path: VoiceTypingMac/VoiceTypingMac.entitlements
```

- [ ] **Step 10: Write Info.plist and entitlements**

```xml
<!-- voicetyping/mac/VoiceTypingMac/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>VoiceTyping uses your microphone for voice input.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>VoiceTyping uses speech recognition to convert your voice to text.</string>
</dict>
</plist>
```

```xml
<!-- voicetyping/mac/VoiceTypingMac/VoiceTypingMac.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 11: Generate Xcode project**

```bash
cd voicetyping/mac && xcodegen generate
```

- [ ] **Step 12: Commit**

```bash
git add voicetyping/mac/
git commit -m "feat: add macOS menu bar app with global hotkey and floating window"
```

---

## Phase 5: Integration Testing & Polish

### Task 12: End-to-End Verification

- [ ] **Step 1: Test Firebase function locally**

```bash
cd voicetyping/firebase && npm run serve
# In another terminal:
curl -X POST http://localhost:5001/voicetyping-prod/asia-northeast1/formatText \
  -H "Content-Type: application/json" \
  -d '{"text":"えーっと、あの、明日のミーティングなんだけど","mode":"casual","deviceId":"test"}'
```

Expected: `{"result":"明日のミーティングなんだけど"}` (or similar cleaned text)

- [ ] **Step 2: Build and run iOS on simulator**

```bash
cd voicetyping/ios && xcodebuild -scheme VoiceTyping -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected: Build succeeds.

- [ ] **Step 3: Build Android project**

```bash
cd voicetyping/android && ./gradlew assembleDebug
```

Expected: APK generated in `app/build/outputs/apk/debug/`.

- [ ] **Step 4: Build Mac app**

```bash
cd voicetyping/mac && xcodebuild -scheme VoiceTypingMac build
```

Expected: Build succeeds.

- [ ] **Step 5: Commit any fixes**

```bash
git add -A && git commit -m "fix: resolve build issues across all platforms"
```

---

### Task 13: Deploy Firebase Function

- [ ] **Step 1: Set Gemini API key**

```bash
cd voicetyping/firebase
firebase functions:secrets:set GEMINI_API_KEY
# Enter your Gemini API key when prompted
```

- [ ] **Step 2: Deploy**

```bash
firebase deploy --only functions
```

Expected: Function deployed to `https://asia-northeast1-voicetyping-prod.cloudfunctions.net/formatText`

- [ ] **Step 3: Verify production endpoint**

```bash
curl -X POST https://asia-northeast1-voicetyping-prod.cloudfunctions.net/formatText \
  -H "Content-Type: application/json" \
  -d '{"text":"um so like the meeting is tomorrow","mode":"casual","deviceId":"test"}'
```

Expected: `{"result":"the meeting is tomorrow"}` (or similar)

- [ ] **Step 4: Commit firebase config**

```bash
git add voicetyping/firebase/.firebaserc voicetyping/firebase/firebase.json
git commit -m "chore: add Firebase deployment config"
```
