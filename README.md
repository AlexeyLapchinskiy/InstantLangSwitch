# Instant Lang Switch

**Switch keyboard layouts on macOS with a single <kbd>Fn</kbd> / <kbd>🌐</kbd> tap.**

Instant Lang Switch selects the next enabled input source as soon as you release the key, without opening the macOS input source picker. Two layouts toggle back and forth. With more than two, each tap advances through the list.

The Swift app runs in the menu bar. Fn shortcuts such as <kbd>Fn</kbd> + <kbd>Delete</kbd> still work, and you can close the settings window while the app runs in the background.

**Requires macOS 13 Ventura or later.** The installer includes Apple silicon and Intel builds. For an external keyboard, the key must report a compatible Fn or Globe event to macOS.

## Install

Download and open `InstantLangSwitch.dmg`, drag **Instant Lang Switch** to **Applications**, then launch it from there. [Download the latest installer](https://github.com/AlexeyLapchinskiy/InstantLangSwitch/releases/latest/download/InstantLangSwitch.dmg)

The release build is ad-hoc signed and unnotarized, so macOS may block it on first launch. You can build a local copy using the instructions below. [Apple’s guide to opening downloaded apps](https://support.apple.com/en-us/102445)

1. In **System Settings → Keyboard**, set **Press 🌐 key to** or **Press fn key to** to **Do Nothing**. This turns off the built-in picker. Under **Text Input → Edit**, make sure at least two input sources are enabled. [Apple Keyboard settings](https://support.apple.com/guide/mac-help/kbdm162/mac)
2. In **System Settings → Privacy & Security → Input Monitoring**, allow **Instant Lang Switch**. The app’s globe menu has an **Enable Input Monitoring…** item that opens this pane. Quit and reopen the app if macOS prompts you. [Apple Input Monitoring settings](https://support.apple.com/guide/mac-help/mchl4cedafb6/mac)
3. Open a text field, tap and release **Fn / 🌐** by itself, and type to try the new layout.

## Open on startup

Choose **Settings…** from the globe icon in the menu bar and check **Open on startup**. If macOS asks for approval, choose **Open Login Items** and enable the app. You can stop switching at any time by choosing **Quit Instant Lang Switch** from the same menu.

## Build from source

Install Xcode and select it as the active developer directory. Run these commands on your Mac.

```sh
git clone https://github.com/AlexeyLapchinskiy/InstantLangSwitch.git
cd InstantLangSwitch
swift test
./scripts/build-dmg.sh
```

The build creates `dist/InstantLangSwitch.dmg` and ad-hoc signs the app for local use. Set `CODESIGN_IDENTITY` to use a Developer ID Application certificate. Notarization is a separate distribution step.

## How it works

The app uses IOKit to detect a standalone Fn / Globe tap and macOS’s Text Input Source API to select the next layout. Input Monitoring allows it to detect the tap while another app is active. Keyboard events are processed in memory and are never stored or transmitted.
