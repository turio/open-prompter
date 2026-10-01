# Open Prompter Personal Fork — 4K SDR + DJI Mic + Voice-Follow Implementation Plan

## Objective

Fork `lelanddutcher/open-prompter` and turn it into a focused personal iPhone teleprompter for an **iPhone 17 Pro Max** with these guarantees:

- front camera recording at **4K SDR**
- selectable **30 fps** and **60 fps**
- **no HDR / Dolby Vision**
- teleprompter text visibly overlaid on the live front-camera preview while recording, but **never burned into the recorded video**
- highly legible teleprompter presentation suitable for direct-to-camera delivery
- **DJI Mic Mini USB receiver** is the preferred recording microphone
- the **same captured DJI audio buffers** drive both the recorded audio track and speech recognition
- voice-follow scrolling tracks the reader's position in the supplied script rather than using fixed-speed scrolling
- preserve the existing `ScriptAligner` behavior rather than replacing it
- save the resulting recording through the existing recording/save pipeline

This is a **surgical fork of the existing app**, not a new app architecture and not a scaffold/rewrite exercise.

Upstream:

- Repository: `https://github.com/lelanddutcher/open-prompter`
- Default branch: `main`
- License: MIT
- Build system: XcodeGen (`xcodegen generate` produces `OpenPrompter.xcodeproj`)
- Current deployment floor: iOS 17+

---

## Non-goals

Do **not** do any of the following unless required to fix a concrete bug discovered during device validation:

- do not create a second iOS app target
- do not rewrite the app in another framework
- do not replace SwiftUI or AVFoundation
- do not introduce React Native, Flutter, Electron, web views, or a server
- do not add HDR, Dolby Vision, Log, ProRes, LUTs, grading, or cinematic capture
- do not add cloud speech recognition
- do not replace `ScriptAligner` with an LLM
- do not add Whisper/WhisperKit in the first implementation
- do not redesign the library/editor/remote-control parts of the app
- do not refactor unrelated upstream code “for cleanliness”
- do not burn teleprompter text, UI, read guides, controls, or camera chrome into the saved video
- do not silently lower a requested 4K take to 1080p
- do not silently record from an unexpected microphone when the app believes DJI is selected
- do not create a second independent microphone capture path for speech recognition

The goal is the smallest reliable patch that produces the requested recording experience on the iPhone 17 Pro Max.

---

# 1. Fork, branch, build, and establish a baseline

Fork and clone upstream rather than copying the repository contents into a new project.

```bash
gh repo fork lelanddutcher/open-prompter --clone --remote
cd open-prompter
git checkout -b personal-4k-dji-voice-follow
```

Record the upstream commit SHA before modifying anything:

```bash
git rev-parse HEAD
```

Install XcodeGen if required, then generate the project exactly as upstream expects:

```bash
brew install xcodegen
xcodegen generate
open OpenPrompter.xcodeproj
```

Before changing code:

1. Build the unmodified fork.
2. Run the existing test suite.
3. Run the app on the physical iPhone 17 Pro Max if signing is already configured.
4. Verify that the upstream app can open the front camera, start a recording, and invoke voice-follow.
5. Capture any existing upstream failure separately; do not attribute a pre-existing failure to this patch.

Do not commit the generated `.xcodeproj`; upstream intentionally gitignores it.

Use the existing app target and bundle structure. Do not change signing/team identifiers in committed source just to make the personal device build work; local signing configuration is acceptable.

---

# 2. Preserve the parts of upstream that already solve the hard problems

The following upstream components are valuable and should remain the source of truth unless a device test proves a defect:

### Camera/recording

- `OpenPrompter/Features/Camera/CameraStore.swift`
- `OpenPrompter/Features/Recording/RecordingSession.swift`
- `OpenPrompter/Features/Recording/RecordingFramerate.swift`
- `OpenPrompter/Features/Recording/RecordingQuality.swift`
- `OpenPrompter/Features/Recording/RecordingAspect.swift`
- `OpenPrompter/Features/Camera/OrientationPolicy.swift`

Keep the existing `AVCaptureSession -> AVCaptureVideoDataOutput / AVCaptureAudioDataOutput -> AVAssetWriter` design.

Keep the iPhone 17 / iOS 26 format-selection and orientation work already present in `CameraStore` and `RecordingSession`. Do not replace it with a generic `.high` session preset.

### Voice-follow

Preserve:

