# Shotput

A native macOS screenshot tool built for one loop: press a mouse button, drag an area, paste it
into your agent. Annotate first when the picture needs a pointer.

![The editor](docs/editor.png)

## Install

Needs macOS 26 or later.

Download `Shotput-<version>.dmg` from [Releases](https://github.com/keshav-exe/shotput/releases/latest),
open it, and drag Shotput to Applications. Release builds are not notarized yet, so the first
time you open it macOS says it cannot check the app. Open **System Settings → Privacy &
Security**, scroll down, and click **Open Anyway**. Or clear the flag in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Shotput.app
```

To build it yourself instead, you need Xcode's command line tools:

```bash
./Scripts/build.sh --install
```

That builds `build/Shotput.app`, signs it, copies it to `/Applications`, and opens it.

On first launch a short welcome guide walks through Screen Recording, the shortcuts, and setting
up a mouse button. Open it again any time from the menu bar icon.

## Use it from a Logitech mouse

Shotput's shortcuts are ordinary system-wide hotkeys, so Logi Options+ can fire them.

1. Open Logi Options+ and pick your mouse, then the button.
2. Choose **Keyboard shortcut** from the actions list.
3. Press the Shotput shortcut you want on that button.

The gesture button takes five actions (click, plus hold and move in four directions), which
covers every shortcut below.

| Action | Default | What happens |
|---|---|---|
| Capture area | ⌃⌥⌘A | Drag an area. It is on the clipboard when you let go. |
| Capture area and annotate | ⌃⌥⌘D | Same, then the editor opens where you captured. |
| Capture window | ⌃⌥⌘W | Click a window. You get it alone, with clean corners. |
| Capture screen | ⌃⌥⌘S | The display under the pointer. |
| Annotate last capture | ⌃⌥⌘E | Opens the most recent capture in the editor. |
| Copy text from area | ⌃⌥⌘T | Drag over text and it is copied as text, read on your Mac. |
| Repeat last area | none | Captures the same area again, with no selection. |
| Annotate clipboard image | none | Opens the image on the clipboard in the editor. |

Change any of them in Settings. Pressing a capture shortcut again while selecting backs out, so
one button both starts and cancels.

Launchers and Smart Actions can also open links: `shotput://area`, `shotput://annotate`,
`shotput://window`, `shotput://text`, `shotput://last`, `shotput://clipboard`,
`shotput://settings`. Turn links off under Settings → General.

## Selecting

- The screen freezes while you select, so open menus and hover states stay put.
- The crosshair snaps to window edges and corners, the menu bar, and the Dock. The guides turn
  blue when snapped. Hold ⌘ to place freely.
- Space switches between area and window. While dragging, hold Space to move the selection and
  Shift to keep it square.
- Esc or a right click cancels.

## After a capture

The image is on the clipboard straight away, so you can paste without waiting. A small preview
then appears in the screen corner nearest your pointer that does not cover what you captured.

- Click it to annotate.
- Drag it into any app as a file.
- Ignore it and it leaves after a few seconds. It never takes focus.

Settings can open the editor every time instead, or skip the preview and copy quietly.

## Annotating

| Tool | Key | Notes |
|---|---|---|
| Arrow | A | Shift snaps to 45° steps. |
| Line | L | |
| Rectangle | R | Shift for a square. Fill tints the inside. |
| Ellipse | O | Shift for a circle. |
| Text | T | Return finishes, Shift Return adds a line. Double click to edit. |
| Step number | N | Counts up on each click. |
| Pen | P | |
| Highlighter | H | |
| Redact | B | Mosaic by default. Fill makes it a solid block. |
| Crop | C | |

Keys 1 to 8 pick a colour. Every mark has a thin halo and soft shadow, so it stays readable on
any background, including one of its own colour.

Drag any mark to move it, drag its handles to reshape it, and use the arrow keys to nudge.
Delete removes it. Undo and redo work as usual.

The toolbar's **Background** button puts any screenshot on your wallpaper or a colour, with
adjustable padding, a soft shadow, and rounded corners. Marks stay where you put them, and
choosing None takes it off again.

**Return** copies the result and closes the editor. ⌘C copies and keeps it open, and ⌘S saves.
The toolbar can also copy the text in the screenshot, read on your Mac.

## Settings

Settings is split into tabs, so each page fits on a laptop screen.

- **General**: open at login, show or hide the menu bar icon, capture sound, allow links, reset.
- **Capture**: magnifier, edge snapping, selection hints, what happens after a capture, where the
  preview appears and how long it stays, window shadow, a background for window captures (your
  current wallpaper or a solid colour, with padding), and the pointer in screen captures.
- **Editor**: what Esc does, whether ⌘C also closes, and how text recognition joins lines.
- **Output**: standard resolution, save folder, save every capture, PNG, JPEG or HEIC with a
  quality slider, and a file name template such as `%n %Y-%m-%d %H.%M.%S`.
- **Shortcuts**: every action above, plus the mouse button guide.

## Privacy and footprint

- Sandboxed with no network entitlement. macOS itself stops Shotput from sending anything.
- It can write only to a folder you choose, or a location you pick in a save panel.
- Links can only start captures that put a selection on screen. A silent full-screen capture is
  shortcut only, so another app cannot use Shotput to read your screen.
- Idle, it uses no CPU and about 15 MB of memory. Hotkeys are event driven and nothing polls.
- No dependencies. Swift, AppKit, and ScreenCaptureKit.

## Development

```bash
swift run shotput-dev editor /tmp/editor.png
```

```bash
swift run shotput-dev overlay /tmp/overlay.png
```

```bash
swift run shotput-dev settings /tmp/settings.png
```

These drive the editor and the selection overlay offscreen with synthetic mouse events, check
the results, and write renders you can look at. `settings` renders every Settings tab and
welcome step and checks that each fits on a small screen. `preview` renders every kind of mark, and
`Scripts/make-icon.sh` rebuilds the app icon from the same renderer.

## Releasing

Push a version tag and GitHub Actions builds a universal app, packages a `.dmg` and `.zip` with
checksums, and publishes the release. Tags with a hyphen, such as `v0.2.0-beta.1`, are marked
as pre-releases.

```bash
git tag v0.2.0 && git push origin v0.2.0
```

To package locally, run `SHOTPUT_VERSION=0.2.0 ./Scripts/build.sh` and then `./Scripts/package.sh`.
Builds are ad-hoc signed unless the Developer ID and notary secrets described in
`.github/workflows/release.yml` are set, in which case they are signed and notarized.

## Licence

MIT. See [LICENSE](LICENSE).
