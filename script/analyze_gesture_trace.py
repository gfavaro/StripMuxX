#!/usr/bin/env python3
"""Summarise a file written by `stripmuxx debug-windows --gesture-trace-stop`.

Each gesture is the inputs up to an `end` marker. Its window never reaches into the next
gesture. For windows that travelled with the strip, the lag is how long after an input step
asked for a position the window was actually there. Borders are compared with the nearest
window edge. Times are milliseconds on one clock.

    analyze_gesture_trace.py TRACE.json            # per-type and per-app summary
    analyze_gesture_trace.py TRACE.json --each     # also one line per gesture
"""
import json
import statistics
import sys
from collections import defaultdict


def percentile(values, p):
    if not values:
        return float('nan')
    values = sorted(values)
    return values[min(len(values) - 1, int(len(values) * p))]


def split_gestures(inputs):
    current = []
    for step in inputs:
        if step['kind'] == 'end':
            if current:
                yield current, step['t']
            current = []
        else:
            current.append(step)
    if current:
        yield current, current[-1]['t']


def monotone(offsets):
    deltas = [b - a for a, b in zip(offsets, offsets[1:]) if abs(b - a) > 0.5]
    return bool(deltas) and (all(d > 0 for d in deltas) or all(d < 0 for d in deltas))


def analyse(trace, cap_ms=700):
    changes = sorted(trace['windowChanges'], key=lambda r: r[0])
    gestures = list(split_gestures(trace['inputs']))
    rows = []
    for index, (moves, t_end) in enumerate(gestures):
        t0, t1 = moves[0]['t'], moves[-1]['t']
        limit = min(t_end + cap_ms, gestures[index + 1][0][0]['t'] - 1) if index + 1 < len(gestures) else t_end + cap_ms
        kind = 'dock' if any(m['kind'] == 'dock' for m in moves) else 'pan'
        offsets = [m['offset'] for m in moves]
        # Where the strip was before the first step; older traces lack it and lose that step.
        origin = moves[0].get('from', offsets[0])
        travel = abs(offsets[-1] - origin)
        # Positions at the start, and changes inside this gesture's own window.
        start = {}
        inside = defaultdict(list)
        for c in changes:
            if c[0] < t0 - 20:
                start[c[1]] = c
            elif c[0] <= limit:
                inside[c[1]].append(c)
        windows = {i: r for i, r in inside.items() if r[0][2] != 'StripMuxX'}
        result = {'n': index + 1, 'kind': kind, 'steps': len(moves), 'ms': t1 - t0, 'travel': travel,
                  'lags': defaultdict(list), 'settle': None, 'border': [], 'moved': 0}
        if travel >= 150 and monotone([origin] + offsets):
            sign = 1 if offsets[-1] > origin else -1
            for wid, rs in windows.items():
                if wid not in start or len(rs) < 3:
                    continue
                x0 = start[wid][3]
                dx = abs(x0 - rs[-1][3])
                if abs(dx - travel) > 0.25 * travel:      # did not travel with the strip
                    continue
                result['moved'] += 1
                owner = rs[0][2]
                for row in rs:
                    shown = abs(x0 - row[3])
                    asked = next((m for m in moves if sign * (m['offset'] - origin) >= shown - 1), None)
                    if asked is not None and row[0] <= t1 + 50:
                        result['lags'][owner].append(max(0.0, row[0] - asked['t']))
                if result['settle'] is None or rs[-1][0] - t1 > result['settle']:
                    result['settle'] = rs[-1][0] - t1
        # Borders against the nearest edge of a window known at that moment.
        known = {i: r for i, r in start.items() if r[2] != 'StripMuxX'}
        for c in sorted([r for rs in inside.values() for r in rs], key=lambda r: r[0]):
            if c[2] != 'StripMuxX':
                known[c[1]] = c
            elif c[6] >= 400 and known:
                edges = [k[3] - 4 for k in known.values() if k[5] > 300] + [k[3] + k[5] - 1 for k in known.values() if k[5] > 300]
                if edges:
                    result['border'].append(min(abs(c[3] - e) for e in edges))
        rows.append(result)
    return rows


