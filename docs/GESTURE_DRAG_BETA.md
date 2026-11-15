# Wide-column gesture and native drag — beta acceptance

These changes preserve the existing three-finger Dock event arbitration and
finger-following displacement. The new behavior happens **only after release**:

- A recognized, committed swipe normally settles to whichever column is nearest.
- If the current column remains nearest despite a committed directional swipe,
  settle to its *immediate neighbor* in the gesture direction.
- Never advance on cancelled swipes, with zero displacement, or beyond strip ends.
- Never skip an extra column when the viewport already arrived elsewhere.
- Option+two-finger scrolling is unaffected.

The user reported that a 100% or oversized column was hard to exit using
three fingers; the improvement is meant to address precisely that case. It
does not change sensitivity or synthetic Dock events.

## Native drag preview

The drag overlay is passive and opt-in per qualified titlebar drag. It uses
the exact same in-desktop tile target lookup as release adoption. Floating
windows, unrecognized source windows and invalid targets are ignored.
The outline is nonactivating and ignores mouse events. It never joins all
Spaces or writes AX frames. The overlay is hidden on mouse-up, lifecycle
invalidation, stop, and on a 3-second idle timeout. The final swap is still
performed only on mouse release by the existing adopted mouse-release path.

## Validation

Run the full `make check` / CI against the final commit and perform the
interactive matrix in `docs/BETA_VERIFICATION.md` before declaring beta
stable. In particular test 50%, 100%, and fixed >100% columns in both swipe
directions, fast and slow gestures, and verify that a rejected swipe never
changes focus. On a nonprimary monitor, verify that drag indicators appear
over the target and never follow a Space change.

A CI pass does not prove Dock/private-event behavior or visual placement on
a physical multi-monitor desktop.
