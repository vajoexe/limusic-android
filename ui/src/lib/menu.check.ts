// Self-check for the placement arithmetic behind `anchorMenu` / `fitMenu`. Run it:
// `node src/lib/menu.check.ts` from ui/.
// ponytail: a script over a test runner — the UI has no test setup and this is the only piece of
// menu.ts that does arithmetic worth getting wrong. `layout` isn't exported, so these go through
// `place`, the same call `fitMenu` makes with a measured popup.
import { anchorMenu, ctxHost, place } from './menu.ts';

// ponytail: two lines instead of node:assert, which would want @types/node in a DOM-only tsconfig.
const eq = (got: string, want: string) => {
	if (got !== want) throw new Error(`expected\n  ${want}\ngot\n  ${got}`);
};
// Every placement carries `transition:none` and a transform origin (see menu.ts); the offsets and
// which corner sits at the anchor are what these check.
const eqp = (got: string, want: string, origin: string) =>
	eq(got, `transition:none;${want};transform-origin:${origin}`);
const viewport = (w: number, h: number) => Object.assign(globalThis, { window: { innerWidth: w, innerHeight: h } });
// A mid-sized menu, the size `fitMenu` would have measured.
const W = 224;
const H = 280;
const at = (x: number, y: number) =>
	place(anchorMenu({ type: 'contextmenu', clientX: x, clientY: y } as unknown as Event), W, H);
const from = (box: { left: number; right: number; top: number; bottom: number }, align?: 'left' | 'right') =>
	place(
		anchorMenu({ type: 'click', currentTarget: { getBoundingClientRect: () => box } } as unknown as Event, {
			align
		}),
		W,
		H
	);

viewport(1000, 800);

// Pointer, room everywhere: opens down and to the right of the cursor.
eqp(at(100, 100), 'left:100px;right:auto;top:100px;bottom:auto', 'top left');
// Near the bottom it flips above the cursor; near the right it hangs off it leftwards.
eqp(at(100, 700), 'left:100px;right:auto;top:auto;bottom:100px', 'bottom left');
eqp(at(900, 100), 'left:auto;right:100px;top:100px;bottom:auto', 'top right');
eqp(at(900, 700), 'left:auto;right:100px;top:auto;bottom:100px', 'bottom right');

// A trigger: 4px below its box, and `align: 'right'` lines the menu's right edge up with it.
const box = { left: 400, right: 440, top: 200, bottom: 240 };
eqp(from(box), 'left:400px;right:auto;top:244px;bottom:auto', 'top left');
eqp(from(box, 'right'), 'left:auto;right:560px;top:244px;bottom:auto', 'top right');

// The clamp, which is what stops a menu running off screen when the anchor asks for too much:
// a left-aligned trigger near the right edge flips, and a right-aligned one near the left edge
// stops 8px short instead of hanging off it.
eqp(from({ left: 900, right: 940, top: 200, bottom: 240 }), 'left:auto;right:60px;top:244px;bottom:auto', 'top right');
eqp(from({ left: 10, right: 50, top: 200, bottom: 240 }, 'right'), 'left:auto;right:768px;top:244px;bottom:auto', 'top right');

// Too little room either way (a short window): stays downwards rather than flipping into nothing,
// and the clamp pulls it back inside.
viewport(1000, 300);
eqp(at(100, 150), 'left:100px;right:auto;top:12px;bottom:auto', 'top left');

// The track menu asks for `align: 'right'`, the ⋯'s alignment. On the desktop a right-click keeps
// it: the menu's right edge sits at the cursor.
const pressed = (x: number, y: number) =>
	place(anchorMenu({ type: 'contextmenu', clientX: x, clientY: y } as unknown as Event, { align: 'right' }), W, H);
viewport(1000, 800);
eqp(pressed(500, 100), 'left:auto;right:500px;top:100px;bottom:auto', 'top right');
// The phone (`html.compact`): a press grows the menu from the thumb into the roomier half, so a
// press on the left of a row no longer opens it against the far edge (which was right:...).
const compact = (on: boolean) =>
	Object.assign(globalThis, { document: { documentElement: { classList: { contains: (c: string) => on && c === 'compact' } } } });
compact(true);
viewport(393, 800);
eqp(pressed(100, 100), 'left:100px;right:auto;top:100px;bottom:auto', 'top left');
eqp(pressed(300, 100), 'left:auto;right:93px;top:100px;bottom:auto', 'top right');
eqp(pressed(100, 700), 'left:100px;right:auto;top:auto;bottom:100px', 'bottom left');
// The ⋯ button itself still lines the menu up under it, phone or not.
eqp(from({ left: 340, right: 370, top: 200, bottom: 230 }, 'right'), 'left:auto;right:23px;top:234px;bottom:auto', 'top right');
// And a non-phone document keeps the desktop rule even with the class check in place: right edge
// at the cursor, clamped 8px short of the left edge when the cursor is too close to it.
compact(false);
viewport(1000, 800);
eqp(pressed(100, 100), 'left:auto;right:768px;top:100px;bottom:auto', 'top right');

// Minimal DOM surface for the shared right-click attachment: artwork opts in, other controls
// keep their own meaning, and Shift+right-click still reaches the native menu.
class MenuElement extends EventTarget {
	button: MenuElement | null = null;
	artwork = false;
	closest(selector: string): MenuElement | null {
		if (selector === '[data-ctx]') return host;
		if (selector === 'button') return this.button;
		return null;
	}
	hasAttribute(name: string) {
		return name === 'data-ctx-button' && this.artwork;
	}
}
Object.assign(globalThis, { Element: MenuElement });
Object.assign(window, { getSelection: () => null });
const host = new MenuElement();
const trigger = new MenuElement();
const artwork = new MenuElement();
artwork.artwork = true;
let opened = 0;
const detach = ctxHost(() => opened++)(trigger as unknown as HTMLElement);
const rightClick = (button: MenuElement | null, shiftKey = false) => {
	host.button = button;
	const event = new Event('contextmenu');
	Object.assign(event, { shiftKey });
	host.dispatchEvent(event);
};
rightClick(null);
eq(String(opened), '1');
rightClick(new MenuElement());
eq(String(opened), '1');
rightClick(artwork);
eq(String(opened), '2');
rightClick(artwork, true);
eq(String(opened), '2');
rightClick(trigger);
eq(String(opened), '3');
detach?.();
rightClick(artwork);
eq(String(opened), '3');

console.log('menu.check: ok');
