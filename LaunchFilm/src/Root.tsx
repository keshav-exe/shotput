import React from 'react';
import { Composition } from 'remotion';
import { SCREEN } from './layout';
import { Desktop, baseDesktop } from './desktop/Screen';
import { DURATION, H, Launch, W } from './Launch';
import { AD_DURATION, Ad } from './Ad';

// The screen exactly as it is when Shotput freezes it, at 2x. The Swift harness feeds this to
// the real selection overlay.
const CaptureStill: React.FC = () => (
  <div style={{ transform: 'scale(2)', transformOrigin: '0 0' }}>
    <Desktop s={{ ...baseDesktop, shotput: 1, shotputInDock: 0 }} />
  </div>
);

export const Root: React.FC = () => (
  <>
    <Composition id="Ad" component={Ad} width={W} height={H} fps={60} durationInFrames={Math.ceil(AD_DURATION * 60)} />
    <Composition id="Launch" component={Launch} width={W} height={H} fps={60} durationInFrames={Math.ceil(DURATION * 60)} />
    <Composition id="CaptureStill" component={CaptureStill} width={SCREEN.w * 2} height={SCREEN.h * 2} fps={60} durationInFrames={1} />
  </>
);
