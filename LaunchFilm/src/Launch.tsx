import React from 'react';
import { AbsoluteFill, Img, staticFile, useCurrentFrame } from 'remotion';
import { CamKey, Move, Pt, cameraAt, clamp01, easeOut, frameAt, lerp, pointerAt, pressAt, ramp, window01, bezier } from './anim';
import { CAPTURE, DMG_APP, DMG_APPS, FPS, ONBOARD, Rect, SCREEN, center } from './layout';
import { REPLY, REQUEST } from './desktop/Chat';
import { Cursor, CursorKind, DISPLAY_FONT, UI_FONT } from './desktop/Desktop';
import { Desktop, baseDesktop, idleChat } from './desktop/Screen';
import { DragGhost, InstallerWindow, SETTINGS_TOGGLE, SettingsWindow, Spotlight, Thumbnail } from './desktop/Surfaces';
import overlayDoc from '../frames/overlay/frames.json';
import editorDoc from '../frames/editor/frames.json';
import onboardDoc from '../frames/onboard/frames.json';
import plan from './plan.json';

export const W = 1920;
export const H = 1080;

type OFrame = { t: number; file: string; x: number; y: number; down: boolean };
type EFrame = OFrame & { typing: boolean; key?: string };
type BFrame = { t: number; file: string; step: number };

const overlayFrames = overlayDoc.frames as OFrame[];
const editorFrames = editorDoc.frames as EFrame[];
const EDITOR_WIN: Rect = { x: editorDoc.window.x, y: editorDoc.window.y, w: editorDoc.window.w, h: editorDoc.window.h };

// The guide was filmed in real time, and SwiftUI stalls for a beat each time a step is first
// built. Close those gaps so a click lands on an immediate response, as it does in the app.
const onboardFrames: BFrame[] = (() => {
  const raw = onboardDoc.frames as BFrame[];
  let shift = 0;
  return raw.map((f, i) => {
    if (i > 0) {
      const gap = f.t - raw[i - 1].t;
      if (gap > 0.2) shift += gap - 1 / FPS;
    }
    return { ...f, t: f.t - shift };
  });
})();
const stepAt = (step: number) => onboardFrames.find((f) => f.step === step)!.t;

// ---------------------------------------------------------------------------------------------
// The timeline, in seconds.

const T = {
  title: 0,
  desk: 4.3,
  pullBack: 6.2,
  dmg: 7.7,
  grab: 9.55,
  drop: 11.05,
  dmgClose: 11.9,
  spot: 12.9,
  spotGo: 14.25,
  onboard: 14.8,
} as const;

const ON = {
  perm: T.onboard + stepAt(1),
  shortcuts: T.onboard + stepAt(2),
  mouse: T.onboard + stepAt(3),
  ready: T.onboard + stepAt(4),
};
const SETTINGS_IN = ON.perm + 1.25;
const TOGGLE = SETTINGS_IN + 1.05;
const SETTINGS_OUT = TOGGLE + 0.85;
const TRY = ON.ready + 1.9;
const ONBOARD_OUT = TRY + 0.05;
const OV = TRY + 0.45; // the overlay freezes the screen
const OV_END = OV + overlayFrames[overlayFrames.length - 1].t + 1 / FPS;
const THUMB_IN = OV_END;
const THUMB_CLICK = THUMB_IN + 1.6;
const ED = THUMB_CLICK + 0.1;
const ED_END = ED + plan.editor.done + 0.1;
const CHAT_CLICK = ED_END + 1.2;
const PASTE = CHAT_CLICK + 0.45;
const TYPE = PASTE + 0.6;
const TYPE_EVERY = 0.034;
const SEND = TYPE + REQUEST.length * TYPE_EVERY + 0.3;
const THINK = SEND + 0.4;
const REPLY_AT = THINK + 1.0;
const REPLY_CPS = 80;
const DIFF = REPLY_AT + REPLY.length / REPLY_CPS - 0.1;
const LOOK = DIFF + 1.2;
const RELOAD = LOOK + 1.3;
const FIXED = RELOAD + 0.35;
const OUTRO = FIXED + 3.0;
const END = OUTRO + 1.2;
export const DURATION = END + 6.2;

