import React from 'react';
import { Img } from 'remotion';
import { CHAT } from '../layout';
import { MONO_FONT, UI_FONT } from './Desktop';
import { TrafficLights, Window } from './Window';

const INK = '#1f1e1c';
const MUTED = '#7a766e';

export const REQUEST = 'The badge is sitting on the price on the Pro card. Can you fix it?';
export const REPLY =
  'The badge is absolutely positioned 76px from the top of the card, which puts it on the price row. I moved it into the header next to the plan name, so it lines up with the title and can’t collide with anything below.';

export type ChatState = {
  active: boolean;
  focus: boolean;
  attach: number; // 0..1, the pasted screenshot arriving in the composer
  draft: string;
  caret: boolean;
  sent: number; // 0..1, the message leaving the composer for the thread
  thinking: number; // 0..1 opacity of the thinking row
  reply: number; // characters of the reply shown
  diff: number; // 0..1, the change summary appearing
  image: string;
  imageSize: { w: number; h: number };
};

const Thumb: React.FC<{ src: string; w: number; h: number; style?: React.CSSProperties }> = ({ src, w, h, style }) => (
  <div style={{ width: w, height: h, borderRadius: 10, overflow: 'hidden', boxShadow: '0 0 0 0.5px rgba(0,0,0,0.18), 0 2px 8px rgba(0,0,0,0.08)', ...style }}>
    <Img src={src} style={{ width: w, height: h, display: 'block', objectFit: 'cover' }} />
  </div>
);

const Diff: React.FC<{ p: number }> = ({ p }) => {
  const rows: [string, string][] = [
    [' ', '<header className="flex items-center justify-between">'],
    [' ', '  <h3>{plan.name}</h3>'],
    ['+', '  {plan.popular && <Badge />}'],
    [' ', '</header>'],
    ['-', '{plan.popular && <Badge className="absolute top-[76px] right-28" />}'],
  ];
  return (
    <div
      style={{
        marginTop: 12,
        borderRadius: 10,
        border: '1px solid #e9e6e0',
        background: '#fbfaf8',
        overflow: 'hidden',
        opacity: p,
        transform: `translateY(${(1 - p) * 6}px)`,
      }}
    >
      <div style={{ display: 'flex', justifyContent: 'space-between', padding: '7px 11px', font: `600 11.5px ${UI_FONT}`, color: MUTED, borderBottom: '1px solid #eeebe6' }}>
        <span style={{ color: INK }}>PricingCard.tsx</span>
        <span>
          <span style={{ color: '#2f8a4f' }}>+1</span> <span style={{ color: '#c4473a' }}>−1</span>
        </span>
      </div>
      <div style={{ padding: '6px 0', font: `400 10.5px/17px ${MONO_FONT}`, color: '#3a3833' }}>
        {rows.map(([s, line], i) => (
          <div
            key={i}
            style={{
              padding: '0 11px',
              whiteSpace: 'pre',
              overflow: 'hidden',
              textOverflow: 'ellipsis',
              background: s === '+' ? 'rgba(47,138,79,0.09)' : s === '-' ? 'rgba(196,71,58,0.08)' : 'transparent',
              color: s === '-' ? '#9b4a40' : undefined,
            }}
          >
            <span style={{ opacity: 0.5, marginRight: 8 }}>{s}</span>
            {line}
          </div>
        ))}
      </div>
    </div>
  );
};

