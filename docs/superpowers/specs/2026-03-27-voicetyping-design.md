# VoiceTyping — Design Spec

**Date:** 2026-03-27
**Author:** Claude Code (for nobu / POST CABINETS)
**Status:** Approved

## 1. Overview

VoiceTyping is a free, cross-platform voice input application that converts spoken language into clean, well-formatted text. It replaces Typeless ($12/mo) and Genspark Speakly ($25/mo+) with a zero-cost alternative.

### Target Platforms (Phase 1)
- **Mac** — Native app with global hotkey (system-wide voice input)
- **iOS** — Custom keyboard extension (works in all apps)
- **Android** — Custom IME keyboard (works in all apps)

### Core Value Proposition
- **Free** — OS-native STT + Gemini Flash free tier (no API cost)
- **Never cuts off** — Unlike Gboard, recording continues until user stops it
- **Smart cleanup** — LLM removes fillers, fixes grammar, formats output
- **Works everywhere** — System keyboard on mobile, global hotkey on Mac

## 2. Architecture

### 2.1 Pipeline

```
[Microphone] → [STT Engine] → [Raw Text] → [LLM Formatter] → [Clean Text] → [Output]
```

### 2.2 Technology Stack

| Layer | Mac | iOS | Android |
|-------|-----|-----|---------|
| **UI Framework** | SwiftUI + AppKit | SwiftUI (Keyboard Extension) | Kotlin + Jetpack Compose (IME) |
| **STT Engine** | Apple Speech Framework | Apple Speech Framework | Android SpeechRecognizer |
| **LLM Formatter** | Gemini Flash API (free) | Gemini Flash API (free) | Gemini Flash API (free) |
| **Fallback Formatter** | Regex-based cleanup | Regex-based cleanup | Regex-based cleanup |
| **Local LLM (optional)** | mlx-community models | Core ML (future) | ONNX Runtime (future) |
| **Networking** | URLSession | URLSession | OkHttp/Ktor |
| **Storage** | UserDefaults + SQLite | App Group shared storage | SharedPreferences + Room |

### 2.3 STT Strategy

**Primary: OS-native Speech APIs (free, no API key needed)**

- **Apple Speech Framework** (iOS/Mac): On-device recognition available for 60+ languages. Continuous recognition mode with no auto-cutoff when configured correctly.
- **Android SpeechRecognizer**: Google's on-device speech recognition. Use `EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS` set to max value to prevent auto-cutoff.

**Why not Whisper locally?**
- Phone CPUs can't run Whisper at real-time speed reliably
- OS APIs are already optimized, free, and high-quality
- No model download required (saves 500MB+ per device)

### 2.4 LLM Formatter Strategy

**Primary: Gemini 2.0 Flash (free tier)**

- 15 requests/minute, 1 million tokens/day — more than enough for voice input
- No API key required for users (app bundles a project key via Firebase proxy)
- Latency: ~200-500ms per request (acceptable for post-recording cleanup)

**Fallback: Local regex-based cleanup**
- When offline or rate-limited
- Handles: filler removal (えー, あの, um, uh), basic punctuation, whitespace normalization

**Optional: User-provided API keys**
- Settings screen allows BYOK for: OpenAI, Anthropic, Gemini, local Ollama endpoint
- Power users can point to their own LLM for max privacy

### 2.5 API Proxy Architecture

```
[App] → [Firebase Cloud Function (rate limiter)] → [Gemini Flash API]
```

- Firebase function acts as thin proxy to protect the API key
- Per-device rate limiting (prevent abuse)
- No user data stored — pass-through only
- Fallback: direct API call with user's own key

## 3. Core Features

### 3.1 Voice Input (MVP)

| Feature | Description |
|---------|-------------|
| **Persistent recording** | Recording continues during silence. User explicitly taps to stop. No auto-cutoff. |
| **Filler removal** | Removes「えー」「あの」「うーん」「um」「uh」「you know」 |
| **Self-correction** | 「明日、いや明後日」→「明後日」 |
| **Auto punctuation** | Inserts 。、.!, based on speech patterns |
| **Grammar cleanup** | Spoken language → written language |
| **Multi-language** | Auto-detect language. Japanese-English mixing supported. |

