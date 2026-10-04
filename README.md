# Vanity ✨

A multi-camera hair mirror for Mac. Front, sides and back are all on one screen.

- **Vanity** (macOS 14+): the mirror and the Lookbook.
- **Vanity Cam** (iPadOS/iOS 17+): turns an iPad or a spare iPhone into an extra camera.

## Cameras

| View | Device | How it connects |
|---|---|---|
| Front | MacBook camera | Automatic |
| Back or side | iPhone | **Continuity Camera**: lock the iPhone, turn it sideways on a stand near the Mac, same Apple ID. It shows up by itself. |
| Another side | iPad (or a second iPhone) | **Vanity Cam** app: finds the Mac over Wi-Fi by itself, with no setup. |

USB webcams also show up automatically.

## Mirror

- **Click** a view to make it big. **Esc** or **Show all** goes back to the grid.
- **Pinch or scroll** to zoom, **drag** to move around while zoomed, **double-click** to reset.
- Hover a view for **mirror flip**, **rotate**, **freeze** and **delay**. Double-click a view's name to rename it.
- **Delay** plays a view 2–10 seconds behind live. Turn around, then watch the back of your head.
- **Capture look** (Space) counts down 3-2-1, then saves a photo from every camera.

Shortcuts: `Space` capture · `D` delay · `F` freeze · `M` mirror · `1`–`4` spotlight · `⌘1` Mirror · `⌘2` Lookbook

## Lookbook

Each look stores:
- Photos from every angle
- Install method, length and tags
- **Hair recipe**: texture, shade/color swatch, length and bundle count for each hair, with a running total
- **Closure/frontal** details
- **Parting chart**: draw parts and paint where each color goes, on a top view and a back view
- Products and notes

**Compare** shows two looks side by side. **Recreate this look** pins a look's photos next to the live mirror.

Looks are saved in `~/Library/Containers/<bundle id>/Data/Library/Application Support/Vanity/` as `looks.json` plus a `Photos/` folder.

## Building

Requires **Xcode 16+** and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate       # re-run after adding/removing files or editing project.yml
open Vanity.xcodeproj
```

1. In `project.yml`, replace `com.example.vanity` with your own bundle ID prefix and set `DEVELOPMENT_TEAM`. (Or set both in Xcode's *Signing & Capabilities* tab.)
2. Run the **Vanity** scheme on the Mac.
3. Run the **VanityCam** scheme on the iPad. In the Simulator it streams a test pattern, so you can try it without a device.
4. Tests: `⌘U` on the Vanity scheme runs the Lookbook tests and the VanityKit (streaming/delay) tests.

### Shipping to her devices with TestFlight

1. In App Store Connect, create two apps (macOS **Vanity** and iOS **Vanity Cam**) with the bundle IDs from `project.yml`.
2. In Xcode, for each scheme: *Product → Archive → Distribute App → TestFlight & App Store*.
3. In TestFlight, add her Apple ID as an internal tester. She installs the **TestFlight** app on her Mac and iPad and taps Install. Updates then arrive automatically.

## How it works

- `Packages/VanityKit`: shared code. It includes the wire format (`Wire.swift`), a low-latency H.264 encoder/decoder (VideoToolbox), the TCP connection wrapper with Bonjour helpers, and the delay buffer.
- `Apps/Mac/Capture`: every camera, local or remote, feeds a `FrameRouter`, which handles live, delayed and frozen output. Local cameras come from `LocalCameras`, and Vanity Cam streams arrive through `CameraServer` (Bonjour `_vanitymirror._tcp`).
- `Apps/Mac/Mirror`: the tile grid, the `AVSampleBufferDisplayLayer` video view, and snapshots.
- `Apps/Mac/Lookbook`: Codable models, `LookStore` (JSON + JPEGs) and the parting chart editor.
- `Apps/Cam`: Vanity Cam. It finds the Mac, then captures, encodes and streams. When Wi-Fi can't keep up it drops frames and resumes from a keyframe.
