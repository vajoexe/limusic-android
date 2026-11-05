// Self-check: no hover-only control the phone can tap without seeing it. No test runner in `ui/`,
// node 22 runs TypeScript directly:
//
//     node --experimental-strip-types ui/src/lib/hoverreveal.check.ts
//
// Prints "ok" and exits 0, or throws listing every offender.
//
// The phone shell (`html.compact`) has no hover at all (layout.css), so a control that only shows
// on hover (`opacity-0` plus some `…hover…:opacity-100`) is invisible there, and an invisible
// element still takes a tap. Each one carries `hover-reveal`, which layout.css turns into
// `pointer-events: none` on the phone while it is hidden, or `touch-show` as well, which shows it
// there instead. Upstream adds controls like this now and then; this is what notices.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const root = new URL('..', import.meta.url).pathname; // ui/src

function files(dir: string): string[] {
	return readdirSync(dir).flatMap((n) => {
		const p = join(dir, n);
		if (statSync(p).isDirectory()) return files(p);
		return /\.(svelte|ts)$/.test(n) && !/\.check\.ts$/.test(n) ? [p] : [];
	});
}

// String literals, multi-line ones included: class lists are often wrapped.
const literal = /"(?:[^"\\]|\\.){0,1500}"|'(?:[^'\\\n]|\\.){0,1500}'|`[^`]{0,3000}`/gs;
const hidden = /(?<![\w:/-])opacity-0(?![\w.-])/;
const revealedOnHover = /(?:group-hover|peer-hover|hover)(?:\/[\w-]+)?:opacity-(?:100|[1-9]\d)\b/;

const offenders: string[] = [];
let found = 0;
for (const f of files(root)) {
	const src = readFileSync(f, 'utf8');
	for (const m of src.matchAll(literal)) {
		const v = m[0];
		if (!hidden.test(v) || !revealedOnHover.test(v)) continue;
		found++;
		// Already inert: a decorative layer that never takes pointer events anywhere.
		if (/\bpointer-events-none\b/.test(v) || /\bhover-reveal\b/.test(v)) continue;
		const line = src.slice(0, m.index).split('\n').length;
		offenders.push(`${relative(root, f)}:${line}  ${v.replace(/\s+/g, ' ').slice(0, 120)}`);
	}
}
if (offenders.length) {
	throw new Error(
		`FAIL: hover-only controls without \`hover-reveal\` (invisible but tappable on a phone):\n  ${offenders.join('\n  ')}`
	);
}
// The scan has to be finding the controls at all, or it passes by matching nothing.
if (found < 15) throw new Error(`FAIL: only ${found} hover-only controls found; the scan is broken`);

// The rule that makes the class mean something, scoped to the phone.
const css = readFileSync(join(root, 'routes/layout.css'), 'utf8');
if (!/html\.compact \.hover-reveal:not\(\.touch-show\):not\(:focus-visible\):not\(:focus-within\)\s*\{\s*pointer-events: none;/.test(css))
	throw new Error('FAIL: layout.css lost the phone rule that makes hidden hover controls untappable');
if (!/html\.compact \.hover-reveal\.touch-show\s*\{\s*opacity: 1;/.test(css))
	throw new Error('FAIL: layout.css lost the rule that shows `touch-show` controls on the phone');

// The controls a phone can't do without: shown there, not made inert.
const mustShow: [string, RegExp][] = [
	['lib/components/Shortcuts.svelte', /hover-reveal touch-show[^"]*"\s*>\s*<HugeiconsIcon icon=\{Cancel01Icon\}/],
	['lib/components/ListenTogether.svelte', /hover-reveal touch-show[^"]*"\s*onclick=\{\(\) => api\.ltTransferHost/],
	['lib/components/ListenTogether.svelte', /hover-reveal touch-show[^"]*"\s*onclick=\{\(\) => api\.ltKick/]
];
for (const [f, re] of mustShow) {
	if (!re.test(readFileSync(join(root, f), 'utf8'))) throw new Error(`FAIL: ${f}: a phone-only way in lost \`touch-show\` (${re})`);
}

console.log(`ok (${found} hover-only controls, all handled)`);
