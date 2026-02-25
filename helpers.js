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
function calcRowHeight(panelHeight, numberOfRows, verticalMargin = 0) {
    let available = panelHeight - (verticalMargin * numberOfRows);
    return Math.floor(available / numberOfRows);
}

/**
 * Calculate per-button height (buttons fill their row).
 * @param {number} panelHeight - Total panel height in pixels
 * @param {number} numberOfRows - Number of rows (1-4)
 * @returns {number} Button height in pixels (floored)
 */
function calcButtonHeight(panelHeight, numberOfRows, verticalMargin = 0) {
    return calcRowHeight(panelHeight, numberOfRows, verticalMargin);
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
 * Calculate effective button width to fit all windows within maxRows.
 * Shrinks below configured buttonWidth when needed; never below minWidth.
 * @param {number} containerWidth - Available width in pixels
 * @param {number} visibleCount - Number of visible window buttons
 * @param {number} buttonWidth - Configured button width in pixels
 * @param {number} maxRows - Maximum allowed rows
 * @param {number} minWidth - Minimum button width before icon-only mode
 * @returns {number} Effective button width in pixels
 */
function calcButtonWidth(containerWidth, visibleCount, buttonWidth, maxRows, minWidth) {
    if (visibleCount <= 0 || containerWidth <= 0 || maxRows <= 0) return buttonWidth;
    let buttonsPerRow = Math.max(1, Math.floor(containerWidth / buttonWidth));
    let maxVisible = buttonsPerRow * maxRows;
    if (visibleCount <= maxVisible) return buttonWidth;
    let neededPerRow = Math.ceil(visibleCount / maxRows);
    return Math.max(minWidth, Math.floor(containerWidth / neededPerRow));
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
function calcAdaptiveFontSize(panelHeight, computedRows, verticalMargin = 0) {
    if (computedRows <= 1) return 0;
    let rowHeight = calcRowHeight(panelHeight, computedRows, verticalMargin);
    return Math.max(6, Math.min(10, Math.floor(rowHeight / 3.5)));
}

/**
 * Calculate icon size for adaptive layout.
 * @param {number} panelHeight - Total panel height in pixels
 * @param {number} computedRows - Number of computed rows
 * @param {number} overrideSize - User override (0 = auto-scale)
 * @returns {number} Icon size in pixels
 */
function calcAdaptiveIconSize(panelHeight, computedRows, overrideSize, verticalMargin = 0) {
    if (overrideSize > 0) return overrideSize;
    let rowHeight = calcRowHeight(panelHeight, computedRows, verticalMargin);
    let ratio = computedRows <= 1 ? 0.25 : 0.4;
    return Math.max(12, Math.floor(rowHeight * ratio));
}

/**
 * Calculate where to insert a new window button to group it with same-app siblings.
 * Returns the index after the last existing window of the same app.
 * If no sibling exists, returns the end of the list (append).
 * @param {Array<string|null>} existingAppIds - App IDs of current buttons in order
 * @param {string|null} newAppId - App ID of the new window
 * @returns {number} Insertion index
 */
function calcGroupedInsertionIndex(existingAppIds, newAppId) {
    if (!newAppId) return existingAppIds.length;
    for (let i = existingAppIds.length - 1; i >= 0; i--) {
        if (existingAppIds[i] === newAppId) return i + 1;
    }
    return existingAppIds.length;
}

/**
 * Calculate the insertion index during drag-and-drop reordering.
 * Finds the child whose center is closest to the cursor position.
 *
 * @param {Array<{x: number, y: number, width: number, height: number}>} childRects
 *   Bounding rectangles of each child in container-local coordinates
 * @param {number} cursorX - Cursor X in container-local coordinates
 * @param {number} cursorY - Cursor Y in container-local coordinates
 * @param {boolean} isVertical - Whether panel is vertical (LEFT/RIGHT)
 * @returns {number} Index of closest child, or -1 if no visible children
 */
function calcDragInsertionIndex(childRects, cursorX, cursorY, isVertical) {
    let insertPos = -1;
    let minDist = -1;
    for (let i = 0; i < childRects.length; i++) {
        let rect = childRects[i];
        let cx = rect.x + rect.width / 2;
        let cy = rect.y + rect.height / 2;
        let dx = cursorX - cx;
        let dy = cursorY - cy;
        let dist = dx * dx + dy * dy;
        if (dist < minDist || minDist == -1) {
            minDist = dist;
            insertPos = i;
        }
    }
    return insertPos;
}

// Export for Node.js testing; ignored in GJS runtime
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        calcRowHeight, calcButtonHeight,
        calcAdaptiveRowCount, calcButtonWidth, calcLayoutMode, calcAdaptiveFontSize, calcAdaptiveIconSize,
        calcGroupedInsertionIndex, calcDragInsertionIndex
    };
}