export const Chat: React.FC<{ s: ChatState }> = ({ s }) => {
  const thumbH = 62;
  const thumbW = Math.round((s.imageSize.w / s.imageSize.h) * thumbH);
  const big = { h: 200, w: Math.round((s.imageSize.w / s.imageSize.h) * 200) };
  const composerText = s.sent > 0 ? '' : s.draft;
  const showAttach = s.attach > 0 && s.sent === 0;
  const reply = REPLY.slice(0, Math.floor(s.reply));
  return (
    <Window rect={CHAT} active={s.active} background="#fcfbf9">
      <div style={{ position: 'absolute', left: 0, right: 0, top: 0, height: 48, borderBottom: '1px solid rgba(0,0,0,0.06)', background: '#f6f5f2' }}>
        <TrafficLights active={s.active} x={18} y={18} />
        <div style={{ position: 'absolute', left: 0, right: 0, top: 15, textAlign: 'center', font: `600 13px ${UI_FONT}`, color: s.active ? INK : '#9a968e' }}>
          Pricing page polish
        </div>
      </div>

      {/* Thread */}
      <div style={{ position: 'absolute', left: 22, right: 22, top: 70, bottom: 150, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end' }}>
        <div style={{ font: `400 13.5px/20px ${UI_FONT}`, color: MUTED, textAlign: 'center', marginBottom: 'auto', paddingTop: 8 }}>Today 9:38</div>
        <div style={{ alignSelf: 'flex-end', maxWidth: 330, marginBottom: 16 }}>
          <div style={{ padding: '9px 13px', borderRadius: 16, background: '#ecebe7', font: `400 13.5px/19px ${UI_FONT}`, color: INK }}>
            Hero copy is in. Pricing page next.
          </div>
        </div>
        <div style={{ font: `400 13.5px/20px ${UI_FONT}`, color: INK, marginBottom: 18, maxWidth: 360 }}>
          Updated the hero. Pricing cards are in <span style={{ font: `400 12.5px ${MONO_FONT}` }}>PricingCard.tsx</span> when you’re ready.
        </div>
        {s.sent > 0 && (
          <div
            style={{
              alignSelf: 'flex-end',
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'flex-end',
              gap: 6,
              opacity: Math.min(1, s.sent * 1.6),
              transform: `translateY(${(1 - s.sent) * 40}px)`,
              marginBottom: 16,
            }}
          >
            <Thumb src={s.image} w={big.w} h={big.h} />
            <div style={{ maxWidth: 320, padding: '9px 13px', borderRadius: 16, background: '#ecebe7', font: `400 13.5px/19px ${UI_FONT}`, color: INK }}>{REQUEST}</div>
          </div>
        )}
        {s.thinking > 0 && (
          <div style={{ opacity: s.thinking, font: `500 13px ${UI_FONT}`, color: MUTED, display: 'flex', alignItems: 'center', gap: 8, height: 20 }}>
            <div style={{ width: 7, height: 7, borderRadius: 4, background: '#d4572a', opacity: 0.85 }} />
            Reading the screenshot and PricingCard.tsx
          </div>
        )}
        {s.reply > 0 && (
          <div style={{ maxWidth: 400 }}>
            <div style={{ font: `400 13.5px/20px ${UI_FONT}`, color: INK }}>{reply}</div>
            {s.diff > 0 && <Diff p={s.diff} />}
          </div>
        )}
      </div>

      {/* Composer */}
      <div
        style={{
          position: 'absolute',
          left: 16,
          right: 16,
          bottom: 16,
          minHeight: 64,
          borderRadius: 18,
          background: '#fff',
          boxShadow: s.focus
            ? '0 0 0 1px rgba(31,111,229,0.55), 0 0 0 4px rgba(31,111,229,0.12), 0 4px 14px rgba(0,0,0,0.05)'
            : '0 0 0 1px rgba(0,0,0,0.09), 0 4px 14px rgba(0,0,0,0.04)',
          padding: '12px 14px 44px',
          boxSizing: 'border-box',
        }}
      >
        {showAttach && (
          <div
            style={{
              marginBottom: 10,
              transform: `scale(${0.6 + 0.4 * s.attach})`,
              transformOrigin: 'left bottom',
              opacity: Math.min(1, s.attach * 2),
              width: thumbW,
            }}
          >
            <Thumb src={s.image} w={thumbW} h={thumbH} />
          </div>
        )}
        <div style={{ font: `400 14px/20px ${UI_FONT}`, color: composerText ? INK : '#a9a59d', minHeight: 20 }}>
          {composerText || (s.attach > 0 && s.sent === 0 ? '' : 'Ask anything')}
          {s.caret && <span style={{ display: 'inline-block', width: 1.5, height: 17, background: '#1f6fe5', verticalAlign: -3, marginLeft: 1 }} />}
        </div>
        <div
          style={{
            position: 'absolute',
            right: 10,
            bottom: 10,
            width: 28,
            height: 28,
            borderRadius: 14,
            background: composerText ? INK : '#e5e2dc',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          <svg width={12} height={13} viewBox="0 0 12 13">
            <path d="M6 12V1.5M1.5 6L6 1.5 10.5 6" stroke="#fff" strokeWidth={1.8} fill="none" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </div>
        <div style={{ position: 'absolute', left: 14, bottom: 14, display: 'flex', gap: 14, opacity: 0.45 }}>
          <svg width={14} height={14} viewBox="0 0 14 14">
            <path d="M7 1v12M1 7h12" stroke="#222" strokeWidth={1.6} strokeLinecap="round" />
          </svg>
        </div>
      </div>
    </Window>
  );
};