- `OpenPrompter/Features/VoiceTracking/VoiceTracker.swift`
- `OpenPrompter/Features/VoiceTracking/ScriptAligner.swift`
- `OpenPrompter/Features/VoiceTracking/PhoneticEncoder.swift`
- `OpenPrompter/Features/VoiceTracking/ScriptBiasVocabulary.swift`
- the existing visible-range constraint
- block-aware cursor positioning
- the existing scroll momentum / pause behavior in `TeleprompterView`

The existing script tracker already has the desired semantics: recognized speech is aligned against nearby script words with word-level edit distance, phonetic assistance, locality preference, forward bias, visible-range protection, and widening after a tracking loss. Do not simplify this into “advance one line whenever speech is detected.”

### Shared audio hook already present

`AppState` currently wires:

```text
RecordingSession.audioFork -> VoiceTracker.feedAudio(sampleBuffer)
```

`RecordingSession.SampleBufferRouter` already sends audio to `audioFork` before it sends the sample to the writer path.

This is the architecture to restore as the live speech input. The current newer speech backends open their own `AVAudioEngine`; remove that duplication for this fork.

---

# 3. Make 4K SDR 30 fps / 60 fps the personal capture contract

## 3.1 SDR is mandatory

Do not add HDR.

Keep the saved video on the current SDR path:

- HEVC
- Rec.709 primaries
- Rec.709 transfer function
- Rec.709 YCbCr matrix
- no Dolby Vision metadata
- no HDR10 / HLG color configuration

`RecordingSession.swift` already explicitly supplies Rec.709 writer color properties. Preserve that behavior.

The current camera output uses `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange`; that is appropriate for this SDR fork. Do not change it to a 10-bit HDR pixel format.

## 3.2 Only surface 30 fps and 60 fps for this personal workflow

`RecordingFramerate.swift` currently defines 24/30/60.

Do not necessarily delete `.fps24`, because removing a persisted enum case can create migration problems. Instead:

- leave `.fps24` supported internally for compatibility
- make **30 fps** the default
- surface only **30 fps** and **60 fps** in the recording UI for this fork

Modify the picker source in `RecordingSettingsView.swift` so the visible choices are exactly 30 and 60.

Do not implement 60 fps by frame duplication. It must be a camera format whose `videoSupportedFrameRateRanges` includes 60 and must retain the existing device lock using:

```text
activeVideoMinFrameDuration
activeVideoMaxFrameDuration
```

## 3.3 Require 4K rather than silently degrading

For the intended **vertical 9:16 recording mode** on the iPhone 17 Pro Max, the final presentation resolution must be 4K-class: **2160 x 3840** portrait presentation, allowing the encoded/raw track to use the inverse landscape dimensions plus orientation metadata if that is how the existing verified writer path represents it.

Important: judge the final presentation dimensions after the track's preferred transform, not only the raw pixel-buffer orientation.

Patch the format-selection / recording-preflight path so that for the personal `wide`/vertical recording mode:

1. Enumerate front-camera formats exactly as the current `CameraStore` does.
2. Filter to formats supporting the selected 30 or 60 fps.
3. Prefer the existing iPhone-17 dynamic-aspect route that produces the vertical 4K shape.
4. Confirm that the resulting capture/output is at least 3840 x 2160 in pixel count and produces a 2160 x 3840 presentation for portrait recording.
5. If the selected fps cannot produce 4K on the active front camera, **surface a clear error and refuse to start that take** rather than silently dropping to 1080p.

Keep open-gate support if it already works; it is not the default requirement. Do not destabilize it merely to implement the 9:16 personal path.

## 3.4 Add a lightweight capture preflight

Before REC transitions into recording on the target device, resolve and retain a small diagnostic snapshot:

- selected camera device name / unique ID
- selected format raw dimensions
- selected fps
- requested aspect
- current/pending presentation orientation
- current SDR color configuration
- selected/current microphone label

In DEBUG builds, log this snapshot. In the user-facing UI, only surface a compact status such as:

```text
4K · 30
DJI Mic Mini
```

or

```text
4K · 60
DJI Mic Mini
```

Do not add a complex diagnostics screen to the normal workflow.

---

# 4. Keep the current HEVC quality model initially

Do not increase bitrate just because “higher is better.” The target is a reliable front-camera talking-head recorder, and 4K60 is already the dominant load.

Keep the existing `RecordingQuality.high` values for the first device pass:

