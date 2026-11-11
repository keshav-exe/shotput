import React from 'react';
import { Img, staticFile } from 'remotion';
import { MENU_BAR, SCREEN } from '../layout';

export const UI_FONT = '-apple-system, "SF Pro Text", "SF Pro", system-ui, sans-serif';
export const DISPLAY_FONT = '-apple-system, "SF Pro Display", "SF Pro", system-ui, sans-serif';
export const MONO_FONT = 'ui-monospace, "SF Mono", Menlo, monospace';

// A quiet wallpaper in the product's own colours: cool sky at the top, warm paper at the bottom,
// with two soft light pools so the windows have something to sit on. Grain stops banding.
export const Wallpaper: React.FC = () => (
  <div style={{ position: 'absolute', inset: 0, overflow: 'hidden', background: '#d9dfe4' }}>
    <div
      style={{
        position: 'absolute',
        inset: 0,
        background:
          'radial-gradient(120% 90% at 18% 8%, #c3d3e2 0%, rgba(195,211,226,0) 60%),' +
          'radial-gradient(90% 80% at 92% 30%, #d7d2e6 0%, rgba(215,210,230,0) 55%),' +
          'radial-gradient(130% 90% at 50% 112%, #efe3cf 0%, rgba(239,227,207,0) 62%),' +
          'linear-gradient(180deg, #ccd8e3 0%, #e4e1db 62%, #ece4d6 100%)',
      }}
    />
    <svg width={SCREEN.w} height={SCREEN.h} style={{ position: 'absolute', inset: 0, opacity: 0.22, mixBlendMode: 'soft-light' }}>
      <filter id="grain">
        <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" stitchTiles="stitch" />
        <feColorMatrix type="saturate" values="0" />
      </filter>
      <rect width="100%" height="100%" filter="url(#grain)" />
    </svg>
  </div>
);

const Apple: React.FC<{ size?: number }> = ({ size = 14 }) => (
  <svg width={size} height={size * 1.2} viewBox="0 0 170 204" style={{ display: 'block' }}>
    <path
      fill="currentColor"
      d="M150.4 69.6c-1 .8-19.2 11-19.2 33.8 0 26.4 23.2 35.8 23.9 36-.1.6-3.7 12.8-12.2 25.2-7.6 11-15.6 21.9-27.6 21.9s-15.1-7-29-7c-13.5 0-18.3 7.2-29.3 7.2s-18.6-10.2-27.4-22.6C19.3 149.6 11 126.9 11 105.4c0-34.5 22.4-52.8 44.5-52.8 11.7 0 21.5 7.7 28.9 7.7 7 0 17.9-8.2 31.3-8.2 5.1 0 23.3.5 34.7 17.5zM109 37.4c5.5-6.6 9.4-15.7 9.4-24.8 0-1.3-.1-2.5-.3-3.6-9 .3-19.7 6-26.1 13.5-5 5.7-9.7 14.8-9.7 24 0 1.4.2 2.8.3 3.2.6.1 1.5.2 2.4.2 8.1 0 18.3-5.4 24-12.5z"
    />
  </svg>
);

// The menu bar glyph Shotput draws: the capture corners with an arrow, as in the app icon.
export const ShotputGlyph: React.FC<{ size?: number; color?: string }> = ({ size = 16, color = 'currentColor' }) => (
  <svg width={size} height={size} viewBox="0 0 16 16" fill="none" stroke={color} strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round">
    <path d="M2 5.5V2h3.5M10.5 2H14v3.5M2 10.5V14h3.5" />
    <path d="M8.6 8.6l4.6 4.6M13.4 9.6v3.8H9.6" />
  </svg>
);

const StatusIcon: React.FC<{ d: string; w?: number }> = ({ d, w = 18 }) => (
  <svg width={w} height={14} viewBox={`0 0 ${w} 14`} fill="currentColor">
    <path d={d} />
  </svg>
);

