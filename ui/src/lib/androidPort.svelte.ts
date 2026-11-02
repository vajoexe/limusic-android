// The Android port's own corner: where it lives on GitHub, its version, and the update check that
// runs on every launch (the desktop's updater plugin has nothing to install on Android).
import { androidUpdateCheck, androidVersion, type AndroidUpdate, type AndroidVersion } from './api';

export const ANDROID_REPO_URL = 'https://github.com/vajoexe/limusic-android';
export const ANDROID_ISSUES_URL = `${ANDROID_REPO_URL}/issues`;
export const ANDROID_RELEASES_URL = `${ANDROID_REPO_URL}/releases`;

export const port = $state({
	version: null as AndroidVersion | null,
	/** A newer release, while its notice is up. Cleared by dismissing it, for the rest of this
	 *  run only: the next launch checks again, and asks again if it is still newer. */
	update: null as AndroidUpdate | null
});

let checked = false;

/** Once per launch, in the background: nothing waits on it, and no network, GitHub being down or
 *  a reply that makes no sense all end the same way, silently. */
export function checkForAndroidUpdate() {
	if (checked) return;
	checked = true;
	androidUpdateCheck()
		.then((u) => (port.update = u))
		.catch((e) => console.warn('update check skipped', e));
}

export function loadAndroidVersion() {
	if (port.version) return;
	androidVersion()
		.then((v) => (port.version = v))
		.catch(() => {});
}
