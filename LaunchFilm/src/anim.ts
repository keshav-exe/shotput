// Timing helpers. Everything is in seconds; the composition converts frames to time once.

export const clamp01 = (t: number) => Math.min(1, Math.max(0, t));
export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

// A cubic-bezier evaluator, so curves can be written the way CSS and Core Animation write them.
export const bezier = (x1: number, y1: number, x2: number, y2: number) => {
  const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx;
  const cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
  const x = (t: number) => ((ax * t + bx) * t + cx) * t;
  const y = (t: number) => ((ay * t + by) * t + cy) * t;
  const dx = (t: number) => (3 * ax * t + 2 * bx) * t + cx;
  return (p: number) => {
    p = clamp01(p);
    let t = p;
    for (let i = 0; i < 8; i++) {
      const e = x(t) - p;
      const d = dx(t);
      if (Math.abs(e) < 1e-5 || Math.abs(d) < 1e-6) break;
      t -= e / d;
    }
    return y(clamp01(t));
  };
};

export const easeInOut = bezier(0.65, 0, 0.35, 1);
// Camera moves: a quick, confident start and a long settle, like a operator easing off.
export const camEase = bezier(0.45, 0.05, 0.15, 1);
export const easeOut = bezier(0.2, 0.9, 0.25, 1);
export const pointerEase = bezier(0.4, 0.0, 0.2, 1);

export const ramp = (t: number, a: number, b: number, ease = easeInOut) => ease(clamp01((t - a) / (b - a)));

/** 0 → 1 over [a, a+inD], holds, then 1 → 0 over [b-outD, b]. */
export const window01 = (t: number, a: number, b: number, inD = 0.25, outD = 0.25) =>
  Math.min(ramp(t, a, a + inD, easeOut), 1 - ramp(t, b - outD, b));

export type Pt = { x: number; y: number };

export const arc = (a: Pt, b: Pt, u: number, bend = 0.12): Pt => {
  const mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2;
  const c = { x: mx - (b.y - a.y) * bend, y: my + (b.x - a.x) * bend };
  return {
    x: (1 - u) * (1 - u) * a.x + 2 * (1 - u) * u * c.x + u * u * b.x,
    y: (1 - u) * (1 - u) * a.y + 2 * (1 - u) * u * c.y + u * u * b.y,
  };
};

// Pointer moves: hold at the last target until a move starts, then travel along a slight arc.
export type Move = { from: number; to: number; x: number; y: number; bend?: number };

export const pointerAt = (moves: Move[], start: Pt, t: number): Pt => {
  let p = start;
  for (const m of moves) {
    if (t < m.from) break;
    const u = pointerEase(clamp01((t - m.from) / (m.to - m.from)));
    const next = arc(p, { x: m.x, y: m.y }, u, m.bend ?? 0.1);
    if (t >= m.to) p = { x: m.x, y: m.y };
    else return next;
  }
  return p;
};

/** A click: the pointer dips over 60 ms and comes back over 120 ms. */
export const pressAt = (clicks: number[], t: number) => {
  let v = 0;
  for (const c of clicks) {
    if (t >= c - 0.06 && t < c) v = Math.max(v, (t - (c - 0.06)) / 0.06);
    else if (t >= c && t < c + 0.12) v = Math.max(v, 1 - (t - c) / 0.12);
  }
  return v;
};

// Camera keys: at `at`, start moving to (x, y, zoom) over `dur`. Zoom travels in log space so a
// push from 1x to 2x feels as even as one from 2x to 4x.
export type CamKey = { at: number; dur: number; x: number; y: number; z: number };

export const cameraAt = (keys: CamKey[], t: number) => {
  let c = { x: keys[0].x, y: keys[0].y, z: keys[0].z };
  for (const k of keys.slice(1)) {
    if (t < k.at) break;
    const u = camEase(clamp01((t - k.at) / k.dur));
    c = {
      x: lerp(c.x, k.x, u),
      y: lerp(c.y, k.y, u),
      z: Math.exp(lerp(Math.log(c.z), Math.log(k.z), u)),
    };
  }
  return c;
};

/** Picks the stamped frame shown at time t: the last one at or before it. */
export const frameAt = <F extends { t: number }>(frames: F[], t: number): F => {
  let lo = 0, hi = frames.length - 1;
  if (t <= frames[0].t) return frames[0];
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (frames[mid].t <= t) lo = mid;
    else hi = mid - 1;
  }
  return frames[lo];
};
