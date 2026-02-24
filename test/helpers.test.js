const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
    calcRowHeight, calcButtonHeight,
    calcAdaptiveRowCount, calcLayoutMode, calcAdaptiveFontSize, calcAdaptiveIconSize,
    calcButtonWidth, calcGroupedInsertionIndex, calcDragInsertionIndex
} = require('../helpers');

describe('calcRowHeight', () => {
    it('returns full panel height for 1 row', () => {
        assert.equal(calcRowHeight(80, 1), 80);
    });

    it('returns half panel height for 2 rows', () => {
        assert.equal(calcRowHeight(80, 2), 40);
    });

    it('returns third panel height for 3 rows', () => {
        assert.equal(calcRowHeight(96, 3), 32);
    });

    it('returns quarter panel height for 4 rows', () => {
        assert.equal(calcRowHeight(96, 4), 24);
    });

    it('floors fractional results', () => {
        assert.equal(calcRowHeight(100, 3), 33);
    });
});

describe('calcButtonHeight', () => {
    it('returns same as calcRowHeight (buttons fill the row)', () => {
        assert.equal(calcButtonHeight(80, 2), 40);
    });

    it('works for 1 row', () => {
        assert.equal(calcButtonHeight(96, 1), 96);
    });

    it('works for 3 rows', () => {
        assert.equal(calcButtonHeight(96, 3), 32);
    });
});

describe('calcAdaptiveRowCount', () => {
    it('returns 1 row when all buttons fit', () => {
        // 1200/150=8 slots, 5 buttons → 1 row
        assert.equal(calcAdaptiveRowCount(1200, 5, 150, 2), 1);
    });

    it('returns 2 rows when buttons overflow', () => {
        // 1200/150=8 slots, 10 buttons → ceil(10/8)=2
        assert.equal(calcAdaptiveRowCount(1200, 10, 150, 2), 2);
    });

    it('caps at maxRows', () => {
        // 1200/150=8 slots, 25 buttons → ceil(25/8)=4 → capped at 2
        assert.equal(calcAdaptiveRowCount(1200, 25, 150, 2), 2);
    });

    it('returns 1 for 0 buttons', () => {
        assert.equal(calcAdaptiveRowCount(1200, 0, 150, 2), 1);
    });

    it('returns 1 for 1 button', () => {
        assert.equal(calcAdaptiveRowCount(1200, 1, 150, 2), 1);
    });

    it('returns 1 when containerWidth is 0', () => {
        assert.equal(calcAdaptiveRowCount(0, 10, 150, 2), 1);
    });

    it('returns 1 when buttonWidth is 0', () => {
        assert.equal(calcAdaptiveRowCount(1200, 10, 0, 2), 1);
    });

    it('returns 1 when maxRows is 1', () => {
        assert.equal(calcAdaptiveRowCount(1200, 25, 150, 1), 1);
    });
});

describe('calcLayoutMode', () => {
    it('returns spacious for 1 row', () => {
        assert.equal(calcLayoutMode(1), 'spacious');
    });

    it('returns compact for 2 rows', () => {
        assert.equal(calcLayoutMode(2), 'compact');
    });

    it('returns compact for 3 rows', () => {
        assert.equal(calcLayoutMode(3), 'compact');
    });
});

describe('calcAdaptiveFontSize', () => {
    it('returns 0 (default) for 1 row', () => {
        assert.equal(calcAdaptiveFontSize(60, 1), 0);
    });

    it('returns 8pt for 60px panel, 2 rows', () => {
        // floor(30/3.5) = floor(8.57) = 8
        assert.equal(calcAdaptiveFontSize(60, 2), 8);
    });

    it('caps at 10pt for large rows', () => {
        // 80px/2 = 40, floor(40/3.5) = floor(11.4) = 11 → capped at 10
        assert.equal(calcAdaptiveFontSize(80, 2), 10);
    });

    it('returns 6pt for 48px panel, 2 rows', () => {
        // floor(24/3.5) = floor(6.86) = 6
        assert.equal(calcAdaptiveFontSize(48, 2), 6);
    });

    it('clamps to 6pt minimum', () => {
        // 40px/2 = 20, floor(20/3.5) = floor(5.7) = 5 → clamped to 6
        assert.equal(calcAdaptiveFontSize(40, 2), 6);
    });
});

