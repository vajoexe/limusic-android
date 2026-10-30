// Icons Limusic draws itself, in Hugeicons' element format so they drop into <HugeiconsIcon>.
import type { IconSvgElement } from '@hugeicons/svelte';
import { RepeatIcon } from '@hugeicons/core-free-icons';

/** Repeat the current song: Hugeicons' Repeat with an infinity sign inside, where RepeatOne01Icon
 *  has a "1". The song repeats until told otherwise, and a "1" read as "repeat it once". Same
 *  stroke and caps as the rest of the set. Source with a PNG export: assets/icons/repeat-forever.*. */
export const RepeatForeverIcon: IconSvgElement = [
	...RepeatIcon,
	[
		'path',
		{
			d: 'M12 12C12.75 10.85 13.6 10.25 14.6 10.25C15.6 10.25 16.35 11.03 16.35 12C16.35 12.97 15.6 13.75 14.6 13.75C13.6 13.75 12.75 13.15 12 12C11.25 10.85 10.4 10.25 9.4 10.25C8.4 10.25 7.65 11.03 7.65 12C7.65 12.97 8.4 13.75 9.4 13.75C10.4 13.75 11.25 13.15 12 12Z',
			stroke: 'currentColor',
			strokeLinecap: 'round',
			strokeLinejoin: 'round',
			strokeWidth: '1.5',
			key: '2'
		}
	]
];
