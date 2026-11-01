<script lang="ts">
	import { Popover as PopoverPrimitive } from "bits-ui";
	import { cn, type WithoutChildrenOrChild } from "$lib/utils.js";
	import PopoverPortal from "./popover-portal.svelte";
	import type { ComponentProps } from "svelte";
	import { platform } from "$lib/platform.svelte";

	let {
		ref = $bindable(null),
		class: className,
		sideOffset = 4,
		align = "center",
		portalProps,
		collisionPadding,
		...restProps
	}: PopoverPrimitive.ContentProps & {
		portalProps?: WithoutChildrenOrChild<ComponentProps<typeof PopoverPortal>>;
	} = $props();

	// On a phone, keep clear of the status and navigation bars and off the screen edges. Not of the
	// keyboard, and the same object for as long as those numbers hold: a new padding re-applies the
	// content's props, bits-ui's focus scope remounts on that and moves focus to the first button,
	// and that closed the keyboard again under a field in the popover (the lyrics search) while
	// its insets were still arriving. A popover with a field in it is moved above the keyboard by
	// its owner instead (MobilePlayer).
	const top = $derived(platform.insets.top + 8);
	const bottom = $derived(platform.barsBottom + 8);
	const left = $derived(platform.insets.left + 16);
	const right = $derived(platform.insets.right + 16);
	const phonePadding = $derived(platform.compact ? { top, bottom, left, right } : undefined);
</script>

<PopoverPortal {...portalProps}>
	<PopoverPrimitive.Content
		bind:ref
		data-slot="popover-content"
		{sideOffset}
		{align}
		collisionPadding={collisionPadding ?? phonePadding}
		class={cn(
			"bg-popover text-popover-foreground data-open:animate-in data-closed:animate-out data-closed:fade-out-0 data-open:fade-in-0 data-closed:zoom-out-95 data-open:zoom-in-95 data-[side=bottom]:slide-in-from-top-2 data-[side=left]:slide-in-from-right-2 data-[side=right]:slide-in-from-left-2 data-[side=top]:slide-in-from-bottom-2 ring-foreground/5 flex flex-col gap-4 rounded-2xl p-4 text-sm shadow-2xl ring-1 duration-100 z-50 w-72 origin-(--bits-popover-content-transform-origin) outline-hidden",
			className
		)}
		{...restProps}
	/>
</PopoverPortal>