// ---------------------------------------------------------------------------------------------
// Geometry helpers.

const onboardPoint = (x: number, y: number): Pt => ({ x: ONBOARD.x + x, y: ONBOARD.y + y });
const GET_STARTED = onboardPoint(502, 598);
const CONTINUE = onboardPoint(510, 598);
const OPEN_SETTINGS = onboardPoint(129, 310);
const TRY_CAPTURE = onboardPoint(496, 598);
const PRO_FOCUS: Pt = { x: CAPTURE.x + 135, y: CAPTURE.y + 104 };
const SCREEN_MID: Pt = { x: SCREEN.w / 2, y: SCREEN.h / 2 + 6 };

const thumbSize = (() => {
  const fit = Math.min(232 / CAPTURE.w, 148 / CAPTURE.h, 1);
  return { w: Math.max(CAPTURE.w * fit, 140), h: Math.max(CAPTURE.h * fit, 84) };
})();
const THUMB_RECT: Rect = { x: plan.thumb.x - thumbSize.w / 2, y: plan.thumb.y - thumbSize.h / 2, ...thumbSize };
const CHAT_COMPOSER: Pt = { x: 1006 + 150, y: 92 + 724 - 50 };

// ---------------------------------------------------------------------------------------------
// The camera. Rest shows the whole screen with a margin; pushes clamp to the screen's edges.

const REST = 0.9;
const cam: CamKey[] = [
  { at: 0, dur: 0, ...PRO_FOCUS, z: 2.5 },
  { at: T.desk, dur: 1.9, ...PRO_FOCUS, z: 2.3 },
  { at: T.pullBack, dur: 1.4, ...SCREEN_MID, z: 1 },
  { at: T.dmg + 0.25, dur: 1.2, x: 756, y: 452, z: 1.6 },
  { at: T.drop + 0.2, dur: 0.6, x: 756, y: 452, z: 1.52 },
  { at: T.dmgClose - 0.1, dur: 1.0, ...SCREEN_MID, z: 1 },
  { at: T.spot + 0.05, dur: 0.9, x: 756, y: 330, z: 1.55 },
  { at: T.spotGo + 0.1, dur: 1.0, ...SCREEN_MID, z: 1.08 },
  { at: T.onboard + 0.15, dur: 1.1, x: 756, y: ONBOARD.y + 320, z: 1.45 },
  { at: T.onboard + 1.9, dur: 1.2, x: 756, y: ONBOARD.y + 32 + 294, z: 2.55 },
  { at: ON.perm - 1.6, dur: 1.0, x: 756, y: ONBOARD.y + 316, z: 1.45 },
  { at: ON.perm + 0.25, dur: 0.9, x: 720, y: 410, z: 1.6 },
  { at: SETTINGS_OUT + 0.15, dur: 0.8, x: 756, y: ONBOARD.y + 316, z: 1.45 },
  { at: ON.shortcuts + 0.2, dur: 1.0, x: ONBOARD.x + 420, y: ONBOARD.y + 230, z: 2.05 },
  { at: ON.shortcuts + 1.3, dur: 2.2, x: ONBOARD.x + 420, y: ONBOARD.y + 400, z: 2.05 },
  { at: ON.mouse - 0.55, dur: 0.6, x: 756, y: ONBOARD.y + 316, z: 1.45 },
  { at: ON.mouse + 0.1, dur: 1.0, x: ONBOARD.x + 300, y: ONBOARD.y + 300, z: 1.85 },
  { at: ON.ready - 0.75, dur: 0.75, x: 756, y: ONBOARD.y + 316, z: 1.45 },
  { at: OV + 0.1, dur: 1.0, x: CAPTURE.x + CAPTURE.w / 2 + 30, y: CAPTURE.y + CAPTURE.h / 2, z: 1.72 },
  { at: OV_END + 0.05, dur: 1.0, x: 420, y: 560, z: 1.22 },
  { at: ED + 0.1, dur: 1.0, ...center(EDITOR_WIN), z: 1.5 },
  { at: ED + 1.3, dur: 1.1, x: CAPTURE.x + 150, y: CAPTURE.y + 170, z: 2.15 },
  { at: ED_END - 0.4, dur: 0.8, ...center(EDITOR_WIN), z: 1.4 },
  { at: ED_END + 0.25, dur: 1.2, x: 1234, y: 520, z: 1.5 },
  { at: SEND + 0.2, dur: 1.4, x: 1234, y: 470, z: 1.5 },
  { at: LOOK, dur: 1.2, ...PRO_FOCUS, z: 2.2 },
  { at: OUTRO, dur: 1.4, ...SCREEN_MID, z: 1 },
];

