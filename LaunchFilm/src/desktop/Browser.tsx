import React from 'react';
import { BROWSER, BROWSER_BAR, CARDS_LEFT, CARDS_TOP, CARD_GAP, CARD_W } from '../layout';
import { UI_FONT } from './Desktop';
import { TrafficLights, Window } from './Window';

const INK = '#1d1c1a';
const MUTED = '#6f6b63';
const LINE = '#e8e5df';
const BRAND = '#2f5d50';

const Check: React.FC<{ color?: string }> = ({ color = BRAND }) => (
  <svg width={14} height={14} viewBox="0 0 14 14" style={{ flex: 'none', marginTop: 2 }}>
    <circle cx={7} cy={7} r={7} fill={color} opacity={0.12} />
    <path d="M4.2 7.2l1.9 1.9 3.8-4" stroke={color} strokeWidth={1.5} fill="none" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

type Plan = { name: string; blurb: string; price: string; per: string; features: string[]; cta: string; pro?: boolean };

const PLANS: Plan[] = [
  { name: 'Starter', blurb: 'For trying it on a project.', price: '$0', per: 'forever', features: ['3 notebooks', 'Sync on two devices', 'Markdown export'], cta: 'Get started' },
  { name: 'Pro', blurb: 'For people who write every day.', price: '$24', per: 'per month', features: ['Unlimited notebooks', 'Sync everywhere', 'Version history', 'Offline mode'], cta: 'Start free trial', pro: true },
  { name: 'Team', blurb: 'For teams that share notes.', price: '$48', per: 'per seat / month', features: ['Everything in Pro', 'Shared spaces', 'Admin controls'], cta: 'Talk to us' },
];

const Badge: React.FC<{ style?: React.CSSProperties }> = ({ style }) => (
  <div
    style={{
      font: `600 11px ${UI_FONT}`,
      letterSpacing: 0.1,
      color: '#fff',
      background: '#d4572a',
      padding: '5px 9px',
      borderRadius: 999,
      whiteSpace: 'nowrap',
      ...style,
    }}
  >
    Most popular
  </div>
);

const Card: React.FC<{ plan: Plan; x: number; fix: number }> = ({ plan, x, fix }) => (
  <div
    style={{
      position: 'absolute',
      left: x,
      top: CARDS_TOP,
      width: CARD_W,
      height: 372,
      boxSizing: 'border-box',
      borderRadius: 14,
      background: plan.pro ? '#fffdf9' : '#fff',
      border: plan.pro ? `1.5px solid ${INK}` : `1px solid ${LINE}`,
      boxShadow: plan.pro ? '0 10px 30px rgba(40,30,10,0.10)' : '0 1px 2px rgba(0,0,0,0.03)',
      padding: '22px 22px 20px',
      color: INK,
      font: `400 13px ${UI_FONT}`,
    }}
  >
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', height: 22 }}>
      <div style={{ font: `650 16px ${UI_FONT}`, letterSpacing: -0.2 }}>{plan.name}</div>
      {plan.pro && <Badge style={{ opacity: fix }} />}
    </div>
    <div style={{ color: MUTED, marginTop: 6 }}>{plan.blurb}</div>
    <div style={{ display: 'flex', alignItems: 'baseline', gap: 7, marginTop: 20 }}>
      <div style={{ font: `650 38px ${UI_FONT}`, letterSpacing: -1.2 }}>{plan.price}</div>
      <div style={{ color: MUTED }}>{plan.per}</div>
    </div>
    {/* The bug: the badge is pinned to the card and lands on the price row. */}
    {plan.pro && <Badge style={{ position: 'absolute', top: 76, right: 108, opacity: 1 - fix }} />}
    <div style={{ height: 1, background: LINE, margin: '20px 0 16px' }} />
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
      {plan.features.map((f) => (
        <div key={f} style={{ display: 'flex', gap: 9 }}>
          <Check />
          <span>{f}</span>
        </div>
      ))}
    </div>
    <div
      style={{
        position: 'absolute',
        left: 22,
        right: 22,
        bottom: 20,
        height: 40,
        borderRadius: 10,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        font: `600 13.5px ${UI_FONT}`,
        background: plan.pro ? INK : '#f3f1ec',
        color: plan.pro ? '#fff' : INK,
      }}
    >
      {plan.cta}
    </div>
  </div>
);

const PricingPage: React.FC<{ fix: number }> = ({ fix }) => (
  <div style={{ position: 'absolute', left: 0, top: BROWSER_BAR, right: 0, bottom: 0, background: '#faf8f4', overflow: 'hidden' }}>
    <div style={{ height: 58, display: 'flex', alignItems: 'center', padding: '0 34px', borderBottom: `1px solid ${LINE}`, font: `500 13px ${UI_FONT}`, color: MUTED }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, color: INK, font: `700 15px ${UI_FONT}`, letterSpacing: -0.3 }}>
        <div style={{ width: 20, height: 20, borderRadius: 6, background: BRAND, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <div style={{ width: 8, height: 10, borderRadius: 2, border: '1.6px solid #fff', borderLeftWidth: 3 }} />
        </div>
        fieldnote
      </div>
      <div style={{ display: 'flex', gap: 26, marginLeft: 44 }}>
        <span>Product</span>
        <span>Changelog</span>
        <span style={{ color: INK }}>Pricing</span>
        <span>Docs</span>
      </div>
      <div style={{ flex: 1 }} />
      <span>Sign in</span>
      <div style={{ marginLeft: 18, padding: '7px 13px', borderRadius: 8, background: INK, color: '#fff', font: `600 12.5px ${UI_FONT}` }}>Start writing</div>
    </div>
    <div style={{ textAlign: 'center', marginTop: 40, color: INK }}>
      <div style={{ font: `650 34px ${UI_FONT}`, letterSpacing: -1 }}>Pricing that stays out of the way</div>
      <div style={{ font: `400 15px ${UI_FONT}`, color: MUTED, marginTop: 10 }}>Start free. Upgrade when your notes outgrow it.</div>
    </div>
    {PLANS.map((p, i) => (
      <Card key={p.name} plan={p} x={CARDS_LEFT + i * (CARD_W + CARD_GAP)} fix={fix} />
    ))}
    <div style={{ position: 'absolute', left: 0, right: 0, top: CARDS_TOP + 372 + 28, textAlign: 'center', font: `400 12.5px ${UI_FONT}`, color: MUTED }}>
      Prices in USD. Cancel any time from Settings.
    </div>
  </div>
);

export const Browser: React.FC<{ active?: boolean; fix?: number; reload?: number }> = ({ active = true, fix = 0, reload = 0 }) => (
  <Window rect={BROWSER} active={active} background="#faf8f4">
    <div
      style={{
        position: 'absolute',
        left: 0,
        top: 0,
        right: 0,
        height: BROWSER_BAR,
        background: active ? '#f4f3f1' : '#f7f7f6',
        borderBottom: '1px solid rgba(0,0,0,0.08)',
      }}
    >
      <TrafficLights active={active} x={18} y={20} />
      {/* back / forward */}
      <svg width={52} height={16} viewBox="0 0 52 16" style={{ position: 'absolute', left: 96, top: 18, opacity: 0.55 }}>
        <path d="M9 2L3 8l6 6M43 2l6 6-6 6" stroke="#222" strokeWidth={1.8} fill="none" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
      <div
        style={{
          position: 'absolute',
          left: '50%',
          top: 11,
          transform: 'translateX(-50%)',
          width: 420,
          height: 30,
          borderRadius: 10,
          background: active ? 'rgba(0,0,0,0.055)' : 'rgba(0,0,0,0.04)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          gap: 6,
          font: `500 13px ${UI_FONT}`,
          color: '#2b2a28',
          overflow: 'hidden',
        }}
      >
        <svg width={10} height={12} viewBox="0 0 10 12" style={{ opacity: 0.5 }}>
          <rect x={1} y={5} width={8} height={6.5} rx={1.5} fill="#333" />
          <path d="M2.8 5V3.6a2.2 2.2 0 014.4 0V5" stroke="#333" strokeWidth={1.3} fill="none" />
        </svg>
        localhost:3000/pricing
        <div style={{ position: 'absolute', left: 0, bottom: 0, height: 2, width: `${reload * 100}%`, background: '#1f6fe5', opacity: reload > 0 && reload < 1 ? 1 : 0 }} />
      </div>
      <svg width={16} height={16} viewBox="0 0 16 16" style={{ position: 'absolute', right: 20, top: 18, opacity: 0.55 }}>
        <path d="M8 2v12M2 8h12" stroke="#222" strokeWidth={1.7} strokeLinecap="round" />
      </svg>
    </div>
    <PricingPage fix={fix} />
  </Window>
);
