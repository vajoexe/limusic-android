// The time until `at` as m:ss, from `now` (both ms since the epoch), for "trying again in 0:42".
// Rounded up, so the last second reads 0:01 rather than 0:00, and never below 0:00: the retry itself
// may take a moment to start after its time comes.
export function countdown(at: number, now: number): string {
	const left = Math.max(0, Math.ceil((at - now) / 1000));
	return `${Math.floor(left / 60)}:${String(left % 60).padStart(2, '0')}`;
}
