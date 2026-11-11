import React from 'react';
import { Img, staticFile } from 'remotion';
import { DMG, DMG_TITLE, Rect } from '../layout';
import { UI_FONT } from './Desktop';
import { TrafficLights, Window } from './Window';

const Alias: React.FC = () => (
  <svg width={22} height={22} viewBox="0 0 22 22" style={{ position: 'absolute', left: 6, bottom: 6 }}>
    <rect x={1} y={1} width={20} height={20} rx={5} fill="#fff" stroke="rgba(0,0,0,0.25)" strokeWidth={0.8} />
    <path d="M7 15c0-4 2.5-6.5 7-6.5M10.5 5.5l3.8 3-3.8 3" stroke="#222" strokeWidth={1.8} fill="none" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

const FinderIcon: React.FC<{ src: string; label: string; selected?: boolean; hot?: number; alias?: boolean; dim?: number }> = ({ src, label, selected, hot = 0, alias, dim = 1 }) => (
  <div style={{ width: 150, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6 }}>
    <div
      style={{
        position: 'relative',
        width: 124,
        height: 124,
        borderRadius: 14,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        background: selected || hot > 0 ? `rgba(0,0,0,${selected ? 0.1 : 0.12 * hot})` : 'transparent',
      }}
    >
      <Img src={src} style={{ width: 112, height: 112, opacity: dim }} />
      {alias && <Alias />}
    </div>
    <div
      style={{
        font: `500 13px ${UI_FONT}`,
        color: selected ? '#fff' : '#26251f',
        background: selected ? '#0a7cff' : 'transparent',
        padding: '1px 6px',
        borderRadius: 4,
      }}
    >
      {label}
    </div>
  </div>
);

export const InstallerWindow: React.FC<{ selected: boolean; hot: number; installed: number }> = ({ selected, hot, installed }) => (
  <Window rect={DMG} radius={14} background="#f4f2ee">
    <div style={{ position: 'absolute', left: 0, right: 0, top: 0, height: DMG_TITLE, background: '#efede9', borderBottom: '1px solid rgba(0,0,0,0.07)' }}>
      <TrafficLights x={12} y={8} />
      <div style={{ position: 'absolute', left: 0, right: 0, top: 6, textAlign: 'center', font: `600 13px ${UI_FONT}`, color: '#2b2a26' }}>Shotput</div>
    </div>
    <Img src={staticFile('installer-bg.png')} style={{ position: 'absolute', left: 0, top: DMG_TITLE, width: 660, height: 400 }} />
    <div style={{ position: 'absolute', left: 165 - 75, top: DMG_TITLE + 200 - 62 }}>
      <FinderIcon src={staticFile('icons/shotput.png')} label="Shotput" selected={selected} />
    </div>
    <div style={{ position: 'absolute', left: 495 - 75, top: DMG_TITLE + 200 - 62 }}>
      <FinderIcon src={staticFile('icons/Applications.png')} label="Applications" hot={hot} alias />
      <div
        style={{
          position: 'absolute',
          left: 62,
          top: 100,
          width: 26,
          height: 26,
          borderRadius: 13,
          background: '#28c840',
          opacity: installed,
          transform: `scale(${0.5 + 0.5 * installed})`,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          boxShadow: '0 0 0 2px #f4f2ee',
        }}
      >
        <svg width={14} height={14} viewBox="0 0 14 14">
          <path d="M3 7.4l2.6 2.6L11 4.4" stroke="#fff" strokeWidth={2} fill="none" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </div>
    </div>
  </Window>
);

// The icon as Finder drags it: a translucent copy under the pointer.
export const DragGhost: React.FC<{ x: number; y: number; scale?: number; opacity?: number }> = ({ x, y, scale = 1, opacity = 0.6 }) => (
  <Img
    src={staticFile('icons/shotput.png')}
    style={{ position: 'absolute', left: x - 56, top: y - 50, width: 112, height: 112, opacity, transform: `scale(${scale})` }}
  />
);

export const Spotlight: React.FC<{ query: string; caret: boolean; results: number }> = ({ query, caret, results }) => (
  <div
    style={{
      position: 'absolute',
      left: 756 - 340,
      top: 250,
      width: 680,
      borderRadius: 26,
      overflow: 'hidden',
      background: 'rgba(246,246,247,0.78)',
      backdropFilter: 'blur(40px) saturate(1.8)',
      boxShadow: 'inset 0 0 0 0.5px rgba(255,255,255,0.7), 0 0 0 0.5px rgba(0,0,0,0.16), 0 24px 70px rgba(0,0,0,0.28)',
      font: `400 22px ${UI_FONT}`,
    }}
  >
    <div style={{ height: 58, display: 'flex', alignItems: 'center', padding: '0 20px', gap: 14 }}>
      <svg width={22} height={22} viewBox="0 0 22 22">
        <circle cx={9.5} cy={9.5} r={7} stroke="#6b6a66" strokeWidth={2.2} fill="none" />
        <path d="M14.8 14.8L20 20" stroke="#6b6a66" strokeWidth={2.4} strokeLinecap="round" />
      </svg>
      <span style={{ color: query ? '#1c1c1e' : '#9a9993', letterSpacing: -0.3 }}>
        {query || 'Spotlight Search'}
        {caret && <span style={{ display: 'inline-block', width: 2, height: 24, background: '#0a7cff', verticalAlign: -4, marginLeft: 1 }} />}
      </span>
    </div>
    {results > 0 && (
      <div style={{ borderTop: '1px solid rgba(0,0,0,0.07)', padding: 8, opacity: results }}>
        <div style={{ height: 52, borderRadius: 14, background: '#0a7cff', display: 'flex', alignItems: 'center', padding: '0 12px', gap: 12 }}>
          <Img src={staticFile('icons/shotput.png')} style={{ width: 38, height: 38 }} />
          <div style={{ color: '#fff', font: `600 15px ${UI_FONT}` }}>Shotput</div>
          <div style={{ flex: 1 }} />
          <div style={{ color: 'rgba(255,255,255,0.8)', font: `400 13px ${UI_FONT}` }}>Application</div>
        </div>
        <div style={{ height: 40, display: 'flex', alignItems: 'center', padding: '0 12px', gap: 12, color: '#3a3936', font: `400 14px ${UI_FONT}` }}>
          <Img src={staticFile('icons/Finder.png')} style={{ width: 24, height: 24 }} />
          Shotput-0.3.0.dmg
          <div style={{ flex: 1 }} />
          <span style={{ color: '#8f8d87', fontSize: 13 }}>Downloads</span>
        </div>
      </div>
    )}
  </div>
);

export const SETTINGS: Rect = { x: 404, y: 196, w: 600, h: 420 };

const Toggle: React.FC<{ on: number }> = ({ on }) => (
  <div style={{ width: 38, height: 22, borderRadius: 11, background: on > 0.5 ? '#0a7cff' : 'rgba(0,0,0,0.1)', position: 'relative', transition: 'none' }}>
    <div
      style={{
        position: 'absolute',
        top: 2,
        left: 2 + 16 * on,
        width: 18,
        height: 18,
        borderRadius: 9,
        background: '#fff',
        boxShadow: '0 1px 3px rgba(0,0,0,0.25)',
      }}
    />
  </div>
);

export const SettingsWindow: React.FC<{ on: number }> = ({ on }) => {
  const rows: [string, React.ReactNode, number][] = [
    ['Chat', <div key="c" style={{ width: 26, height: 26, borderRadius: 6, background: 'linear-gradient(160deg,#3a3936,#1d1c1a)' }} />, 1],
    ['Shotput', <Img key="s" src={staticFile('icons/shotput.png')} style={{ width: 28, height: 28 }} />, on],
    ['Terminal', <Img key="t" src={staticFile('icons/Terminal.png')} style={{ width: 28, height: 28 }} />, 0],
  ];
  const side = ['Wi-Fi', 'Bluetooth', 'Network', 'Notifications', 'Sound', 'Focus', 'General', 'Appearance', 'Privacy & Security', 'Desktop & Dock', 'Displays'];
  return (
    <Window rect={SETTINGS} radius={16} background="#f7f7f6">
      <div style={{ position: 'absolute', left: 8, top: 8, bottom: 8, width: 176, borderRadius: 12, background: 'rgba(236,236,234,0.9)', padding: '44px 8px 0', boxSizing: 'border-box' }}>
        <TrafficLights x={10} y={10} />
        {side.map((s) => (
          <div
            key={s}
            style={{
              height: 26,
              borderRadius: 7,
              display: 'flex',
              alignItems: 'center',
              padding: '0 9px',
              font: `500 12.5px ${UI_FONT}`,
              color: s === 'Privacy & Security' ? '#fff' : '#2c2c2a',
              background: s === 'Privacy & Security' ? '#0a7cff' : 'transparent',
            }}
          >
            {s}
          </div>
        ))}
      </div>
      <div style={{ position: 'absolute', left: 204, top: 16, right: 20 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, font: `700 14px ${UI_FONT}`, color: '#1d1d1f', height: 24 }}>
          <svg width={10} height={14} viewBox="0 0 10 14" style={{ opacity: 0.5 }}>
            <path d="M8 1.5L2.5 7 8 12.5" stroke="#222" strokeWidth={1.8} fill="none" strokeLinecap="round" />
          </svg>
          Screen & System Audio Recording
        </div>
        <div style={{ font: `400 12px/17px ${UI_FONT}`, color: '#6e6e6a', margin: '22px 2px 12px' }}>
          Allow the applications below to record the content of your screen and audio, even while using other applications.
        </div>
        <div style={{ borderRadius: 12, background: '#fff', boxShadow: '0 0 0 0.5px rgba(0,0,0,0.1)' }}>
          {rows.map(([name, icon, value], i) => (
            <div key={name} style={{ height: 46, display: 'flex', alignItems: 'center', gap: 12, padding: '0 12px', borderTop: i ? '1px solid rgba(0,0,0,0.06)' : 'none' }}>
              {icon}
              <span style={{ font: `500 13px ${UI_FONT}`, color: '#1d1d1f', flex: 1 }}>{name}</span>
              <Toggle on={value} />
            </div>
          ))}
        </div>
      </div>
    </Window>
  );
};

// Where the Shotput toggle sits on screen, for the pointer.
export const SETTINGS_TOGGLE = { x: SETTINGS.x + SETTINGS.w - 20 - 12 - 19, y: SETTINGS.y + 16 + 24 + 22 + 34 + 12 + 46 + 17 };

const ThumbButton: React.FC<{ d: string }> = ({ d }) => (
  <div style={{ width: 26, height: 26, borderRadius: 13, background: 'rgba(255,255,255,0.92)', display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 1px 3px rgba(0,0,0,0.2)' }}>
    <svg width={14} height={14} viewBox="0 0 14 14">
      <path d={d} stroke="#1d1c1a" strokeWidth={1.5} fill="none" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  </div>
);

// The preview Shotput leaves in the corner: the capture itself, rounded, on a two-layer shadow.
export const Thumbnail: React.FC<{ src: string; rect: Rect; opacity: number; hover: number; press?: number }> = ({ src, rect, opacity, hover, press = 0 }) => (
  <div
    style={{
      position: 'absolute',
      left: rect.x,
      top: rect.y,
      width: rect.w,
      height: rect.h,
      opacity,
      transform: `scale(${1 - press * 0.04})`,
      borderRadius: 14,
      boxShadow: '0 1px 3px rgba(0,0,0,0.18), 0 12px 32px rgba(0,0,0,0.22)',
    }}
  >
    <div style={{ position: 'absolute', inset: 0, borderRadius: 14, overflow: 'hidden', background: '#f1f0ed', boxShadow: 'inset 0 0 0 0.5px rgba(0,0,0,0.18)' }}>
      <Img src={src} style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(25,25,23,0.55)', opacity: hover }} />
    </div>
    <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, opacity: hover }}>
      <ThumbButton d="M3 11l1-3.2 5.6-5.6a1.5 1.5 0 012.2 2.2L6.2 10 3 11z" />
      <ThumbButton d="M4.5 4.5V2.5h7v7h-2M2.5 4.5h7v7h-7z" />
      <ThumbButton d="M7 2v7M4 6.5L7 9.5l3-3M2.5 11.5h9" />
      <ThumbButton d="M5 2.5h4l-.6 4 2.1 2H3.5l2.1-2zM7 8.5v3.5" />
    </div>
    <div style={{ position: 'absolute', right: 6, top: 6, opacity: hover, transform: 'scale(0.8)' }}>
      <ThumbButton d="M4 4l6 6M10 4l-6 6" />
    </div>
  </div>
);
