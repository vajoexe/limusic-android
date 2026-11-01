<script lang="ts">
	// The phone's full-screen player: theater mode's room (the cover's baked wash, its colour as
	// light, the vignette) around a portrait layout. The cover, or the lyrics, or the queue fill the
	// middle; the seek bar and transport sit low where a thumb reaches them.
	//
	// It is `np.open` on a phone, so everything that opens the desktop's player view opens this. The
	// layout gives it a history entry while it is up (`page.state.sheet`), so the system Back closes
	// it instead of leaving the page underneath. A swipe down on the header or cover closes it too.
	//
	// The same performance rules as theater mode apply (artroom.svelte.ts): no live blur, nothing
	// full-screen that repaints every frame.
	import { fade, fly } from 'svelte/transition';
	import { cubicOut } from 'svelte/easing';
	import { HugeiconsIcon } from '@hugeicons/svelte';
	import {
		ArrowDown01Icon,
		Comment01Icon,
		FavouriteIcon,
		Mic01Icon,
		MusicNote01Icon,
		NextIcon,
		PauseIcon,
		PlayIcon,
		PreviousIcon,
		Queue01Icon,
		RepeatIcon,
		ShuffleIcon,
		GoBackward15SecIcon,
		GoForward15SecIcon
	} from '@hugeicons/core-free-icons';
	import { RepeatForeverIcon } from '$lib/icons';
	import * as api from '$lib/api';
	import {
		cycleRepeat,
		np,
		openAddToPlaylist,
		playback,
		prefs,
		SKIP_SECS,
		skipBy,
		toggleNowPlayingRating
	} from '$lib/player.svelte';
	import { artRoom } from '$lib/artroom.svelte';
	import {
		canSwitch,
		claimVideo,
		parkVideo,
		pickVersion,
		showVideo,
		videoSide
	} from '$lib/video.svelte';
	import { platform } from '$lib/platform.svelte';
	import { appearance } from '$lib/theme.svelte';
	import { thumb } from '$lib/thumb';
	import { t } from '$lib/i18n.svelte';
	import Ambient from './Ambient.svelte';
	import ArtistLine from './ArtistLine.svelte';
	import CommentsView from './CommentsView.svelte';
	import LyricsView from './LyricsView.svelte';
	import Marquee from './Marquee.svelte';
	import QueueList from './QueueList.svelte';
	import SpeedPicker from './SpeedPicker.svelte';
	import TheaterMode from './TheaterMode.svelte';
	import TrackMenu from './TrackMenu.svelte';

	let { onClose }: { onClose: () => void } = $props();

	/** What fills the middle. The desktop's `np.tab` picks it on open, so a tab chosen there carries
	 *  over (the queue opens on the cover: it is a button away and the cover is the usual want). */
	let view = $state<'art' | 'lyrics' | 'queue' | 'comments'>(
		np.tab === 'lyrics' || np.tab === 'comments' ? np.tab : 'art'
	);
	/** A comment or reply is being typed. The keyboard takes half the screen, so the title and
	 *  controls step aside for it, or the box and its send button end up under the keyboard. Not
	 *  once the keyboard is hidden with the box still focused (Gboard's hide button).
	 *  The lyrics search counts too: its fields are in the source picker's popover, which lives
	 *  outside this section (a portal), so focus is watched on the document. Left in place there,
	 *  the title and controls squeezed the lyrics box the popover hangs from to nothing. */
	let focused = $state(false);
	const typing = $derived(focused && platform.keyboard);
	const onFocus = () =>
		queueMicrotask(() => {
			const el = document.activeElement;
			focused =
				!!el?.matches('textarea, input') &&
				(!!sheet?.contains(el) || !!el.closest('[data-popover-content]'));
		});
	$effect(() => {
		document.addEventListener('focusin', onFocus);
		document.addEventListener('focusout', onFocus);
		return () => {
			document.removeEventListener('focusin', onFocus);
			document.removeEventListener('focusout', onFocus);
		};
	});

	const toggle = (v: 'lyrics' | 'queue' | 'comments') => {
		view = view === v ? 'art' : v;
		np.tab = v;
	};

	const room = artRoom();
	/** A tab switch's crossfade, ms. */
	const XFADE = 220;

	/** The music video's box while it is the picture, for the ambient light to glow around. */
	let picBox = $state<HTMLElement | null>(null);

	// The cover, largest first, falling back on a load error like theater mode does.
	let attempt = $state(0);
	$effect(() => {
		playback.now?.thumbnail;
		attempt = 0;
	});
	const srcs = $derived([720, 400, 120].map((px) => thumb(playback.now?.thumbnail, px)));
	const src = $derived(srcs[attempt]);

	const fmt = (secs: number) => {
		if (!secs || secs < 0) return '0:00';
		const s = Math.floor(secs);
		const h = Math.floor(s / 3600);
		const m = Math.floor((s % 3600) / 60);
		const mm = h ? String(m).padStart(2, '0') : `${m}`;
		return `${h ? `${h}:` : ''}${mm}:${String(s % 60).padStart(2, '0')}`;
	};

	// Hold the thumb while dragging, like the player bar: mpv's ticks must not yank it back.
	let seekDrag = $state<number | null>(null);
	const shownPosition = $derived((seekDrag ?? playback.position) / playback.speed);
	const shownDuration = $derived(playback.duration / playback.speed);
	const pct = $derived(shownDuration ? (shownPosition / shownDuration) * 100 : 0);

	const shuffleOn = $derived(playback.queue.shuffle ?? false);
	const repeat = $derived(playback.queue.repeat ?? 'off');
	const episode = $derived(!!playback.now?.isEpisode);
	const local = $derived(!!playback.now && api.isLocalId(playback.now.videoId));
	/** What the middle shows: a local file has no comments, so comments left open fall back to the
	 *  cover until a track that has them comes on. */
	const middle = $derived(view === 'comments' && local ? 'art' : view);

	const currentSong = $derived.by(() => {
		const cur = playback.queue.items[playback.queue.currentIndex];
		return cur?.video_id === playback.now?.videoId ? cur : null;
	});

	let justLiked = $state(false);
	function toggleLike() {
		if (playback.rating !== 'like') justLiked = true;
		toggleNowPlayingRating();
	}

	// Swipe down to close, from the cover or anywhere in a band from the top of the screen to a bit
	// under the header: the header alone was a thin strip to aim for, and on the lyrics, queue and
	// comments tabs it was the only place. In the band the controls (the header's buttons, the
	// Song/Video switch, fields) keep their touch; a lyric line or a list row can start the drag,
	// and a drag that moved isn't also taken as a tap on it (`dragged`, `swallowClick`).
	const GRAB_BELOW = 72;
	let dragY = $state(0);
	/** A finger is on the sheet: it follows 1:1. Otherwise a release eases it back (`transition`). */
	let held = $state(false);
	let startY: number | null = null;
	let dragged = false;
	function onDown(e: PointerEvent) {
		if ((e.target as HTMLElement).closest('button, a, input, textarea, [role="button"]')) return;
		startY = e.clientY;
		held = true;
	}
	function onSheetDown(e: PointerEvent) {
		// The header is this view's or, on a phone on its side, theater mode's.
		const header = sheet?.querySelector('header');
		if (startY !== null || !header) return;
		if (e.clientY > header.getBoundingClientRect().bottom + GRAB_BELOW) return;
		const t = e.target as HTMLElement;
		if (t.closest('header button, [role="group"] button, a, input, textarea')) return;
		startY = e.clientY;
		held = true;
	}
	function swallowClick(e: MouseEvent) {
		if (!dragged) return;
		dragged = false;
		e.stopPropagation();
		e.preventDefault();
	}
	function onMove(e: PointerEvent) {
		if (startY === null) return;
		dragY = Math.max(0, e.clientY - startY);
		if (dragY > 10) dragged = true;
	}
	// A band drag that starts over the lyrics or a list would otherwise become that list's
	// scroll, and the browser cancels the pointer the moment it pans. Holding the touch here
	// (non-passive; Svelte's ontouchmove is passive) keeps the gesture ours.
	let sheet = $state<HTMLElement | null>(null);
	$effect(() => {
		const el = sheet;
		if (!el) return;
		const hold = (e: TouchEvent) => {
			if (startY !== null && e.cancelable) e.preventDefault();
		};
		el.addEventListener('touchmove', hold, { passive: false });
		return () => el.removeEventListener('touchmove', hold);
	});
	function onUp() {
		if (startY === null) return;
		startY = null;
		held = false;
		// Closing leaves the sheet where the finger let go: the exit (fly) starts from there.
		if (dragY > 120) return onClose();
		dragY = 0;
	}

	const round =
		'flex shrink-0 items-center justify-center rounded-full transition-colors active:bg-foreground/10';
