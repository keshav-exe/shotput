import React from 'react';
import { AbsoluteFill, Audio, Img, interpolate, staticFile, useCurrentFrame } from 'remotion';
import { bezier, clamp01, lerp, ramp } from './anim';
import { DISPLAY_FONT, UI_FONT } from './desktop/Desktop';
import { FPS } from './layout';
import { SRC, Shot } from './Launch';

// The cut is laid on the track's grid: 124 BPM, a breakdown from beat 23 to the drop at beat 32,
// a stop-down at beat 59, and the final hit on beat 64.
const BEAT = 60 / 124;
const at = (beat: number) => beat * BEAT;
const HIT = at(64);
export const AD_DURATION = HIT + 3.7;

type ShotSeg = { kind: 'shot'; b0: number; b1: number; s0: number; s1: number; punch?: boolean; ease?: (u: number) => number };
type CardSeg = { kind: 'card'; b0: number; b1: number; words: { beat: number; text: string }[]; keys?: string[] };
type Seg = ShotSeg | CardSeg;

// Holds a moment, then lets it go: for shots that should slow into their key frame.
const settle = bezier(0.15, 0.55, 0.5, 1);

const EDL: Seg[] = [
  { kind: 'shot', b0: 0, b1: 4, s0: SRC.desk + 0.1, s1: SRC.pullBack + 0.95 },
  { kind: 'card', b0: 4, b1: 6, words: [{ beat: 4, text: 'Get' }, { beat: 5, text: 'Shotput.' }] },
  { kind: 'shot', b0: 6, b1: 9, s0: SRC.grab - 0.45, s1: SRC.drop + 0.45, punch: true },
  { kind: 'shot', b0: 9, b1: 11, s0: SRC.spot - 0.05, s1: SRC.spotGo + 0.3, punch: true },
  { kind: 'shot', b0: 11, b1: 15, s0: SRC.onboard + 3.1, s1: SRC.onboard + 6.6 },
  { kind: 'shot', b0: 15, b1: 17, s0: SRC.TOGGLE - 0.75, s1: SRC.TOGGLE + 0.35, punch: true },
  { kind: 'shot', b0: 17, b1: 19, s0: SRC.shortcuts + 0.4, s1: SRC.shortcuts + 2.6 },
  { kind: 'shot', b0: 19, b1: 21, s0: SRC.TRY - 0.85, s1: SRC.TRY + 0.15, punch: true },
  { kind: 'card', b0: 21, b1: 23, words: [{ beat: 22, text: 'Press.' }], keys: ['⌃', '⌥', '⌘', 'A'] },
  // The breakdown: the capture at a little under real speed, so the drag can be watched.
  { kind: 'shot', b0: 23, b1: 32, s0: SRC.OV, s1: SRC.THUMB_CLICK - 0.3, ease: settle },
  { kind: 'shot', b0: 32, b1: 34, s0: SRC.THUMB_CLICK - 0.3, s1: SRC.ED + 1.1, punch: true },
  { kind: 'shot', b0: 34, b1: 40, s0: SRC.ED + 1.1, s1: SRC.ED_END },
  { kind: 'shot', b0: 40, b1: 44, s0: SRC.CHAT_CLICK - 0.35, s1: SRC.SEND + 0.35, punch: true },
  { kind: 'shot', b0: 44, b1: 48, s0: SRC.THINK + 0.55, s1: SRC.DIFF + 0.75 },
  // The fix lands on beat 50.
  { kind: 'shot', b0: 48, b1: 54, s0: SRC.FIXED - 0.95, s1: SRC.FIXED - 0.95 + 0.95 * 3, punch: true },
  { kind: 'shot', b0: 54, b1: 58, s0: SRC.OUTRO - 0.1, s1: SRC.OUTRO + 1.6, ease: settle },
  { kind: 'card', b0: 58, b1: 64, words: [{ beat: 58, text: 'Press.' }, { beat: 60, text: 'Drag.' }, { beat: 62, text: 'Paste.' }] },
];

const STAGE = '#121211';

const KeyCap: React.FC<{ label: string; down: number }> = ({ label, down }) => (
  <div
    style={{
      width: 112,
      height: 112,
      borderRadius: 26,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      font: `500 52px ${UI_FONT}`,
      color: '#f4f2ee',
      background: 'linear-gradient(180deg, #34332f, #242320)',
      boxShadow: `inset 0 1px 0 rgba(255,255,255,0.14), 0 0 0 1px rgba(0,0,0,0.6), 0 ${7 - 5 * down}px 0 #0b0b0a, 0 18px 40px rgba(0,0,0,0.4)`,
      transform: `translateY(${5 * down}px)`,
    }}
  >
    {label}
  </div>
);

