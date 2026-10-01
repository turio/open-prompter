# Repository guide for coding agents

Open Prompter is an iOS 17+ SwiftUI teleprompter with local Markdown scripts, on-device speech following, and AVFoundation recording. `OpenPrompter/App/OpenPrompterApp.swift` creates `AppState`, the SwiftData recents cache, and `RootView` navigation. XcodeGen generates the Xcode project from `project.yml`.

## Map and execution

| Path | Role |
| --- | --- |
| `OpenPrompter/App` | App entry, permissions, navigation, shared camera/recording/voice owners |
| `OpenPrompter/Features/Prompter` | `TeleprompterView`, measured block geometry, `PrompterViewModel`, frame-driven `AutoScroller` |
| `OpenPrompter/Features/Camera` | `CameraStore` owns capture session; UIKit preview layer; format and orientation policy |
| `OpenPrompter/Features/Recording` | Locked writer state, audio session coordination, Photos/script-folder saving, recovery, markers |
| `OpenPrompter/Features/VoiceTracking` | Speech backend seam, `ScriptAligner`, phonetic matching and vocabulary bias |
| `OpenPrompter/Features/Remote` | Keyboard/mouse/media/volume sources feed `RemoteEventBus`; persisted bindings and learn wizard |
| `OpenPrompter/Features/Format` | Availability-gated Foundation Models formatter, streaming controller, undo stash and presets |
| `OpenPrompter/Features/Library`, `Editor`, `Settings`, `Onboarding`, `ReviewPrompt` | Script selection/editing, preferences, first-run flows, review counters |
| `OpenPrompter/Parsing` | swift-markdown visitor, stripping rules, typed blocks and inline styling |
| `OpenPrompter/Sync` | Security-scoped file access, coordinated reads/writes, iCloud metadata watcher |
| `OpenPrompter/Persistence` | UserDefaults/KVS preferences, bookmarks, local SwiftData recents |
| `OpenPrompter/UI`, `Resources` | Theme/fonts/glass controls; bundled scripts, assets and debug audio fixture |
| `OpenPrompterLiveActivity` | Widget extension, shared recording ActivityKit attributes |
| `OpenPrompterTests` | XCTest unit tests and Markdown fixtures |
| `docs`, `logos`, `AppIcon.icon` | Documentation images, brand assets and Icon Composer source |
| `.github/workflows/ci.yml` | Simulator build/test; `project.yml` is authoritative build configuration |

Script flow: folder picker → `BookmarkStore` / `ICloudWatcher` → `ScriptFile` → coordinated read → `MarkdownCleaner` → typed `ParsedScript` → measured prompter blocks. Editor writes through `FileCoordinatorReader`; recents are a cache with CloudKit disabled.

Capture flow: `CameraStore` session → pre-attached video/audio data outputs → `RecordingSession.SampleBufferRouter` → lazy AVAssetWriter → Photos and optional script-folder copy. `AppState` wires the same audio router to `VoiceTracker.feedAudio`; recognized words reach `ScriptAligner`, then the existing block geometry/momentum controller.

## Build and validation

Use macOS with Xcode and XcodeGen (`README.md`, `project.yml`). Run `xcodegen generate` after adding/removing source files. `OpenPrompter.xcodeproj` and derived build output are generated/ignored; do not commit them. Preserve committed signing identifiers; simulator commands use `CODE_SIGNING_ALLOWED=NO`.

```sh
xcodegen generate
xcodebuild build -scheme OpenPrompter -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest' CODE_SIGNING_ALLOWED=NO -skipPackagePluginValidation
xcodebuild test -scheme OpenPrompter -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest' CODE_SIGNING_ALLOWED=NO -skipPackagePluginValidation
```

The CI uses the same build/test pattern with its available simulator. For focused XCTest runs add `-only-testing:OpenPrompterTests/TestClass`. Parsing/autoscroll changes require tests (`CONTRIBUTING.md`). Camera formats, orientation metadata, USB routes and sustained 4K recording need physical-device validation; simulator passing cannot establish these guarantees.

## Critical invariants and change guidance

- Keep camera session configuration on its serial queue and writer state inside `OSAllocatedUnfairLock`. MainActor owns observable UI state. Audio packet ingestion must avoid a MainActor hop per packet.
- Keep `.inputPriority`, dynamic-aspect selection and locked min/max frame durations. The verified 9x16/16x9 mapping and `OrientationPolicy` transform table are hardware-sensitive.
- Writer frames come directly from capture output. SwiftUI prompts, scrims and controls are preview-only.
- Preserve Rec.709 HEVC and 8-bit camera output for SDR. Do not silently downgrade the personal wide recording contract to HD.
- Preserve stored enum raw strings and preference migrations. `fps24` and legacy vertical aspect remain decodable.
- Keep `ScriptAligner` thresholds and existing visible-range/block/momentum semantics when modifying audio transport.
- Shared AVAudioSession claims belong to `AudioSessionCoordinator`. Stopping speech must not stop recorded audio; stopping recording must not stop speech.
- `PreferredAudioInput` resolves session ports separately from capture IDs: exact UID, then a unique exact active-route name bridge. A saved pin alone never establishes the current source. `AudioRouteMonitor` and `CaptureStatusModifier` show actual routing and retain take-change warnings.
- `SFSpeechBackend` takes externally supplied sample buffers under a lock; live SF owns no `AVAudioEngine`. `SpeechAnalyzerBackend` stays compiled but disabled until shared-buffer ingestion is implemented, including when an old analyzer preference is persisted.
- Fresh installs use `.wide`, High, 30 fps, with 30/60 surfaced. Existing explicit aspects and the historical open-gate migration are preserved. `PersonalCaptureContract` checks 4K eligibility and actual transformed first-frame presentation; unsupported takes fail closed.
- Camera preference refresh occurs before a take only when capture preferences/current route changed. Do not add a session configuration bracket to an unchanged REC transition.
- No analytics or additional network/services/dependencies without an explicit request. The formatter and recognizer operate on device.

For capture changes start in `CameraStore`, `RecordingSession`, and their pure selector/orientation tests. For following behavior inspect `VoiceTracker`, `SpeechBackend`, `ScriptAligner` and `TeleprompterView`. Preference additions require `PrefKey`, defaults/migrations and KVS mirroring review. Remote input changes start at the source adapter and `RemoteBindingStore`.

## Implementation recovery

The personal capture source plan is `docs/personal-4k-dji-implementation-plan.md`. Use AmnesiaGraph `amnesia resume` and follow its source pointers; use `ready`, `start`, and verified `done` transitions. Hardware acceptance results belong in implementation notes, not assertions inferred from simulator tests.

If `amnesia` is unavailable, the upstream CLI installs with `go install github.com/turio/AmnesiaGraph/cmd/amnesia@latest`; ensure the Go bin directory is on PATH. This implementation used a temporary CLI at `/tmp/amnesia` without editing personal skills or configuration.
