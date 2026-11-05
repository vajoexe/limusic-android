// What the Android port says differently from the desktop app, picked by `t()` on Android only.
// Kept out of the catalogs so the desktop strings, and every language's coverage in the picker,
// stay as they are.
//
// `all`: the port's identity and who Ko-fi reaches. These must read right in every language, so
// they win over a translated desktop string (English until someone translates them).
// `en`: desktop wording ("this computer") put in phone terms. Only over the English catalog: a
// translated sentence is better than an English one, whatever device it names.
import type { TranslationKey } from '../i18n.svelte';

export const ANDROID_ALL: Partial<Record<TranslationKey, string>> = {
	'settings.about.description':
		'A beautiful, fast, and lightweight music player powered by Tauri and Svelte. This is an unofficial Android port of the Limusic desktop app.',
	'settings.about.kofi': 'Support the Limusic developers',
	'settings.about.kofi_hint':
		'Limusic is free and made by SimoHypers and its contributors. Ko-fi goes to them, the original developers, not to this unofficial Android port.',
	// Android's "Sign in" opens a chooser (CookieSignIn.svelte): Google's page, or a pasted cookie.
	'common.sign_in_google': 'Sign in',
	'nav.sign_in_hint':
		'Sign in with your YouTube Music session to reach your library and playlists.'
};

export const ANDROID_EN: Partial<Record<TranslationKey, string>> = {
	'library.songs_signed_out':
		'Sign in to see the songs saved in your YouTube Music library. Music on this device is in the Local tab.',
	'library.on_this_device_tooltip': 'Saved on this device, not on a YouTube Music account',
	'settings.themes.font_placeholder': 'Font installed on this device, e.g. Inter',
	'settings.themes.load_font_file_hint':
		'Load a .ttf, .otf or .woff from this device. It joins both dropdowns above.',
	'settings.themes.mode_hint': "System follows your device's setting and switches with it.",
	// Off by default on Android (autoopen.ts), so the hint says where the song went instead.
	'settings.themes.open_player_hint':
		'On, playing a song, album or playlist opens the full player. Off, it starts playing in the bar at the bottom of the screen, and tapping the bar opens the player.',
	'dialogs.edit_playlist.local_artwork_note':
		'Artwork stays on this device. Square JPEG or PNG works best.',
	'dialogs.new_playlist.device_desc': 'No account needed, it stays on this device',
	'dialogs.new_playlist.device_only':
		'It stays on this device, no account needed. Sign in to make playlists on YouTube Music instead.',
	'dialogs.new_playlist.local_files': 'Songs stored on this device can only go in a playlist kept on it.',
	'import.desc':
		'Bring your playlists over. It all runs on this device: Spotify is only asked for the playlist, YouTube Music only for the songs.',
	// Touch: taps, not clicks; and a card is added from its ⋯ menu rather than dragged.
	'home.shortcuts_desc':
		"Whatever you reach for most, one tap from home. Pick from your library, or use Add a shortcut in a card's ⋯ menu.",
	'import.nudge_desc': 'Bring your playlists and Liked Songs over in a few taps.',
	'toasts.could_not_copy_link': 'Could not copy the link. Select it and copy it by hand.',
	'settings.about.diagnostics_save_hint': 'Same text as a .txt file, to attach to the issue instead of pasting it.',
	// Nothing gets dropped onto a phone screen: the zip comes in through Choose file.
	'import.drop_hint':
		'When the email arrives, pick the zip with Choose file. CSV files from Exportify, TuneMyMusic or Soundiiz work too.',
	'home.sections_hint': "Hold a section's handle and drag it to move it. Hidden sections keep their place.",
	// Read out by TalkBack, where Space and Enter mean nothing: the row says what it is.
	// Integrations (Discord, the tray) and the updater are desktop-only, so the tabs don't promise them.
	// What happens when the app opens has a tab of its own (Startup).
	'settings.tabs.general_hint': 'Language and listening history.',
	'settings.tabs.about_hint': 'Version, support and what changed.',
	// An app on a phone has no environment to set a variable in.
	'settings.general.stream_clients_hint': 'Turn a client off to skip it when resolving streams.',
	'selection.track': '{title}',
	'selection.track_guest': '{title}'
};