### 3.2 Output Modes

| Mode | Behavior | Example |
|------|----------|---------|
| **Casual** | Light cleanup, keep conversational tone | Chat, LINE, SNS |
| **Business** | Formal tone, proper keigo | Email, documents |
| **Technical** | Clear instruction language | Vibe coding prompts, specs |
| **Raw** | No LLM processing, just STT output | When user wants exact words |

Mode selection: Auto-detect from context + manual toggle in keyboard UI.

### 3.3 Keyboard Features (iOS/Android)

- Full standard keyboard (QWERTY/flick) with integrated mic button
- Mic button: single tap to start, single tap to stop
- Real-time transcription preview while speaking
- Before/after toggle (see raw vs. cleaned text)
- Mode selector (casual/business/technical/raw)
- Haptic feedback on recording start/stop

### 3.4 Mac App Features

- Menu bar app (always running, minimal footprint)
- Global hotkey (default: Right Option) — hold or toggle to record
- Floating transcription window near cursor
- Output: paste into active text field via clipboard or accessibility API
- Settings: hotkey customization, LLM provider selection, language preferences

## 4. UX Flow

### 4.1 Mobile (Primary)

```
┌─────────────────────────────┐
│  [Any App - text field]     │
│                             │
│  ┌───────────────────────┐  │
│  │ VoiceTyping Keyboard  │  │
│  │                       │  │
│  │  [Real-time preview]  │  │
│  │  "明後日の会議..."     │  │
│  │                       │  │
│  │  [q][w][e][r][t][y].. │  │
│  │  [a][s][d][f][g][h].. │  │
│  │  [z][x][c][v][b][n].. │  │
│  │  [🌐][  space  ][🎤]  │  │
│  └───────────────────────┘  │
└─────────────────────────────┘

Flow:
1. User taps 🎤 → button turns red, recording starts
2. User speaks (can pause, think, continue — no timeout)
3. Real-time STT text appears in preview area
4. User taps 🎤 again → recording stops
5. LLM processes text (~300ms)
6. Clean text replaces raw text in preview
7. User taps preview or hits send → text inserted into app
```

### 4.2 Mac

```
Flow:
1. User holds Right Option (or configured hotkey)
2. Small floating window appears near cursor
3. User speaks → real-time transcription in window
4. User releases key → LLM cleanup
5. Clean text auto-pasted into active field
```

## 5. Data Flow & Privacy

### 5.1 Data Flow

```
Audio (mic) → OS Speech API (on-device) → Raw text
                                            ↓
                                     Gemini Flash API
                                     (via Firebase proxy)
                                            ↓
                                      Clean text → UI
```

### 5.2 Privacy Guarantees

- **Audio never leaves device** — STT is 100% on-device via OS APIs
- **Text sent to LLM** — only the raw transcription, no metadata
- **Zero data retention** — Firebase proxy is pass-through, no logging
- **No analytics** — no tracking, no telemetry in v1
- **User's own key** — optional BYOK mode for full control

## 6. LLM Prompt Design

### 6.1 System Prompt (Formatter)

```
You are a voice-to-text formatter. Your job is to clean up speech transcriptions.

Rules:
1. Remove filler words (えー, あの, うーん, um, uh, like, you know)
2. Detect self-corrections: keep only the final version
   Example: "明日、いや明後日" → "明後日"
3. Add proper punctuation (。、！？ for Japanese; .,!? for English)
4. Convert spoken grammar to written grammar
5. Preserve the speaker's meaning exactly — do NOT add content
6. Keep the same language as input
7. If mixed languages, preserve the mixing naturally

Mode: {casual|business|technical}
- casual: light cleanup, keep conversational
- business: formal, polite (敬語 for Japanese)
- technical: clear, precise instruction language

Output ONLY the cleaned text. No explanations.
```

### 6.2 Example Transformations

**Input (casual):**
「えっとあのさ、明日のミーティングなんだけど、あ、いや明後日だった、明後日の3時からでいい？」

**Output (casual):**
「明後日の3時からのミーティングでいい？」

**Output (business):**
「明後日の15時からのミーティングでよろしいでしょうか。」

