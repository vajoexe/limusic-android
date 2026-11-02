<script lang="ts">
	import './layout.css';
	import favicon from '$lib/assets/favicon.svg';
	import { ModeWatcher, mode } from 'mode-watcher';
	import { HugeiconsIcon } from '@hugeicons/svelte';
	import {
		CheckmarkCircle02Icon,
		AlertCircleIcon,
		InformationCircleIcon,
		Cancel01Icon
	} from '@hugeicons/core-free-icons';
	import { browser } from '$app/environment';
	import { afterNavigate, pushState } from '$app/navigation';
	import { page } from '$app/state';
	import { cancelRestore, restoreTo } from '$lib/scrollrestore';
	import { onMount, tick, untrack } from 'svelte';
	import { getCurrentWindow } from '@tauri-apps/api/window';
	import { fly } from 'svelte/transition';
	import { cubicOut } from 'svelte/easing';
	import {
		appearance,
		applyArtworkAccent,
		prewarmArtworkAccent,
		refreshArtworkAccent,
		initTheme
	} from '$lib/theme.svelte';
	import { loadAppIcon } from '$lib/appicon.svelte';
	import { thumb } from '$lib/thumb';
	import { t } from '$lib/i18n.svelte';
	import { blockForeignDrag, dragScroll } from '$lib/dnd';
	import { suppressNative } from '$lib/menu';
	import Sidebar from '$lib/components/Sidebar.svelte';
	import Titlebar from '$lib/components/Titlebar.svelte';
	import ResizeBorders from '$lib/components/ResizeBorders.svelte';
	import PlayerBar from '$lib/components/PlayerBar.svelte';
	import QueuePanel from '$lib/components/QueuePanel.svelte';
	import LyricsPanel from '$lib/components/LyricsPanel.svelte';
	import CommentsPanel from '$lib/components/CommentsPanel.svelte';
	import AddToPlaylist from '$lib/components/AddToPlaylist.svelte';
	import NewPlaylistDialog from '$lib/components/NewPlaylistDialog.svelte';
	import SettingsDialog from '$lib/components/SettingsDialog.svelte';
	import TempoPitchDialog from '$lib/components/TempoPitchDialog.svelte';
	import ShareDialog from '$lib/components/ShareDialog.svelte';
	import ChannelPicker from '$lib/components/ChannelPicker.svelte';
	import ListenTogether from '$lib/components/ListenTogether.svelte';
	import LinkDialog from '$lib/components/LinkDialog.svelte';
	import ImportDialog from '$lib/components/ImportDialog.svelte';
	import { handleImportDrop, initImport } from '$lib/import.svelte';
	import MiniPlayer from '$lib/components/MiniPlayer.svelte';
	import NowPlaying from '$lib/components/NowPlaying.svelte';
	import TheaterMode from '$lib/components/TheaterMode.svelte';
	import VideoSurface from '$lib/components/VideoSurface.svelte';
	import CommandPalette from '$lib/components/CommandPalette.svelte';
	import KeyboardShortcuts from '$lib/components/KeyboardShortcuts.svelte';
	import CookieSignIn from '$lib/components/CookieSignIn.svelte';
	import MobileTopBar from '$lib/components/MobileTopBar.svelte';
	import MobileNav from '$lib/components/MobileNav.svelte';
	import MobileMiniPlayer from '$lib/components/MobileMiniPlayer.svelte';
	import MobilePlayer from '$lib/components/MobilePlayer.svelte';
	import { initPlatform, isAndroid, platform } from '$lib/platform.svelte';
	import { Button } from '$lib/components/ui/button';
	import { auth, initApp, np, playback, prefs, ui } from '$lib/player.svelte';
	import { isLocalId } from '$lib/api';
	import { video } from '$lib/video.svelte';
	import { initWin, windowCorners } from '$lib/win.svelte';
	import { initZoom } from '$lib/zoom.svelte';
	import { initShortcuts } from '$lib/shortcuts';
	import { initErrorLog } from '$lib/errlog';
	import AndroidUpdateDialog from '$lib/components/AndroidUpdateDialog.svelte';
	import { checkForAndroidUpdate, loadAndroidVersion } from '$lib/androidPort.svelte';
	import {
		updateState,
		availableMessage,
		installUpdate,
		openDownloadPage,
		checkForUpdatesQuiet,
		QUIET_INTERVAL_MS
	} from '$lib/updater.svelte';

	// SvelteKit's `snapshot` keys a saved scroll to the *history entry*: two visits to the same URL
	// each restore the position they left at, where a URL→scroll Map would collapse both onto the
	// last save. Kit 2.69 reads `.snapshot` off the bound component *instance* (the generated
	// root.svelte does `bind:this`), so it must be exported from this script, not the module. This
	// covers every route that scrolls `<main>` (`$lib/scrollrestore`); /playlist/[id] scrolls its
	// own container and exports a snapshot of its own.
	let scroller = $state<HTMLElement | null>(null);
	// The phone shell's mini player + navigation height. On <html>, since the selection bar and
	// other floating pieces are positioned against the viewport, some of them from <body>.
	let navDock = $state(0);
	// A text field has focus and the on-screen keyboard is up: the dock gives the room back, the way
	// a phone app's bottom bar steps aside for the keyboard. Both, since Gboard's hide button puts
	// the keyboard away with the field still focused, and the dock has to come back then.
	let focused = $state(false);
	const typing = $derived(focused && platform.keyboard);
	// The floating pill's height plus its gap, while it shows (it sits over the page, outside the
	// measured row).
	let pillHeight = $state(0);
	const dock = $derived(
		navDock + (platform.short && playback.now && !typing ? pillHeight + 8 : 0)
	);
	$effect(() => {
		document.documentElement.style.setProperty('--dock', `${platform.compact ? dock : 0}px`);
	});
	export const snapshot = {
		capture: () => (scroller ? scroller.scrollTop : null),
		restore: (y: unknown) => {
			if (!scroller || typeof y !== 'number') return;
			restoreTo(scroller, y);
		}
	};
	afterNavigate((nav) => {
		if (!scroller || !nav.to) return;
		// Kit invokes snapshot.restore after afterNavigate on its own, so back/forward needs
		// nothing here. Direct navigation (a link, the sidebar, a fresh history entry) starts at
		// the top instead.
		if (nav.type === 'popstate') return;
		// A direct navigation mid-restore must kill the settle loop — a link clicked while the
		// previous page's restore was still re-applying would otherwise keep writing y beneath it.
		cancelRestore();
		scroller.scrollTop = 0;
	});

	let { children } = $props();
	// Queue and lyrics toggle independently and both float over the page rather than docking into
	// it — two docked columns squeezed the content down to an unusable strip. At lg+ they sit side
	// by side over the content; narrower, they stack (see QueuePanel / LyricsPanel).
	// Comments take the lyrics' slot rather than a third column, so the two are exclusive with each
	// other (opening one closes the other) and everything that offsets for "the lyrics panel" counts
	// either as that one slot.
	let queueOpen = $state(false);
	let lyricsOpen = $state(false);
	let commentsOpen = $state(false);
	// Two ways the now-playing view and these panels can divide the same two buttons, picked in
	// settings (#62). Tabbed (the default): the view carries queue and lyrics itself, so the panels
	// step aside for it and the bar's buttons switch its tabs. Off: these are the only owner, the
	// buttons always mean the panels, and the panels float over that view like they float over a
	// page, so opening it costs you nothing you had open.
	const tabbed = $derived(np.open && appearance.tabbedPlayer);
	// Stepping aside hides the panels without closing them, so closing the view brings back
	// whatever was open before it (#365).
	const showQueue = $derived(queueOpen && !tabbed);
	const showLyrics = $derived(lyricsOpen && !tabbed);
	const showComments = $derived(commentsOpen && !tabbed);
	// A local file has no YouTube comments, and the bar and the view hide their comments buttons for
	// it, so nothing could close them: comments count as closed. Docked, the panel goes; tabbed, the
	// view goes back to the tab that was open before comments. Opened again on a YouTube track as usual.
	let tabBeforeComments = $state<'queue' | 'lyrics'>('queue');
	$effect(() => {
		if (np.tab !== 'comments') tabBeforeComments = np.tab;
	});
	$effect(() => {
		if (!playback.now || !isLocalId(playback.now.videoId)) return;
		commentsOpen = false;
		if (np.tab === 'comments') np.tab = tabBeforeComments;
	});

	// "Adapt colors to artwork": re-run on every track change and on the toggle itself. The 120px
	// cover is the one the player bar has already loaded, so this costs no extra request. A Matugen
	// palette owns every colour while it's on, so the artwork stands down.
	const artworkTint = $derived(appearance.artworkAccent && !appearance.matugen);
	$effect(() => {
		applyArtworkAccent(artworkTint ? thumb(playback.now?.thumbnail, 120) : null);
	});
	// The accent is banded against the active theme (a cover's colour that reads on a light page is
	// mud on a dark one, #137), so flipping light/dark has to re-derive it from the same cover.
	$effect(() => {
		refreshArtworkAccent(mode.current === 'dark');
	});
	// Same colour, one track early. Reading it off the queue instead of the track change means the
	// palette starts moving on the frame the artwork swaps, not after a fetch and a decode.
	$effect(() => {
		if (!artworkTint) return;
		const q = playback.queue;
		prewarmArtworkAccent(thumb(q.items[q.currentIndex + 1]?.thumbnail, 120));
	});

	// The mini player runs this same SPA in a second window (Rust `mini.rs`), so the window label is
	// what tells the two apart: `mini` gets the widget instead of the app chrome, and none of the
	// routes below it are ever rendered. Constant for the window's lifetime.
	const isMini = browser && getCurrentWindow().label === 'mini';

	// Apply the saved accent color before the first paint (ssr=false → nothing renders until now).
	if (browser) initTheme();
	// Which shell (phone or desktop) and the system bars' insets, also before the first paint.
	if (browser) initPlatform();

	// The phone's full-screen player gets a history entry of its own while it is open, so the
	// system Back (and the back gesture) closes it rather than leaving the page under it. Opening
	// pushes the entry; Back pops it and that closes the player; closing it any other way (the
	// chevron, a swipe) goes back over the entry so it can't linger as a dead step. A link followed
	// from inside the player lands on a new entry without the flag, which closes it as well.
	let sheetPushed = false;
	$effect(() => {
		const open = platform.compact && np.open && !!playback.now;
		untrack(() => {
			if (open && !sheetPushed) {
				sheetPushed = true;
				pushState('', { sheet: 'player' });
			} else if (!open && sheetPushed) {
				sheetPushed = false;
				if (page.state.sheet === 'player') history.back();
			}
		});
	});
	$effect(() => {
		if (page.state.sheet === 'player') return;
		untrack(() => {
			if (!sheetPushed) return;
			sheetPushed = false;
			np.open = false;
		});
	});
	// Dialogs and menus get the same on Android: Back closes the one on top instead of walking the
	// page under it. Any open one counts, so this needs no wiring in each of them: a dialog is a
	// bits-ui one (`role="dialog"` with `data-state="open"`) and Back hands it the Escape that closes
	// it; a ⋯ menu is the full-window "click outside" button under it, which Back clicks.
	let dialogPushed = false;
	// A `history.back()` of ours is on its way: nothing pushes until it lands, or a dialog opened
	// in between would get its entry popped instead of the old one.
	let backPending = false;
	// Back is closing the dialog on top: until it has left the page, a DOM change (synced lyrics
	// redraw all the time) must not read it as still open and push its entry again. That push has
	// no user gesture behind it, and the WebView skips such entries on Back (`canGoBack()` false),
	// which sent the app to the background instead of closing the player under the dialog.
	let closingTop = false;
	// The bits-ui dialogs, popovers and menus (a popover carries no role, only its data
	// attributes, so Back used to skip it and close the player under it), and the three
	// hand-built modals (ShortcutPicker, ShareDialog, AddToPlaylist: a `fixed inset-0 …
	// bg-black/50` scrim that closes on Escape).
	const DIALOG =
		'[role="dialog"][data-state="open"], [role="alertdialog"][data-state="open"], [data-popover-content][data-state="open"], [role="menu"][data-state="open"], div.fixed.inset-0[class*="bg-black/50"]';
	const MENU_BACKDROP = 'button.fixed.inset-0.cursor-default';
	const dialogOpen = () => !!document.querySelector(`${DIALOG}, ${MENU_BACKDROP}`);
	function closeTop() {
		const menus = document.querySelectorAll<HTMLElement>(MENU_BACKDROP);
		if (menus.length) menus[menus.length - 1].click();
		// Cancelable like a real key press, so the one that takes it can say so (`preventDefault`)
		// and the view under it (theater mode) leaves it alone.
		else
			document.dispatchEvent(
				new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true })
			);
	}
	function back() {
		backPending = true;
		history.back();
	}
	function syncDialog() {
		if (backPending || closingTop) return;
		const open = dialogOpen();
		if (open && !dialogPushed) {
			dialogPushed = true;
			pushState('', { ...page.state, dialog: true });
		} else if (!open && dialogPushed) {
			dialogPushed = false;
			if (page.state.dialog) back();
		}
	}
	$effect(() => {
		const onDialogEntry = !!page.state.dialog;
		untrack(() => {
			if (backPending) {
				backPending = false;
				syncDialog(); // a dialog may have opened while the entry was going
				return;
			}
			if (onDialogEntry) {
				// Back (or a link's Back) onto an entry whose dialog is gone, e.g. one closed by
				// following a link inside it: a dead step, so step over it.
				if (!dialogPushed && !dialogOpen()) back();
				return;
			}
			if (!dialogPushed) return;
			// Back popped our entry: close what is on top. One still open under it pushes again,
			// once the closed one is gone.
			dialogPushed = false;
			if (dialogOpen()) {
				closingTop = true;
				closeTop();
				tick().then(() => {
					closingTop = false;
					syncDialog();
				});
			}
		});
	});
	onMount(() => {
		if (!isAndroid) return;
		const TEXT = 'input:not([type=checkbox],[type=radio],[type=range],[type=button],[type=submit]), textarea, [contenteditable=""], [contenteditable=true]';
		// Re-checked on DOM changes as well: a focused field removed with its dialog sends no
		// focusout, which left the dock hidden after the sign-in dialog closed. Deferred: a dialog
		// that moves focus while it renders fires focusin in the middle of Svelte's update, and a
		// state write there throws `state_unsafe_mutation`.
		const check = () =>
			(focused = !!(document.activeElement?.isConnected && document.activeElement.matches(TEXT)));
		const focus = () => queueMicrotask(check);
		// A search submitted from the phone's keyboard puts the keyboard away so the results show.
		// After the form's own handler: the listener is on the document.
		const submitted = (e: SubmitEvent) => {
			if (platform.compact && (e.target as HTMLElement).contains(document.activeElement))
				(document.activeElement as HTMLElement).blur();
		};
		document.addEventListener('focusin', focus);
		document.addEventListener('focusout', focus);
		document.addEventListener('submit', submitted);
		const watch = new MutationObserver(() => {
			syncDialog();
			focus();
		});
		watch.observe(document.body, {
			subtree: true,
			childList: true,
			attributes: true,
			attributeFilter: ['data-state']
		});
		return () => {
			watch.disconnect();
			document.removeEventListener('focusin', focus);
			document.removeEventListener('focusout', focus);
			document.removeEventListener('submit', submitted);
		};
	});
	// The custom app icon (#173) is a file on disk, so the titlebar has to ask Rust for it.
	if (browser) loadAppIcon();

	// Wire the Tauri event bridge once for the whole app; teardown on destroy. Check for an update
	// on every app open (silent unless one exists).
	onMount(() => {
		// Before the mini-window bail-out: both windows run this SPA and both can throw.
		initErrorLog();
		if (isMini) {
			// The widget gets the transport keys too. No zoom: it is a fixed-size card.
			const teardownMiniApp = initApp(true);
			const teardownMiniKeys = initShortcuts(true);
			return () => {
				teardownMiniApp();
				teardownMiniKeys();
			};
		}
		// First: it reveals the window (see initWin).
		const teardownWin = initWin();
		// The updater plugin is desktop-only. Android asks the port's GitHub releases instead, once
		// per launch and in the background (`checkForAndroidUpdate`), and points at the download.
		if (!isAndroid) checkForUpdatesQuiet();
		else {
			loadAndroidVersion();
			checkForAndroidUpdate();
		}
		// Repeat while the app stays open: ✕ hides to tray by default, so this component can stay
		// mounted for days and a mount-only check would never see a release published in between.
		const updateTimer = isAndroid ? undefined : setInterval(checkForUpdatesQuiet, QUIET_INTERVAL_MS);
		const teardownApp = initApp();
		const teardownZoom = initZoom();
		const teardownShortcuts = initShortcuts();
		initImport();
		return () => {
			clearInterval(updateTimer);
			teardownApp();
			teardownWin();
			teardownZoom();
			teardownShortcuts();
		};
	});