const cameraTransform = (t: number) => {
  const c = cameraAt(cam, t);
  const s = REST * c.z;
  const sw = SCREEN.w * s;
  const sh = SCREEN.h * s;
  const fit = (size: number, frame: number, focus: number) => {
    if (size <= frame) return (frame - size) / 2;
    return Math.min(0, Math.max(frame - size, frame / 2 - focus * s));
  };
  return { s, x: fit(sw, W, c.x), y: fit(sh, H, c.y), z: c.z };
};

// ---------------------------------------------------------------------------------------------
// The pointer outside the stretches where the harness recorded it.

const START: Pt = { x: 470, y: 452 };
const moves: Move[] = [
  { from: T.desk + 0.3, to: T.desk + 1.3, x: 432, y: 404, bend: 0.3 },
  { from: T.desk + 1.35, to: T.desk + 1.9, x: 500, y: 396, bend: -0.4 },
  { from: T.dmg + 0.6, to: T.grab - 0.1, x: DMG_APP.x + 6, y: DMG_APP.y + 8, bend: 0.12 },
  // The drag follows the background's own curved arrow into Applications.
  { from: T.grab + 0.08, to: T.drop - 0.12, x: DMG_APPS.x - 4, y: DMG_APPS.y + 6, bend: -0.16 },
  { from: T.dmgClose + 0.1, to: T.spot + 0.4, x: 830, y: 600, bend: 0.1 },
  { from: T.onboard + 0.6, to: T.onboard + 2.2, x: GET_STARTED.x + 140, y: GET_STARTED.y + 70, bend: 0.1 },
  { from: ON.perm - 1.3, to: ON.perm - 0.12, x: GET_STARTED.x, y: GET_STARTED.y, bend: 0.15 },
  { from: ON.perm + 0.2, to: ON.perm + 1.05, x: OPEN_SETTINGS.x, y: OPEN_SETTINGS.y, bend: -0.1 },
  { from: SETTINGS_IN + 0.25, to: TOGGLE - 0.12, x: SETTINGS_TOGGLE.x, y: SETTINGS_TOGGLE.y, bend: 0.1 },
  { from: SETTINGS_OUT + 0.15, to: ON.shortcuts - 0.15, x: CONTINUE.x, y: CONTINUE.y, bend: 0.12 },
  { from: ON.shortcuts + 0.3, to: ON.shortcuts + 1.1, x: CONTINUE.x + 90, y: CONTINUE.y + 70, bend: 0.1 },
  { from: ON.mouse - 0.9, to: ON.mouse - 0.15, x: CONTINUE.x, y: CONTINUE.y, bend: 0.1 },
  { from: ON.ready - 0.8, to: ON.ready - 0.15, x: CONTINUE.x, y: CONTINUE.y + 0.5, bend: 0.1 },
  { from: ON.ready + 0.6, to: TRY - 0.15, x: TRY_CAPTURE.x, y: TRY_CAPTURE.y, bend: 0.1 },
];
const clicks = [T.grab, ON.perm - 0.04, ON.perm + 1.15, TOGGLE, ON.shortcuts - 0.04, ON.mouse - 0.04, ON.ready - 0.04, TRY, THUMB_CLICK, CHAT_CLICK];

