// The Android port's own corner: where it lives on GitHub, its version, and the update check (the
// desktop's updater plugin has nothing to install on Android).
//
// The check runs at startup unless Settings > Startup turns it off, and again whenever Settings
// opens without an answer in hand (the startup check was off, offline or refused). An update it
// finds is shown in Settings > About, and at startup also as a popup, which "Don't show again"
// turns off for good (Settings > Startup turns it back on).
import {
	androidUpdateCheck,
	androidVersion,
	getSettings,
	setSetting,
	type AndroidUpdate,
	type AndroidVersion,
	type FetchError
} from './api';

export const ANDROID_REPO_URL = 'https://github.com/vajoexe/limusic-android';
export const ANDROID_ISSUES_URL = `${ANDROID_REPO_URL}/issues`;
export const ANDROID_RELEASES_URL = `${ANDROID_REPO_URL}/releases`;

/** Settings keys (on unless set to `'false'`). */
export const UPDATE_CHECK_SETTING = 'android_update_check';
export const UPDATE_POPUP_SETTING = 'android_update_popup';

export type UpdateStatus = 'unchecked' | 'checking' | 'current' | 'available' | 'failed';

export const port = $state({
	version: null as AndroidVersion | null,
	/** The last check's answer. */
	status: 'unchecked' as UpdateStatus,
	/** A newer release, once a check has found one. */
	update: null as AndroidUpdate | null,
	/** Why the last check failed. */
	error: null as FetchError | null,
	/** The startup popup is up. Closing it clears this for the rest of the run only. */
	popup: false
});

const asFetchError = (e: unknown): FetchError =>
	e && typeof e === 'object' && 'kind' in e ? (e as FetchError) : { kind: 'unknown' };

/** One check at a time; a second caller shares the first one's answer. */
let inFlight: Promise<void> | null = null;

function check(): Promise<void> {
	if (inFlight) return inFlight;
	port.status = 'checking';
	inFlight = androidUpdateCheck()
		.then((u) => {
			port.update = u;
			port.error = null;
			port.status = u ? 'available' : 'current';
		})
		.catch((e) => {
			// Nothing waits on this and nothing else breaks: the status says it failed, and
			// Settings > About offers another try.
			port.error = asFetchError(e);
			port.status = 'failed';
		})
		.finally(() => (inFlight = null));
	return inFlight;
}

/** At startup, in the background, as Settings > Startup has it. */
export async function checkForAndroidUpdate() {
	let settings: Record<string, string> = {};
	try {
		settings = await getSettings();
	} catch {
		// Unreadable settings: the defaults, which check and show.
	}
	if (settings[UPDATE_CHECK_SETTING] === 'false') return;
	await check();
	if (port.status === 'available' && settings[UPDATE_POPUP_SETTING] !== 'false') port.popup = true;
}

/** Settings opened: ask now unless there is already an answer from this run. */
export function ensureAndroidUpdateInfo() {
	if (port.status === 'unchecked' || port.status === 'failed') void check();
}

/** The Retry button in Settings > About. */
export function retryAndroidUpdateCheck() {
	return check();
}

/** "Don't show again" on the popup: no more popups, until Settings > Startup turns them back on.
 *  Updates still show in Settings > About. */
export async function neverShowUpdatePopup() {
	port.popup = false;
	await setSetting(UPDATE_POPUP_SETTING, 'false');
}

export function loadAndroidVersion() {
	if (port.version) return;
	androidVersion()
		.then((v) => (port.version = v))
		.catch(() => {});
}