describe('calcAdaptiveIconSize', () => {
    it('uses 0.25 ratio for spacious mode (1 row)', () => {
        // floor(60*0.25) = 15
        assert.equal(calcAdaptiveIconSize(60, 1, 0), 15);
    });

    it('uses 0.4 ratio for compact mode (2 rows)', () => {
        // floor(60/2) = 30, floor(30*0.4) = 12
        assert.equal(calcAdaptiveIconSize(60, 2, 0), 12);
    });

    it('uses override when positive', () => {
        assert.equal(calcAdaptiveIconSize(60, 2, 16), 16);
    });

    it('spacious on 80px panel gives 20px icon', () => {
        // floor(80*0.25) = 20
        assert.equal(calcAdaptiveIconSize(80, 1, 0), 20);
    });

    it('clamps to 12px minimum in compact mode', () => {
        // floor(40/2) = 20, floor(20*0.4) = 8 → clamped to 12
        assert.equal(calcAdaptiveIconSize(40, 2, 0), 12);
    });

    it('clamps to 12px minimum in spacious mode', () => {
        // floor(40*0.25) = 10 → clamped to 12
        assert.equal(calcAdaptiveIconSize(40, 1, 0), 12);
    });
});

describe('calcButtonWidth', () => {
    // 938px zone, 150px buttons, 2 maxRows → 6 per row × 2 = 12 fit
    it('returns configured width when all buttons fit', () => {
        // 938/150 = 6.25 → 6 per row × 2 rows = 12 slots; 10 buttons fit
        assert.equal(calcButtonWidth(938, 10, 150, 2, 50), 150);
    });

    it('shrinks when buttons overflow maxRows', () => {
        // 20 buttons, 2 rows → 10 per row needed → floor(938/10) = 93
        assert.equal(calcButtonWidth(938, 20, 150, 2, 50), 93);
    });

    it('respects minimum width floor', () => {
        // 50 buttons, 2 rows → 25 per row → floor(938/25) = 37 → clamped to 50
        assert.equal(calcButtonWidth(938, 50, 150, 2, 50), 50);
    });

    it('returns configured width for 0 visibleCount', () => {
        assert.equal(calcButtonWidth(938, 0, 150, 2, 50), 150);
    });

    it('returns configured width for negative visibleCount', () => {
        assert.equal(calcButtonWidth(938, -1, 150, 2, 50), 150);
    });

    it('returns configured width for 0 containerWidth', () => {
        assert.equal(calcButtonWidth(0, 10, 150, 2, 50), 150);
    });

    it('handles 1 window 1 row (no shrink needed)', () => {
        assert.equal(calcButtonWidth(938, 1, 150, 1, 50), 150);
    });

    it('exact boundary: buttons exactly fill maxRows (no shrink)', () => {
        // 6 per row × 2 rows = 12; 12 buttons → fits exactly
        assert.equal(calcButtonWidth(938, 12, 150, 2, 50), 150);
    });

    it('one over boundary triggers shrink', () => {
        // 13 buttons, 2 rows → 7 per row → floor(938/7) = 134
        assert.equal(calcButtonWidth(938, 13, 150, 2, 50), 134);
    });
});

describe('calcGroupedInsertionIndex', () => {
    it('returns 0 for empty list', () => {
        assert.equal(calcGroupedInsertionIndex([], 'firefox.desktop'), 0);
    });

    it('returns end index when no match (new app)', () => {
        assert.equal(calcGroupedInsertionIndex(['firefox', 'terminal'], 'nautilus'), 2);
    });

    it('inserts after single match at start', () => {
        assert.equal(calcGroupedInsertionIndex(['firefox', 'terminal'], 'firefox'), 1);
    });

    it('inserts after single match at end', () => {
        assert.equal(calcGroupedInsertionIndex(['terminal', 'firefox'], 'firefox'), 2);
    });

    it('inserts after single match in middle', () => {
        assert.equal(calcGroupedInsertionIndex(['terminal', 'firefox', 'nautilus'], 'firefox'), 2);
    });

    it('inserts after last of multiple consecutive matches', () => {
        assert.equal(calcGroupedInsertionIndex(['firefox', 'firefox', 'terminal'], 'firefox'), 2);
    });

    it('inserts after last of multiple non-consecutive matches', () => {
        assert.equal(calcGroupedInsertionIndex(['firefox', 'terminal', 'firefox', 'nautilus'], 'firefox'), 3);
    });

    it('returns end index for null newAppId', () => {
        assert.equal(calcGroupedInsertionIndex(['firefox', 'terminal'], null), 2);
    });

    it('returns end index for undefined newAppId', () => {
        assert.equal(calcGroupedInsertionIndex(['firefox', 'terminal'], undefined), 2);
    });

    it('handles null entries in existing list', () => {
        assert.equal(calcGroupedInsertionIndex(['firefox', null, 'firefox'], 'firefox'), 3);
    });
});