**Input (technical/vibe coding):**
「えっとログイン画面にさ、パスワード忘れたっていうリンク追加してほしくて、あのそれ押したらメール入力画面に飛ぶみたいな」

**Output (technical):**
「ログイン画面に『パスワードを忘れた方はこちら』リンクを追加。タップするとメールアドレス入力画面に遷移する。」

## 7. Error Handling

| Scenario | Handling |
|----------|----------|
| **Microphone permission denied** | Clear prompt to enable in Settings, deep link |
| **STT unavailable** | Show message, suggest language download |
| **LLM rate limited** | Fall back to regex cleanup, notify user |
| **Network offline** | STT still works (on-device). Regex cleanup only. Badge shows "offline mode" |
| **LLM response slow (>2s)** | Show spinner, allow cancel, user can send raw text |
| **Empty transcription** | Ignore, don't send to LLM |

## 8. Project Structure

```
voicetyping/
├── shared/                    # Shared logic (Kotlin Multiplatform or Swift Package)
│   ├── LLMFormatter.swift/.kt  # LLM API calls + prompt
│   ├── RegexCleanup.swift/.kt  # Offline fallback
│   ├── Settings.swift/.kt      # User preferences
│   └── Models.swift/.kt        # Data models
│
├── mac/                       # macOS app
│   ├── VoiceTypingApp.swift     # Menu bar app entry
│   ├── HotkeyManager.swift     # Global hotkey handling
│   ├── FloatingWindow.swift    # Transcription overlay
│   ├── AudioRecorder.swift     # Speech recognition
│   └── TextInjector.swift      # Paste into active field
│
├── ios/                       # iOS keyboard extension
│   ├── KeyboardViewController.swift
│   ├── KeyboardView.swift       # SwiftUI keyboard layout
│   ├── SpeechManager.swift     # Speech recognition
│   └── Info.plist              # Keyboard extension config
│
├── android/                   # Android IME
│   ├── VoiceTypingIME.kt        # InputMethodService
│   ├── KeyboardView.kt         # Compose keyboard layout
│   ├── SpeechManager.kt        # SpeechRecognizer wrapper
│   └── AndroidManifest.xml
│
├── firebase/                  # API proxy
│   └── functions/
│       └── index.ts            # Gemini proxy function
│
└── docs/
    └── design.md              # This document
```

## 9. Build & Ship Strategy

### Phase 1: iOS Keyboard (Week 1-2)
- Custom keyboard extension with mic button
- Apple Speech Framework integration
- Gemini Flash formatter
- Basic UI (keyboard + preview + mode toggle)
- TestFlight release

### Phase 2: Android IME (Week 2-3)
- Kotlin IME with same feature set
- Android SpeechRecognizer integration
- Same Gemini formatter (shared prompt)
- Internal testing APK

### Phase 3: Mac App (Week 3-4)
- Menu bar app
- Global hotkey
- Floating window
- Accessibility API text injection

### Phase 4: Polish & Launch (Week 4-5)
- App Store / Google Play submission
- Landing page
- Settings UI (BYOK, mode defaults, language)
- Performance optimization

## 10. Success Criteria

- [ ] Voice input works in any app on all 3 platforms
- [ ] Silence does NOT auto-terminate recording
- [ ] Filler words reliably removed (Japanese + English)
- [ ] Self-corrections properly resolved
- [ ] Output mode switching works (casual/business/technical)
- [ ] Zero cost for normal daily usage
- [ ] Cold start to first input < 2 seconds
- [ ] LLM cleanup latency < 500ms average

## 11. Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Gemini free tier rate limit hit | Regex fallback + BYOK option |
| Apple rejects custom keyboard | Follow App Review Guidelines strictly, no network in keyboard (use app group for API) |
| Android speech auto-cutoff | Override silence timeout parameters, use continuous recognition mode |
| Privacy concerns (text to cloud) | Clear privacy policy, BYOK option, on-device-only mode |

## 12. Future Enhancements (Post-MVP)

- Voice commands on selected text ("translate this", "summarize")
- Custom vocabulary/jargon learning
- Conversation history for context-aware formatting
- Widget for quick voice notes
- Apple Watch / Wear OS companion
- Local LLM option (mlx on Mac, Core ML on iOS)
