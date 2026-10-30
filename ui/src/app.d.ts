// See https://svelte.dev/docs/kit/types#app.d.ts
// for information about these interfaces
declare global {
	namespace App {
		// interface Error {}
		// interface Locals {}
		// interface PageData {}
		interface PageState {
			/** The phone's full-screen player is open on this history entry, so Back closes it. */
			sheet?: 'player';
			/** A dialog is open on this history entry (Android), so Back closes it. */
			dialog?: boolean;
		}
		// interface Platform {}
	}
}

export {};