const lastEditor = editorFrames[editorFrames.length - 1];
const lastOverlay = overlayFrames[overlayFrames.length - 1];
const afterOverlay: Move[] = [{ from: THUMB_IN + 0.55, to: THUMB_CLICK - 0.2, x: plan.thumb.x, y: plan.thumb.y, bend: -0.1 }];
const afterEditor: Move[] = [
  { from: ED_END + 0.3, to: CHAT_CLICK - 0.1, x: CHAT_COMPOSER.x, y: CHAT_COMPOSER.y, bend: 0.08 },
  { from: SEND + 0.5, to: SEND + 1.4, x: CHAT_COMPOSER.x + 120, y: CHAT_COMPOSER.y + 30, bend: 0.1 },
];

const inside = (p: Pt, r: Rect, pad = 0) => p.x >= r.x - pad && p.x <= r.x + r.w + pad && p.y >= r.y - pad && p.y <= r.y + r.h + pad;

const pointer = (t: number): { p: Pt; kind: CursorKind; press: number } => {
  if (t >= OV && t < OV_END) {
    const f = frameAt(overlayFrames, t - OV);
    return { p: f, kind: 'crosshair', press: f.down ? 1 : 0 };
  }
  if (t >= ED && t < ED_END) {
    const f = frameAt(editorFrames, t - ED);
    const canvas: Rect = { x: CAPTURE.x, y: CAPTURE.y, w: CAPTURE.w, h: CAPTURE.h };
    return { p: f, kind: inside(f, canvas, 30) && t - ED > 0.9 ? 'crosshair' : 'arrow', press: f.down ? 1 : pressAt([ED + plan.editor.labelClick], t) };
  }
  if (t >= OV_END && t < ED) {
    return { p: pointerAt(afterOverlay, lastOverlay, t), kind: 'arrow', press: pressAt(clicks, t) };
  }
  if (t >= ED_END) {
    return { p: pointerAt(afterEditor, lastEditor, t), kind: 'arrow', press: pressAt(clicks, t) };
  }
  return { p: pointerAt(moves, START, t), kind: 'arrow', press: pressAt(clicks, t) };
};

// ---------------------------------------------------------------------------------------------
// Keys and captions, set over the frame rather than the screen.

const keys: { at: number; label: string[] }[] = [
  { at: T.spot - 0.1, label: ['⌘', 'Space'] },
  { at: T.spotGo, label: ['Return'] },
  ...editorFrames.filter((f) => f.key).map((f) => ({ at: ED + f.t, label: [f.key === 'return' ? 'Return' : f.key!] })),
  { at: PASTE, label: ['⌘', 'V'] },
  { at: SEND, label: ['Return'] },
];

const captions: { from: number; to: number; text: string }[] = [
  { from: T.dmg + 1.0, to: T.drop + 0.6, text: 'Drag it into Applications.' },
  { from: ON.perm + 0.5, to: SETTINGS_OUT, text: 'One permission. macOS asks once.' },
  { from: ON.shortcuts + 0.5, to: ON.mouse - 0.3, text: 'Every capture has a shortcut that works from any app.' },
  { from: ON.mouse + 0.5, to: ON.ready - 0.2, text: 'Or put it on a mouse button.' },
  { from: OV + 0.6, to: OV_END + 0.1, text: 'The screen holds still while you drag.' },
  { from: THUMB_IN + 0.3, to: THUMB_CLICK, text: 'It’s on the clipboard already.' },
  { from: ED + 1.5, to: ED_END, text: 'Point at it, then Return copies it.' },
  { from: PASTE + 0.1, to: SEND - 0.1, text: 'Paste it wherever you’re working.' },
];

const KeyCap: React.FC<{ label: string }> = ({ label }) => (
  <div
    style={{
      minWidth: 60,
      height: 60,
      padding: label.length > 1 ? '0 20px' : 0,
      boxSizing: 'border-box',
      borderRadius: 14,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      font: `500 ${label.length > 1 ? 21 : 27}px ${UI_FONT}`,
      color: '#f4f2ee',
      background: 'linear-gradient(180deg, #33322f, #252422)',
      boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.12), 0 0 0 0.5px rgba(0,0,0,0.6), 0 3px 0 #141412, 0 10px 24px rgba(0,0,0,0.3)',
    }}
  >
    {label}
  </div>
);

