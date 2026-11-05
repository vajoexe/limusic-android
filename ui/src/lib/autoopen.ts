// Whether starting playback opens the full player, and which saved preference says so.
//
// The desktop keeps upstream's `openPlayerOnPlay` (on by default, #64). Android has a preference
// of its own, off by default: a song starts in the player pill at the bottom, and a tap on the pill
// opens the player. It can't reuse upstream's key with a new default, because the appearance
// object is saved whole on every change: anyone who ever touched an appearance setting has
// `openPlayerOnPlay: true` stored, and a changed default would never reach them (the same trap
// `stagePlayer` fell into, see theme.svelte.ts).
//
// Plain TypeScript, no runes, so autoopen.check.ts can run it under node.

export const AUTO_OPEN_DEFAULTS = {
	/** Desktop: starting playback opens the now-playing view. Off, it plays and leaves you put. */
	openPlayerOnPlay: true,
	/** Android: starting playback opens the full player. Off, it plays in the pill. */
	openPlayerOnPlayAndroid: false
};

export type AutoOpenKey = keyof typeof AUTO_OPEN_DEFAULTS;

/** The preference that applies on this platform. */
export function autoOpenKey(android: boolean): AutoOpenKey {
	return android ? 'openPlayerOnPlayAndroid' : 'openPlayerOnPlay';
}

/** Does starting playback open the player, given the saved preferences? */
export function opensPlayerOnPlay(prefs: Record<AutoOpenKey, boolean>, android: boolean): boolean {
	return prefs[autoOpenKey(android)];
}
