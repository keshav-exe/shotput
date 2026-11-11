# Shotput launch film

A 68-second film of Shotput's first run: install, the welcome guide, a first capture, annotating
it, and pasting it into a chat that fixes the bug.

Every piece of Shotput's UI in it is the app itself. `shotput-dev film-capture` and
`film-onboard` drive the real selection overlay, editor, and welcome guide offscreen with
synthetic events and write each frame with where the pointer was. This Remotion project sets
those frames on a macOS desktop and adds the camera, the pointer, the keys, and the captions.

## Rebuild

```bash
npm install
npx remotion still src/index.ts CaptureStill frames/still.png
cp src/plan.json frames/
(cd .. && swift run shotput-dev film-capture LaunchFilm/frames && swift run shotput-dev film-onboard LaunchFilm/frames)
npm run render
```

`film-capture` needs a display that is 1512 by 982 points (a 14-inch MacBook Pro at its default
size). `src/plan.json` holds the choreography both sides share. `npm run studio` opens the edit
for scrubbing.