- approximately 50 Mbps base at 30 fps
- approximately 75 Mbps at 60 fps via the existing 1.5x multiplier

Keep `High` as the personal default.

Only raise bitrate after reviewing actual iPhone 17 Pro Max samples for visible blocking/banding. A bitrate increase is a separate tuning change and must not be mixed into the initial audio/voice-routing patch.

---

# 5. Make the DJI Mic Mini the explicit preferred recording input

Relevant existing files:

- `OpenPrompter/Features/Recording/AudioRouteMonitor.swift`
- `OpenPrompter/Features/Recording/RecordingSettingsView.swift`
- `OpenPrompter/Features/Camera/CameraStore.swift`
- `OpenPrompter/Features/Recording/AudioSessionCoordinator.swift`

The upstream UI already enumerates available audio inputs and identifies USB audio. Retain this rather than building a DJI-specific SDK integration. The DJI receiver should behave as a USB audio input.

## 5.1 Preferred-input behavior

When the DJI USB receiver is attached:

- show it in the existing microphone picker
- allow the user to pin it
- persist that preference
- show the **actual current input route** independently of the preferred selection

Never treat the saved preference itself as proof that the current route is DJI.

## 5.2 Reconcile the two audio identity APIs

The current code stores an `AVAudioSession` input UID in the picker but `CameraStore.preferredAudioDevice()` searches `AVCaptureDevice` audio devices by `uniqueID`. Do not assume those IDs are always interchangeable.

Make the resolution explicit and testable:

1. Resolve the saved preferred `AVAudioSessionPortDescription` from `AVAudioSession.availableInputs`.
2. Call `setPreferredInput(...)` on the shared `AVAudioSession` before/while activating the capture configuration.
3. Resolve the actual `AVCaptureDevice` used for the audio input.
4. Verify that the resulting current route/device corresponds to the intended port.
5. If exact UID matching across the two APIs works on the iPhone/DJI pair, keep it.
6. If the IDs differ, use the active route as the authority and only use a device-name match as a narrowly-scoped bridge, with DEBUG logging showing both IDs/names so this is diagnosable.

Do not add fuzzy vendor heuristics such as “anything containing wireless is DJI.” Matching `DJI` by name may be used only as a convenience default suggestion, never as the final correctness check.

## 5.3 No silent wrong-mic state

At REC time:

- if the user explicitly selected the DJI input and DJI is active, continue
- if DJI was selected but is disconnected before the take, show a clear warning and require an explicit user choice to continue with the built-in mic or reconnect DJI
- if DJI disconnects during a take and iOS reroutes, keep the file alive if AVFoundation can continue, but show a persistent visible warning that the input changed

Do not silently label a take as DJI when it is actually using the built-in microphone.

The normal personal workflow should make the expected state obvious before REC:

```text
MIC  DJI Mic Mini
```

---

# 6. Use one DJI audio stream for BOTH recording and voice-follow

This is the most important behavior change.

Target flow:

```text
DJI Mic Mini USB receiver
        |
        v
AVCapture audio input
        |
        v
AVCaptureAudioDataOutput
        |
        +--------------------> RecordingSession / AVAssetWriter audio track
        |
        +--------------------> VoiceTracker -> speech recognizer -> ScriptAligner
```

There must not be an independent `AVAudioEngine` microphone tap for live voice-follow in the final personal fork.

## 6.1 Reuse the already-existing sample-buffer fork

The repository already contains:

- `RecordingSession.audioFork`
- `SampleBufferRouter.captureOutput(...)`
- `AppState` wiring the fork to `VoiceTracker.feedAudio(...)`
- `RecordingSession.ensureAudioCaptureRunning(...)`

Keep those pieces.

The current problem is that the newer production speech backend path no longer consumes `VoiceTracker.feedAudio`; instead `SFSpeechBackend` and `SpeechAnalyzerBackend` create their own `AVAudioEngine` taps.

Refactor that seam rather than creating another router.

## 6.2 Make `SpeechBackend` externally-fed

Update `SpeechBackend.swift` so a live backend can receive the camera audio stream.

Add an ingestion method with thread-safe semantics, for example:

```swift
nonisolated func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer)
```

or an equivalent name consistent with the project style.

Requirements:

- callable from `RecordingSession`'s audio queue
- no MainActor hop for every audio packet
- a no-op when the backend is not active
- recognition callbacks still arrive through the current `onWords`, `onTranscription`, `onFinal`, and `onError` plumbing

