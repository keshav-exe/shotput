# Shotput

A native macOS screenshot tool built for one loop: press a mouse button, drag an area, paste it
into your agent. Annotate first when the picture needs a pointer.

![The editor](docs/editor.png)

## Install

Needs macOS 26 or later and Xcode's command line tools.

```bash
./Scripts/build.sh --install
```

That builds `build/Shotput.app`, signs it, copies it to `/Applications`, and opens it. Shotput
lives in the menu bar. The first capture asks for Screen Recording. Allow it, then reopen Shotput.

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

Change any of them in Settings. Pressing a capture shortcut again while selecting backs out, so
one button both starts and cancels.

Launchers and Smart Actions can also open links: `shotput://area`, `shotput://annotate`,
`shotput://window`, `shotput://last`, `shotput://settings`.

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

**Return** copies the result and closes the editor. ⌘C copies and keeps it open, and ⌘S saves.
The toolbar can also copy the text in the screenshot, read on your Mac.

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

These drive the editor and the selection overlay offscreen with synthetic mouse events, check
the results, and write renders you can look at. `preview` renders every kind of mark, and
`Scripts/make-icon.sh` rebuilds the app icon from the same renderer.
