<!--
	What's new, in Settings > About. The text is the GitHub release description verbatim (see
	RELEASING.md for the format releases are written in), so the changelog has one source of truth.

	The markdown here is deliberately tiny: headings, bullets, bold, code, links, @mentions, images.
	That is the whole vocabulary the release-note format uses, so a markdown dependency would be
	40 KB to render six constructs. GitHub's own editor drops in raw HTML for images and their
	<p align="center"> wrappers, so those are handled too and any other stray tag is dropped rather
	than shown as text.
-->
<script lang="ts" module>
	// The parser, on its own: the Android update notice shows a release's notes too.
	export type Span = { t: 'text' | 'b' | 'code' | 'link'; s: string; href?: string };
	export type Block =
		| { t: 'h'; spans: Span[] }
		| { t: 'p'; spans: Span[] }
		| { t: 'ul'; items: Span[][] }
		| { t: 'pre'; text: string }
		| { t: 'img'; src: string; alt: string };

	/** ![alt](src) and GitHub's raw <img src=...>, which it writes when you paste a screenshot. */
	const IMAGE = /!\[([^\]]*)\]\(([^)]+)\)|<img\b[^>]*?\bsrc=["']([^"']+)["'][^>]*>/gi;

	const INLINE = /\*\*(.+?)\*\*|`([^`]+)`|\[([^\]]+)\]\(([^)]+)\)|(https?:\/\/\S+)|@([\w-]+)/g;

	function inline(text: string): Span[] {
		const out: Span[] = [];
		let last = 0;
		for (const m of text.matchAll(INLINE)) {
			if (m.index > last) out.push({ t: 'text', s: text.slice(last, m.index) });
			if (m[1]) out.push({ t: 'b', s: m[1] });
			else if (m[2]) out.push({ t: 'code', s: m[2] });
			else if (m[3]) out.push({ t: 'link', s: m[3], href: m[4] });
			else if (m[5]) out.push({ t: 'link', s: m[5], href: m[5] });
			else out.push({ t: 'link', s: `@${m[6]}`, href: `https://github.com/${m[6]}` });
			last = m.index + m[0].length;
		}
		if (last < text.length) out.push({ t: 'text', s: text.slice(last) });
		return out;
	}

	/** Line-based on purpose: release notes are headings, bullets and one-line paragraphs. */
	export function parse(body: string): Block[] {
		const blocks: Block[] = [];
		let fenced: string[] | null = null;
		for (const raw of body.replaceAll('\r', '').split('\n')) {
			let line = raw.trim();
			if (line.startsWith('```')) {
				if (fenced) blocks.push({ t: 'pre', text: fenced.join('\n') });
				fenced = fenced ? null : [];
				continue;
			}
			if (fenced) {
				fenced.push(raw);
				continue;
			}
			const images = [...line.matchAll(IMAGE)];
			// Whatever HTML is left over (<p align="center">, <br>, <details>) is layout, not content.
			line = line.replace(IMAGE, '').replace(/<\/?[a-z][^>]*>/gi, '').trim();
			for (const m of images) blocks.push({ t: 'img', src: m[2] ?? m[3], alt: m[1] ?? '' });
			if (!line) continue;
			const heading = line.match(/^#{1,6}\s+(.*)/);
			const bullet = line.match(/^[-*]\s+(.*)/);
			if (heading) blocks.push({ t: 'h', spans: inline(heading[1]) });
			else if (bullet) {
				const prev = blocks.at(-1);
				if (prev?.t === 'ul') prev.items.push(inline(bullet[1]));
				else blocks.push({ t: 'ul', items: [inline(bullet[1])] });
			} else blocks.push({ t: 'p', spans: inline(line) });
		}
		return blocks;
	}
</script>

<script lang="ts">
	import { onMount } from 'svelte';
	import { HugeiconsIcon } from '@hugeicons/svelte';
	import {
		Alert02Icon,
		ArrowDown01Icon,
		Copy01Icon,
		Tick02Icon,
		RefreshIcon
	} from '@hugeicons/core-free-icons';
	import { Button } from '$lib/components/ui/button';
	import { releaseNotes, openExternal, type FetchError, type ReleaseNote } from '$lib/api';
	import { copyText } from '$lib/clipboard';
	import { t } from '$lib/i18n.svelte';

	/** Automatic retries: about once a minute, or later when GitHub says when, for a while. After
	 *  that only the Retry button tries again, so a long outage doesn't keep polling. */
	const AUTO_RETRY_SECS = 60;
	const MAX_WAIT_SECS = 3600;
	const MAX_AUTO_RETRIES = 10;

	let releases = $state<ReleaseNote[] | null>(null);
	let error = $state<FetchError | null>(null);
	let loading = $state(true);
	/** Minutes until the next automatic try, or null when none is scheduled. */
	let retryInMin = $state<number | null>(null);
	let autoRetries = 0;
	let timer: ReturnType<typeof setTimeout> | undefined;

	/** The command rejects with a `github_api::FetchError`; anything else (the IPC itself failing)
	 *  is unknown and not retried on its own. */
	function asFetchError(e: unknown): FetchError {
		if (e && typeof e === 'object' && 'kind' in e) return e as FetchError;
		return { kind: 'unknown' };
	}
	const transient = (e: FetchError) =>
		e.kind === 'rate_limited' || e.kind === 'server' || e.kind === 'network';

	async function load() {
		clearTimeout(timer);
		retryInMin = null;
		loading = true;
		try {
			releases = await releaseNotes();
			error = null;
			autoRetries = 0;
		} catch (e) {
			const err = asFetchError(e);
			error = err;
			if (transient(err) && autoRetries < MAX_AUTO_RETRIES) {
				autoRetries++;
				const secs = Math.min(
					MAX_WAIT_SECS,
					Math.max(AUTO_RETRY_SECS, err.retry_after_secs ?? AUTO_RETRY_SECS)
				);
				retryInMin = Math.ceil(secs / 60);
				timer = setTimeout(load, secs * 1000);
			}
		} finally {
			loading = false;
		}
	}

	function retryNow() {
		// Asked for: try now, and give the automatic retries a fresh run after it.
		autoRetries = 0;
		load();
	}

	onMount(() => {
		load();
		return () => clearTimeout(timer);
	});

	const message = (e: FetchError) => t(`changelog.error.${e.kind}`);

	/** Newest first, with the installed release marked: anything listed before it is newer. */
	const status = (list: ReleaseNote[], i: number): 'installed' | 'available' | null => {
		const mine = list.findIndex((r) => r.installed);
		if (i === mine) return 'installed';
		return mine > 0 && i < mine ? 'available' : null;
	};

	const day = (iso: string) =>
		iso ? new Date(iso + 'T00:00:00').toLocaleDateString(undefined, { dateStyle: 'medium' }) : '';

	/** A paragraph that is a checksum line, `SHA-256: \`<64 hex>\``: its label and the hash. */
	function checksum(spans: Span[]): { label: string; hash: string } | null {
		const code = spans.filter((s) => s.t === 'code');
		if (code.length !== 1 || !/^[0-9a-f]{64}$/i.test(code[0].s.trim())) return null;
		const label = spans
			.filter((s) => s.t !== 'code')
			.map((s) => s.s)
			.join('')
			.trim()
			.replace(/:$/, '');
		return label.length <= 24 ? { label: label || 'SHA-256', hash: code[0].s.trim() } : null;
	}

	let copied = $state<string | null>(null);
	async function copy(hash: string) {
		try {
			await copyText(hash);
			copied = hash;
			setTimeout(() => (copied = null), 1500);
		} catch {
			/* the clipboard refused; the hash is still selectable */
		}
	}
</script>

<!-- prettier-ignore -->
{#snippet spans(list: Span[])}{#each list as s}{#if s.t === 'b'}<strong class="font-medium text-foreground">{s.s}</strong>{:else if s.t === 'code'}<code class="rounded bg-muted px-1 py-0.5 font-mono text-xs [overflow-wrap:anywhere]">{s.s}</code>{:else if s.t === 'link'}<button type="button" class="text-primary hover:underline" onclick={() => openExternal(s.href!)}>{s.s}</button>{:else}{s.s}{/if}{/each}{/snippet}

{#if releases}
	{#each releases as r, i (r.version)}
		{@const st = status(releases, i)}
		<details class="group min-w-0 border-b last:border-b-0" open={i === 0}>
			<!-- Version on the left, the date and its status stacked on the right. The grid's first
			     column may shrink, so a long version wraps rather than pushing the date off. -->
			<summary
				class="grid cursor-pointer list-none grid-cols-[minmax(0,1fr)_auto] items-start gap-x-3 py-2.5 [&::-webkit-details-marker]:hidden"
			>
				<span class="flex min-w-0 items-start gap-1.5">
					<HugeiconsIcon
						icon={ArrowDown01Icon}
						class="mt-0.5 size-4 shrink-0 -rotate-90 text-muted-foreground transition-transform group-open:rotate-0"
					/>
					<span class="min-w-0 text-base leading-snug font-semibold [overflow-wrap:anywhere]"
						>{r.version}</span
					>
				</span>
				<span class="flex flex-col items-end gap-1 pt-0.5 text-right">
					{#if r.date}
						<span class="text-xs whitespace-nowrap text-muted-foreground">{day(r.date)}</span>
					{/if}
					{#if st === 'installed'}
						<span class="rounded bg-primary/15 px-1.5 py-0.5 text-xs text-primary"
							>{t('changelog.installed')}</span
						>
					{:else if st === 'available'}
						<span class="rounded border border-primary/40 px-1.5 py-0.5 text-xs text-primary"
							>{t('changelog.available')}</span
						>
					{/if}
				</span>
			</summary>
			<div class="min-w-0 pb-3 text-sm text-muted-foreground">
				{#each parse(r.body) as b}
					{#if b.t === 'h'}
						<h4 class="mt-3 mb-1 font-medium text-foreground">{@render spans(b.spans)}</h4>
					{:else if b.t === 'p'}
						{@const sum = checksum(b.spans)}
						{#if sum}
							<div class="mt-3 rounded-lg bg-muted px-3 py-2">
								<div class="flex items-center justify-between gap-2">
									<span class="text-xs font-medium text-foreground">{sum.label}</span>
									<Button
										variant="ghost"
										size="xs"
										onclick={() => copy(sum.hash)}
										aria-label={t('changelog.copy_hash', { label: sum.label })}
									>
										<HugeiconsIcon
											icon={Copy01Icon}
											altIcon={Tick02Icon}
											showAlt={copied === sum.hash}
										/>
										{copied === sum.hash ? t('common.done') : t('settings.about.copy')}
									</Button>
								</div>
								<!-- The whole hash, wrapped anywhere: it never widens the page, and selecting
								     or copying it still gives all 64 characters. -->
								<code class="mt-1 block font-mono text-xs break-all text-foreground select-all"
									>{sum.hash}</code
								>
							</div>
						{:else}
							<p class="mt-1">{@render spans(b.spans)}</p>
						{/if}
					{:else if b.t === 'img'}
						<img
							src={b.src}
							alt={b.alt}
							loading="lazy"
							class="mt-2 max-w-full rounded-lg border"
						/>
					{:else if b.t === 'pre'}
						<pre
							class="mt-2 overflow-x-auto rounded bg-muted px-2 py-1.5 text-xs">{b.text}</pre>
					{:else}
						<ul class="mt-1 ml-4 list-disc space-y-1">
							{#each b.items as item}<li>{@render spans(item)}</li>{/each}
						</ul>
					{/if}
				{/each}
			</div>
		</details>
	{:else}
		<p class="py-2 text-sm text-muted-foreground">{t('changelog.no_releases')}</p>
	{/each}
{:else if error}
	<!-- What went wrong, the status code when there was one, and a way to try now. The rest of the
	     app does not wait on this. -->
	<div class="my-1 flex items-start gap-3 rounded-lg border bg-muted/40 p-3" role="status">
		<HugeiconsIcon icon={Alert02Icon} class="mt-0.5 size-5 shrink-0 text-muted-foreground" />
		<div class="min-w-0 flex-1 text-sm">
			<p class="font-medium text-foreground">
				{t('changelog.load_failed_title')}
				{#if error.status}<span class="ml-1 font-mono text-xs text-muted-foreground"
						>HTTP {error.status}</span
					>{/if}
			</p>
			<p class="mt-0.5 text-muted-foreground">{message(error)}</p>
			{#if retryInMin !== null && !loading}
				<p class="mt-1 text-xs text-muted-foreground">
					{t('changelog.retry_in', { minutes: retryInMin })}
				</p>
			{/if}
			<Button class="mt-2.5" size="sm" onclick={retryNow} disabled={loading}>
				<HugeiconsIcon icon={RefreshIcon} class={loading ? 'animate-spin' : ''} />
				{loading ? t('changelog.retrying') : t('common.retry')}
			</Button>
		</div>
	</div>
{:else}
	<p class="py-2 text-sm text-muted-foreground">{t('common.loading')}</p>
{/if}