const Card: React.FC<{ seg: CardSeg; t: number }> = ({ seg, t }) => {
  const shown = seg.words.filter((w) => t >= at(w.beat));
  return (
    <AbsoluteFill style={{ background: STAGE, alignItems: 'center', justifyContent: 'center', gap: 48 }}>
      {seg.keys && (
        <div style={{ display: 'flex', gap: 18 }}>
          {seg.keys.map((k, i) => {
            const hitAt = at(seg.b0) + i * 0.07;
            const inP = clamp01((t - hitAt) / 0.12);
            const down = t >= at(22) && t < at(22) + 0.22 ? 1 : 0;
            return (
              <div key={k} style={{ opacity: inP, transform: `translateY(${(1 - inP) * 24}px)` }}>
                <KeyCap label={k} down={down} />
              </div>
            );
          })}
        </div>
      )}
      <div style={{ display: 'flex', gap: 34, height: 150, alignItems: 'center' }}>
        {shown.map((w) => {
          const p = clamp01((t - at(w.beat)) / 0.16);
          const e = bezier(0.2, 0.9, 0.25, 1)(p);
          return (
            <div
              key={w.text + w.beat}
              style={{
                font: `650 136px ${DISPLAY_FONT}`,
                letterSpacing: -5,
                color: '#f6f4ef',
                opacity: e,
                transform: `scale(${lerp(1.12, 1, e)})`,
                filter: `blur(${(1 - e) * 10}px)`,
              }}
            >
              {w.text}
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

const EndCard: React.FC<{ t: number }> = ({ t }) => {
  const d = t - HIT;
  const icon = bezier(0.2, 1.4, 0.3, 1)(clamp01(d / 0.45));
  const name = bezier(0.2, 0.9, 0.25, 1)(clamp01((d - 0.12) / 0.4));
  const sub = bezier(0.2, 0.9, 0.25, 1)(clamp01((d - 0.9) / 0.5));
  const out = ramp(t, AD_DURATION - 0.5, AD_DURATION);
  return (
    <AbsoluteFill style={{ background: STAGE, alignItems: 'center', justifyContent: 'center', opacity: 1 - out }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 30 }}>
        <Img src={staticFile('icons/shotput.png')} style={{ width: 150, height: 150, transform: `scale(${lerp(0.6, 1, icon)})`, opacity: clamp01(icon * 2) }} />
        <div style={{ font: `650 120px ${DISPLAY_FONT}`, letterSpacing: -4.5, color: '#f6f4ef', opacity: name, transform: `translateX(${(1 - name) * -20}px)` }}>Shotput</div>
      </div>
      <div style={{ marginTop: 34, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12, opacity: sub, transform: `translateY(${(1 - sub) * 10}px)` }}>
        <div style={{ font: `500 32px ${DISPLAY_FONT}`, letterSpacing: -0.5, color: '#c9c4ba' }}>Screenshots for pasting. Free for macOS.</div>
        <div style={{ font: `500 22px ${UI_FONT}`, color: '#7d786f' }}>github.com/keshav-exe/shotput</div>
      </div>
    </AbsoluteFill>
  );
};

export const Ad: React.FC = () => {
  const t = useCurrentFrame() / FPS;
  const volume = (f: number) => interpolate(f / FPS, [0, 0.05, AD_DURATION - 0.6, AD_DURATION], [0, 1, 1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
  let body: React.ReactNode;
  if (t >= HIT) {
    body = <EndCard t={t} />;
  } else {
    const seg = EDL.find((s) => t >= at(s.b0) && t < at(s.b1)) ?? EDL[EDL.length - 1];
    if (seg.kind === 'card') {
      body = <Card seg={seg} t={t} />;
    } else {
      const u = clamp01((t - at(seg.b0)) / (at(seg.b1) - at(seg.b0)));
      const src = lerp(seg.s0, seg.s1, (seg.ease ?? ((x: number) => x))(u));
      const since = t - at(seg.b0);
      const punch = seg.punch ? 0.045 * (1 - bezier(0.2, 0.9, 0.25, 1)(clamp01(since / 0.35))) : 0;
      body = <Shot t={src} punch={punch} />;
    }
  }
  const fadeIn = clamp01(t / 0.12);
  return (
    <AbsoluteFill style={{ background: STAGE }}>
      <AbsoluteFill style={{ opacity: fadeIn }}>{body}</AbsoluteFill>
      <Audio src={staticFile('audio/track.mp3')} volume={volume} />
    </AbsoluteFill>
  );
};