export const MenuBar: React.FC<{ app: string; menus: string[]; shotput: number; shotputActive?: boolean; time?: string }> = ({
  app,
  menus,
  shotput,
  shotputActive,
  time = 'Thu 12 Nov  9:41',
}) => (
  <div
    style={{
      position: 'absolute',
      left: 0,
      top: 0,
      width: SCREEN.w,
      height: MENU_BAR,
      display: 'flex',
      alignItems: 'center',
      padding: '0 14px 0 20px',
      boxSizing: 'border-box',
      font: `500 13px ${UI_FONT}`,
      color: 'rgba(20,20,22,0.92)',
      background: 'rgba(246,246,248,0.42)',
      backdropFilter: 'blur(30px) saturate(1.6)',
      letterSpacing: -0.08,
    }}
  >
    <Apple size={13} />
    <span style={{ fontWeight: 700, marginLeft: 20 }}>{app}</span>
    {menus.map((m) => (
      <span key={m} style={{ marginLeft: 20 }}>
        {m}
      </span>
    ))}
    <div style={{ flex: 1 }} />
    <div style={{ display: 'flex', alignItems: 'center', gap: 18 }}>
      <div
        style={{
          opacity: shotput,
          transform: `scale(${0.6 + 0.4 * shotput})`,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          width: 26,
          height: 22,
          borderRadius: 6,
          background: shotputActive ? 'rgba(0,0,0,0.12)' : 'transparent',
        }}
      >
        <ShotputGlyph size={15} />
      </div>
      <StatusIcon w={22} d="M2 3.5h15.5a1.5 1.5 0 011.5 1.5v4a1.5 1.5 0 01-1.5 1.5H2A1.5 1.5 0 01.5 9V5A1.5 1.5 0 012 3.5zm0 1A.5.5 0 001.5 5v4a.5.5 0 00.5.5h15.5A.5.5 0 0018 9V5a.5.5 0 00-.5-.5zm1 1h11v3H3zM20 5.5h.6a.6.6 0 01.6.6v1.8a.6.6 0 01-.6.6H20z" />
      <StatusIcon d="M9 11.8a1.3 1.3 0 110 .01zM4.9 8.4a5.8 5.8 0 018.2 0l-.9.9a4.5 4.5 0 00-6.4 0zM2.3 5.8a9.5 9.5 0 0113.4 0l-.9.9a8.2 8.2 0 00-11.6 0z" />
      <StatusIcon d="M7.5 2a5.5 5.5 0 014.4 8.8l3.4 3.4-.9.9-3.4-3.4A5.5 5.5 0 117.5 2zm0 1.2a4.3 4.3 0 100 8.6 4.3 4.3 0 000-8.6z" w={16} />
      <span style={{ fontVariantNumeric: 'tabular-nums', whiteSpace: 'pre' }}>{time}</span>
    </div>
  </div>
);

export const DOCK_APPS = ['Finder', 'Safari', 'Chat', 'Mail', 'Calendar', 'Notes', 'Music', 'Terminal', 'Settings'];

export const ChatIcon: React.FC<{ size: number }> = ({ size }) => (
  <div
    style={{
      width: size,
      height: size,
      borderRadius: size * 0.225,
      background: 'linear-gradient(160deg, #3a3936 0%, #1d1c1a 100%)',
      boxShadow: 'inset 0 0 0 0.5px rgba(255,255,255,0.12)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      transform: 'scale(0.82)',
    }}
  >
    <svg width={size * 0.5} height={size * 0.5} viewBox="0 0 24 24">
      <path d="M4 5.5A2.5 2.5 0 016.5 3h11A2.5 2.5 0 0120 5.5v8a2.5 2.5 0 01-2.5 2.5H11l-4.6 3.6c-.4.3-1 0-1-.5V16h0A2.5 2.5 0 014 13.5z" fill="#f4efe6" />
      <circle cx="9" cy="9.6" r="1.2" fill="#1d1c1a" />
      <circle cx="12" cy="9.6" r="1.2" fill="#1d1c1a" />
      <circle cx="15" cy="9.6" r="1.2" fill="#1d1c1a" />
    </svg>
  </div>
);