def smoothness(trace):
    """Gaps between input steps and between a window's position updates while the fingers are
    down (gestures over 300 pt)."""
    changes = sorted(trace['windowChanges'], key=lambda c: c[0])
    inputs, windows = [], []
    for moves, _ in split_gestures(trace['inputs']):
        times = [m['t'] for m in moves]
        inputs += [b - a for a, b in zip(times, times[1:])]
        if abs(moves[-1]['offset'] - moves[0].get('from', moves[0]['offset'])) < 300:
            continue
        per = {}
        for c in changes:
            if times[0] <= c[0] <= times[-1] and c[2] != 'StripMuxX':
                per.setdefault(c[1], []).append(c[0])
        if per:
            best = max(per.values(), key=len)
            if len(best) >= 4:
                windows += [b - a for a, b in zip(best, best[1:])]
    return inputs, windows


def gap_line(values):
    if not values:
        return 'n/a'
    return (f"median {statistics.median(values):.1f} ms, p90 {percentile(values, 0.9):.1f} ms, max {max(values):.0f} ms; "
            f"{100 * sum(v > 33 for v in values) // len(values)}% over 33 ms, "
            f"{100 * sum(v > 50 for v in values) // len(values)}% over 50 ms ({len(values)} gaps)")


def fmt(values):
    if not values:
        return 'n/a'
    return f"median {statistics.median(values):.0f} ms, p90 {percentile(values, 0.9):.0f} ms, max {max(values):.0f} ms ({len(values)} samples)"


def report(rows, each=False):
    out = []
    for kind in ('dock', 'pan'):
        mine = [r for r in rows if r['kind'] == kind]
        if not mine:
            continue
        lags = [v for r in mine for vs in r['lags'].values() for v in vs]
        borders = [d for r in mine for d in r['border']]
        settles = [r['settle'] for r in mine if r['settle'] is not None]
        moving = [r for r in mine if r['travel'] >= 150]
        out.append(f"{kind}: {len(mine)} gestures ({len(moving)} moved the strip 150 pt or more), "
                   f"{statistics.median([r['steps'] / max(r['ms'] / 1000, 0.001) for r in mine]):.0f} input steps/s")
        out.append(f"   window lag behind the fingers: {fmt(lags)}")
        if settles:
            out.append(f"   last window move after the last input: median {statistics.median(settles):.0f} ms, max {max(settles):.0f} ms")
        if borders:
            late = [d for d in borders if d > 6]
            out.append(f"   border pieces off a window edge by more than 6 pt: {100 * len(late) / len(borders):.0f}% of {len(borders)} updates "
                       f"(p90 {percentile(borders, 0.9):.0f} pt)")
    by_app = defaultdict(list)
    for r in rows:
        for app, vs in r['lags'].items():
            by_app[app].extend(vs)
    if by_app:
        out.append("window lag by app (gestures that moved the strip):")
        for app, vs in sorted(by_app.items(), key=lambda kv: -statistics.median(kv[1])):
            out.append(f"   {app:<18} {fmt(vs)}")
    if each:
        out.append("per gesture:")
        for r in rows:
            lags = [v for vs in r['lags'].values() for v in vs]
            out.append(f"   #{r['n']:<3} {r['kind']} {r['steps']:>3} steps {r['travel']:>5.0f} pt  lag median "
                       f"{statistics.median(lags) if lags else float('nan'):>4.0f} ms  borders off-edge "
                       f"{100 * sum(d > 6 for d in r['border']) / max(len(r['border']), 1):>3.0f}%")
    return '\n'.join(out)


if __name__ == '__main__':
    arguments = [a for a in sys.argv[1:] if not a.startswith('--')]
    if len(arguments) != 1:
        sys.exit(__doc__)
    with open(arguments[0]) as handle:
        trace = json.load(handle)
    print(report(analyse(trace), each='--each' in sys.argv))
    inputs, windows = smoothness(trace)
    print('smoothness while the fingers are down (a steady 60 Hz is 16.7 ms):')
    print('   input steps:                ' + gap_line(inputs))
    print('   window position updates:    ' + gap_line(windows))
