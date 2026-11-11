import React from 'react';
import { SCREEN } from '../layout';
import { Browser } from './Browser';
import { Chat, ChatState } from './Chat';
import { Dock, MenuBar, Wallpaper } from './Desktop';

export const MENUS: Record<string, string[]> = {
  Finder: ['File', 'Edit', 'View', 'Go', 'Window', 'Help'],
  Safari: ['File', 'Edit', 'View', 'History', 'Bookmarks', 'Window', 'Help'],
  Shotput: ['File', 'Edit', 'Window', 'Help'],
  Chat: ['File', 'Edit', 'View', 'Window', 'Help'],
};

export const idleChat: ChatState = {
  active: false, focus: false, attach: 0, draft: '', caret: false, sent: 0, thinking: 0, reply: 0, diff: 0,
  image: '', imageSize: { w: 308, h: 404 },
};

export type DesktopState = {
  app: string;
  shotput: number;
  shotputInDock: number;
  front: 'browser' | 'chat' | 'none';
  chat: ChatState;
  fix: number;
  reload: number;
};

export const baseDesktop: DesktopState = {
  app: 'Safari', shotput: 0, shotputInDock: 0, front: 'browser', chat: idleChat, fix: 0, reload: 0,
};

// Everything that sits on the screen below Shotput's own windows.
export const Desktop: React.FC<{ s: DesktopState; children?: React.ReactNode }> = ({ s, children }) => (
  <div style={{ position: 'absolute', left: 0, top: 0, width: SCREEN.w, height: SCREEN.h, overflow: 'hidden' }}>
    <Wallpaper />
    <Chat s={{ ...s.chat, active: s.front === 'chat' }} />
    <Browser active={s.front === 'browser'} fix={s.fix} reload={s.reload} />
    {children}
    <Dock shotput={s.shotputInDock} running={['Finder', 'Safari', 'Chat', ...(s.shotputInDock > 0.5 ? ['Shotput'] : [])]} />
    <MenuBar app={s.app} menus={MENUS[s.app] ?? []} shotput={s.shotput} />
  </div>
);
