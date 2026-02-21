const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
    calcRowHeight, calcIconSize, calcButtonHeight,
    calcAdaptiveRowCount, calcLayoutMode, calcAdaptiveFontSize, calcAdaptiveIconSize
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

describe('calcIconSize', () => {
    it('auto-scales to rowHeight - 8 when override is 0', () => {
        // panelHeight=80, rows=2 → rowHeight=40 → icon=32
        assert.equal(calcIconSize(80, 2, 0), 32);
    });

    it('uses override when positive', () => {
        assert.equal(calcIconSize(80, 2, 24), 24);
    });

    it('enforces minimum of 16 when auto-scaling', () => {
        // panelHeight=80, rows=4 → rowHeight=20 → 20-8=12 → clamped to 16
        assert.equal(calcIconSize(80, 4, 0), 16);
    });

    it('does not clamp override values (user knows best)', () => {
        assert.equal(calcIconSize(80, 4, 12), 12);
    });

    it('auto-scales for single row', () => {
        // panelHeight=48, rows=1 → rowHeight=48 → 48-8=40
        assert.equal(calcIconSize(48, 1, 0), 40);
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
    it('auto-scales for single row', () => {
        // floor(60*0.4) = 24
        assert.equal(calcAdaptiveIconSize(60, 1, 0), 24);
    });

    it('auto-scales for 2 rows', () => {
        // floor(60/2) = 30, floor(30*0.4) = 12
        assert.equal(calcAdaptiveIconSize(60, 2, 0), 12);
    });

    it('uses override when positive', () => {
        assert.equal(calcAdaptiveIconSize(60, 2, 16), 16);
    });

    it('clamps to 12px minimum', () => {
        // floor(40/2)-8 = 20-8 = 12
        assert.equal(calcAdaptiveIconSize(40, 2, 0), 12);
    });

    it('enforces 12px floor for very small rows', () => {
        // floor(36/2)-8 = 18-8 = 10 → clamped to 12
        assert.equal(calcAdaptiveIconSize(36, 2, 0), 12);
    });
});
