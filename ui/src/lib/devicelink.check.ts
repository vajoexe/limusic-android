// Self-check: the Android port leaves upstream's device link out. No test runner in `ui/`, node 22
// runs TypeScript directly:
//
//     node --experimental-strip-types ui/src/lib/devicelink.check.ts
//
// Prints "ok" and exits 0, or throws on the first broken invariant.
//
// Upstream's link is the desktop's half (Settings › Devices shows a code for a phone to type), and
// the port decided against it on Android (2026-11-09); desktop builds keep it as upstream has it.
// Pairing only starts from that tab, and the player bar's device picker only shows once something
// is linked, so leaving the tab out on Android is the whole switch. Upstream edits the tab list now
// and then, which is what this notices.
import { readFileSync } from 'node:fs';

function ok(cond: boolean, what: string): void {
	if (!cond) throw new Error(`FAIL: ${what}`);
}
const src = (p: string) => readFileSync(new URL(p, import.meta.url), 'utf8');

const dialog = src('./components/SettingsDialog.svelte');
const filter = dialog.slice(dialog.indexOf('] satisfies Tab[]).filter('), dialog.indexOf('));', dialog.indexOf('] satisfies Tab[]).filter(')));
ok(filter.length > 0, 'SettingsDialog still filters its tabs per platform');
ok(/isAndroid\s*\?[^:]*tb\.id !== 'devices'/.test(filter), "Android leaves out the Devices tab");
ok(!/:\s*tb\.id !== 'startup'[^)]*'devices'/.test(filter), 'the desktop keeps the Devices tab');

// The only other way in: the device picker, shown once a link exists.
const bar = src('./components/PlayerBar.svelte');
ok(bar.includes("{#if link.status !== 'off'}<DevicePicker />{/if}"), 'the device picker still waits for a link');
// Pairing is started from the Devices tab alone.
const starts = ['./components/DevicesSettings.svelte', './components/DevicePicker.svelte', './player.svelte.ts', './components/PlayerBar.svelte']
	.filter((f) => src(f).includes('linkStartPairing'));
ok(starts.length === 1 && starts[0] === './components/DevicesSettings.svelte', `pairing starts from the Devices tab only (found in ${starts.join(', ')})`);

console.log('ok');
