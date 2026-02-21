/**
 * Pure computation helpers for multi-row window list sizing.
 * No Cinnamon/GJS dependencies — testable in Node.js.
 */

/**
 * Calculate the height of a single row given panel height and number of rows.
 * @param {number} panelHeight - Total panel height in pixels
 * @param {number} numberOfRows - Number of rows (1-4)
 * @returns {number} Row height in pixels (floored)
 */
function calcRowHeight(panelHeight, numberOfRows) {
    return Math.floor(panelHeight / numberOfRows);
}

/**
 * Calculate icon size for a given configuration.
 * @param {number} panelHeight - Total panel height in pixels
 * @param {number} numberOfRows - Number of rows (1-4)
 * @param {number} overrideSize - User override (0 = auto-scale)
 * @returns {number} Icon size in pixels
 */
function calcIconSize(panelHeight, numberOfRows, overrideSize) {
    if (overrideSize > 0) {
        return overrideSize;
    }
    let rowHeight = calcRowHeight(panelHeight, numberOfRows);
    return Math.max(16, rowHeight - 8);
}

/**
 * Calculate per-button height (buttons fill their row).
 * @param {number} panelHeight - Total panel height in pixels
 * @param {number} numberOfRows - Number of rows (1-4)
 * @returns {number} Button height in pixels (floored)
 */
function calcButtonHeight(panelHeight, numberOfRows) {
    return calcRowHeight(panelHeight, numberOfRows);
}

/**
 * Calculate how many rows are needed for the given button count.
 * @param {number} containerWidth - Available width in pixels
 * @param {number} buttonCount - Number of visible buttons
 * @param {number} buttonWidth - Width per button in pixels
 * @param {number} maxRows - Maximum allowed rows (1-4)
 * @returns {number} Number of rows (1 to maxRows)
 */
function calcAdaptiveRowCount(containerWidth, buttonCount, buttonWidth, maxRows) {
    if (buttonCount <= 0 || containerWidth <= 0 || buttonWidth <= 0 || maxRows <= 0) {
        return 1;
    }
    let buttonsPerRow = Math.max(1, Math.floor(containerWidth / buttonWidth));
    let needed = Math.ceil(buttonCount / buttonsPerRow);
    return Math.max(1, Math.min(needed, maxRows));
}

/**
 * Return layout mode based on computed row count.
 * @param {number} computedRows - Number of rows from calcAdaptiveRowCount
 * @returns {'spacious'|'compact'}
 */
function calcLayoutMode(computedRows) {
    return computedRows <= 1 ? 'spacious' : 'compact';
}

/**
 * Calculate font size for adaptive layout.
 * @param {number} panelHeight - Total panel height in pixels
 * @param {number} computedRows - Number of computed rows
 * @returns {number} Font size in pt (0 = use default theme font)
 */
function calcAdaptiveFontSize(panelHeight, computedRows) {
    if (computedRows <= 1) return 0;
    let rowHeight = Math.floor(panelHeight / computedRows);
    return Math.max(6, Math.min(10, Math.floor(rowHeight / 3.5)));
}

/**
 * Calculate icon size for adaptive layout.
 * @param {number} panelHeight - Total panel height in pixels
 * @param {number} computedRows - Number of computed rows
 * @param {number} overrideSize - User override (0 = auto-scale)
 * @returns {number} Icon size in pixels
 */
function calcAdaptiveIconSize(panelHeight, computedRows, overrideSize) {
    if (overrideSize > 0) return overrideSize;
    let rowHeight = Math.floor(panelHeight / computedRows);
    return Math.max(12, Math.floor(rowHeight * 0.4));
}

// Export for Node.js testing; ignored in GJS runtime
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        calcRowHeight, calcIconSize, calcButtonHeight,
        calcAdaptiveRowCount, calcLayoutMode, calcAdaptiveFontSize, calcAdaptiveIconSize
    };
}