export const Dock: React.FC<{ shotput: number; running: string[] }> = ({ shotput, running }) => {
  const size = 50;
  const apps = [...DOCK_APPS];
  const items = apps.map((a) => ({ name: a, appear: 1 }));
  items.push({ name: 'Shotput', appear: shotput });
  return (
    <div
      style={{
        position: 'absolute',
        bottom: 6,
        left: '50%',
        transform: 'translateX(-50%)',
        display: 'flex',
        alignItems: 'flex-end',
        padding: '6px 8px 6px',
        borderRadius: 22,
        background: 'rgba(250,250,252,0.32)',
        backdropFilter: 'blur(28px) saturate(1.7)',
        boxShadow: 'inset 0 0 0 0.5px rgba(255,255,255,0.65), 0 0 0 0.5px rgba(0,0,0,0.12), 0 10px 30px rgba(0,0,0,0.12)',
      }}
    >
      {items.map((it) => (
        <div
          key={it.name}
          style={{
            width: (size + 6) * it.appear,
            height: size + 6,
            display: 'flex',
            justifyContent: 'center',
            alignItems: 'flex-start',
            position: 'relative',
            opacity: it.appear,
          }}
        >
          <div style={{ transform: `scale(${it.appear})`, transformOrigin: 'bottom center' }}>
            {it.name === 'Chat' ? (
              <ChatIcon size={size} />
            ) : (
              <Img src={staticFile(`icons/${it.name}.png`)} style={{ width: size, height: size, display: 'block' }} />
            )}
          </div>
          {running.includes(it.name) && (
            <div style={{ position: 'absolute', bottom: -1, width: 4, height: 4, borderRadius: 2, background: 'rgba(0,0,0,0.55)' }} />
          )}
        </div>
      ))}
      <div style={{ width: 1, alignSelf: 'stretch', margin: '4px 8px', background: 'rgba(0,0,0,0.14)' }} />
      <Img src={staticFile('icons/Trash.png')} style={{ width: size, height: size, margin: '0 3px 6px' }} />
    </div>
  );
};

// Pointers, drawn to match the system's: a black arrow with a white keyline, and the crosshair.
export type CursorKind = 'arrow' | 'crosshair' | 'ibeam' | 'hand' | 'none';

export const Cursor: React.FC<{ x: number; y: number; kind: CursorKind; press?: number }> = ({ x, y, kind, press = 0 }) => {
  if (kind === 'none') return null;
  const s = 1 - press * 0.12;
  const shadow = 'drop-shadow(0 1.5px 2px rgba(0,0,0,0.35))';
  if (kind === 'crosshair') {
    return (
      <svg
        width={25}
        height={25}
        viewBox="0 0 25 25"
        style={{ position: 'absolute', left: x - 12.5, top: y - 12.5, filter: shadow, transform: `scale(${s})` }}
      >
        <path d="M12.5 1v23M1 12.5h23" stroke="white" strokeWidth={3.4} strokeLinecap="square" />
        <path d="M12.5 2v21M2 12.5h21" stroke="black" strokeWidth={1.3} />
      </svg>
    );
  }
  if (kind === 'ibeam') {
    return (
      <svg width={11} height={22} viewBox="0 0 11 22" style={{ position: 'absolute', left: x - 5.5, top: y - 11, filter: shadow }}>
        <path d="M1.5 1.5c2 0 4 .6 4 2.5v14c0 1.9-2 2.5-4 2.5M9.5 1.5c-2 0-4 .6-4 2.5v14c0 1.9 2 2.5 4 2.5M3 11h5" stroke="white" strokeWidth={3} fill="none" strokeLinecap="round" />
        <path d="M1.5 1.5c2 0 4 .6 4 2.5v14c0 1.9-2 2.5-4 2.5M9.5 1.5c-2 0-4 .6-4 2.5v14c0 1.9 2 2.5 4 2.5M3 11h5" stroke="black" strokeWidth={1.2} fill="none" strokeLinecap="round" />
      </svg>
    );
  }
  return (
    <svg
      width={24}
      height={34}
      viewBox="0 0 24 34"
      style={{
        position: 'absolute',
        left: x - 3,
        top: y - 2,
        filter: shadow,
        transform: `scale(${s})`,
        transformOrigin: '3px 2px',
      }}
    >
      <path
        d="M3 2 L3 26.2 L8.6 20.9 L12.4 29.6 L16.6 27.8 L12.9 19.3 L20.6 19.3 Z"
        fill="black"
        stroke="white"
        strokeWidth={1.7}
        strokeLinejoin="round"
      />
    </svg>
  );
};
