<!--
	Android: a newer release of the port is out (`checkForAndroidUpdate`, on every launch). A
	centred modal over a dimmed app, closed by its X or a tap outside it, for the rest of this run.
	What it says the update brings is the release's own notes, nothing else: the port can't know
	what a release changed beyond what its description says.
-->
<script lang="ts">
	import * as Dialog from '$lib/components/ui/dialog';
	import { Button } from '$lib/components/ui/button';
	import { parse, type Span } from './Changelog.svelte';
	import { ANDROID_RELEASES_URL, port } from '$lib/androidPort.svelte';
	import { openExternal } from '$lib/api';
	import { t } from '$lib/i18n.svelte';
	import { toast } from '$lib/player.svelte';

	/** Shown at most, the rest is on the release page. */
	const MAX_ITEMS = 8;

	const text = (spans: Span[]) => spans.map((s) => s.s).join('');

	/** The notes' headings and bullets, as plain lines: enough to say what changed, short enough to
	 *  read in a notice. Paragraphs (an intro, the checksum) stay on the release page. */
	const items = $derived.by(() => {
		const out: { heading: boolean; text: string }[] = [];
		for (const b of parse(port.update?.notes ?? '')) {
			if (b.t === 'h') out.push({ heading: true, text: text(b.spans) });
			else if (b.t === 'ul') for (const i of b.items) out.push({ heading: false, text: text(i) });
		}
		// A heading with no bullets under it before the cut says nothing.
		const shown = out.slice(0, MAX_ITEMS);
		while (shown.at(-1)?.heading) shown.pop();
		return { shown, more: out.length > shown.length };
	});

	let open = $state(true);
	// Closing is the dismissal: it holds until the next launch checks again.
	$effect(() => {
		if (!open) port.update = null;
	});

	function update() {
		openExternal(ANDROID_RELEASES_URL).catch((e) =>
			toast.error(t('toasts.browser_failed', { error: String(e) }))
		);
		open = false;
	}
</script>

{#if port.update}
	<Dialog.Root bind:open>
		<!-- Well short of the screen: the dimmed band above and below is where a tap outside closes
		     it. The side gutters alone are too thin to hit on a phone. Inline, because the compact
		     layout's dialog rule (layout.css) sets max-height and overflow with the same insets and
		     wins over a utility class. Only the notes scroll: the Update button stays in view. -->
		<Dialog.Content
			class="grid-rows-[auto_minmax(0,1fr)_auto]"
			style="max-height: min(32rem, calc(100dvh - var(--inset-top, 0px) - var(--inset-bottom, 0px) - 10rem)); overflow: hidden"
		>
			<Dialog.Header>
				<Dialog.Title>{t('android_update.title')}</Dialog.Title>
				<Dialog.Description>
					{t('android_update.body', {
						version: port.update.version,
						installed: port.version?.release ?? ''
					})}
				</Dialog.Description>
			</Dialog.Header>
			{#if items.shown.length}
				<div class="min-h-0 overflow-y-auto text-sm text-muted-foreground">
					<p class="font-medium text-foreground">{t('android_update.whats_new')}</p>
					<ul class="mt-1.5 space-y-1">
						{#each items.shown as item}
							{#if item.heading}
								<li class="pt-1.5 font-medium text-foreground">{item.text}</li>
							{:else}
								<li class="ml-4 list-disc">{item.text}</li>
							{/if}
						{/each}
					</ul>
					{#if items.more}
						<p class="mt-2">{t('android_update.more')}</p>
					{/if}
				</div>
			{:else}
				<p class="text-sm text-muted-foreground">{t('android_update.no_notes')}</p>
			{/if}
			<Dialog.Footer>
				<Button onclick={update}>{t('android_update.update')}</Button>
			</Dialog.Footer>
		</Dialog.Content>
	</Dialog.Root>
{/if}