## 6.3 SFSpeech backend: remove the second mic capture

In the existing `SFSpeechBackend` implementation inside `SpeechBackend.swift`:

Keep:

- `SFSpeechRecognizer`
- `SFSpeechAudioBufferRecognitionRequest`
- `shouldReportPartialResults = true`
- `requiresOnDeviceRecognition = true`
- contextual bias strings
- current recognition-task callback behavior

Remove from the live path:

- the backend-owned `AVAudioEngine`
- `startAudioEngineTap(...)`
- installing/removing an `AVAudioEngine.inputNode` tap

Instead, when `appendAudioSampleBuffer(...)` is called:

```text
recognitionRequest.appendAudioSampleBuffer(sampleBuffer)
```

Use the camera/recording stream as the only audio source.

`start()` should create and arm the recognition request/task, but it should not open a microphone.

The audio session is still coordinated through `AudioSessionCoordinator`; activation can remain idempotent, but microphone sample acquisition belongs to the camera/recording capture path.

## 6.4 VoiceTracker: forward the fork to the active backend

`VoiceTracker.feedAudio(_:)` currently points at a dormant legacy `recognitionRequest` property.

Change it to forward each incoming `CMSampleBuffer` to the currently active externally-fed speech backend.

Continue computing the existing throttled audio-level meter from the same sample buffer.

The resulting behavior should be:

```text
camera audio buffer arrives
 -> VoiceTracker.feedAudio
 -> speechBackend.appendAudioSampleBuffer
 -> recognition partial result
 -> handleRecognizerResult(allWords:)
 -> existing ScriptAligner
 -> existing scroll target/momentum code
```

Do not change the alignment algorithm while making this audio plumbing change.

## 6.5 Ensure audio delivery starts before recording

Voice-follow must work while the user is rehearsing/reading **before REC is pressed**, as long as the camera capture mode is active.

`RecordingSession.ensureAudioCaptureRunning()` already exists for this purpose. Keep it as the mechanism that installs the persistent `AVCaptureAudioDataOutput` delegate and activates the capture audio route.

Adjust the voice-start path in `TeleprompterView.startVoiceOrSurfaceFailure()` so voice activation guarantees that `ensureAudioCaptureRunning(role: .voiceTracking)` is invoked and the persistent router is installed.

Avoid a race where the recognizer is marked active but no audio delegate will ever be installed.

It is acceptable for the recognizer task to be armed slightly before the first audio packet, but failure to establish the shared capture path must produce a user-visible error rather than leaving the voice button apparently active forever.

## 6.6 Recording and voice must coexist

When REC starts while voice-follow is already active:

- do not tear down/recreate the DJI input
- do not open a new audio route
- do not interrupt the recognizer
- keep sending each audio sample to both consumers
- writer audio and recognizer audio must originate from the same `AVCaptureAudioDataOutput`

When recording stops but voice-follow remains enabled:

- the persistent audio router should continue delivering samples for speech tracking
- the writer consumer stops; the voice consumer remains

When voice-follow stops during a recording:

- the recording audio must continue uninterrupted
- only the speech consumer stops

This separation is already conceptually represented by the existing router; preserve that model.

---

# 7. Keep SpeechAnalyzer optional; do not let it expand the first patch

The iOS 26 `SpeechAnalyzerBackend` is useful, but converting externally supplied `CMSampleBuffer` audio into the analyzer's required `AVAudioPCMBuffer` format is more code than the SFSpeech path needs.

For the minimal first delivery:

1. Make the shared-buffer-fed `SFSpeechBackend` the default production voice path.
2. Keep the existing `SpeechAnalyzerBackend.swift` source compiling.
3. Leave the existing analyzer feature/lab preference disabled by default.
4. Do not delete it.
5. Do not allow it to open a second microphone in the normal personal configuration.

If the analyzer path is enabled later, it must consume the **same camera/DJI audio buffers**, converting those buffers to `SpeechAnalyzer.bestAvailableAudioFormat(...)` as needed. It must not restore an independent `AVAudioEngine` mic tap.

Do not delay the initial working personal fork merely to modernize both recognition engines simultaneously.

---

# 8. Preserve ScriptAligner behavior exactly during the first implementation

Do not retune thresholds in `ScriptAligner.swift` while changing camera/audio plumbing.

Preserve current behavior including:

