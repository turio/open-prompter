# Personal capture implementation handoff

Implemented and deployed to the iPhone 17 Pro Max simulator on October 1, 2026. Hardware acceptance remains unverified; the simulator delivery requested in this chat is complete.

- Fork: https://github.com/turio/open-prompter
- Branch: `personal-4k-dji-voice-follow`
- Upstream base: `894ae79c9ce8cbf47f6d046cf9f109d3201d17d1`
- Final revision: use `git rev-parse HEAD` (also reported in the chat).
- `upstream` remote tracks https://github.com/lelanddutcher/open-prompter.git.
- Generated Xcode project and signing settings were not committed.

## Implementation

Wide recording now defaults to 4K SDR at 30 fps, with 30/60 visible and 24 still decodable. Format selection excludes sub-4K wide candidates; preflight checks actual selected fps, locked frame durations and SDR. The first captured frame must produce a 4K wide presentation after the existing writer transform or the take fails. HEVC Rec.709 settings and High bitrate (50 Mbps / 75 Mbps) remain unchanged.

Microphone selection resolves AVAudioSession ports before selecting the capture input. Capture IDs are resolved by exact UID or a unique exact active-route name. An explicit missing/mismatched selection blocks REC with instructions to reconnect or choose Built-in Microphone. The screen displays the actual current route and retains a warning when a take changes inputs. Camera preferences are refreshed before REC only if settings or the active route changed.

`AppState`'s existing `audioFork` sends the same capture samples to `VoiceTracker.feedAudio`, which forwards to the active backend through a lock. `SFSpeechBackend` appends those CMSampleBuffers directly to its on-device recognition request; it has no AVAudioEngine or input tap. Start/stop and packet ingestion are serialized. Voice start installs the persistent router before rehearsal and reports setup/no-packet failures. The analyzer source is retained but its live start is disabled, even if an old preference is enabled. The analyzer's dormant engine code must not be re-enabled until shared-buffer ingestion exists.

`ScriptAligner.swift`, phonetic thresholds, visible-range policy and momentum algorithm were not edited. The behind preview is a SwiftUI background layer beneath scrolling text, with a localized 45% dark reading band and semibold/shadow treatment. Layout and visible-range calculations share the raised top padding. Controls and scrim never enter the asset writer. Camera cycle is off → behind → pip → off.

## Automated validation

Unmodified baseline built and passed its test suite before implementation.

```sh
xcodegen generate
xcodebuild test -quiet -scheme OpenPrompter -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest' -derivedDataPath /tmp/myteleprompter-build CODE_SIGNING_ALLOWED=NO -skipPackagePluginValidation
```

Final result: **647 passed, 0 failed, 0 skipped** on iPhone 17 Pro Max / iOS 26.4.1 simulator, Xcode 26.4.1. Result bundle: `/tmp/myteleprompter-build/Logs/Test/Test-OpenPrompter-2026.10.01_16-44-55--0400.xcresult`.

Targeted tests: `PersonalCaptureTests`, `PersonalAudioRouteTests`, `SharedSpeechAudioTests`, plus the unchanged `ScriptAlignerTests`. The shared-audio fixture is a valid 48 kHz mono PCM CMSampleBuffer, delivered from a background task. Legacy default tests now distinguish fresh wide defaults from preserved existing open-gate migration. Camera's suppressed test mode no longer reads real simulator authorization.

Compiler emits upstream deprecation and Swift-6-concurrency warnings under the existing Swift 5.10/minimal strict-concurrency configuration. No warning cleanup or concurrency migration was attempted.

## Simulator deployment

Installed the generated Debug app via `xcrun simctl install`, launched `app.openprompter.ios -autoDemo 1`, and exercised native camera/microphone/speech permission dialogs. Clean-installed after testing so test-written preferences do not become the user's initial simulator settings. Simulator cannot supply the target front sensor or a DJI USB route.

## Physical acceptance

| Test | Result | Missing evidence |
| --- | --- | --- |
| A — 60 seconds 4K30 SDR | Not run | File dimensions after transform, fps, HEVC/Rec.709 metadata, orientation, no overlay |
| B — 60 seconds 4K60 SDR | Not run | Same metadata plus sustained true 60 fps |
| C — DJI recording | Not run | Actual route name/type/UID, acoustic proof, audio sync |
| D — DJI rehearsal before REC | Not run | Live USB buffers reach recognizer and follow the script |
| E — simultaneous two-minute take | Not run | Start/stop continuity and pause/repeat/skip recovery |
| F — receiver disconnect | Not run | Valid continued take and persistent actual-input warning |
| G — 10-minute 30 / 5-minute 60 | Not run | Thermal, writer, sync and recognition stability |

Observed 4K30/4K60 file metadata: **none**, because no device recording was made. Observed DJI name/type/UID: **none**, because no DJI receiver was attached. No physical success claim is made.

Next acceptance procedure: connect the iPhone 17 Pro Max and DJI Mic Mini USB receiver, configure local signing without committing team changes, select/pin the receiver in Camera & Recording, confirm the actual route, then perform plan Tests A–G. Cross-API audio identities and dynamic-aspect dimensions must be confirmed on that pair. If IDs and exact names both differ, REC intentionally refuses the unverifiable route; collect DEBUG `[AudioRoute]` identities before implementing a narrowly scoped bridge.

AmnesiaGraph `personal-capture`: T001–T006 verified complete; T007 blocked on hardware acceptance. Run `amnesia resume` to recover. No personal skills, agents or Codex settings were modified.

## Changed files

- `.amnesiagraph/current`
- `.amnesiagraph/graphs/personal-capture.json`
- `AGENTS.md`
- `OpenPrompter/Features/Camera/CameraStore.swift`
- `OpenPrompter/Features/Camera/CameraStyle.swift`
- `OpenPrompter/Features/Prompter/TeleprompterView.swift`
- `OpenPrompter/Features/Recording/AudioRouteMonitor.swift`
- `OpenPrompter/Features/Recording/AudioSessionCoordinator.swift`
- `OpenPrompter/Features/Recording/CaptureStatusModifier.swift`
- `OpenPrompter/Features/Recording/PersonalCaptureContract.swift`
- `OpenPrompter/Features/Recording/PreferredAudioInput.swift`
- `OpenPrompter/Features/Recording/RecordingAspect.swift`
- `OpenPrompter/Features/Recording/RecordingFramerate.swift`
- `OpenPrompter/Features/Recording/RecordingSession.swift`
- `OpenPrompter/Features/Recording/RecordingSettingsView.swift`
- `OpenPrompter/Features/Settings/LabsSettingsView.swift`
- `OpenPrompter/Features/VoiceTracking/SpeechAnalyzerBackend.swift`
- `OpenPrompter/Features/VoiceTracking/SpeechBackend.swift`
- `OpenPrompter/Features/VoiceTracking/VoiceTracker.swift`
- `OpenPrompter/Persistence/Prefs.swift`
- `OpenPrompterTests/CameraTests.swift`
- `OpenPrompterTests/HotfixDefaultsTests.swift`
- `OpenPrompterTests/PersonalAudioRouteTests.swift`
- `OpenPrompterTests/PersonalCaptureTests.swift`
- `OpenPrompterTests/RecordingAspectTests.swift`
- `OpenPrompterTests/SharedSpeechAudioTests.swift`
- `docs/baseline.md`
- `docs/personal-4k-dji-implementation-plan.md`
- `docs/personal-capture.graph.json`
- `docs/implementation-notes.md`
