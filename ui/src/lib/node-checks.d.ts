// Types for the few node built-ins the self-checks (`*.check.ts`, run by run-checks.mjs) use to read
// the sources they guard. `ui/` has no @types/node and the app never runs in node, so these
// declarations stand in for it instead of a new dependency. Not used by the app.
declare module 'node:fs' {
	export function readFileSync(path: string | URL, encoding: 'utf8'): string;
	export function readdirSync(path: string | URL): string[];
	export function statSync(path: string | URL): { isDirectory(): boolean };
}
declare module 'node:path' {
	export function join(...parts: string[]): string;
	export function relative(from: string, to: string): string;
}
