<script lang="ts">
	// The phone's top bar: what the titlebar carries on the desktop, cut to what a phone needs and
	// sized for a finger. Back appears below the four bottom-nav roots (the system Back works too);
	// the window buttons, mini player, theater mode and Discord stay desktop-only.
	import { HugeiconsIcon } from '@hugeicons/svelte';
	import {
		ArrowLeft01Icon,
		Link04Icon,
		Refresh03Icon,
		UserGroup02Icon
	} from '@hugeicons/core-free-icons';
	import { page } from '$app/state';
	import { appIcon } from '$lib/appicon.svelte';
	import { platform } from '$lib/platform.svelte';
	import { lt } from '$lib/lt.svelte';
	import { refreshView, ui } from '$lib/player.svelte';
	import { t } from '$lib/i18n.svelte';
	import AccountMenu from './AccountMenu.svelte';

	const ROOTS = ['/', '/search', '/library', '/stats'];
	const atRoot = $derived(ROOTS.includes(page.url.pathname));

	// On its side (`platform.short`) every row counts: the bar slims to the height of its buttons.
	const btn = $derived(
		`flex ${platform.short ? 'size-8 [&_svg]:size-4' : 'size-10'} shrink-0 items-center justify-center rounded-full text-muted-foreground transition-colors active:bg-foreground/10`
	);
</script>

<header
	class="relative z-10 flex shrink-0 items-center gap-1 bg-background px-2 {platform.short
		? 'pb-0'
		: 'pb-1'}"
	style="padding-top:calc(var(--inset-top) + {platform.short ? '0.125rem' : '0.25rem'})"
>
	{#if atRoot}
		<img
			src={appIcon.src}
			alt=""
			class="pointer-events-none mx-2 {platform.short ? 'h-5 w-5' : 'h-6 w-6'}"
		/>
		<span class="font-heading font-bold tracking-tight {platform.short ? 'text-base' : 'text-lg'}"
			>Limusic</span
		>
	{:else}
		<button class={btn} onclick={() => history.back()} aria-label={t('common.back')}>
			<HugeiconsIcon icon={ArrowLeft01Icon} strokeWidth={2.5} class="h-5 w-5 text-foreground" />
		</button>
	{/if}
	<div class="flex-1"></div>
	<button class={btn} onclick={refreshView} aria-label={t('common.refresh')}>
		<HugeiconsIcon icon={Refresh03Icon} class="h-5 w-5" />
	</button>
	<button class={btn} onclick={() => (ui.linkOpen = true)} aria-label={t('dialogs.link.title')}>
		<HugeiconsIcon icon={Link04Icon} class="h-5 w-5" />
	</button>
	<button
		class="{btn} {lt.role !== 'none' ? 'text-primary' : ''}"
		onclick={() => (ui.ltOpen = true)}
		aria-label={t('nav.listen_together')}
	>
		<HugeiconsIcon icon={UserGroup02Icon} class="h-5 w-5" />
	</button>
	<AccountMenu />
	<!-- A fade hung under the bar, over the top of the page: a page's artwork wash then rises into
	     the bar instead of stopping at a hard line, and scrolled content slips under it softly. -->
	<div
		class="pointer-events-none absolute inset-x-0 top-full h-6 bg-gradient-to-b from-background to-transparent"
		aria-hidden="true"
	></div>
</header>
