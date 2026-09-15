<p align="center">
  <img src="Resources/Onboarding/comic-upright.png" width="220" alt="AirPoise mascot wearing AirPods">
</p>

<h1 align="center">AirPoise</h1>

<p align="center">
  A tiny Mac menu-bar app. Wear AirPods, sit better, and run shortcuts with your head.
</p>

<p align="center">
  <a href="https://github.com/jaskirat1616/AirPoise/releases/latest"><img src="https://img.shields.io/badge/download-DMG-black?style=flat-square" alt="Download"></a>
  <a href="#what-you-need"><img src="https://img.shields.io/badge/macOS-14%2B-black?style=flat-square" alt="macOS 14+"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-e31b23?style=flat-square" alt="MIT"></a>
</p>

**[Download AirPoise 1.0.0](https://github.com/jaskirat1616/AirPoise/releases/latest)** — open the DMG and drag the app onto Applications.

AirPoise reads the motion sensors already inside AirPods (the same ones Spatial Audio uses). It does two jobs:

1. **Posture** — reminds you when your chin drifts forward or your head tilts.
2. **Head shortcuts** — nod, shake, glance, or tilt to play/pause, switch desktops, run a Mac shortcut, open a link, and more.

No camera. No account. No internet. It lives in the menu bar, not the Dock.

This is the **Mac app**. It is not the sitting cushion sold at airpoise.com.

---

## Quick start

1. Install from the [DMG](https://github.com/jaskirat1616/AirPoise/releases/latest) (or build from source below).
2. Put on **AirPods Pro / 3 / 4 / Max** or **Beats Fit Pro**, and set them as the Mac’s sound output.
3. Allow **Motion & Fitness** when asked.
4. Sit the way you want to sit, look at the screen, and **Calibrate upright**.
5. Click the menu-bar icon for the live readout. Right-click for Pause / Calibrate / **Settings** / Quit.

If macOS blocks the app: right-click AirPoise → **Open**.

---

## How to control it (shortcuts and more)

Everything is in **Settings** (right-click the menu-bar icon → Settings).

### Actions — pick what each head move does

Open **Settings → Actions**. Tap a gesture, then choose what it should do.

| You can bind a gesture to… | Examples |
|---|---|
| Keyboard shortcut | Record ⌘⇥, media keys, anything you type |
| Apple Shortcuts app | Run a Shortcut by name |
| Open a link or an app | URL, or pick an `.app` |
| Media / volume / brightness | Play-pause, next, mute, brighter |
| Mac system stuff | Mission Control, Spaces, screenshot, lock, Spotlight, sleep |
| Notification, speak, or paste text | A ping, a spoken line, clipboard paste |
| Shell or AppleScript | Only if you write that command yourself |
| Nothing | Leave it unassigned |

**Out of the box**

| Head move | What it does |
|---|---|
| Double nod | Play / Pause |
| Look left / look right | Switch Space (desktop) |
| Hold left tilt | Mission Control |
| Double shake | A small ping notification |
| Everything else | Off until you assign it |

Turn a gesture off by setting its action to **Do nothing**, or disable **Head-gesture shortcuts** under **Settings → Gestures**.

Custom keyboard shortcuts need **Accessibility** (Settings → General → Grant). Play/pause and volume usually do not.

### Gestures — how sensitive the moves feel

**Settings → Gestures**

- Master on/off for all head shortcuts
- **Sensitivity** — easier or harder to trigger
- **Cooldown** — wait between triggers so you don’t double-fire
- **Hold duration** — how long to hold a tilt
- A list of all 16 moves with a short how-to for each: nod, double nod, shake, look left/right/up/down, tilt, hold-tilt, lean, roll

A shortcut fires when you move and **come back**. Sitting still in a slouch is not a nod.

### Posture — how strict the coach is

**Settings → Posture**

- Turn the coach on or off
- How many degrees of forward lean count as good vs “nudge me”
- How long you must stay there before a reminder
- Overlay card, notification, sound, or spoken cue
- Ignore you while walking

Calibrate again any time from the menu bar if your chair or desk changes.

### General

Launch at login, menu-bar style, Motion & Accessibility status, and invert an axis if a direction feels backwards on your buds.

---

## What you need

- **macOS 14 Sonoma** or later
- AirPods with **head tracking**: Pro, 3, 4, Max, or Beats Fit Pro, worn and selected as Mac audio output
- Original AirPods / AirPods 2 will not work (no motion sensor). The menu bar will say “No head-tracking buds”

---

## Honest limits

- It sees **head pose**, not your whole spine. A level head on a rounded back still reads “good”.
- About 25 samples a second. Fine for sitting and discrete gestures, not a VR headset.
- Intel Macs on Sonoma may run. Apple Silicon is what we test.

---

## Privacy

Nothing is uploaded. No analytics. Settings stay in `~/Library/Application Support/AirPoise/`. See [SECURITY.md](SECURITY.md).

---

## Download

**[AirPoise-1.0.0.dmg](https://github.com/jaskirat1616/AirPoise/releases/latest)** — drag onto Applications.

## Build from source

Always run the **`.app`**, not the raw `swift build` binary. macOS needs `NSMotionUsageDescription` in the app bundle.

```bash
./scripts/build-app.sh
open dist/AirPoise.app
```

```bash
./scripts/make-dmg.sh          # disk image
swift test --package-path .    # tests
```

---

## How the sensors work (for developers)

Apple already fuses the AirPods accelerometer + gyro for Spatial Audio. AirPoise does not invent a second compass. It reads `CMDeviceMotion` (~25 Hz).

Headphone frame: **x = right ear, y = nose, z = crown**. Relative pose is `ref⁻¹ · q`. Gyro: turn = ωz, nod = ωx, ear tilt = ωy. Invert any axis in Settings → General if firmware feels backwards.

| Field | Used for |
|---|---|
| `attitude` | Gestures (yaw / pitch / roll vs calibrate) |
| `gravity` | Posture (chin-forward and side tilt). Survives taking the buds out |
| `rotationRate` | Flick energy, hold-still, walk rejection |
| `userAcceleration` | Ignore tracking while you walk |
| `sensorLocation` | Which bud is the motion source |

Smoothing is a 1€ filter. A watchdog re-subscribes after idle/wake. Ear detection connect/disconnects as you put buds in or take them out.

| Path | What |
|---|---|
| `Sources/AirPoiseCore` | Math, pose, gestures, posture, settings. No AppKit |
| `Sources/AirPoise` | Menu bar, first-launch window, overlays, Settings |
| `Tests/AirPoiseTests` | Unit tests |
| `scripts/build-app.sh` | Build the `.app` |

## Uninstall

Quit AirPoise, delete the app, and optionally:

```bash
rm -rf ~/Library/Application\ Support/AirPoise
```

Turn off Login Items if you enabled launch-at-login.

## License

[MIT](LICENSE) © 2026 Jaskirat Singh

Onboarding fonts: [Bangers](https://github.com/googlefonts/bangers) and [Archivo Black](https://github.com/Omnibus-Type/ArchivoBlack) (SIL OFL), in `Resources/Fonts/`.
