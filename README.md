# Instant Lang Switch

Tap **Fn / 🌐** to switch directly to the next enabled keyboard input source. With two layouts, it toggles between them. The switch happens as soon as you release Fn by itself. Fn shortcuts still pass through to macOS.

Requires macOS 13 Ventura or later. The installer supports Apple silicon and Intel Macs.

## Install and set up

1. Open `InstantLangSwitch.dmg` and drag **Instant Lang Switch** to **Applications**.
2. In **System Settings → Keyboard**, set **Press 🌐 key to** (or **Press fn key to**) to **Do Nothing** to turn off the macOS picker. Add at least two input sources under **Text Input → Edit**. [Apple Keyboard settings](https://support.apple.com/guide/mac-help/keyboard-settings-kbdm162/mac)
3. Launch **Instant Lang Switch**. Allow it under **System Settings → Privacy & Security → Input Monitoring**, then quit and reopen the app if macOS asks. Use **Enable Input Monitoring…** in the app’s menu if you need to reopen that settings pane.
4. To launch it at sign-in, choose **Settings…** from the globe icon in the menu bar and check **Open on startup**. If macOS asks for approval, enable the app in **Login Items**.

You can close the settings window and keep switching layouts. To stop the app, choose **Quit Instant Lang Switch** from its menu bar icon.

## Build from source

With Xcode selected as the active developer directory, run these commands from the repository root.

```sh
swift test
./scripts/build-dmg.sh
```

The installer is written to `dist/InstantLangSwitch.dmg`. The script uses ad-hoc signing by default for local use. To use a Developer ID Application certificate, set `CODESIGN_IDENTITY` when building. Notarization is a separate distribution step.

Inspired by [Fn Lang Switch](https://github.com/tonku321/fn-lang-switcher) and [LangSwitch](https://github.com/Nikeev/LangSwitch).
The HID approach is described in [BetterSwitch’s implementation notes](https://github.com/hamet/betterswitch#how-it-works).