- rolling recognized-word window
- filler stripping
- word-level Levenshtein comparison
- phonetic score assistance
- locality bias
- stronger resistance to backward jumps
- visible-token-range restriction
- widened search after loss of tracking
- no-match = hold position
- existing block-aware position mapping
- existing scroll velocity / momentum behavior
- silence handling

The point of this patch is to make the recognizer hear the same clean DJI signal that the video records. First test the existing alignment algorithm with that higher-quality signal before changing its parameters.

Only tune alignment in a follow-up commit if physical-device tests demonstrate a reproducible failure such as consistent late following, repeated-line jumping, or skipped-section recovery failure.

---

# 9. Restore a true “camera behind teleprompter text” composition

The user's desired recording screen is the front-camera feed filling the screen with prompt text over it.

The enum still contains `CameraStyle.behind`, but the current `TeleprompterView` no longer mounts a full-screen camera preview below the scrolling text; the current PiP promotion path instead places the camera over the content.

Restore the minimal behind-text implementation.

Relevant files:

- `OpenPrompter/Features/Camera/CameraStyle.swift`
- `OpenPrompter/Features/Camera/CameraPreview.swift`
- `OpenPrompter/Features/Prompter/TeleprompterView.swift`
- existing camera settings/chip files as needed

## 9.1 Layer order

The core ZStack should behave as:

```text
full-screen CameraPreview
    -> readability scrim / localized text backing
        -> scrolling teleprompter text
            -> non-recorded controls / read indicators
```

The camera preview belongs **below** the text in the SwiftUI view hierarchy.

The saved video still comes directly from `AVCaptureVideoDataOutput -> AVAssetWriter`, so no SwiftUI layer is composited into the recording.

## 9.2 Legibility without covering the whole face

Do not place an opaque black sheet over the full camera preview.

Use a restrained readability treatment around the reading area. Start with:

- white or near-white prompt text
- semibold/bold system font using the existing adjustable font-size controls
- subtle dark text shadow/stroke if already supported cleanly by SwiftUI
- a localized black/material backing behind the active reading region at roughly 35–55% opacity
- sufficient horizontal inset so lines do not run edge-to-edge
- keep the active read area close to the front-camera lens/top region so eye movement remains small

Prefer approximately 3–4 readable lines in the primary reading band on an iPhone 17 Pro Max in portrait orientation. Do not enforce line count by destructive truncation; use viewport/font/layout sizing.

Do not dim the actual captured video; the scrim is UI-only.

## 9.3 Make behind mode reachable again

For this personal fork, make `behind` an actual user-selectable camera composition again.

A minimal cycle is acceptable, for example:

```text
off -> behind -> pip -> off
```

or expose `behind` in the existing camera settings while leaving the chip behavior simple.

Do not remove PiP if it is already stable; `behind` simply becomes the default/intended recording composition for this fork.

---

# 10. Personal defaults

Set defaults for a new install of this fork to favor the intended workflow without removing configurability:

- recording fps: **30**
- surfaced fps choices: **30 / 60**
- recording quality: **High**
- color: current SDR Rec.709 path
- aspect for normal shorts: existing vertical/wide path that produces 9:16 presentation
- voice-follow: user-controlled, not forced on globally
- camera composition: behind-text should be one obvious action away; it may be the personal default after camera permission is granted
- microphone: retain last explicit selection; suggest/show the connected DJI USB input prominently

Do not auto-grant permissions or bypass Apple's camera/mic/speech authorization flows.

---

# 11. Error behavior

Use explicit, actionable errors for conditions that violate the personal recording contract.

Required examples:

### 4K unavailable

```text
4K 60 isn't available on the current front-camera format. Switch to 30 fps.
```

Do not silently record 1080p.

### DJI selected but unavailable before REC

```text
DJI Mic Mini is selected but isn't connected. Reconnect it or choose Built-in Microphone.
```

### Input changes during take

Persistent, non-modal warning:

```text
Audio input changed: Built-in Microphone
```

Do not stop the video automatically solely because the route changed if AVFoundation is still delivering valid audio; preserve the take and make the change obvious.

### Voice path not receiving audio

If voice-follow starts but no shared capture audio is available, fail the voice mode with a useful message instead of leaving a green/active control with no movement.

---

# 12. Tests to add or update

Do not depend only on manual testing.

## 12.1 Frame-rate UI/default tests

Add tests asserting:

