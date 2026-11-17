# PhoneBox for macOS

Menu bar app (SwiftUI `MenuBarExtra`, no Dock icon) plus a native panel window for the PhoneBox desktop agent.
Bundle id `vn.xox.phonebox.mac`, team `4DU4BTV46U`, macOS 14+. UI is Vietnamese.

## What it does
- Menu: agent status (polled every 8 s), connected phones (USB / Wi-Fi), open panel, settings, Wi-Fi pairing,
  restart agent (`launchctl kickstart -k gui/<uid>/net.oxog.phonebox.agent`), launch at login (this app only), quit
  (quits the menu app only; the agent keeps running under launchd).
- Panel window: `http://127.0.0.1:8765/panel/` in a WKWebView, "always on top", opacity slider (30-100 %), size and
  position remembered (`PhoneBoxPanelWindow`). Default 900x420.
- Settings window: `http://127.0.0.1:8765/` (the agent's settings page). "Pair a phone over Wi-Fi" opens it and
  clicks the page's pairing button (the page has no deep link for the dialog).
- Agent missing (binary or launchd plist absent): the menu says so and offers "Cài đặt PhoneBox agent…", which runs the
  bundled `setup.sh --yes --no-phone` as you (never sudo) and streams the log. setup.sh downloads the release from
  GitHub and verifies its SHA-256 itself. Packages that need sudo (e.g. Homebrew installs) cannot prompt from the app;
  in that case run setup.sh from Terminal once.

## Security
- Web views only load `http://127.0.0.1:8765` (exact scheme/host/port, no userinfo). Other http(s)/mailto links open in the
  default browser; every other scheme is blocked. Non-persistent web data store.
- ATS exception only for `127.0.0.1` and `localhost`.
- The panel identifies as a browser: it sends no `X-PhoneBox-Device` header, so the agent does not list the Mac as a phone.
  The agent also only accepts Host `127.0.0.1`/`localhost` and Origin `http://127.0.0.1:8765`, which matches.
- The app never calls `/api/pair` (it returns the Wi-Fi token). No secrets in this repo.
- Hardened runtime ON. App Sandbox is OFF on purpose: the app must run `/bin/launchctl` and the bundled `setup.sh`
  and read `~/Library/Application Support/PhoneBox` / `~/Library/LaunchAgents`, none of which a sandbox allows.

## Build
```sh
cd macos
export DEVELOPER_DIR=/Volumes/XcodeExternal/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild -project PhoneBoxMac.xcodeproj -scheme PhoneBoxMac -destination 'platform=macOS' test | tail -30
xcodebuild -project PhoneBoxMac.xcodeproj -scheme PhoneBoxMac -destination 'platform=macOS' build | tail -30
```
`open <DerivedData>/Build/Products/Debug/PhoneBox.app --args --show-panel` opens the panel at launch.

## Release (Developer ID, notarized, stapled)
```sh
DEVELOPER_DIR=... macos/scripts/release-notarized.sh
```
Builds a universal (arm64 + x86_64) Release, signs through the Xcode account's cloud-managed Developer ID and notarizes
with `scripts/notarize-with-xcode.sh` (`xcodebuild -exportArchive` + `-exportNotarizedApp`), then writes a DMG signed
with `Developer ID Application: Trinh Hao (4DU4BTV46U)` plus a ZIP of the app to
`/Volumes/XcodeExternal/SharedBuild/phonebox-mac/`. **Distribute `PhoneBox-<ver>-mac.zip`**: the app inside is notarized
and stapled, so Gatekeeper accepts it on any Mac. The Xcode-account flow notarizes apps only, so the DMG is just signed;
to notarize it too, run with `NOTARIZE_DMG=1` and a `notarytool` keychain profile (`NOTARY_PROFILE`, default
`phonebox-notary`, created with `xcrun notarytool store-credentials`). Verify:
`spctl -a -vvv -t exec PhoneBox.app`, `spctl -a -vvv -t open --context context:primary-signature PhoneBox-<ver>.dmg`.

## Install
Open the DMG and drag PhoneBox to Applications (or `cp -R PhoneBox.app /Applications/`). Run it; use "Mở khi đăng nhập" in
its menu to start it at login.
