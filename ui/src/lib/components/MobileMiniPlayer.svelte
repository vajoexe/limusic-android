<script lang="ts">
	// The phone's player bar: one row above the bottom navigation, the track and the three buttons a
	// thumb reaches for (previous, play/pause, next). Tapping anywhere else opens the full-screen player (MobilePlayer), and so
	// does a swipe up. A swipe down puts a session that isn't playing away (`dismissSession`); a
	// playing one springs back, because the gesture must never be what stops the music.
	import { HugeiconsIcon } from '@hugeicons/svelte';
	import {
		MusicNote01Icon,
		NextIcon,
		PauseIcon,
		PlayIcon,
		PreviousIcon
	} from '@hugeicons/core-free-icons';
	import * as api from '$lib/api';
	import { np, playback, toast } from '$lib/player.svelte';
	import { thumb } from '$lib/thumb';
	import { t } from '$lib/i18n.svelte';
	import Marquee from './Marquee.svelte';

	/** A phone on its side (`platform.short`): a compact pill the layout floats at the bottom right,
	 *  instead of a full-width row. Same gestures and buttons. */
	let { pill = false }: { pill?: boolean } = $props();

	const pct = $derived(playback.duration ? (playback.position / playback.duration) * 100 : 0);

	/** How far down a release has to be to count as "put it away", CSS px. Under it, the capsule
	 *  springs back: a thumb resting on it, or a slightly vertical tap, does nothing. */
	const DISMISS = 56;

	let start: { x: number; y: number } | null = null;
	/** The drag so far: down is positive. Only downward moves follow the finger. */
	let dragY = $state(0);
	/** Mid-gesture or mid-exit: the capsule ignores the CSS transition while the finger leads it. */
	let dragging = $state(false);
	let leaving = $state(false);
	/** A drag ended on this capsule, so the click that follows is not a tap. */
	let moved = false;

	function onDown(e: PointerEvent) {
		if (leaving || (e.target as HTMLElement).closest('button')) return;
		start = { x: e.clientX, y: e.clientY };
		moved = false;
		(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
	}
	function onMove(e: PointerEvent) {
		if (!start) return;
		const dx = e.clientX - start.x;
		const dy = e.clientY - start.y;
		if (!dragging) {
			// Decide once, past a little slop: mostly sideways is not this gesture at all.
			if (Math.hypot(dx, dy) < 8) return;
			if (Math.abs(dx) > Math.abs(dy)) return void (start = null);
			dragging = true;
			moved = true;
		}
		dragY = Math.max(0, dy);
	}
	async function onUp(e: PointerEvent) {
		if (!start) return;
		const dy = e.clientY - start.y;
		start = null;
		if (!dragging) return;
		dragging = false;
		if (dy < -40) {
			dragY = 0;
			np.open = true;
			return;
		}
		if (dy < DISMISS) return void (dragY = 0);
		if (!playback.paused) {
			dragY = 0;
			toast(t('mobile.dismiss_playing'));
			return;
		}
		// Off it goes, then the session: the capsule unmounts with `playback.now`.
		leaving = true;
		dragY = 160;
		try {
			if (await api.dismissSession()) {
				playback.now = null;
				playback.position = 0;
				playback.duration = 0;
				return;
			}
		} catch {
			// Fall through: it stays, as it would have if the gesture were never made.
		}
		leaving = false;
		dragY = 0;
	}
	function onCancel() {
		start = null;
		dragging = false;
		if (!leaving) dragY = 0;
	}
</script>

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div
	class="relative flex shrink-0 touch-none items-center overflow-hidden border bg-card {pill
		? 'gap-2 rounded-full py-1 pr-1 pl-1 shadow-lg'
		: 'mx-2 mb-2 gap-3 rounded-xl p-2 pr-1 shadow-sm'} {dragging
		? ''
		: 'transition-[transform,opacity] duration-200 ease-out'}"
	style="transform:translateY({dragY}px);opacity:{1 - Math.min(dragY / 160, 1) * 0.8}"
	onclick={(e) => {
		if (moved) return void (moved = false);
		if (!(e.target as HTMLElement).closest('button')) np.open = true;
	}}
	onpointerdown={onDown}
	onpointermove={onMove}
	onpointerup={onUp}
	onpointercancel={onCancel}
>
	{#if playback.now?.thumbnail}
		<img
			src={thumb(playback.now.thumbnail, 120)}
			alt=""
			style="max-width:none"
			class="shrink-0 object-cover {pill ? 'h-9 w-9 rounded-full' : 'h-11 w-11 rounded-lg'}"
		/>
	{:else}
		<div
			class="flex shrink-0 items-center justify-center bg-muted text-muted-foreground/50 {pill
				? 'h-9 w-9 rounded-full'
				: 'h-11 w-11 rounded-lg'}"
		>
			<HugeiconsIcon icon={MusicNote01Icon} class="h-5 w-5" />
		</div>
	{/if}
	<div class="min-w-0 flex-1">
		<Marquee text={playback.now?.title ?? t('player.not_playing')} class="text-sm font-medium" />
		<p class="truncate text-xs text-muted-foreground">{playback.now?.artists ?? ''}</p>
	</div>
	<button
		class="flex {pill
			? 'size-9'
			: 'size-11'} shrink-0 items-center justify-center rounded-full active:bg-foreground/10"
		onclick={() => api.prevTrack()}
		aria-label={t('player.previous')}
	>
		<HugeiconsIcon icon={PreviousIcon} class="h-5 w-5" />
	</button>
	<button
		class="flex size-11 shrink-0 items-center justify-center rounded-full active:bg-foreground/10"
		onclick={() => api.togglePause()}
		aria-label={playback.paused ? t('player.play') : t('player.pause')}
	>
		<!-- showAlt, not a ternary: HugeiconsIcon reads `icon` once at mount. -->
		<HugeiconsIcon icon={PauseIcon} altIcon={PlayIcon} showAlt={playback.paused} class="h-6 w-6" />
	</button>
	<button
		class="flex {pill
			? 'size-9'
			: 'size-11'} shrink-0 items-center justify-center rounded-full active:bg-foreground/10"
		onclick={() => api.nextTrack()}
		aria-label={t('player.next')}
	>
		<HugeiconsIcon icon={NextIcon} class="h-5 w-5" />
	</button>
	<div class="absolute {pill ? 'inset-x-6' : 'inset-x-2'} bottom-0 h-0.5 overflow-hidden rounded-full bg-foreground/10">
		<div class="h-full bg-primary" style="width:{pct}%"></div>
	</div>
</div>
