import React from 'react';
import { Rect } from '../layout';

export const TrafficLights: React.FC<{ active?: boolean; only?: 'close'; x?: number; y?: number }> = ({ active = true, only, x = 16, y = 16 }) => {
  const colors = active ? ['#ff5f57', '#febc2e', '#28c840'] : ['#dcdcdc', '#dcdcdc', '#dcdcdc'];
  return (
    <div style={{ position: 'absolute', left: x, top: y, display: 'flex', gap: 8 }}>
      {colors.map((c, i) => (
        <div
          key={i}
          style={{
            width: 12,
            height: 12,
            borderRadius: 6,
            background: only && i > 0 ? 'rgba(0,0,0,0.1)' : c,
            boxShadow: 'inset 0 0 0 0.5px rgba(0,0,0,0.12)',
          }}
        />
      ))}
    </div>
  );
};

// A macOS window: big continuous corners, a hairline edge, and the layered system shadow, which
// is deeper on the key window.
export const Window: React.FC<{
  rect: Rect;
  radius?: number;
  active?: boolean;
  background?: string;
  style?: React.CSSProperties;
  children?: React.ReactNode;
}> = ({ rect, radius = 16, active = true, background = '#fff', style, children }) => (
  <div
    style={{
      position: 'absolute',
      left: rect.x,
      top: rect.y,
      width: rect.w,
      height: rect.h,
      borderRadius: radius,
      overflow: 'hidden',
      background,
      boxShadow: active
        ? '0 0 0 0.5px rgba(0,0,0,0.22), 0 2px 6px rgba(0,0,0,0.08), 0 22px 60px rgba(0,0,0,0.26)'
        : '0 0 0 0.5px rgba(0,0,0,0.16), 0 1px 3px rgba(0,0,0,0.06), 0 12px 34px rgba(0,0,0,0.14)',
      ...style,
    }}
  >
    {children}
  </div>
);
