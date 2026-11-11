// Shared geometry, in screen points with a top-left origin. The screen is a 14-inch MacBook Pro
// at its default "looks like" size. The Swift harness reads the same numbers from layout.json.

export const SCREEN = { w: 1512, h: 982 };
export const MENU_BAR = 30;
export const FPS = 60;

export type Rect = { x: number; y: number; w: number; h: number };

export const BROWSER: Rect = { x: 52, y: 62, w: 930, h: 812 };
export const CHAT: Rect = { x: 1006, y: 92, w: 456, h: 724 };

// The Pro card inside the browser page, and the area the viewer drags over it.
export const BROWSER_BAR = 52;
export const CARD_W = 276;
export const CARD_GAP = 18;
export const CARDS_LEFT = (BROWSER.w - CARD_W * 3 - CARD_GAP * 2) / 2;
export const CARDS_TOP = 186;
export const PRO_CARD: Rect = { x: BROWSER.x + CARDS_LEFT + CARD_W + CARD_GAP, y: BROWSER.y + BROWSER_BAR + CARDS_TOP, w: CARD_W, h: 372 };
export const CAPTURE: Rect = { x: PRO_CARD.x - 16, y: PRO_CARD.y - 16, w: PRO_CARD.w + 32, h: PRO_CARD.h + 32 };

// The installer window, sized as Scripts/package.sh sets it.
export const DMG: Rect = { x: 426, y: 236, w: 660, h: 428 };
export const DMG_TITLE = 28;
export const DMG_APP = { x: DMG.x + 165, y: DMG.y + DMG_TITLE + 200 };
export const DMG_APPS = { x: DMG.x + 495, y: DMG.y + DMG_TITLE + 200 };

export const ONBOARD: Rect = { x: 456, y: 170, w: 600, h: 632 };

export const center = (r: Rect) => ({ x: r.x + r.w / 2, y: r.y + r.h / 2 });
