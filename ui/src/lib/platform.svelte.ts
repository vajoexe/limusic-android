// Which shell the app wears, and the system UI it has to keep clear of.
//
// The desktop window never gets narrower than 900px (tauri.conf.json), so the compact shell is
// Android's alone: a phone, or a narrow split-screen / DeX window. A tablet in landscape or a wide
// DeX window gets the desktop layout (sidebar, player bar, the now-playing view with its queue and
// lyrics side by side), which is the same app with room to breathe, minus the window chrome the
// system draws itself (`native_chrome` reports "on" there).
import { browser } from '$app/environment';
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';

/** Running on Android. Constant for the life of the page. */
export const isAndroid = browser && /\bAndroid\b/i.test(navigator.userAgent);

/** Below this width an Android window gets the phone layout. Material's compact/medium split
 *  (600dp) would hand a 700px window the desktop layout, which needs about 840 to fit the sidebar,
 *  the page and the player bar's three clusters. */
const COMPACT_MAX = 840;
/** Below this height (a phone on its side, ~380px) the phone shell packs tighter: the mini player
 *  floats as a pill at the bottom right and the navigation drops its labels. */
const SHORT_MAX = 500;

export const platform = $state({
	/** The phone shell: bottom navigation, mini player, full-screen player. */
	compact: false,
	/** A short window (`SHORT_MAX`): landscape on a phone. Always the phone shell as well. */
	short: false,
	/** Kept clear of the status bar, cutout, navigation bar and (while open) the keyboard, in CSS
	 *  pixels. Zero on the desktop. */
	insets: { top: 0, right: 0, bottom: 0, left: 0 },
	/** Android's sign-in dialog: Google's sign-in page, or a pasted cookie (see `loginWebview`). */
	signInOpen: false,
	/** That dialog was opened to add another account rather than to sign in. */
	signInAddAccount: false
});

function applyInsets([top, right, bottom, left]: [number, number, number, number]) {
	platform.insets = { top, right, bottom, left };
	const s = document.documentElement.style;
	s.setProperty('--inset-top', `${top}px`);
	s.setProperty('--inset-right', `${right}px`);
	s.setProperty('--inset-bottom', `${bottom}px`);
	s.setProperty('--inset-left', `${left}px`);
}

let started = false;

/** Wire the window size and inset listeners once, for the whole app. Before the first paint, so the
 *  page never flashes the wrong shell. */
export function initPlatform(): void {
	if (!browser || started) return;
	started = true;
	document.documentElement.classList.toggle('android', isAndroid);
	if (!isAndroid) return;
	// Or short at any width: the desktop shell does not fit 400-odd pixels of height either, and a
	// phone on its side is 915 wide as often as 832 (a 412x915 Pixel or Galaxy Ultra).
	const mq = window.matchMedia(
		`(max-width: ${COMPACT_MAX - 0.02}px), (max-height: ${SHORT_MAX - 0.02}px)`
	);
	const sync = () => {
		platform.compact = mq.matches;
		// For CSS that only the phone shell needs (layout.css: keyboard hints, `[data-kbd-hint]`).
		document.documentElement.classList.toggle('compact', mq.matches);
	};
	sync();
	mq.addEventListener('change', sync);
	const low = window.matchMedia(`(max-height: ${SHORT_MAX - 0.02}px)`);
	const syncShort = () => (platform.short = low.matches);
	syncShort();
	low.addEventListener('change', syncShort);
	// The activity reports the bars as they change (rotation, a DeX window crossing displays, the
	// keyboard), and holds the latest for a page that loads after the first report.
	invoke<[number, number, number, number]>('window_insets')
		.then(applyInsets)
		.catch(() => {});
	listen<[number, number, number, number]>('window-insets', (e) => applyInsets(e.payload)).catch(
		() => {}
	);
}
