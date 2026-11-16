#!/usr/bin/env python3
"""Summarise a file written by `stripmuxx debug-windows --gesture-trace-stop`.

For every gesture (inputs up to an `end` marker): input rate and travel, how often and how
late the windows follow the fingers, and how far each border piece sits from the window
edge it belongs to. Times are milliseconds on one clock.
"""
import json
import statistics
import sys
from bisect import bisect_left


def percentile(values, p):
    if not values:
        return float('nan')
    values = sorted(values)
    return values[min(len(values) - 1, int(len(values) * p))]


def gestures(inputs):
    current = []
    for step in inputs:
        current.append(step)
        if step['kind'] == 'end':
            yield current
            current = []
    if current:
        yield current


def analyse(trace):
    changes = trace['windowChanges']
    report = []
    for number, steps in enumerate(gestures(trace['inputs']), 1):
        moves = [s for s in steps if s['kind'] != 'end']
        if not moves:
            continue
        t0, t1 = moves[0]['t'], steps[-1]['t']
        kinds = sorted({s['kind'] for s in moves})
        offsets = [s['offset'] for s in moves]
        lines = [f"gesture {number} ({'+'.join(kinds)}): {len(moves)} input steps in {t1 - t0:.0f} ms "
                 f"({len(moves) / max((t1 - t0) / 1000, 0.001):.0f}/s), offset {offsets[0]:.0f} -> {offsets[-1]:.0f}"]
        window = [c for c in changes if t0 - 20 <= c[0] <= t1 + 600 and c[2] != 'StripMuxX']
        border = [c for c in changes if t0 - 20 <= c[0] <= t1 + 600 and c[2] == 'StripMuxX']
        per_window = {}
        for c in window:
            per_window.setdefault(c[1], []).append(c)
        moved = {k: v for k, v in per_window.items() if len({round(r[3]) for r in v}) > 1}
        if moved:
            best = max(moved.values(), key=len)
            span = (best[-1][0] - best[0][0]) / 1000
            lines.append(f"  busiest window ({best[0][2]}): {len(best)} position updates, "
                         f"{len(best) / max(span, 0.001):.0f}/s; {len(moved)} windows moved")
            # Lag: when the input first asked for the offset this position corresponds to.
            x0 = best[0][3]
            times = [m['t'] for m in moves]
            lags = []
            base = moves[0]['offset']
            for row in best[1:]:
                shown = base + (x0 - row[3])
                ahead = [m for m in moves if (m['offset'] - base) * (shown - base) >= 0 and abs(m['offset'] - base) >= abs(shown - base) - 1]
                if ahead:
                    lags.append(max(0.0, row[0] - ahead[0]['t']))
            if lags:
                lines.append(f"  window lag behind the fingers: median {statistics.median(lags):.0f} ms, "
                             f"p90 {percentile(lags, 0.9):.0f} ms, max {max(lags):.0f} ms")
            settle = best[-1][0] - t1
            lines.append(f"  last window move {settle:.0f} ms after the last input step")
        else:
            lines.append("  no window moved")
        # Borders: each tall piece against the nearest window edge, at the moment it changed.
        distances = []
        frames = {}
        for c in sorted(window + border, key=lambda r: r[0]):
            if c[2] != 'StripMuxX':
                frames[c[1]] = c
            elif c[6] >= 400 and frames:
                edges = [f[3] - 4 for f in frames.values()] + [f[3] + f[5] - 1 for f in frames.values()]
                distances.append(min(abs(c[3] - e) for e in edges))
        if distances:
            off = [d for d in distances if d > 6]
            lines.append(f"  border pieces: {len(distances)} updates, {len(off)} more than 6 pt from a window edge "
                         f"({100 * len(off) / len(distances):.0f}%), max {max(distances):.0f} pt")
        else:
            lines.append("  no border updates (borders hidden or disabled)")
        report.append('\n'.join(lines))
    return report or ['no gestures recorded']


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    with open(sys.argv[1]) as handle:
        print('\n\n'.join(analyse(json.load(handle))))