- default remains 30 fps
- user-facing choices for the personal fork are 30 and 60
- persisted 24 fps does not crash/misparse if encountered from existing preferences

## 12.2 4K format-selection tests

Extend the pure format-descriptor tests around `CameraStore.pickOpenGateFormat` / related selectors.

Provide synthetic descriptor sets where:

- 1080p supports 60 but 4K also supports 60 -> 4K wins
- 4K supports 30 only and user requests 60 -> personal 4K60 preflight rejects instead of selecting 1080p60
- multiple 4K formats support the fps -> existing largest/dynamic-aspect priority remains deterministic

Do not hardcode the entire camera database; test the decision rules.

## 12.3 Voice backend tests

Add a fake externally-fed `SpeechBackend` test implementation.

Verify:

- `VoiceTracker.feedAudio` forwards to the active backend
- stopping voice stops forwarding while recording can continue
- the backend lifecycle no longer requires an `AVAudioEngine`
- repeated start/stop remains idempotent

Where constructing a real `CMSampleBuffer` is cumbersome, add a narrow injectable seam around forwarding and keep at least one test with a valid audio sample-buffer fixture if feasible.

## 12.4 Existing ScriptAligner suite must remain green

Do not alter expected alignment outputs merely because the input pipeline changed.

Explicitly retain coverage for:

- clean sequential reading
- one-word substitution
- omitted words
- repeated common words
- backward retake
- skipped section
- temporary loss/no-match hold
- visible-range protection

## 12.5 Audio-routing tests

Unit-test whatever pure helper resolves preferred input identity.

At minimum verify behavior for:

- saved device present
- saved device absent
- built-in selection
- auto selection
- route name/UID mismatch fallback path

Actual DJI routing still requires physical-device validation.

---

# 13. Physical iPhone 17 Pro Max acceptance pass

Simulator success is not sufficient for this change.

Run the following tests on the actual iPhone 17 Pro Max.

## Test A — 4K30 SDR

1. Select 30 fps.
2. Use front camera.
3. Use behind-text teleprompter mode.
4. Record at least 60 seconds.
5. Inspect resulting file metadata.

Pass conditions:

- 4K portrait presentation (2160 x 3840 effective presentation for 9:16)
- approximately 30 fps with no systematic frame dropping
- HEVC
- Rec.709 SDR
- no Dolby Vision/HDR flagging in Photos/QuickTime/ffprobe-style metadata
- teleprompter UI absent from recorded pixels
- orientation correct in Photos and at least one external editor/player

## Test B — 4K60 SDR

Repeat at 60 fps.

Pass conditions:

- 4K portrait presentation
- approximately 60 fps
- SDR Rec.709
- no systematic dropped-frame behavior
- correct orientation
- no teleprompter UI in file

## Test C — DJI recorded audio

1. Attach DJI Mic Mini receiver by USB-C.
2. Select/pin it.
3. Confirm UI says DJI is the current input.
4. Place the iPhone several feet away and speak close to the DJI transmitter so the acoustic difference from the phone mic is obvious.
5. Record a clip.

Pass conditions:

- recorded audio unmistakably comes from DJI
- current-route display remains accurate
- audio is synchronized with video

## Test D — DJI drives voice-follow before REC

1. Keep DJI connected.
2. Open a known script.
3. Enable camera/behind mode but do not press REC.
4. Enable voice-follow.
5. Read the script through the DJI transmitter.

Pass conditions:

- scrolling starts from the shared camera audio path
- no second microphone capture is opened by voice tracking
- pauses stop momentum according to current behavior
- minor wording deviations do not immediately lose position

## Test E — simultaneous recording + voice-follow

With DJI connected:

1. Start voice-follow.
2. Start recording.
3. Read for at least two minutes.
4. Pause in the middle.
5. Repeat one sentence.
6. Skip one sentence.
7. Continue normally.
8. Stop recording while leaving voice-follow active briefly.

Pass conditions:

- no audio interruption when REC starts/stops
- scrolling remains responsive during recording
- repeated sentence does not cause a wild far-back jump
- skipped sentence recovers without fixed-speed drift
- recording audio remains DJI throughout

## Test F — input disconnect handling

During a take, disconnect the DJI receiver.

Pass conditions:

- app does not crash
- UI immediately reports route change
- if iOS reroutes and keeps supplying audio, recording remains valid
- app does not continue displaying DJI as the active source

## Test G — thermal/stability sanity

