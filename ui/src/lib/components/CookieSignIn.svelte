<script lang="ts">
	// Android's sign-in (`api.loginWebview` opens this there). First choice: Google's own sign-in
	// page (SignInActivity.kt, via `login_webview`). Fallback, for an account Google won't sign in
	// there: the cookies of a session the user already has elsewhere, to Rust's `sign_in_cookie`.
	// Both end in the same `AppState::sign_in` as the desktop's sign-in window: validated against
	// YouTube before anything is kept, rolled back on failure, and on to the channel picker for a
	// multi-channel account.
	//
	// The field is a credential: it is cleared on close and on success, never logged, and the dialog
	// says plainly what it is and where it goes.
	import * as Dialog from '$lib/components/ui/dialog';
	import { Button } from '$lib/components/ui/button';
	import { Textarea } from '$lib/components/ui/textarea';
	import { readText, writeText } from '@tauri-apps/plugin-clipboard-manager';
	import * as api from '$lib/api';
	import { platform } from '$lib/platform.svelte';
	import { toast } from '$lib/player.svelte';
	import { t } from '$lib/i18n.svelte';

	let cookie = $state('');
	let busy = $state(false);
	let error = $state('');

	$effect(() => {
		if (!platform.signInOpen) {
			cookie = '';
			error = '';
		}
	});

	async function google() {
		const addAccount = platform.signInAddAccount;
		// The sign-in page covers the app; its result arrives as a toast and `auth-changed`.
		platform.signInOpen = false;
		try {
			await api.openGoogleSignIn(addAccount);
		} catch (err) {
			toast.error(String(err));
		}
	}

	/** What the Paste button put in the field, to empty the clipboard of it after a sign-in. */
	let pasted = '';

	async function paste() {
		try {
			cookie = (await readText()) ?? '';
			pasted = cookie;
		} catch {
			// No clipboard permission or nothing in it: the field's own long-press paste still works.
		}
	}

	async function submit(e: Event) {
		e.preventDefault();
		if (!cookie.trim() || busy) return;
		busy = true;
		error = '';
		try {
			// `true` means a channel has to be picked; Rust raises the picker itself.
			const picking = await api.signInCookie(cookie);
			// The session is in Limusic now: don't leave a copy on the clipboard, where the keyboard's
			// clipboard history and any app reading it would see it. Only when the field still holds
			// exactly what the Paste button read, so nothing else the user copied is touched.
			if (pasted && cookie === pasted) writeText('').catch(() => {});
			pasted = '';
			platform.signInOpen = false;
			if (!picking) toast.success(t('toasts.signed_in'));
		} catch (err) {
			error = String(err);
		} finally {
			busy = false;
		}
	}
</script>

<Dialog.Root bind:open={platform.signInOpen}>
	<!-- No focus on open: on a phone that would raise the keyboard over the steps, and the usual
	     way in is the Paste button anyway. -->
	<Dialog.Content
		class="max-h-[85dvh] overflow-y-auto sm:max-w-lg"
		onOpenAutoFocus={(e) => e.preventDefault()}
	>
		<Dialog.Header>
			<Dialog.Title>{t('mobile.sign_in_title')}</Dialog.Title>
			<Dialog.Description>{t('mobile.sign_in_desc')}</Dialog.Description>
		</Dialog.Header>
		<Button onclick={google}>{t('mobile.sign_in_google')}</Button>
		<p class="text-xs text-muted-foreground">{t('mobile.sign_in_google_hint')}</p>
		<div class="flex items-center gap-3 text-xs text-muted-foreground">
			<div class="h-px flex-1 bg-border"></div>
			{t('mobile.sign_in_or_cookie')}
			<div class="h-px flex-1 bg-border"></div>
		</div>
		<p class="text-sm text-muted-foreground">{t('mobile.sign_in_steps')}</p>
		<form class="flex flex-col gap-3" onsubmit={submit}>
			<label class="flex flex-col gap-1.5 text-sm font-medium">
				{t('mobile.cookie_label')}
				<Textarea
					bind:value={cookie}
					rows={4}
					autocomplete="off"
					autocapitalize="off"
					spellcheck={false}
					placeholder={t('mobile.cookie_placeholder')}
					class="font-mono text-xs [-webkit-text-security:disc]"
				/>
			</label>
			{#if error}<p class="text-sm text-destructive">{error}</p>{/if}
			<p class="text-xs text-muted-foreground">{t('mobile.sign_in_privacy')}</p>
			<div class="flex justify-end gap-2">
				<Button type="button" variant="outline" onclick={paste}>{t('mobile.paste')}</Button>
				<Button type="submit" disabled={!cookie.trim() || busy}>
					{busy ? t('mobile.signing_in') : t('nav.sign_in')}
				</Button>
			</div>
		</form>
	</Dialog.Content>
</Dialog.Root>
