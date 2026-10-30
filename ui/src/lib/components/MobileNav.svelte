<script lang="ts">
	// The phone's bottom navigation: the sidebar's destinations, plus Settings (a dialog on the
	// desktop too). Sits above the gesture bar, which the page draws under (edge to edge).
	import { HugeiconsIcon } from '@hugeicons/svelte';
	import {
		Home01Icon,
		Search01Icon,
		LibraryIcon,
		Chart02Icon,
		Settings01Icon
	} from '@hugeicons/core-free-icons';
	import { page } from '$app/state';
	import { ui } from '$lib/player.svelte';
	import { t } from '$lib/i18n.svelte';

	/** A phone on its side: a rail down the left instead of a bar along the bottom, since there
	 *  the height is what is short and the width is spare. */
	let { rail = false }: { rail?: boolean } = $props();

	const nav = $derived([
		{ href: '/', label: t('nav.home'), icon: Home01Icon },
		{ href: '/search', label: t('nav.search'), icon: Search01Icon },
		{ href: '/library', label: t('nav.library'), icon: LibraryIcon },
		{ href: '/stats', label: t('nav.stats'), icon: Chart02Icon }
	]);
	const isActive = (href: string) =>
		href === '/' ? page.url.pathname === '/' : page.url.pathname.startsWith(href);

	// A phone on its side is ~380px tall, and the bar, the mini player and the top bar took half of
	// it. There the labels go (each item keeps its name for screen readers) and the bar slims down.
	const item = $derived(
		rail
			? 'flex min-h-0 flex-1 flex-col items-center justify-center transition-colors'
			: 'flex min-w-0 flex-1 flex-col items-center gap-1 pt-2 pb-1.5 text-[11px] font-medium transition-colors [@media(max-height:500px)]:py-1'
	);
	const label = 'max-w-full truncate [@media(max-height:500px)]:hidden';
</script>

<!-- Above the mini player (z-10): dragging it down slides it under the bar, not over it. -->
<nav
	class="relative z-10 flex shrink-0 bg-card {rail
		? 'w-12 flex-col border-r'
		: 'border-t'}"
	style={rail
		? 'padding-top:var(--inset-top);padding-bottom:var(--inset-bottom)'
		: 'padding-bottom:var(--inset-bottom)'}
	aria-label={t('mobile.navigation')}
>
	{#if rail}
		<!-- On its side the rail runs past the camera cutout, which sits mid-edge: the destinations
		     keep to the half above it, Settings has the half below to itself, and the middle stays
		     empty. The lower half mirrors the upper one, four slots with the padding at the far end,
		     so Settings sits as far from the bottom as Home does from the top. -->
		<div class="flex min-h-0 flex-1 flex-col pt-2">
			{#each nav as n (n.href)}{@render link(n)}{/each}
		</div>
		<div class="h-12 shrink-0" aria-hidden="true"></div>
		<div class="flex min-h-0 flex-1 flex-col pb-2">
			<div class="min-h-0 flex-[3]" aria-hidden="true"></div>
			{@render settingsButton()}
		</div>
	{:else}
		{#each nav as n (n.href)}{@render link(n)}{/each}
		{@render settingsButton()}
	{/if}
</nav>

{#snippet link(n: (typeof nav)[number])}
	{@const on = isActive(n.href)}
	<a
		href={n.href}
		class="{item} {on ? 'text-foreground' : 'text-muted-foreground'}"
		aria-current={on ? 'page' : undefined}
		aria-label={n.label}
	>
		<span
			class="flex {rail ? 'h-10 w-9' : 'h-8 w-14'} items-center justify-center rounded-full transition-colors {on
				? 'bg-primary/15 text-primary'
				: ''}"
		>
			<HugeiconsIcon icon={n.icon} class="h-5 w-5" />
		</span>
		<span class={label}>{n.label}</span>
	</a>
{/snippet}

{#snippet settingsButton()}
	<button
		class="{item} text-muted-foreground"
		onclick={() => (ui.settingsOpen = true)}
		aria-label={t('nav.settings')}
	>
		<span class="flex {rail ? 'h-10 w-9' : 'h-8 w-14'} items-center justify-center rounded-full">
			<HugeiconsIcon icon={Settings01Icon} class="h-5 w-5" />
		</span>
		<span class={label}>{t('nav.settings')}</span>
	</button>
{/snippet}