Record:

- at least 10 minutes at 4K30
- at least 5 minutes at 4K60

Watch for:

- sustained frame-rate collapse
- writer failures
- audio desynchronization
- recognizer stopping unexpectedly
- camera session reconfiguration
- thermal shutdown

Do not optimize prematurely, but record concrete results in the implementation notes.

---

# 14. Debug instrumentation required during implementation

Keep instrumentation lightweight and DEBUG-only where possible.

Log at the start of each take:

- camera device
- raw input/sample-buffer dimensions
- effective presentation orientation/dimensions
- selected fps
- writer codec and bitrate
- color primaries/transfer/matrix
- preferred mic UID/name
- actual route UID/name/type
- audio sample rate/channels received by `AVCaptureAudioDataOutput`
- active speech backend
- whether speech audio source is `AVCaptureAudioDataOutput` shared fork

Log audio route changes while recording.

Do not log script contents or recognized transcript text by default in release builds.

---

# 15. Implementation order

Follow this order so regressions are attributable:

### Commit 1 — fork baseline / no functional changes

- fork upstream
- branch
- confirm build/tests
- record upstream SHA in implementation notes

### Commit 2 — personal 4K SDR 30/60 contract

- surface only 30/60
- default 30
- add 4K preflight/fail-closed behavior
- keep existing SDR writer
- add/extend format-selection tests

### Commit 3 — deterministic preferred audio route

- harden preferred/current route handling
- reconcile `AVAudioSession` vs `AVCaptureDevice` identity
- current source is visible in UI
- route-change warning
- tests for pure selection helpers

### Commit 4 — shared DJI audio into voice recognition

- externally-fed `SpeechBackend` seam
- remove `AVAudioEngine` tap from default SFSpeech live path
- forward `VoiceTracker.feedAudio` to backend
- guarantee `ensureAudioCaptureRunning` on voice start
- retain existing ScriptAligner untouched
- voice/audio lifecycle tests

### Commit 5 — restore camera-behind-text UI

- full-screen camera layer under scrolling text
- localized readability scrim
- make `behind` reachable
- confirm overlay is preview-only and never enters writer frames

### Commit 6 — physical-device fixes only

Only issues observed on the real iPhone 17 Pro Max + DJI Mic Mini should go here. Do not use this commit as an excuse for unrelated refactoring.

---

# 16. Definition of done

The task is complete only when all of the following are true:

- fork exists and tracks upstream as a remote
- project builds from generated Xcode project
- existing automated tests pass
- new targeted tests pass
- app deploys to the user's iPhone 17 Pro Max
- front camera records **4K SDR at 30 fps**
- front camera records **4K SDR at 60 fps**
- a requested 4K mode never silently becomes 1080p
- saved video is Rec.709 SDR, not HDR/Dolby Vision
- camera preview can fill the screen behind readable teleprompter text
- prompt/UI is not burned into the recording
- DJI Mic Mini USB input is visibly identifiable and selectable
- actual current input is shown, not merely preferred input
- the recorded audio comes from DJI when DJI is selected/active
- voice-follow consumes the **same `AVCaptureAudioDataOutput` stream** as recording
- normal live voice-follow does not open a second `AVAudioEngine` microphone tap
- voice-follow works before REC as long as camera/audio capture is active
- starting/stopping REC does not interrupt voice-follow
- stopping voice-follow does not interrupt recorded audio
- existing `ScriptAligner` behavior remains intact
- pause/repeat/skip tests succeed without uncontrolled scrolling
- DJI disconnect produces a visible route-change warning and does not leave stale “DJI active” UI
- 10-minute 4K30 and 5-minute 4K60 sanity runs complete without a writer/audio-sync failure

---

# 17. Final handoff from the coding agent

Return all of the following, not just “implemented”:

1. fork repository URL
2. working branch name
3. final commit SHA
4. upstream base SHA used for the fork
5. concise list of files changed
6. automated test command(s) and result summary
7. physical-device test table for Tests A–G above
8. actual observed 4K30 and 4K60 output metadata
9. actual DJI route name/type/UID observed on device
10. confirmation that the speech backend consumed shared `AVCaptureAudioDataOutput` buffers and did not create an independent live microphone tap
11. any remaining issue, with exact reproduction steps

Do not claim completion based only on simulator tests. The camera-format, USB audio-route, 4K60, orientation, and shared-mic acceptance criteria are physical-device requirements.