</script>

<!-- oncontextmenu: the app's own menus handle their right-click and stop the event, so anything
     that reaches the window is a place where WebKit would have offered back / reload / inspect.
     Text fields and selections keep the native menu (see `suppressNative`). -->
<!-- A Spotify export, CSV or link dropped anywhere opens the import (#375); anything else foreign is
     refused as before. -->
<svelte:window
	ondragover={blockForeignDrag}
	ondrop={(e) => handleImportDrop(e) || blockForeignDrag(e)}
	oncontextmenu={suppressNative}
/>

<svelte:head><link rel="icon" href={favicon} /></svelte:head>
<ModeWatcher />

<!-- The mini player is the whole window when it is the window: no titlebar, no sidebar, no routes,
     and no toasts (a banner would cover most of a 560x180 widget). -->
{#if isMini}
	<MiniPlayer />
{:else if platform.compact}
	<!-- The phone shell (Android below 840px wide: a phone, or a narrow split-screen or DeX
	     window): top bar, the page, the mini player and the bottom navigation, edge to edge with
	     the system bars kept clear by the insets. The routes are the same ones; only the frame
	     around them changes. A wider window gets the desktop shell below. -->
	<!-- On its side (`platform.short`) the navigation is a rail down the left and the column
	     beside it has the full height: top bar and page, the mini player floating over the page. -->
	<div
		class="relative flex h-dvh overflow-hidden bg-background text-foreground {platform.short
			? 'flex-row'
			: 'flex-col'}"
		style="padding-left:var(--inset-left);padding-right:var(--inset-right)"
	>
		{#if platform.short}<MobileNav rail />{/if}
		<div class="relative flex min-h-0 min-w-0 flex-1 flex-col">
			<MobileTopBar />
			<main
				class="min-w-0 flex-1 overflow-x-hidden overflow-y-auto overscroll-contain"
				bind:this={scroller}
			>
				{#key `${auth.epoch}:${ui.epoch}`}
					{@render children()}
				{/key}
			</main>
			{#if !prefs.nativeVideo}<VideoSurface />{/if}
			<!-- Measured, as `--dock`, so the floating buttons (back to top, selection bar…) sit above
			     the mini player and the navigation instead of on them (layout.css). -->
			<!-- On its side (`platform.short`) the mini player floats as a pill at the bottom right,
			     over the page, so the page keeps the height a full-width row would take. `--dock`
			     still counts it, so the floating buttons stay above it. -->
			<div
				class="relative shrink-0"
				class:hidden={typing}
				style:padding-bottom={platform.short ? 'var(--inset-bottom)' : undefined}
				bind:clientHeight={navDock}
			>
				{#if playback.now}
					{#if platform.short}
						<div
							class="absolute right-3 bottom-full mb-2 w-[min(20rem,45vw)]"
							bind:clientHeight={pillHeight}
							in:fly={{ y: 32, duration: 250, easing: cubicOut }}
						>
							<MobileMiniPlayer pill />
						</div>
					{:else}
						<div in:fly={{ y: 64, duration: 250, easing: cubicOut }}><MobileMiniPlayer /></div>
					{/if}
				{/if}
				{#if !platform.short}<MobileNav />{/if}
			</div>
		</div>
	</div>
	{#if np.open && playback.now}<MobilePlayer onClose={() => (np.open = false)} />{/if}
{/if}
{#if !isMini && !platform.compact}
	<!-- The window itself is transparent; this root paints the background and, when not maximized,
	     rounds the corners (the compositor can't round an undecorated window for us on Linux).
	     Theater mode counts as maximized here: it is fullscreen, and rounding it clips the corners
	     of a view that is meant to reach every edge (#139). With a system frame (win.chrome), or on
	     Windows 11, the compositor rounds for us, so ours would only fight it (#504).
	     Invisible while theater mode shows mpv's picture: theater is transparent over the hole, and
	     the titlebar, sidebar or player bar under it would paint over the video. -->
	<div
		class="relative flex h-screen flex-col overflow-hidden text-foreground {video.hole
			? ''
			: 'bg-background'} {windowCorners()} {ui.theaterOpen && video.hole ? 'invisible' : ''}"
		style={isAndroid
			? 'padding:var(--inset-top) var(--inset-right) var(--inset-bottom) var(--inset-left)'
			: undefined}
	>
		{#if video.hole}
			<!-- Linux: mpv draws the music video underneath the page (nativevideo.rs), so the page
			     paints its background everywhere except the picture's box: a spread shadow, not a
			     blur, so it costs one static paint. At -z-10 it sits under everything else, and the
			     root's own background and <main> step aside while it is up (both paint the box). -->
			<div
				aria-hidden="true"
				class="pointer-events-none visible absolute -z-10 rounded-2xl"
				style="left:{video.hole.x}px;top:{video.hole.y}px;width:{video.hole.w}px;height:{video.hole
					.h}px;box-shadow:0 0 0 100vmax var(--background)"
			></div>
		{/if}
		<ResizeBorders />
		<Titlebar />
		<!-- relative: the queue and lyrics panels are absolute overlays inside it (see QueuePanel). -->
		<div class="relative flex min-h-0 flex-1">
			<Sidebar />
			<!-- dragScroll: dragging a card up to home's Shortcuts grid has to be possible from anywhere in
			     the feed, so aiming at the top edge scrolls this container while the drag is in flight. -->
			<main
				class="min-w-0 flex-1 overflow-y-auto {video.hole ? 'invisible' : ''}"
				bind:this={scroller}
				{@attach dragScroll}
			>
				<!-- Remount the current page on sign-in/out so it refetches with the new account, and on
				     a refresh (titlebar button / F5), which drops the browse cache first. -->
				{#key `${auth.epoch}:${ui.epoch}`}
					{@render children()}
				{/key}
			</main>
			<!-- Always mounted, unlike the player view below it: it owns the one <video> element, which
			     has to keep playing while the view is closed. It renders nothing but a zero-sized
			     parking container until the view borrows the picture. Not on Linux, where mpv draws the
			     picture itself (prefs.nativeVideo). -->
			{#if !prefs.nativeVideo}<VideoSurface />{/if}
			{#if np.open && playback.now}<NowPlaying
					queueOpen={showQueue}
					lyricsOpen={showLyrics || showComments}
				/>{/if}
			<!-- Lyrics before queue: side by side over the page, lyrics on the left, queue on the right. -->
			{#if showLyrics}<LyricsPanel onClose={() => (lyricsOpen = false)} queueOpen={showQueue} />{/if}
			{#if showComments}<CommentsPanel
					onClose={() => (commentsOpen = false)}
					queueOpen={showQueue}
				/>{/if}
			{#if showQueue}<QueuePanel onClose={() => (queueOpen = false)} />{/if}
		</div>
		{#if playback.now}
			<!-- Slides up from its own height on first play; leaves instantly (bar removal is rare).
			     z-20 on the wrapper, not the bar: the intro's transform makes this a stacking context,
			     so a z on the footer inside would be trapped under it. The now-playing view is z-20 and
			     earlier in the DOM, which is what puts it behind the bar as it slides in and out. -->
			<div class="relative z-20" in:fly={{ y: 64, duration: 250, easing: cubicOut }}>
				<PlayerBar
					onToggleQueue={() => (tabbed ? (np.tab = 'queue') : (queueOpen = !queueOpen))}
					queueOpen={tabbed ? np.tab === 'queue' : queueOpen}
					onToggleLyrics={() => {
						if (tabbed) np.tab = 'lyrics';
						else {
							lyricsOpen = !lyricsOpen;
							if (lyricsOpen) commentsOpen = false;
						}
					}}
					lyricsOpen={tabbed ? np.tab === 'lyrics' : lyricsOpen}
					onToggleComments={() => {
						if (tabbed) np.tab = 'comments';
						else {
							commentsOpen = !commentsOpen;
							if (commentsOpen) lyricsOpen = false;
						}
					}}
					commentsOpen={tabbed ? np.tab === 'comments' : commentsOpen}
				/>
			</div>
		{/if}
	</div>

	<!-- Theater mode covers everything, titlebar included, and puts the window in fullscreen for as
	     long as it is mounted. Nothing playing means nothing to show, and that guard is also what
	     closes it (and leaves fullscreen) when the queue runs out. -->
	{#if ui.theaterOpen && playback.now}<TheaterMode />{/if}
{/if}
{#if !isMini}
	<CommandPalette />
	<KeyboardShortcuts />
	<AddToPlaylist />
	<NewPlaylistDialog />
	<ShareDialog />
	<SettingsDialog />
	<TempoPitchDialog bind:open={ui.tempoPitchOpen} />
	<ChannelPicker />
	<ListenTogether />
	<LinkDialog />
	<ImportDialog />
	{#if isAndroid}<CookieSignIn />{/if}

	<!-- The two notification banners below run at z-[100]. Dialogs and menus sit at z-50 and portal to
	     <body>, so a z-50 banner loses the tie on DOM order and hides behind an open modal. The update
	     banner also needs pointer-events-auto: an open dialog sets `pointer-events: none` on <body>,
	     so without it the banner shows above the modal but its buttons can't be clicked. -->
	{#if isAndroid}
		<AndroidUpdateDialog />
	{/if}
	{#if updateState.available}
		<div
			transition:fly={{ y: 16, duration: 220, easing: cubicOut }}
			class="pointer-events-auto fixed bottom-24 left-1/2 z-[100] flex -translate-x-1/2 items-center gap-3 rounded-lg border bg-card px-4 py-2 text-sm shadow-lg"
		>
			<span>{availableMessage(updateState.available)}</span>
			{#if updateState.canInstall}
				<Button size="sm" onclick={installUpdate} disabled={updateState.installing}>
					{updateState.installing ? t('common.loading') : t('settings.about.install_update')}
				</Button>
			{:else}
				<!-- Packaged build (.rpm, AUR): the updater can only rewrite an AppImage, so send them
				     to the releases page and let their package manager do it. -->
				<Button size="sm" onclick={openDownloadPage}>{t('settings.about.download_page')}</Button>
			{/if}
			{#if !updateState.installing}
				<Button
					variant="ghost"
					size="icon-sm"
					class="-mr-2 text-muted-foreground hover:text-foreground"
					aria-label={t('common.close')}
					onclick={() => (updateState.available = null)}
				>
					<HugeiconsIcon icon={Cancel01Icon} strokeWidth={2} />
				</Button>
			{/if}
		</div>
	{/if}

	{#if ui.toast}
		{@const t = ui.toast}
		<div
			transition:fly={{ y: 16, duration: 220, easing: cubicOut }}
			class="fixed bottom-40 left-1/2 z-[100] flex -translate-x-1/2 items-center gap-2 rounded-lg border bg-card px-4 py-2 text-sm shadow-lg"
		>
			<!-- Three branches instead of a ternary on `icon`: HugeiconsIcon freezes `icon` at mount, so a
			     new toast replacing a visible one would keep the old glyph. -->
			{#if t.kind === 'success'}
				<HugeiconsIcon icon={CheckmarkCircle02Icon} class="h-4 w-4 shrink-0 text-primary" />
			{:else if t.kind === 'error'}
				<HugeiconsIcon icon={AlertCircleIcon} class="h-4 w-4 shrink-0 text-destructive" />
			{:else}
				<HugeiconsIcon
					icon={InformationCircleIcon}
					class="h-4 w-4 shrink-0 text-muted-foreground"
				/>
			{/if}
			{t.msg}
		</div>
	{/if}
{/if}
