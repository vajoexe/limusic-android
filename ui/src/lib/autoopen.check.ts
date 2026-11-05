// Self-check for `autoopen.ts`: whether starting playback opens the full player. No test runner in
// `ui/`, node 22 runs TypeScript directly:
//
//     node --experimental-strip-types ui/src/lib/autoopen.check.ts
//
// Prints "ok" and exits 0, or throws on the first broken invariant.
//
// The last block reads the sources that use it. The appearance store, `openPlayer` and the
// Settings switch are Svelte modules node can't import, and each is one line an upstream merge
// could quietly undo (it was the old key in all three before).
import { readFileSync } from 'node:fs';
import { AUTO_OPEN_DEFAULTS, autoOpenKey, opensPlayerOnPlay } from './autoopen.ts';

function ok(cond: boolean, what: string): void {
	if (!cond) throw new Error(`FAIL: ${what}`);
}

// Defaults: the desktop opens the player as upstream does, Android leaves the song in the pill.
ok(opensPlayerOnPlay(AUTO_OPEN_DEFAULTS, false), 'desktop opens the player by default');
ok(!opensPlayerOnPlay(AUTO_OPEN_DEFAULTS, true), 'Android stays in the pill by default');

// Each platform reads only its own key.
ok(autoOpenKey(true) === 'openPlayerOnPlayAndroid', 'Android key');
ok(autoOpenKey(false) === 'openPlayerOnPlay', 'desktop key');
ok(opensPlayerOnPlay({ openPlayerOnPlay: false, openPlayerOnPlayAndroid: true }, true), 'Android switched on');
ok(!opensPlayerOnPlay({ openPlayerOnPlay: true, openPlayerOnPlayAndroid: false }, true), 'desktop key ignored on Android');
ok(!opensPlayerOnPlay({ openPlayerOnPlay: false, openPlayerOnPlayAndroid: true }, false), 'Android key ignored on desktop');

// An install from before this setting has the whole appearance object saved, with the desktop key
// set to true. Loading it over the defaults (as initTheme does) must still leave Android closed:
// that is the reason for a key of its own.
const older = { openPlayerOnPlay: true };
ok(!opensPlayerOnPlay({ ...AUTO_OPEN_DEFAULTS, ...older }, true), 'an older saved appearance keeps the new Android default');
ok(opensPlayerOnPlay({ ...AUTO_OPEN_DEFAULTS, ...older }, false), 'and the desktop keeps its saved choice');
// A saved Android choice survives the same load.
ok(opensPlayerOnPlay({ ...AUTO_OPEN_DEFAULTS, openPlayerOnPlayAndroid: true }, true), 'a saved Android choice is kept');

// Wiring.
const src = (p: string) => readFileSync(new URL(p, import.meta.url), 'utf8');
const theme = src('./theme.svelte.ts');
ok(theme.includes('...AUTO_OPEN_DEFAULTS'), 'the appearance store takes both defaults from autoopen.ts');
// initTheme only reads back the boolean keys it lists; one left out is never persisted.
const loaded = theme.slice(theme.indexOf('export function initTheme'));
ok(/'openPlayerOnPlay',/.test(loaded) && /'openPlayerOnPlayAndroid',/.test(loaded), 'initTheme reads both keys back');
const player = src('./player.svelte.ts');
ok(/openPlayer = \(\) => \{\s*if \(opensPlayerOnPlay\(appearance, isAndroid\)\) np\.open = true;/.test(player), 'openPlayer asks autoopen.ts, at the call');
const settings = src('./components/AppearanceSettings.svelte');
ok(settings.includes('checked={appearance[autoOpenKey(isAndroid)]}'), 'the switch shows the platform key');
ok(settings.includes('setAppearance({ [autoOpenKey(isAndroid)]: on })'), 'the switch saves the platform key');
const phone = settings.slice(settings.indexOf('{#if platform.compact}'), settings.indexOf('{:else}', settings.indexOf('{#if platform.compact}')));
ok(phone.includes('control: openPlayerSwitch'), 'the phone layout shows the switch');

console.log('ok');
