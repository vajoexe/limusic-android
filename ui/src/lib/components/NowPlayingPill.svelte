<script lang="ts">
	// "Now playing ↑/↓": the way back to the playing row once a list has scrolled it off screen.
	// The queue and the playlist page both float it over their scroller. Place it after the
	// scroller in the DOM, inside a positioned box: a transition painted before a scroller can
	// blank its scrollbar on WebKitGTK (docs/UI-PERFORMANCE.md). Opacity only.
	import { fade } from 'svelte/transition';
	import { MediaQuery } from 'svelte/reactivity';
	import { HugeiconsIcon } from '@hugeicons/svelte';
	import { ArrowDown01Icon, ArrowUp01Icon } from '@hugeicons/core-free-icons';
	import { t } from '$lib/i18n.svelte';
	import { platform } from '$lib/platform.svelte';

	let {
		above,
		onclick,
		overPage = false
	}: {
		above: boolean;
		onclick: () => void;
		/** Floats over a page, where a phone on its side has the mini player in the bottom corner
		 *  (`--dock` is its height): the pill rises above it rather than sitting beside it. */
		overPage?: boolean;
	} = $props();

	const reducedMotion = new MediaQuery('(prefers-reduced-motion: reduce)');
</script>

<button
	class="absolute bottom-3 left-1/2 z-10 flex -translate-x-1/2 cursor-pointer items-center rounded-full border bg-popover font-medium text-popover-foreground shadow-lg hover:bg-accent {platform.short
		? 'gap-1 px-2 py-0.5 text-[11px]'
		: 'gap-1.5 px-3 py-1.5 text-xs'}"
	style:bottom={overPage && platform.short ? 'calc(var(--dock, 0px) + 0.25rem)' : undefined}
	{onclick}
	transition:fade={{ duration: reducedMotion.current ? 0 : 150 }}
>
	<!-- altIcon/showAlt: `icon` is frozen at mount. -->
	<HugeiconsIcon icon={ArrowDown01Icon} altIcon={ArrowUp01Icon} showAlt={above} class="size-3.5" />
	{t('player.now_playing')}
</button>
