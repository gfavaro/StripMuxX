# Window management internals

Each desktop's strip is a shallow tree: the root's children are columns, and a
column is a window or a vertical stack. Layout geometry is calculated from value
inputs (column widths, stack weights, gaps and learned window minimum sizes) before
the traversal applies frame changes. The geometry functions are pure and contain no
live windows or Accessibility elements.

## Measurements

`stripmuxx debug-windows --events-start` enables bounded runtime measurements along
with the existing event history. `--events-stop` stops and clears the session;
`--events-export` writes the event history and measurement summary. Samples are
kept in memory and are capped per measurement series. Collection is off by
default.

Recorded values include AX reads/writes/actions reached through instrumented
paths and queued RunLoop job wait. AX duration excludes queue wait. Current counts
are process-wide, not per application, and do not cover every direct AX call;
`doctor` labels them as partial. Its live WindowServer frame query is reported
separately and is excluded from the recorded AX counts. Export schema 2 adds
the `workMetrics` summary while retaining event fields from schema 1.

The summary contains scalar operation counts, failure counts, bounded duration
samples, and sample overflow. It does not include window titles, keyboard text,
or configuration contents. Timing samples are diagnostic observations; they
are not pass/fail performance targets and should be compared on the same machine
and workload.

## Private paths

`doctor` reports whether a tracked window's WindowServer frame agrees with the
public CoreGraphics window list within one point. A missing public witness is
inconclusive. The report is observational and does not change macOS preferences.
Desktop switching and moves between desktops are described in
[Native Spaces](NATIVE_SPACES.md).
