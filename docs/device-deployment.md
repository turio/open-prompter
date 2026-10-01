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
