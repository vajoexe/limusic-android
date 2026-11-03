// Self-check for `countdown.ts`, the changelog's "trying again in m:ss". No test runner in `ui/`,
// node 22 runs TypeScript directly:
//
//     node --experimental-strip-types ui/src/lib/countdown.check.ts
//
// Prints "ok" and exits 0, or throws on the first broken invariant.
import { countdown } from './countdown.ts';

function eq(got: string, want: string, what: string): void {
	if (got !== want) throw new Error(`FAIL: ${what}: got ${got}, want ${want}`);
}

const t0 = 1_000_000;
eq(countdown(t0 + 60_000, t0), '1:00', 'a full minute');
eq(countdown(t0 + 59_001, t0), '1:00', 'part of a second rounds up');
eq(countdown(t0 + 59_000, t0), '0:59', 'seconds are padded');
eq(countdown(t0 + 9_000, t0), '0:09', 'one digit gets a zero');
eq(countdown(t0 + 1, t0), '0:01', 'the last moment still reads 0:01');
eq(countdown(t0, t0), '0:00', 'due now');
eq(countdown(t0 - 5_000, t0), '0:00', 'overdue never goes negative');
eq(countdown(t0 + 90_000, t0), '1:30', 'a Retry-After of 90 s');
eq(countdown(t0 + 3_600_000, t0), '60:00', 'the longest wait, an hour');
console.log('ok');
