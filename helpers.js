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

/**
 * Parse pin rules from a JSON string.
 * Validates fields, pre-compiles title regexes. Invalid entries are dropped silently.
 * @param {string} jsonString - JSON array of pin rule objects
 * @returns {Array<{appId: string, titleRegex: RegExp|null, priority: number}>}
 */
function parsePinRules(jsonString) {
    let raw;
    try {
        raw = JSON.parse(jsonString);
    } catch (e) {
        return [];
    }
    if (!Array.isArray(raw)) return [];
    let results = [];
    for (let i = 0; i < raw.length; i++) {
        let entry = raw[i];
        if (!entry || typeof entry.appId !== 'string' || !entry.appId) continue;
        if (typeof entry.priority !== 'number' || !isFinite(entry.priority)) continue;
        let titleRegex = null;
        if (entry.title !== undefined && entry.title !== null) {
            if (typeof entry.title !== 'string') continue;
            try {
                titleRegex = new RegExp(entry.title);
            } catch (e) {
                continue;
            }
        }
        results.push({ appId: entry.appId, titleRegex: titleRegex, priority: entry.priority });
    }
    return results;
}

/**
 * Find the matching pin rule for a window.
 * Match logic: appId must match exactly; if rule has titleRegex, it must match windowTitle.
 * Returns the matching rule with the lowest priority, or null.
 * @param {Array<{appId: string, titleRegex: RegExp|null, priority: number}>} rules
 * @param {string|null} appId
 * @param {string|null} windowTitle
 * @returns {{appId: string, titleRegex: RegExp|null, priority: number}|null}
 */
function matchPinRule(rules, appId, windowTitle) {
    if (!appId) return null;
    let best = null;
    for (let i = 0; i < rules.length; i++) {
        let rule = rules[i];
        if (rule.appId !== appId) continue;
        if (rule.titleRegex !== null) {
            if (!windowTitle || !rule.titleRegex.test(windowTitle)) continue;
        }
        if (best === null || rule.priority < best.priority) {
            best = rule;
        }
    }
    return best;
}

/**
 * Find insertion index for a pinned button among existing children.
 * Pinned buttons are sorted by priority; within same priority+appId, append after last sibling.
 * @param {Array<{pinPriority: number|null, appId: string|null}>} children - existing button info
 * @param {number} newPriority - priority of new pinned button
 * @param {string} newAppId - app ID of new pinned button
 * @returns {number} insertion index
 */
function calcPinnedInsertionIndex(children, newPriority, newAppId) {
    let lastSiblingIndex = -1;
    let firstHigherIndex = -1;
    for (let i = 0; i < children.length; i++) {
        let child = children[i];
        if (child.pinPriority === null) {
            // First unpinned button — all pinned must be before this
            if (firstHigherIndex === -1) firstHigherIndex = i;
            break;
        }
        if (child.pinPriority === newPriority && child.appId === newAppId) {
            lastSiblingIndex = i;
        } else if (child.pinPriority > newPriority && firstHigherIndex === -1) {
            firstHigherIndex = i;
        }
    }
    if (lastSiblingIndex !== -1) return lastSiblingIndex + 1;
    if (firstHigherIndex !== -1) return firstHigherIndex;
    // All existing pinned have lower or equal priority — append after all pinned
    for (let i = 0; i < children.length; i++) {
        if (children[i].pinPriority === null) return i;
    }
    return children.length;
}

/**
 * Compute the full sorted button order with pinned buttons first, then unpinned.
 * Pinned sorted by priority, then appId (alpha), then title (alpha), then original index.
 * Unpinned maintain their relative order.
 * @param {Array<{pinPriority: number|null, appId: string|null, title: string|null, originalIndex: number}>} buttons
 * @returns {Array<number>} Array of originalIndex values in the new order
 */
function calcSortedButtonOrder(buttons) {
    let pinned = [];
    let unpinned = [];
    for (let i = 0; i < buttons.length; i++) {
        let b = buttons[i];
        if (b.pinPriority !== null && b.pinPriority !== undefined) {
            pinned.push(b);
        } else {
            unpinned.push(b);
        }
    }
    pinned.sort(function(a, b) {
        if (a.pinPriority !== b.pinPriority) return a.pinPriority - b.pinPriority;
        let appCmp = (a.appId || '').localeCompare(b.appId || '');
        if (appCmp !== 0) return appCmp;
        let titleCmp = (a.title || '').localeCompare(b.title || '');
        if (titleCmp !== 0) return titleCmp;
        return a.originalIndex - b.originalIndex;
    });
    let result = [];
    for (let i = 0; i < pinned.length; i++) result.push(pinned[i].originalIndex);
    for (let i = 0; i < unpinned.length; i++) result.push(unpinned[i].originalIndex);
    return result;
}

/**
 * Build pin rules array from editor row data.
 * Rows with invalid (non-numeric) priority are skipped.
 * @param {Array<{appId: string, title: string, priority: string}>} rows - Editor row data
 * @returns {Array<{appId: string, title: string, priority: number}>} Valid rules
 */
function buildEditorRules(rows) {
    let result = [];
    for (let i = 0; i < rows.length; i++) {
        let p = parseInt(rows[i].priority);
        if (isNaN(p)) continue;
        result.push({ appId: rows[i].appId, title: rows[i].title, priority: p });
    }
    return result;
}

/**
 * Remove a pin rule matching the given appId and priority.
 * @param {Array<{appId: string, title: string, priority: number}>} rawRules - Current raw rules
 * @param {string} appId - App ID to match
 * @param {number} priority - Priority to match
 * @returns {Array<{appId: string, title: string, priority: number}>} Filtered rules
 */
function filterPinRule(rawRules, appId, priority) {
    return rawRules.filter(function(r) {
        return !(r.appId === appId && r.priority === priority);
    });
}

// Export for Node.js testing; ignored in GJS runtime
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        calcRowHeight, calcButtonHeight,
        calcAdaptiveRowCount, calcButtonWidth, calcLayoutMode, calcAdaptiveFontSize, calcAdaptiveIconSize,
        calcGroupedInsertionIndex, calcDragInsertionIndex,
        parsePinRules, matchPinRule, calcPinnedInsertionIndex, calcSortedButtonOrder,
        buildEditorRules, filterPinRule
    };
}
