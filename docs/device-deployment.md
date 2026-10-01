# AI Tele Prompter device deployment

On October 1, 2026, the personal fork was built with Xcode 26.4.1, signed using the available local Apple Development identity, installed, and launched on the connected physical iPhone 17 Pro Max running iOS 27.2 beta.

- App display name: **AI Tele Prompter**
- Bundle ID: `com.turio.aiteleprompter`
- Live Activity extension: `com.turio.aiteleprompter.liveactivity`
- iCloud container: `iCloud.com.turio.aiteleprompter`
- Xcode project/scheme: `OpenPrompter`

`project.yml` now declares the personal identity and generates matching Info.plist/entitlements files. The signing team was overridden for the device build and set in the ignored local Xcode project; no owner-specific team was added to committed configuration. Xcode automatic provisioning succeeded for the new identity. Regenerating the project requires reapplying the local signing team.

Validation: signed Debug device build succeeded; `codesign --verify --deep --strict` passed; the built display name matched; `devicectl` confirmed installation and successful launch. Build products are in `/tmp/ai-tele-device-build/Build/Products/Debug-iphoneos/OpenPrompter.app` and the build log is `/tmp/ai-tele-device-build.log`.

This confirms physical deployment and launch. The recording, DJI route, speech-follow and sustained-capture acceptance tests A–G are still unverified; deployment alone does not establish those results.

## Follow-up UI changes — 2026-10-01

Added a shared Reading/Labs setting to hide the green voice diagnostics overlay (default hidden). Replaced independently overlapping bottom control layers with an adaptive shared row and a separate camera row when space is tight. Source diff checks pass. Signed device rebuild and deployment remain blocked by repeated macOS disk exhaustion (`No space left on device`); these changes have not been installed on the iPhone or visually verified. Generated intermediates from this project were removed to reclaim space. Physical capture acceptance T007 remains unverified.