const Keys: React.FC<{ t: number }> = ({ t }) => {
  const active = keys.filter((k) => t >= k.at - 0.02 && t < k.at + 0.9).slice(-1)[0];
  if (!active) return null;
  const a = window01(t, active.at - 0.02, active.at + 0.9, 0.12, 0.3);
  const press = t >= active.at && t < active.at + 0.16 ? 1 : 0;
  return (
    <div style={{ position: 'absolute', left: 0, right: 0, bottom: 124, display: 'flex', justifyContent: 'center', gap: 10, opacity: a, transform: `translateY(${(1 - a) * 10 + press * 2}px)` }}>
      {active.label.map((l, i) => (
        <KeyCap key={i} label={l} />
      ))}
    </div>
  );
};

const Caption: React.FC<{ t: number }> = ({ t }) => {
  const c = captions.find((c) => t >= c.from && t < c.to);
  if (!c) return null;
  const a = window01(t, c.from, c.to, 0.35, 0.3);
  return (
    <div style={{ position: 'absolute', left: 0, right: 0, bottom: 52, display: 'flex', justifyContent: 'center', opacity: a }}>
      <div
        style={{
          padding: '10px 20px',
          borderRadius: 999,
          font: `500 21px ${DISPLAY_FONT}`,
          letterSpacing: -0.2,
          color: '#f6f4ef',
          background: 'rgba(25,25,23,0.84)',
          backdropFilter: 'blur(20px)',
          boxShadow: '0 0 0 0.5px rgba(255,255,255,0.08), 0 10px 30px rgba(0,0,0,0.25)',
          transform: `translateY(${(1 - a) * 8}px)`,
        }}
      >
        {c.text}
      </div>
    </div>
  );
};

// ---------------------------------------------------------------------------------------------
// The screen at time t.

const appear = (t: number, at: number, d = 0.26) => easeOut(clamp01((t - at) / d));
const windowOpen = (t: number, at: number, close?: number): React.CSSProperties => {
  const o = appear(t, at, 0.28);
  const c = close === undefined ? 0 : ramp(t, close, close + 0.2);
  return { opacity: o * (1 - c), transform: `scale(${lerp(0.94, 1, o) - 0.03 * c})` };
};

const typed = (text: string, t: number, at: number, every: number) => text.slice(0, Math.max(0, Math.min(text.length, Math.floor((t - at) / every) + 1)));

