// Self-check: touch and hold on a song row opens its ⋯ menu on the phone. No test runner in `ui/`,
// node 22 runs TypeScript directly:
//
//     node --experimental-strip-types ui/src/lib/longpress.check.ts
//
// Prints "ok" and exits 0, or throws on the first broken invariant.
//
// The press itself is the WebView's `contextmenu`, which `ctxHost` (menu.ts) already turns into the
// row's menu; what this guards is the two pieces around it, each one line an upstream merge could
// undo. Without the CSS the press selects a word and the system's copy bar wins; without the
// TrackRow class every phone row draws a ⋯ again.
import { readFileSync } from 'node:fs';

function ok(cond: boolean, what: string): void {
	if (!cond) throw new Error(`FAIL: ${what}`);
}
const src = (p: string) => readFileSync(new URL(p, import.meta.url), 'utf8');

const css = src('../routes/layout.css');
const rule = /html\.compact \[data-ctx\]\s*\{([^}]*)\}/.exec(css);
ok(!!rule, 'layout.css has the phone rule for items');
ok(/(^|;|\s)user-select: none;/.test(rule![1]) && /-webkit-user-select: none;/.test(rule![1]), 'phone items are not text-selectable');
ok(/-webkit-touch-callout: none;/.test(rule![1]), 'the system long-press callout is off on phone items');
ok(/html\.compact \[data-ctx\] :is\(input, textarea, \[contenteditable\]\)\s*\{[^}]*user-select: text;/.test(css), 'fields inside items stay editable');
// Scoped to the phone: the desktop keeps selecting text in rows.
ok(!/(^|\n)\[data-ctx\]\s*\{[^}]*user-select: none/.test(css), 'the rule is phone-only');

// The menu ctxHost opens is the one the ⋯ button opens: same component, same handler.
const menu = src('./components/TrackMenu.svelte');
ok(/onclick=\{openMenu\}[^>]*\{@attach ctxHost\(openMenu\)\}/.test(menu), 'TrackMenu opens one menu for the button and the press');
ok(src('./menu.ts').includes("trigger.closest('[data-ctx]')"), 'ctxHost listens on the item');

const row = src('./components/TrackRow.svelte');
ok(/\bdata-ctx\b/.test(row), 'a song row is an item');
ok(row.includes("const PHONE_MENU_TRIGGER = 'sr-only focus-visible:not-sr-only';"), 'the phone ⋯ is screen-reader only, shown on keyboard focus');
ok(/\{platform\.compact\s*\?\s*PHONE_MENU_TRIGGER\s*:\s*narrow\s*\?\s*''\s*:\s*'invisible group-focus-within:visible group-hover:visible'\}/.test(row), 'the desktop rows keep their ⋯ (on hover, or always when compact)');

console.log('ok');
