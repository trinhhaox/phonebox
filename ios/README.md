# PhoneBox for iOS

Thin native shell (SwiftUI + WKWebView) around the same panel the Android app uses. It talks to the desktop agent
over pinned HTTPS (`:8766`, Wi-Fi / Tailscale). There is no USB route on iPhone.

## Requirements
- Xcode 16+ (tested with 27.1), iOS 16+ deployment target, iPhone only
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) - the project is generated from `project.yml`
- Apple team `4DU4BTV46U`, automatic signing, bundle id `vn.xox.phonebox`

## Build and run
```sh
cd ios
xcodegen generate            # only needed after editing project.yml
open PhoneBox.xcodeproj      # or:
DEVELOPER_DIR=/Volumes/XcodeExternal/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project PhoneBox.xcodeproj -scheme PhoneBox \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```
To run on a device, pick it in Xcode and press Run (signing is automatic).

## Panel assets
`../android/app/src/main/assets/www` is added as a **folder reference** (`www` in the bundle), not copied, so the
Android and iOS apps always ship the same panel. `PANEL_VERSION` (project.yml) is sent to the agent as
`X-PhoneBox-App` and must match the agent/panel release the assets come from.
The panel is served to the WebView from `pbapp://panel/` by `PanelSchemeHandler`; `/agent/*` requests are proxied
natively and only when they carry the `X-PhoneBox-Panel` header.

Swift files under `PhoneBox/` and `PhoneBoxTests/` are synchronized folders: new files need no project edits.