const Screen: React.FC<{ t: number }> = ({ t }) => {
  // Which app is frontmost decides the menu bar and which window looks key.
  let app = 'Safari';
  let front: 'browser' | 'chat' | 'none' = 'browser';
  if (t >= T.dmg && t < T.dmgClose + 0.2) (app = 'Finder'), (front = 'none');
  if (t >= T.spotGo && t < ONBOARD_OUT) (app = 'Shotput'), (front = 'none');
  if (t >= ED && t < ED_END) (app = 'Shotput'), (front = 'none');
  if (t >= CHAT_CLICK - 0.05) (app = 'Chat'), (front = 'chat');
  if (t >= SETTINGS_IN && t < SETTINGS_OUT) (app = 'System Settings'), (front = 'none');

  const chat = {
    ...idleChat,
    focus: t >= CHAT_CLICK && t < SEND,
    attach: appear(t, PASTE + 0.04, 0.32),
    draft: t >= TYPE ? typed(REQUEST, t, TYPE, TYPE_EVERY) : '',
    caret: t >= CHAT_CLICK && t < SEND && Math.floor((t - CHAT_CLICK) * 1.9) % 2 === 0,
    sent: appear(t, SEND + 0.02, 0.45),
    thinking: window01(t, THINK, REPLY_AT + 0.1, 0.2, 0.15),
    reply: t >= REPLY_AT ? Math.min(REPLY.length, (t - REPLY_AT) * REPLY_CPS) : 0,
    diff: appear(t, DIFF, 0.4),
    image: staticFile('frames/annotated.png'),
    imageSize: { w: CAPTURE.w, h: CAPTURE.h },
  };

  const desktop = {
    ...baseDesktop,
    app,
    front,
    shotput: appear(t, T.spotGo + 0.45, 0.3),
    shotputInDock: appear(t, T.spotGo + 0.1, 0.35),
    chat,
    fix: t >= FIXED ? appear(t, FIXED, 0.14) : 0,
    reload: t >= RELOAD ? clamp01((t - RELOAD) / 0.45) : 0,
  };

  const overlay = t >= OV && t < OV_END ? frameAt(overlayFrames, t - OV) : null;
  const ptr = pointer(t);

  // Installer drag.
  const dragging = t >= T.grab && t < T.drop;
  const dropShrink = ramp(t, T.drop, T.drop + 0.22);
  const hot = dragging ? clamp01(1 - (Math.hypot(ptr.p.x - DMG_APPS.x, ptr.p.y - DMG_APPS.y) - 50) / 40) : 0;

  // Thumbnail flight from the capture into its corner.
  const fly = bezier(0.2, 0.9, 0.25, 1)(clamp01((t - THUMB_IN) / 0.42));
  const cap = center(CAPTURE);
  const thumbRect: Rect = {
    ...THUMB_RECT,
    x: lerp(cap.x - THUMB_RECT.w / 2, THUMB_RECT.x, fly),
    y: lerp(cap.y - THUMB_RECT.h / 2, THUMB_RECT.y, fly),
  };
  const thumbHover = ramp(t, THUMB_CLICK - 0.5, THUMB_CLICK - 0.3, easeOut);
  const thumbOpacity = Math.min(fly * 1.4, 1 - ramp(t, THUMB_CLICK + 0.05, THUMB_CLICK + 0.2));

  // Spotlight.
  const spotIn = appear(t, T.spot, 0.18) * (1 - ramp(t, T.spotGo + 0.05, T.spotGo + 0.2));

  // Editor window.
  const editor = t >= ED && t < ED_END + 0.25 ? frameAt(editorFrames, Math.min(t - ED, plan.editor.end)) : null;

  return (
    <div style={{ position: 'absolute', width: SCREEN.w, height: SCREEN.h, overflow: 'hidden', background: '#000' }}>
      <Desktop s={desktop}>
        {t >= T.dmg && t < T.dmgClose + 0.25 && (
          <div style={{ position: 'absolute', inset: 0, transformOrigin: '756px 450px', ...windowOpen(t, T.dmg, T.dmgClose) }}>
            <InstallerWindow selected={t >= T.grab - 0.02 && t < T.drop} hot={hot} installed={ramp(t, T.drop + 0.15, T.drop + 0.45, easeOut)} />
          </div>
        )}
        {(dragging || (t >= T.drop && t < T.drop + 0.25)) && (
          <DragGhost x={dragging ? ptr.p.x : DMG_APPS.x} y={dragging ? ptr.p.y : DMG_APPS.y} scale={1 - 0.6 * dropShrink} opacity={0.6 * (1 - dropShrink)} />
        )}
        {spotIn > 0 && (
          <div style={{ position: 'absolute', inset: 0, opacity: spotIn, transform: `scale(${lerp(0.97, 1, spotIn)})`, transformOrigin: '756px 280px' }}>
            <Spotlight query={t >= T.spot + 0.3 ? typed('Shotput', t, T.spot + 0.3, 0.07) : ''} caret={Math.floor(t * 2) % 2 === 0 || t > T.spot + 0.3} results={appear(t, T.spot + 0.34, 0.12)} />
          </div>
        )}
        {t >= T.onboard && t < ONBOARD_OUT + 0.25 && (
          <div
            style={{
              position: 'absolute',
              left: ONBOARD.x,
              top: ONBOARD.y,
              width: ONBOARD.w,
              height: ONBOARD.h,
              borderRadius: 16,
              overflow: 'hidden',
              boxShadow: '0 0 0 0.5px rgba(0,0,0,0.22), 0 2px 6px rgba(0,0,0,0.08), 0 26px 70px rgba(0,0,0,0.28)',
              ...windowOpen(t, T.onboard, ONBOARD_OUT),
            }}
          >
            <Img src={staticFile(`frames/onboard/${frameAt(onboardFrames, t - T.onboard).file}`)} style={{ width: ONBOARD.w, height: ONBOARD.h, display: 'block' }} />
          </div>
        )}
        {t >= SETTINGS_IN && t < SETTINGS_OUT + 0.25 && (
          <div style={{ position: 'absolute', inset: 0, transformOrigin: '704px 406px', ...windowOpen(t, SETTINGS_IN, SETTINGS_OUT) }}>
            <SettingsWindow on={ramp(t, TOGGLE, TOGGLE + 0.18)} />
          </div>
        )}
        {t >= THUMB_IN && t < THUMB_CLICK + 0.25 && (
          <Thumbnail src={staticFile('frames/capture.png')} rect={thumbRect} opacity={thumbOpacity} hover={thumbHover} press={pressAt([THUMB_CLICK], t)} />
        )}
        {editor && (
          <div
            style={{
              position: 'absolute',
              left: EDITOR_WIN.x,
              top: EDITOR_WIN.y,
              width: EDITOR_WIN.w,
              height: EDITOR_WIN.h,
              borderRadius: 24,
              overflow: 'hidden',
              boxShadow: '0 0 0 0.5px rgba(0,0,0,0.22), 0 2px 6px rgba(0,0,0,0.08), 0 26px 70px rgba(0,0,0,0.28)',
              ...windowOpen(t, ED, ED_END),
            }}
          >
            <Img src={staticFile(`frames/editor/${editor.file}`)} style={{ width: EDITOR_WIN.w, height: EDITOR_WIN.h, display: 'block' }} />
            {/* The toolbar's prominent Done is tinted glass, which offscreen renders cannot see. */}
            <div
              style={{
                position: 'absolute',
                left: 695.5,
                top: 7.5,
                width: 56.5,
                height: 36.5,
                borderRadius: 18.25,
                background: '#0a7cff',
                color: '#fff',
                font: `500 13px ${UI_FONT}`,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                boxShadow: 'inset 0 0.5px 0 rgba(255,255,255,0.35)',
              }}
            >
              Done
            </div>
          </div>
        )}
      </Desktop>
      {overlay && <Img src={staticFile(`frames/overlay/${overlay.file}`)} style={{ position: 'absolute', left: 0, top: 0, width: SCREEN.w, height: SCREEN.h }} />}
      <Cursor x={ptr.p.x} y={ptr.p.y} kind={ptr.kind} press={ptr.press} />
    </div>
  );
};