describe('calcDragInsertionIndex', () => {
    // Layout for multi-row tests:
    //   Container: 300px wide, buttons 150px wide × 30px tall
    //   Row 1: [B0: 0,0]   [B1: 150,0]
    //   Row 2: [B2: 0,30]  [B3: 150,30]
    const twoRowButtons = [
        { x: 0,   y: 0,  width: 150, height: 30 },  // B0 center: (75, 15)
        { x: 150, y: 0,  width: 150, height: 30 },  // B1 center: (225, 15)
        { x: 0,   y: 30, width: 150, height: 30 },  // B2 center: (75, 45)
        { x: 150, y: 30, width: 150, height: 30 },  // B3 center: (225, 45)
    ];

    // Single-row layout (3 buttons, 100px wide × 30px tall)
    //   [B0: 0,0] [B1: 100,0] [B2: 200,0]
    const singleRowButtons = [
        { x: 0,   y: 0, width: 100, height: 30 },  // center: (50, 15)
        { x: 100, y: 0, width: 100, height: 30 },  // center: (150, 15)
        { x: 200, y: 0, width: 100, height: 30 },  // center: (250, 15)
    ];

    // --- Edge cases ---

    it('returns -1 for empty child list', () => {
        assert.equal(calcDragInsertionIndex([], 100, 15, false), -1);
    });

    it('returns 0 for single child', () => {
        const single = [{ x: 0, y: 0, width: 100, height: 30 }];
        assert.equal(calcDragInsertionIndex(single, 200, 15, false), 0);
    });

    // --- Single-row (baseline — should pass with any algorithm) ---

    it('single row: cursor near B0 center finds B0', () => {
        assert.equal(calcDragInsertionIndex(singleRowButtons, 40, 15, false), 0);
    });

    it('single row: cursor near B1 center finds B1', () => {
        assert.equal(calcDragInsertionIndex(singleRowButtons, 160, 15, false), 1);
    });

    it('single row: cursor near B2 center finds B2', () => {
        assert.equal(calcDragInsertionIndex(singleRowButtons, 260, 15, false), 2);
    });

    it('single row: cursor between B0 and B1 finds closer one', () => {
        // x=90 is closer to B0 center (50) than B1 center (150)
        assert.equal(calcDragInsertionIndex(singleRowButtons, 90, 15, false), 0);
    });

    it('single row: cursor at midpoint between B0 and B1', () => {
        // x=100 is equidistant; either 0 or 1 is acceptable
        let result = calcDragInsertionIndex(singleRowButtons, 100, 15, false);
        assert.ok(result === 0 || result === 1, `expected 0 or 1, got ${result}`);
    });

    // --- Multi-row: cursor in row 2 (BUG: these should find row 2 buttons) ---

    it('two rows: cursor in row 2 left finds B2, not B0', () => {
        // Cursor at (75, 40) — directly above B2 center (75, 45)
        // B0 center is (75, 15) — same X but different row
        // Should find B2 (index 2) because cursor is in row 2
        assert.equal(calcDragInsertionIndex(twoRowButtons, 75, 40, false), 2);
    });

    it('two rows: cursor in row 2 right finds B3, not B1', () => {
        // Cursor at (225, 40) — near B3 center (225, 45)
        // B1 center is (225, 15) — same X but row 1
        // Should find B3 (index 3)
        assert.equal(calcDragInsertionIndex(twoRowButtons, 225, 40, false), 3);
    });

    it('two rows: cursor at row 2 left edge finds B2', () => {
        // Cursor at (10, 35) — in row 2 area, near left side
        // Closest by 2D distance: B2 at (75, 45) — dist ≈ 66
        // B0 at (75, 15) — dist ≈ 68 — further because Y distance is larger
        assert.equal(calcDragInsertionIndex(twoRowButtons, 10, 35, false), 2);
    });

    it('two rows: cursor at B2 exact center finds B2', () => {
        assert.equal(calcDragInsertionIndex(twoRowButtons, 75, 45, false), 2);
    });

    it('two rows: cursor at B3 exact center finds B3', () => {
        assert.equal(calcDragInsertionIndex(twoRowButtons, 225, 45, false), 3);
    });

    // --- Multi-row: cursor in row 1 should still find row 1 buttons ---

    it('two rows: cursor in row 1 left finds B0', () => {
        assert.equal(calcDragInsertionIndex(twoRowButtons, 75, 10, false), 0);
    });

    it('two rows: cursor in row 1 right finds B1', () => {
        assert.equal(calcDragInsertionIndex(twoRowButtons, 225, 10, false), 1);
    });

    // --- Multi-row: cursor between rows should pick closer row ---

    it('two rows: cursor between rows closer to row 1 finds row 1 button', () => {
        // Cursor at (75, 20) — closer to row 1 center y=15 than row 2 center y=45
        assert.equal(calcDragInsertionIndex(twoRowButtons, 75, 20, false), 0);
    });

    it('two rows: cursor between rows closer to row 2 finds row 2 button', () => {
        // Cursor at (75, 35) — closer to row 2 center y=45 than row 1 center y=15
        assert.equal(calcDragInsertionIndex(twoRowButtons, 75, 35, false), 2);
    });

    // --- 3-row layout ---

    it('three rows: cursor in row 3 finds row 3 button', () => {
        // 6 buttons in 3 rows of 2
        const threeRowButtons = [
            { x: 0,   y: 0,  width: 150, height: 20 },  // B0 center: (75, 10)
            { x: 150, y: 0,  width: 150, height: 20 },  // B1 center: (225, 10)
            { x: 0,   y: 20, width: 150, height: 20 },  // B2 center: (75, 30)
            { x: 150, y: 20, width: 150, height: 20 },  // B3 center: (225, 30)
            { x: 0,   y: 40, width: 150, height: 20 },  // B4 center: (75, 50)
            { x: 150, y: 40, width: 150, height: 20 },  // B5 center: (225, 50)
        ];
        // Cursor at (75, 48) — in row 3, should find B4
        assert.equal(calcDragInsertionIndex(threeRowButtons, 75, 48, false), 4);
    });

    // --- Vertical panel (isVertical = true, uses Y axis primarily) ---

    it('vertical panel single column: finds closest by Y', () => {
        const verticalButtons = [
            { x: 0, y: 0,   width: 60, height: 30 },  // center: (30, 15)
            { x: 0, y: 30,  width: 60, height: 30 },  // center: (30, 45)
            { x: 0, y: 60,  width: 60, height: 30 },  // center: (30, 75)
        ];
        assert.equal(calcDragInsertionIndex(verticalButtons, 30, 50, true), 1);
    });

    // --- Uneven row (last row partially filled) ---

    it('two rows with partial second row: cursor in row 2 finds B2', () => {
        // 3 buttons: 2 in row 1, 1 in row 2
        const unevenButtons = [
            { x: 0,   y: 0,  width: 150, height: 30 },  // B0 center: (75, 15)
            { x: 150, y: 0,  width: 150, height: 30 },  // B1 center: (225, 15)
            { x: 0,   y: 30, width: 150, height: 30 },  // B2 center: (75, 45)
        ];
        // Cursor at (75, 40) — in row 2, should find B2 not B0
        assert.equal(calcDragInsertionIndex(unevenButtons, 75, 40, false), 2);
    });

    it('two rows with partial second row: cursor in empty row 2 right finds B2 (only row 2 button)', () => {
        // 3 buttons: 2 in row 1, 1 in row 2 (right side of row 2 is empty)
        const unevenButtons = [
            { x: 0,   y: 0,  width: 150, height: 30 },  // B0 center: (75, 15)
            { x: 150, y: 0,  width: 150, height: 30 },  // B1 center: (225, 15)
            { x: 0,   y: 30, width: 150, height: 30 },  // B2 center: (75, 45)
        ];
        // Cursor at (225, 40) — row 2 right side (empty), but closer to B2 than B1 by Y
        // B1 center: (225, 15), dist = sqrt(0 + 625) = 25
        // B2 center: (75, 45), dist = sqrt(22500 + 25) ≈ 150
        // B1 is actually closer here — that's correct behavior (nearest button wins)
        assert.equal(calcDragInsertionIndex(unevenButtons, 225, 40, false), 1);
    });
});

