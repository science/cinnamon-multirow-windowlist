const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
    calcRowHeight, calcButtonHeight,
    calcAdaptiveRowCount, calcLayoutMode, calcAdaptiveFontSize, calcAdaptiveIconSize,
    calcButtonWidth, calcGroupedInsertionIndex, calcDragInsertionIndex,
    parsePinRules, matchPinRule, calcPinnedInsertionIndex, calcSortedButtonOrder,
    buildEditorRules, filterPinRule
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

    it('subtracts vertical margin (60px, 2 rows, 3px margin)', () => {
        assert.equal(calcRowHeight(60, 2, 3), 27);
    });

    it('defaults to 0 margin for backwards compat', () => {
        assert.equal(calcRowHeight(60, 2), 30);
    });

    it('handles single row with margin', () => {
        assert.equal(calcRowHeight(60, 1, 3), 57);
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

    it('accounts for vertical margin (60px, 2 rows, 3px)', () => {
        assert.equal(calcButtonHeight(60, 2, 3), 27);
    });

    it('backwards compat with no margin arg', () => {
        assert.equal(calcButtonHeight(60, 2), 30);
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

    it('uses margin-adjusted row height (60px, 2 rows, 3px margin)', () => {
        // rowHeight = (60-6)/2 = 27, floor(27/3.5) = 7
        assert.equal(calcAdaptiveFontSize(60, 2, 3), 7);
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

    it('uses margin-adjusted row height (60px, 2 rows, 0 override, 3px margin)', () => {
        // rowHeight = (60-6)/2 = 27, floor(27*0.4) = 10 → clamped to 12
        assert.equal(calcAdaptiveIconSize(60, 2, 0, 3), 12);
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

describe('calcAdaptiveRowCount — row transition boundary', () => {
    it('transitions from 2 rows to 1 at exact boundary', () => {
        // containerWidth=900, buttonWidth=150 → buttonsPerRow=6
        // 7 windows → ceil(7/6)=2 rows; 6 windows → ceil(6/6)=1 row
        assert.equal(calcAdaptiveRowCount(900, 7, 150, 2), 2);
        assert.equal(calcAdaptiveRowCount(900, 6, 150, 2), 1);
    });

    it('transitions from 1 row to 2 when adding one window', () => {
        // 6 fit in 1 row, 7th triggers row 2
        assert.equal(calcAdaptiveRowCount(900, 6, 150, 2), 1);
        assert.equal(calcAdaptiveRowCount(900, 7, 150, 2), 2);
    });

    it('stays at 1 row when closing windows below boundary', () => {
        // Simulate closing: 7→6→5→4 all stay at 1 row once below threshold
        for (let n = 6; n >= 1; n--) {
            assert.equal(calcAdaptiveRowCount(900, n, 150, 2), 1,
                `${n} windows should be 1 row`);
        }
    });
});

describe('calcButtonHeight — margin math for theme correctness', () => {
    it('allocation + margin fits panel for Pragmatic theme (2 rows)', () => {
        // Pragmatic-Darker-Blue: margin-bottom=3, margin-top=0 → total vMargin=3
        // calcButtonHeight returns allocation height (content + overhead budget)
        // (allocation + margin) × rows must not exceed panelHeight
        let panelHeight = 60;
        let rows = 2;
        let vMargin = 3;
        let allocHeight = calcButtonHeight(panelHeight, rows, vMargin);
        assert.ok((allocHeight + vMargin) * rows <= panelHeight,
            `(${allocHeight} + ${vMargin}) × ${rows} = ${(allocHeight + vMargin) * rows}px > ${panelHeight}px`);
    });

    it('allocation + margin fits panel with both margins (2 rows)', () => {
        // Theme with margin-top=3 + margin-bottom=3 → total vMargin=6
        let panelHeight = 60;
        let rows = 2;
        let vMargin = 6;
        let allocHeight = calcButtonHeight(panelHeight, rows, vMargin);
        assert.ok((allocHeight + vMargin) * rows <= panelHeight,
            `(${allocHeight} + ${vMargin}) × ${rows} = ${(allocHeight + vMargin) * rows}px > ${panelHeight}px`);
    });

    it('allocation + margin fits panel for single row', () => {
        let panelHeight = 60;
        let rows = 1;
        let vMargin = 3;
        let allocHeight = calcButtonHeight(panelHeight, rows, vMargin);
        assert.ok((allocHeight + vMargin) * rows <= panelHeight,
            `(${allocHeight} + ${vMargin}) × ${rows} = ${(allocHeight + vMargin) * rows}px > ${panelHeight}px`);
    });

    it('margin=0 gives same result as no-margin calcButtonHeight', () => {
        assert.equal(calcButtonHeight(60, 2, 0), calcButtonHeight(60, 2));
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

describe('parsePinRules', () => {
    it('parses valid JSON array', () => {
        let rules = parsePinRules('[{"appId":"firefox.desktop","title":"^Mail","priority":0}]');
        assert.equal(rules.length, 1);
        assert.equal(rules[0].appId, 'firefox.desktop');
        assert.equal(rules[0].priority, 0);
        assert.ok(rules[0].titleRegex instanceof RegExp);
        assert.ok(rules[0].titleRegex.test('Mail - Firefox'));
    });

    it('returns empty array for empty JSON array', () => {
        assert.deepEqual(parsePinRules('[]'), []);
    });

    it('returns empty array for invalid JSON', () => {
        assert.deepEqual(parsePinRules('not json'), []);
    });

    it('returns empty array for non-array JSON', () => {
        assert.deepEqual(parsePinRules('{"appId":"foo"}'), []);
    });

    it('drops entries missing appId', () => {
        let rules = parsePinRules('[{"priority":0}]');
        assert.equal(rules.length, 0);
    });

    it('drops entries with empty appId', () => {
        let rules = parsePinRules('[{"appId":"","priority":0}]');
        assert.equal(rules.length, 0);
    });

    it('drops entries missing priority', () => {
        let rules = parsePinRules('[{"appId":"firefox.desktop"}]');
        assert.equal(rules.length, 0);
    });

    it('drops entries with non-numeric priority', () => {
        let rules = parsePinRules('[{"appId":"firefox.desktop","priority":"high"}]');
        assert.equal(rules.length, 0);
    });

    it('drops entries with Infinity priority', () => {
        let rules = parsePinRules(JSON.stringify([{appId: "firefox.desktop", priority: Infinity}]));
        assert.equal(rules.length, 0);
    });

    it('drops entries with invalid regex', () => {
        let rules = parsePinRules('[{"appId":"firefox.desktop","title":"[invalid","priority":0}]');
        assert.equal(rules.length, 0);
    });

    it('allows title-optional rules (titleRegex is null)', () => {
        let rules = parsePinRules('[{"appId":"terminal.desktop","priority":3}]');
        assert.equal(rules.length, 1);
        assert.equal(rules[0].titleRegex, null);
    });

    it('keeps valid entries and drops invalid ones', () => {
        let input = JSON.stringify([
            {appId: "firefox.desktop", title: "^Mail", priority: 0},
            {priority: 1},
            {appId: "terminal.desktop", priority: 2}
        ]);
        let rules = parsePinRules(input);
        assert.equal(rules.length, 2);
        assert.equal(rules[0].appId, 'firefox.desktop');
        assert.equal(rules[1].appId, 'terminal.desktop');
    });

    it('handles null title (treated as no title filter)', () => {
        let rules = parsePinRules('[{"appId":"firefox.desktop","title":null,"priority":0}]');
        assert.equal(rules.length, 1);
        assert.equal(rules[0].titleRegex, null);
    });
});

describe('matchPinRule', () => {
    const rules = parsePinRules(JSON.stringify([
        {appId: "firefox.desktop", title: "^Mail -", priority: 0},
        {appId: "firefox.desktop", title: "^Calendar -", priority: 1},
        {appId: "terminal.desktop", priority: 3},
        {appId: "firefox.desktop", priority: 5}
    ]));

    it('matches appId + title regex', () => {
        let match = matchPinRule(rules, 'firefox.desktop', 'Mail - Firefox');
        assert.notEqual(match, null);
        assert.equal(match.priority, 0);
    });

    it('matches second title rule', () => {
        let match = matchPinRule(rules, 'firefox.desktop', 'Calendar - Firefox');
        assert.notEqual(match, null);
        assert.equal(match.priority, 1);
    });

    it('appId-only rule matches any title', () => {
        let match = matchPinRule(rules, 'terminal.desktop', 'bash - ~');
        assert.notEqual(match, null);
        assert.equal(match.priority, 3);
    });

    it('returns lowest priority match when multiple rules match', () => {
        // "Some Page - Firefox" matches appId-only rule (priority 5) but not title rules
        let match = matchPinRule(rules, 'firefox.desktop', 'Some Page - Firefox');
        assert.notEqual(match, null);
        assert.equal(match.priority, 5);
    });

    it('title rule wins over appId-only rule when both match (lower priority)', () => {
        // "Mail - Firefox" matches title rule (priority 0) and appId-only rule (priority 5)
        let match = matchPinRule(rules, 'firefox.desktop', 'Mail - Firefox');
        assert.equal(match.priority, 0);
    });

    it('returns null for no match', () => {
        assert.equal(matchPinRule(rules, 'nautilus.desktop', 'Files'), null);
    });

    it('returns null for null appId', () => {
        assert.equal(matchPinRule(rules, null, 'anything'), null);
    });

    it('returns null for undefined appId', () => {
        assert.equal(matchPinRule(rules, undefined, 'anything'), null);
    });

    it('title-requiring rule does not match null title', () => {
        // Only the appId-only firefox rule (priority 5) should match
        let match = matchPinRule(rules, 'firefox.desktop', null);
        assert.notEqual(match, null);
        assert.equal(match.priority, 5);
    });

    it('returns null for empty rules array', () => {
        assert.equal(matchPinRule([], 'firefox.desktop', 'Mail'), null);
    });
});

describe('calcPinnedInsertionIndex', () => {
    it('returns 0 for empty container', () => {
        assert.equal(calcPinnedInsertionIndex([], 0, 'firefox.desktop'), 0);
    });

    it('inserts at start when priority is lower than all existing', () => {
        let children = [
            {pinPriority: 5, appId: 'terminal.desktop'},
            {pinPriority: null, appId: 'nautilus.desktop'}
        ];
        assert.equal(calcPinnedInsertionIndex(children, 0, 'firefox.desktop'), 0);
    });

    it('inserts after existing pinned with lower priority', () => {
        let children = [
            {pinPriority: 0, appId: 'firefox.desktop'},
            {pinPriority: null, appId: 'nautilus.desktop'}
        ];
        assert.equal(calcPinnedInsertionIndex(children, 5, 'terminal.desktop'), 1);
    });

    it('appends after last sibling with same priority+appId', () => {
        let children = [
            {pinPriority: 0, appId: 'firefox.desktop'},
            {pinPriority: 0, appId: 'firefox.desktop'},
            {pinPriority: 5, appId: 'terminal.desktop'},
            {pinPriority: null, appId: 'nautilus.desktop'}
        ];
        assert.equal(calcPinnedInsertionIndex(children, 0, 'firefox.desktop'), 2);
    });

    it('inserts before first higher priority when no siblings exist', () => {
        let children = [
            {pinPriority: 0, appId: 'firefox.desktop'},
            {pinPriority: 10, appId: 'nautilus.desktop'},
            {pinPriority: null, appId: 'gedit.desktop'}
        ];
        assert.equal(calcPinnedInsertionIndex(children, 5, 'terminal.desktop'), 1);
    });

    it('inserts before unpinned when all pinned have lower priority', () => {
        let children = [
            {pinPriority: 0, appId: 'firefox.desktop'},
            {pinPriority: 1, appId: 'terminal.desktop'},
            {pinPriority: null, appId: 'nautilus.desktop'},
            {pinPriority: null, appId: 'gedit.desktop'}
        ];
        assert.equal(calcPinnedInsertionIndex(children, 5, 'code.desktop'), 2);
    });

    it('appends at end when all are pinned with lower priority', () => {
        let children = [
            {pinPriority: 0, appId: 'firefox.desktop'},
            {pinPriority: 1, appId: 'terminal.desktop'}
        ];
        assert.equal(calcPinnedInsertionIndex(children, 5, 'code.desktop'), 2);
    });
});

describe('calcSortedButtonOrder', () => {
    it('returns original order when no rules match (all unpinned)', () => {
        let buttons = [
            {pinPriority: null, appId: 'firefox', title: 'A', originalIndex: 0},
            {pinPriority: null, appId: 'terminal', title: 'B', originalIndex: 1},
            {pinPriority: null, appId: 'nautilus', title: 'C', originalIndex: 2}
        ];
        assert.deepEqual(calcSortedButtonOrder(buttons), [0, 1, 2]);
    });

    it('puts all pinned before unpinned, sorted by priority', () => {
        let buttons = [
            {pinPriority: null, appId: 'nautilus', title: 'Files', originalIndex: 0},
            {pinPriority: 5, appId: 'terminal', title: 'bash', originalIndex: 1},
            {pinPriority: 0, appId: 'firefox', title: 'Mail', originalIndex: 2}
        ];
        assert.deepEqual(calcSortedButtonOrder(buttons), [2, 1, 0]);
    });

    it('unpinned buttons preserve relative order', () => {
        let buttons = [
            {pinPriority: null, appId: 'nautilus', title: 'Files', originalIndex: 0},
            {pinPriority: 0, appId: 'firefox', title: 'Mail', originalIndex: 1},
            {pinPriority: null, appId: 'gedit', title: 'doc.txt', originalIndex: 2},
            {pinPriority: null, appId: 'terminal', title: 'bash', originalIndex: 3}
        ];
        // Pinned: [1], Unpinned in order: [0, 2, 3]
        assert.deepEqual(calcSortedButtonOrder(buttons), [1, 0, 2, 3]);
    });

    it('sorts same-priority pinned by appId then title', () => {
        let buttons = [
            {pinPriority: 0, appId: 'terminal', title: 'bash', originalIndex: 0},
            {pinPriority: 0, appId: 'firefox', title: 'Mail', originalIndex: 1},
            {pinPriority: 0, appId: 'firefox', title: 'Calendar', originalIndex: 2}
        ];
        // Same priority: firefox < terminal (alpha), then Calendar < Mail
        assert.deepEqual(calcSortedButtonOrder(buttons), [2, 1, 0]);
    });

    it('tiebreaks by originalIndex when priority+appId+title all match', () => {
        let buttons = [
            {pinPriority: 0, appId: 'firefox', title: 'Tab', originalIndex: 0},
            {pinPriority: 0, appId: 'firefox', title: 'Tab', originalIndex: 1}
        ];
        assert.deepEqual(calcSortedButtonOrder(buttons), [0, 1]);
    });

    it('handles empty array', () => {
        assert.deepEqual(calcSortedButtonOrder([]), []);
    });

    it('mixed pinned priorities sort correctly', () => {
        let buttons = [
            {pinPriority: 3, appId: 'terminal', title: 'T', originalIndex: 0},
            {pinPriority: null, appId: 'nautilus', title: 'N', originalIndex: 1},
            {pinPriority: 0, appId: 'firefox', title: 'Mail', originalIndex: 2},
            {pinPriority: 1, appId: 'firefox', title: 'Calendar', originalIndex: 3},
            {pinPriority: null, appId: 'gedit', title: 'G', originalIndex: 4}
        ];
        // Pinned sorted: priority 0 (idx 2), priority 1 (idx 3), priority 3 (idx 0)
        // Unpinned in order: idx 1, idx 4
        assert.deepEqual(calcSortedButtonOrder(buttons), [2, 3, 0, 1, 4]);
    });
});

describe('buildEditorRules', () => {
    it('builds rules from valid editor row data', () => {
        let rows = [
            { appId: 'xterm.desktop', title: 'foo', priority: '0' },
            { appId: 'gedit.desktop', title: 'bar', priority: '5' }
        ];
        let result = buildEditorRules(rows);
        assert.deepEqual(result, [
            { appId: 'xterm.desktop', title: 'foo', priority: 0 },
            { appId: 'gedit.desktop', title: 'bar', priority: 5 }
        ]);
    });

    it('skips rows with non-numeric priority', () => {
        let rows = [
            { appId: 'a.desktop', title: 'a', priority: 'abc' },
            { appId: 'b.desktop', title: 'b', priority: '3' },
            { appId: 'c.desktop', title: 'c', priority: '' }
        ];
        assert.deepEqual(buildEditorRules(rows), [
            { appId: 'b.desktop', title: 'b', priority: 3 }
        ]);
    });

    it('returns empty array for empty input', () => {
        assert.deepEqual(buildEditorRules([]), []);
    });

    it('handles negative priority', () => {
        let rows = [{ appId: 'x.desktop', title: 't', priority: '-1' }];
        assert.deepEqual(buildEditorRules(rows), [
            { appId: 'x.desktop', title: 't', priority: -1 }
        ]);
    });

    it('preserves empty title string', () => {
        let rows = [{ appId: 'x.desktop', title: '', priority: '0' }];
        assert.deepEqual(buildEditorRules(rows), [
            { appId: 'x.desktop', title: '', priority: 0 }
        ]);
    });

    it('produces valid JSON for round-trip through parsePinRules', () => {
        let rows = [
            { appId: 'xterm.desktop', title: 'hello.*world', priority: '2' },
            { appId: 'gedit.desktop', title: '', priority: '0' }
        ];
        let built = buildEditorRules(rows);
        let json = JSON.stringify(built);
        let parsed = parsePinRules(json);
        assert.equal(parsed.length, 2);
        assert.equal(parsed[0].appId, 'xterm.desktop');
        assert.ok(parsed[0].titleRegex instanceof RegExp);
        assert.equal(parsed[0].titleRegex.source, 'hello.*world');
        assert.equal(parsed[1].appId, 'gedit.desktop');
        assert.ok(parsed[1].titleRegex instanceof RegExp); // empty string = match-all regex
    });
});

describe('filterPinRule', () => {
    it('removes rule matching appId and priority', () => {
        let rules = [
            { appId: 'a.desktop', title: 'foo', priority: 0 },
            { appId: 'b.desktop', title: 'bar', priority: 1 },
            { appId: 'a.desktop', title: 'baz', priority: 2 }
        ];
        let result = filterPinRule(rules, 'b.desktop', 1);
        assert.deepEqual(result, [
            { appId: 'a.desktop', title: 'foo', priority: 0 },
            { appId: 'a.desktop', title: 'baz', priority: 2 }
        ]);
    });

    it('does not remove when appId matches but priority differs', () => {
        let rules = [
            { appId: 'a.desktop', title: 'foo', priority: 0 },
            { appId: 'a.desktop', title: 'bar', priority: 1 }
        ];
        let result = filterPinRule(rules, 'a.desktop', 5);
        assert.equal(result.length, 2);
    });

    it('does not remove when priority matches but appId differs', () => {
        let rules = [
            { appId: 'a.desktop', title: 'foo', priority: 0 },
            { appId: 'b.desktop', title: 'bar', priority: 0 }
        ];
        let result = filterPinRule(rules, 'c.desktop', 0);
        assert.equal(result.length, 2);
    });

    it('returns empty array when removing the only rule', () => {
        let rules = [{ appId: 'a.desktop', title: 'foo', priority: 0 }];
        assert.deepEqual(filterPinRule(rules, 'a.desktop', 0), []);
    });

    it('does not mutate the original array', () => {
        let rules = [
            { appId: 'a.desktop', title: 'foo', priority: 0 },
            { appId: 'b.desktop', title: 'bar', priority: 1 }
        ];
        filterPinRule(rules, 'a.desktop', 0);
        assert.equal(rules.length, 2);
    });

    it('result round-trips through JSON and parsePinRules', () => {
        let rules = [
            { appId: 'a.desktop', title: 'hello', priority: 0 },
            { appId: 'b.desktop', title: 'world', priority: 1 }
        ];
        let filtered = filterPinRule(rules, 'a.desktop', 0);
        let json = JSON.stringify(filtered);
        let parsed = parsePinRules(json);
        assert.equal(parsed.length, 1);
        assert.equal(parsed[0].appId, 'b.desktop');
        assert.equal(parsed[0].priority, 1);
    });
});

describe('pin rules serialization bug', () => {
    it('parsePinRules output loses title field (has titleRegex instead)', () => {
        let json = '[{"appId":"x.desktop","title":"hello","priority":0}]';
        let parsed = parsePinRules(json);
        // parsed has titleRegex (RegExp), not title (string)
        assert.equal(parsed[0].titleRegex instanceof RegExp, true);
        assert.equal(parsed[0].title, undefined);
    });

    it('JSON.stringify of parsed rules loses title regex', () => {
        let json = '[{"appId":"x.desktop","title":"hello","priority":0}]';
        let parsed = parsePinRules(json);
        let reserialized = JSON.stringify(parsed);
        // RegExp serializes as {} and 'title' key is gone — titleRegex becomes null on re-parse
        let reparsed = parsePinRules(reserialized);
        assert.equal(reparsed.length, 1);
        assert.equal(reparsed[0].titleRegex, null, 'title regex is lost after round-trip through parsed rules');
    });

    it('raw rules (with title string) round-trip correctly', () => {
        let raw = [{ appId: 'x.desktop', title: 'hello', priority: 0 }];
        let json = JSON.stringify(raw);
        let parsed = parsePinRules(json);
        assert.equal(parsed.length, 1);
        assert.equal(parsed[0].appId, 'x.desktop');
        assert.equal(parsed[0].priority, 0);
    });
});