// ---------------------------------------------------------------------------------------------
// Title and end cards.

const STAGE = '#121211';

const Title: React.FC<{ t: number }> = ({ t }) => {
  const icon = appear(t, 0.5, 1.1);
  const word = appear(t, 1.0, 0.9);
  const line = appear(t, 1.8, 0.9);
  const out = ramp(t, 3.6, T.desk);
  return (
    <AbsoluteFill style={{ background: STAGE, alignItems: 'center', justifyContent: 'center', opacity: 1 - out }}>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', transform: `scale(${1 + out * 0.04})` }}>
        <Img
          src={staticFile('icons/shotput.png')}
          style={{ width: 168, height: 168, opacity: icon, transform: `translateY(${(1 - icon) * 14}px) scale(${lerp(0.94, 1, icon)})`, filter: `blur(${(1 - icon) * 8}px)` }}
        />
        <div style={{ marginTop: 26, font: `600 64px ${DISPLAY_FONT}`, letterSpacing: -2, color: '#f4f2ee', opacity: word, transform: `translateY(${(1 - word) * 10}px)` }}>Shotput</div>
        <div style={{ marginTop: 12, font: `400 26px ${DISPLAY_FONT}`, letterSpacing: -0.3, color: '#9d988d', opacity: line, transform: `translateY(${(1 - line) * 8}px)` }}>
          Screenshots for pasting.
        </div>
      </div>
    </AbsoluteFill>
  );
};

