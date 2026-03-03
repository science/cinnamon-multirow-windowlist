# Fix: Button width overflow and single-window full-width bugs

## Context

Two bugs on the live desktop (host uses Pragmatic-Darker-Blue theme with `border: 1px solid` and `margin-bottom: 3px` on `.window-list-item-box`):

1. **Windows disappearing instead of shrinking** — with many windows open, buttons wrap beyond `maxRows` and become invisible below the panel, instead of shrinking to fit. Closing windows reveals the hidden ones.
2. **Single window full-width** (hard to repro) — after switching to a new workspace and opening Firefox, the single button spanned the entire panel zone. Adding a second window fixed it.

## Bug 2 Root Cause: Missing horizontal border in `hPad`

In `_recomputeAdaptiveRows()` (applet.js:1373), `hPad` only includes CSS padding:
```javascript
hPad = Math.ceil(tn.get_horizontal_padding());  // MISSING: border + margin
```

But the vertical analog correctly includes borders:
```javascript
vOverhead = tn.get_vertical_padding()
    + tn.get_border_width(0) + tn.get_border_width(2);  // padding + border ✓
```

With `border: 1px solid`, each button is 2px wider than calculated. For 20 windows: computed 10/row but only 9 fit → 2 buttons invisible. The VM tests didn't catch this because the default Cinnamon theme has no borders on `.window-list-item-box`, and the ±2 "warn" tolerance masks the overflow.

## Bug 1 Analysis: Defensive guards needed

Can't pinpoint exact root cause (unreproducible). Likely a timing race during workspace switch where FlowLayout has stale cache state, or a `homogeneous: true` edge case with a single child. Two defensive measures will reduce the likelihood.

---

## Changes

### 1. Fix `hPad` → `hOverhead` (applet.js `_recomputeAdaptiveRows`, lines 1368-1380)

Rename `hPad` to `hOverhead` and include horizontal borders + margins:

```javascript
// Before:
hPad = Math.ceil(tn.get_horizontal_padding());

// After:
let hMargin = tn.get_length('margin-left') + tn.get_length('margin-right');
hOverhead = Math.ceil(tn.get_horizontal_padding()
    + tn.get_border_width(1) + tn.get_border_width(3)
    + hMargin);
```

Update all 3 references from `hPad` → `hOverhead` in the method (lines 1380, 1386, 1388).

### 2. Cap `_getPreferredWidth` output (applet.js, line 685)

Prevent any button from reporting a preferred width exceeding configured `buttonWidth` (only in the fixed-width branch, not `buttonsUseEntireSpace`):

```javascript
// Before:
alloc.natural_size = this._applet._effectiveButtonWidth * global.ui_scale;

// After:
alloc.natural_size = Math.min(
    this._applet._effectiveButtonWidth * global.ui_scale,
    this._applet.buttonWidth * global.ui_scale);
```

### 3. Force FlowLayout refresh on 0→N visible transition (applet.js)

Track `_lastVisibleCount` and force FlowLayout replacement when transitioning from 0 visible windows to >0 (workspace switch scenario):

- Constructor (after line 1194): `this._lastVisibleCount = 0;`
- In `_recomputeAdaptiveRows()` after line 1363:
  ```javascript
  let wasEmpty = this._lastVisibleCount === 0;
  this._lastVisibleCount = visibleCount;
  ```
- Modify condition at line 1411:
  ```javascript
  if (widthChanged || (wasEmpty && visibleCount > 0)) {
  ```

### 4. Lint tests (test/applet-lint.test.js)

New `describe('button width accounts for CSS box model')` block:
- Verify `_recomputeAdaptiveRows` includes `get_border_width(1)` and `get_border_width(3)`
- Verify horizontal margin (`margin-left`, `margin-right`) is included
- Verify `hOverhead` naming (not `hPad`)
- Verify `_lastVisibleCount` tracking exists

---

## Implementation Order (TDD)

1. Write lint tests → `npm test` → new tests fail
2. Apply Bug 2 fix (hOverhead) in applet.js
3. Apply Bug 1 guards in applet.js
4. `npm test` → all pass
5. VM test: `./test/vm-panel-test.sh --revert 0 1 10 15 20 30 40 50`
6. Crop + inspect screenshots at 65px height

## Files Modified

| File | Change |
|------|--------|
| `applet.js` | `hPad` → `hOverhead` with border+margin; `_getPreferredWidth` cap; `_lastVisibleCount` tracking |
| `test/applet-lint.test.js` | 4 new lint assertions for horizontal CSS box model |

## Verification

- `npm test` — all tests pass (including new lint checks)
- VM panel test 0–50 windows — "All buttons on-screen" should show PASS (not warn) for 15/20-window cases
- Screenshot inspection — no clipped/invisible buttons at moderate window counts