</script>

<!-- overflow-clip, not -hidden: the blurred backdrop overhangs the sheet, and a hidden box can
     still be scrolled from script or by focus, which slid the whole player up under the status
     bar on the lyrics tab. A clipped box can't scroll at all. -->
<section
	transition:fly={{ y: 48, duration: 260, easing: cubicOut }}
	class="fixed inset-0 z-40 flex flex-col overflow-clip bg-background text-foreground {held
		? ''
		: 'transition-transform duration-300 ease-out'}"
	style="transform:translateY({dragY}px);padding:var(--inset-top) var(--inset-right) var(--inset-bottom) var(--inset-left)"
	bind:this={sheet}
	onpointerdown={onSheetDown}
	onclickcapture={swallowClick}
	onpointermove={onMove}
	onpointerup={onUp}
	onpointercancel={onUp}
	aria-label={t('mobile.player')}
>
	<!-- A phone on its side gets the desktop's theater mode, sized down for it (`phone`): a stage
	     with the picture and one column beside it, every control in a dock along the bottom. The
	     stacked player had no height for its middle there. -->
	{#if platform.short}
		<TheaterMode phone {onClose} bind:tab={view} composing={typing} />
	{:else}
		<!-- The room, as in theater mode: the baked wash, the cover's colour as light, the vignette. -->
		{#if appearance.artworkBackground && room.wash}
			{#key room.wash}
				<div
					transition:fade={{ duration: 700 }}
					style="background-image:url({room.wash});background-size:100% 100%;{room.washVars}"
					class="pointer-events-none absolute inset-0 opacity-[min(0.5,var(--wash-light))] dark:opacity-[min(0.6,var(--wash-dark))]"
				></div>
			{/key}
		{/if}
		<div class="pointer-events-none absolute -inset-[15%]" style="background-image:{room.mesh}"></div>
		<div
			class="pointer-events-none absolute inset-0"
			style="background-image:radial-gradient(120% 80% at 50% 35%, transparent 25%, var(--background) 100%)"
		></div>
		<!-- The ambient light (Settings > Playback), as in the desktop's player view: the video's colours
		     spilling into the room around it. -->
		{#if prefs.ambient && showVideo() && picBox && middle === 'art'}
			<Ambient box={picBox} />
		{/if}

		<!-- Header: close, where the queue came from, the track's menu. -->
		<!-- svelte-ignore a11y_no_static_element_interactions -->
		<header class="relative z-10 flex items-center gap-2 px-3 pt-2">
			<button class="{round} size-11" onclick={onClose} aria-label={t('mobile.close_player')}>
				<HugeiconsIcon icon={ArrowDown01Icon} strokeWidth={2.5} class="h-6 w-6" />
			</button>
			<div class="min-w-0 flex-1 text-center">
				{#if playback.queue.sourceName}
					<p class="text-[10px] font-semibold uppercase tracking-[0.22em] text-muted-foreground">
						{t('mobile.playing_from')}
					</p>
					<p class="truncate text-sm font-medium">{playback.queue.sourceName}</p>
				{/if}
			</div>
			{#if currentSong}
				<TrackMenu
					song={currentSong}
					linksOnly
					playlistId={playback.queue.sourceId}
					queueIndex={playback.queue.currentIndex}
					onAdd={() => openAddToPlaylist(currentSong!)}
					triggerClass="{round} size-11 text-muted-foreground"
				/>
			{:else}
				<div class="size-11"></div>
			{/if}
		</header>

		<!-- Song/Video, as in the desktop's player view: the user's choice, not what is on screen, so
		     "Video" stays picked while the picture loads and the cover stands in until it arrives. -->
		{#if canSwitch()}
			<div class="relative z-10 mt-2 flex justify-center">
				<div class="flex rounded-full bg-foreground/[0.07] p-1" role="group">
					{#each [false, true] as on (on)}
						<button
							type="button"
							onclick={() => pickVersion(on)}
							aria-pressed={videoSide() === on}
							class="rounded-full px-5 py-1.5 text-sm font-medium transition-colors {videoSide() === on
								? 'bg-background text-foreground shadow-sm'
								: 'text-muted-foreground'}"
						>
							{on ? t('player.video') : t('player.song')}
						</button>
					{/each}
				</div>
			</div>
		{/if}

		<!-- The middle: the cover, the music video, or the lyrics, or the queue. -->
		<!-- One grid cell for all four, so a switch crossfades: the old view fades out over the
		     new one fading in, instead of the two stacking for the length of the fade. -->
		<div
			class="relative z-10 grid min-h-0 flex-1 grid-cols-[minmax(0,1fr)] grid-rows-[minmax(0,1fr)] px-6 pt-4"
		>
			{#if middle === 'art'}
				<!-- svelte-ignore a11y_no_static_element_interactions -->
				<div
					transition:fade={{ duration: XFADE }}
					class="col-start-1 row-start-1 flex min-h-0 items-center justify-center [container-type:size]"
					onpointerdown={onDown}
				>
					<!-- The picture is VideoSurface's element (always mounted, see $lib/video), moved in
					     here while it is what shows. `contents`, so the element's own w-full and
					     aspect-video size it against this box. -->
					{#if showVideo()}
						<div bind:this={picBox} class="relative w-full">
							<div
								class="contents"
								{@attach (box: HTMLElement) => {
									claimVideo(box);
									return () => parkVideo(box);
								}}
							></div>
						</div>
					{:else}
					{#key playback.now?.videoId}
						<div
							in:fade={{ duration: 300 }}
							class="relative aspect-square w-[min(100cqw,100cqh)] overflow-hidden rounded-2xl shadow-2xl"
						>
							{#if src}
								<img
									{src}
									alt=""
									class="h-full w-full object-cover"
									onerror={() => attempt < srcs.length - 1 && attempt++}
								/>
							{:else}
								<div
									class="flex h-full w-full items-center justify-center bg-muted text-muted-foreground/40"
								>
									<HugeiconsIcon icon={MusicNote01Icon} class="h-20 w-20" />
								</div>
							{/if}
							<div class="pointer-events-none absolute inset-0 rounded-2xl ring-1 ring-inset ring-foreground/10"></div>
						</div>
					{/key}
					{/if}
				</div>
			{:else if middle === 'lyrics'}
				<div
					transition:fade={{ duration: XFADE }}
					class="col-start-1 row-start-1 flex min-h-0 flex-col overflow-hidden [&_*]:[scrollbar-width:none] [&_*::-webkit-scrollbar]:hidden"
				>
					<LyricsView />
				</div>
			{:else if middle === 'comments'}
				<!-- The desktop's comments (CommentsView): the playing track's, following it as it
				     changes, with its own loading, empty and error states and the composer. Pulled out
				     by its own px-4, so its text lines up with the title and the queue. -->
				<div
					transition:fade={{ duration: XFADE }}
					class="col-start-1 row-start-1 -mx-4 flex min-h-0 flex-col overflow-hidden"
				>
					<CommentsView />
				</div>
			{:else}
				<div
					transition:fade={{ duration: XFADE }}
					class="col-start-1 row-start-1 -mx-4 flex min-h-0 flex-col overflow-hidden"
				>
					<QueueList />
				</div>
			{/if}
		</div>

		<!-- Title, seek, transport. -->
		<div class="relative z-10 px-6 pt-5 pb-3" class:hidden={typing}>
			<div class="flex items-center gap-3">
				<div class="min-w-0 flex-1">
					<Marquee
						text={playback.now?.title ?? t('player.not_playing')}
						class="font-heading text-xl font-bold tracking-tight"
					/>
					<ArtistLine
						runs={playback.now?.artistRuns}
						text={playback.now?.artists ?? ''}
						marquee
						class="block max-w-full text-sm text-muted-foreground"
					/>
				</div>
				{#if playback.now && !local}
					<button
						class="{round} size-11 text-muted-foreground"
						onclick={toggleLike}
						aria-label={t('common.like')}
						aria-pressed={playback.rating === 'like'}
					>
						<span
							class="inline-flex"
							class:animate-heart-pop={justLiked}
							onanimationend={() => (justLiked = false)}
						>
							<HugeiconsIcon
								icon={FavouriteIcon}
								class="h-6 w-6 {playback.rating === 'like' ? 'fill-current text-primary' : ''}"
							/>
						</span>
					</button>
				{/if}
			</div>

			<input
				type="range"
				class="range theater-range mt-4 w-full"
				style="--pct:{pct}%"
				min="0"
				max={shownDuration || 0}
				value={shownPosition}
				oninput={(e) => (seekDrag = Number(e.currentTarget.value) * playback.speed)}
				onchange={(e) => {
					const v = Number(e.currentTarget.value) * playback.speed;
					playback.position = v;
					seekDrag = null;
					api.seek(v);
				}}
				aria-label={t('player.seek')}
			/>
			<div class="mt-1 flex justify-between text-xs font-medium tabular-nums text-muted-foreground">
				<span>{fmt(shownPosition)}</span>
				<span>{fmt(shownDuration)}</span>
			</div>

			<div class="mt-2 flex items-center justify-between">
				{#if episode}
					<SpeedPicker
						class="flex size-12 items-center justify-center rounded-full text-sm active:bg-foreground/10"
					/>
				{:else}
					<button
						class="{round} size-12"
						onclick={() => api.toggleShuffle()}
						aria-label={t('player.shuffle')}
						aria-pressed={shuffleOn}
					>
						<HugeiconsIcon
							icon={ShuffleIcon}
							class="h-5 w-5 {shuffleOn ? 'text-primary' : 'text-muted-foreground'}"
						/>
					</button>
				{/if}
				{#if episode}
					<button
						class="{round} size-12"
						onclick={() => skipBy(-SKIP_SECS)}
						aria-label={t('player.skip_back', { seconds: SKIP_SECS })}
					>
						<HugeiconsIcon icon={GoBackward15SecIcon} class="h-6 w-6" />
					</button>
				{:else}
					<button class="{round} size-14" onclick={() => api.prevTrack()} aria-label={t('player.previous')}>
						<HugeiconsIcon icon={PreviousIcon} class="h-7 w-7" />
					</button>
				{/if}
				<button
					class="flex size-18 shrink-0 items-center justify-center rounded-full bg-primary text-primary-foreground shadow-lg transition-transform active:scale-95"
					onclick={() => api.togglePause()}
					aria-label={playback.paused ? t('player.play') : t('player.pause')}
				>
					<HugeiconsIcon icon={PauseIcon} altIcon={PlayIcon} showAlt={playback.paused} class="h-8 w-8" />
				</button>
				{#if episode}
					<button
						class="{round} size-12"
						onclick={() => skipBy(SKIP_SECS)}
						aria-label={t('player.skip_forward', { seconds: SKIP_SECS })}
					>
						<HugeiconsIcon icon={GoForward15SecIcon} class="h-6 w-6" />
					</button>
				{:else}
					<button class="{round} size-14" onclick={() => api.nextTrack()} aria-label={t('player.next')}>
						<HugeiconsIcon icon={NextIcon} class="h-7 w-7" />
					</button>
				{/if}
				<button
					class="{round} size-12"
					onclick={cycleRepeat}
					aria-label={t('player.repeat_state', {
						state:
							repeat === 'off'
								? t('player.repeat_off')
								: repeat === 'one'
									? t('player.repeat_one')
									: t('player.repeat_all')
					})}
					aria-pressed={repeat !== 'off'}
				>
					<HugeiconsIcon
						icon={RepeatIcon}
						altIcon={RepeatForeverIcon}
						showAlt={repeat === 'one'}
						class="h-5 w-5 {repeat !== 'off' ? 'text-primary' : 'text-muted-foreground'}"
					/>
				</button>
			</div>

			<!-- The middle's switches. -->
			<div class="mt-3 flex items-center justify-around">
				<button
					class="{round} h-10 gap-2 px-3 text-sm {view === 'lyrics'
						? 'bg-foreground/10 text-foreground'
						: 'text-muted-foreground'}"
					onclick={() => toggle('lyrics')}
					aria-pressed={view === 'lyrics'}
				>
					<HugeiconsIcon icon={Mic01Icon} class="h-5 w-5" />
					{t('player.lyrics')}
				</button>
				<button
					class="{round} h-10 gap-2 px-3 text-sm {view === 'queue'
						? 'bg-foreground/10 text-foreground'
						: 'text-muted-foreground'}"
					onclick={() => toggle('queue')}
					aria-pressed={view === 'queue'}
				>
					<HugeiconsIcon icon={Queue01Icon} class="h-5 w-5" />
					{t('player.queue')}
				</button>
				{#if !local}
					<button
						class="{round} h-10 gap-2 px-3 text-sm {view === 'comments'
							? 'bg-foreground/10 text-foreground'
							: 'text-muted-foreground'}"
						onclick={() => toggle('comments')}
						aria-pressed={view === 'comments'}
					>
						<HugeiconsIcon icon={Comment01Icon} class="h-5 w-5" />
						{t('player.comments')}
					</button>
				{/if}
			</div>
		</div>
	{/if}
</section>