const EndCard: React.FC<{ t: number }> = ({ t }) => {
  const a = ramp(t, END, END + 0.7);
  const icon = appear(t, END + 0.3, 1.0);
  const words = ['Press.', 'Drag.', 'Paste.'];
  const sub = appear(t, END + 2.2, 0.8);
  const fade = ramp(t, DURATION - 0.8, DURATION - 0.05);
  if (a <= 0) return null;
  return (
    <AbsoluteFill style={{ background: STAGE, opacity: a * (1 - fade), alignItems: 'center', justifyContent: 'center' }}>
      <Img src={staticFile('icons/shotput.png')} style={{ width: 132, height: 132, opacity: icon, transform: `translateY(${(1 - icon) * 12}px)` }} />
      <div style={{ display: 'flex', gap: 22, marginTop: 30 }}>
        {words.map((w, i) => {
          const p = appear(t, END + 0.9 + i * 0.32, 0.6);
          return (
            <div key={w} style={{ font: `600 60px ${DISPLAY_FONT}`, letterSpacing: -1.8, color: '#f4f2ee', opacity: p, transform: `translateY(${(1 - p) * 14}px)` }}>
              {w}
            </div>
          );
        })}
      </div>
      <div style={{ marginTop: 26, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10, opacity: sub }}>
        <div style={{ font: `400 23px ${DISPLAY_FONT}`, color: '#b7b2a8', letterSpacing: -0.2 }}>Shotput for macOS. Free and open source.</div>
        <div style={{ font: `500 17px ${UI_FONT}`, color: '#7d786f', letterSpacing: 0.2 }}>github.com/keshav-exe/shotput</div>
      </div>
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------------------------------------

export const Launch: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  const c = cameraTransform(t);
  const deskIn = ramp(t, T.desk - 0.5, T.desk + 0.35);
  // Corners and shadow belong to the screen at rest; they fade as the camera pushes in.
  const framed = clamp01((1.35 - c.z) / 0.35);
  return (
    <AbsoluteFill style={{ background: STAGE, overflow: 'hidden' }}>
      {t >= T.desk - 0.6 && t < END + 0.8 && (
        <div
          style={{
            position: 'absolute',
            left: c.x,
            top: c.y,
            width: SCREEN.w,
            height: SCREEN.h,
            transform: `scale(${c.s})`,
            transformOrigin: '0 0',
            borderRadius: 14 * framed,
            overflow: 'hidden',
            boxShadow: `0 0 0 1px rgba(255,255,255,${0.06 * framed}), 0 40px 120px rgba(0,0,0,${0.55 * framed})`,
            opacity: deskIn,
          }}
        >
          <Screen t={t} />
        </div>
      )}
      <Keys t={t} />
      <Caption t={t} />
      {t < T.desk + 0.1 && <Title t={t} />}
      <EndCard t={t} />
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------------------------------------
// For the ad cut: one moment of the film, by its own clock, with the camera it had then.

export const SRC = {
  ...T, ...ON, SETTINGS_IN, TOGGLE, SETTINGS_OUT, TRY, OV, OV_END, THUMB_IN, THUMB_CLICK, ED, ED_END,
  CHAT_CLICK, PASTE, TYPE, SEND, THINK, REPLY_AT, DIFF, LOOK, RELOAD, FIXED, OUTRO,
};

export const Shot: React.FC<{ t: number; punch?: number; keys?: boolean }> = ({ t, punch = 0, keys = true }) => {
  const c = cameraTransform(t);
  const framed = clamp01((1.35 - c.z) / 0.35);
  return (
    <AbsoluteFill style={{ background: STAGE, overflow: 'hidden' }}>
      {/* A cut lands with a small push about the frame's centre. */}
      <AbsoluteFill style={{ transform: `scale(${1 + punch})`, transformOrigin: `${W / 2}px ${H / 2}px` }}>
        <div
          style={{
            position: 'absolute',
            left: c.x,
            top: c.y,
            width: SCREEN.w,
            height: SCREEN.h,
            transform: `scale(${c.s})`,
            transformOrigin: '0 0',
            borderRadius: 14 * framed,
            overflow: 'hidden',
            boxShadow: `0 0 0 1px rgba(255,255,255,${0.06 * framed}), 0 40px 120px rgba(0,0,0,${0.55 * framed})`,
          }}
        >
          <Screen t={t} />
        </div>
      </AbsoluteFill>
      {keys && <Keys t={t} />}
    </AbsoluteFill>
  );
};
