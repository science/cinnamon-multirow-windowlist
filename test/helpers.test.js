const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
    calcRowHeight, calcButtonHeight,
    calcAdaptiveRowCount, calcLayoutMode, calcAdaptiveFontSize, calcAdaptiveIconSize,
    calcButtonWidth, calcGroupedInsertionIndex
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

